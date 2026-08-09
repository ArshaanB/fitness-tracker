import Foundation
import FitnessKit
import GRDB
import Observation
import UserNotifications

/// Live workout state. Kept in memory for instant UI, written through to the
/// database on every mutation so the session survives app termination.
@MainActor
@Observable
final class WorkoutSessionModel {
    struct SessionSet: Identifiable {
        let id: String
        var position: Int
        var isWarmup: Bool
        var weight: Double?
        var reps: Int?
        var completedAt: Date?
        var completed: Bool { completedAt != nil }

        var e1RM: Double? {
            guard let weight, let reps else { return nil }
            return Strength.estimatedOneRepMax(weight: weight, reps: reps)
        }
    }

    struct SessionExercise: Identifiable {
        let id: String  // workoutItem id
        let exerciseId: String
        let name: String
        var restSeconds: Int?
        var previous: [LoadedSet]
        var sets: [SessionSet]
        var baselineE1RM: Double?

        var completedCount: Int { sets.filter(\.completed).count }
    }

    struct RestState {
        var exerciseName: String
        var endDate: Date
        var totalSeconds: Int
    }

    struct FinishPR: Identifiable {
        var id: String { name }
        let name: String
        let e1RM: Double
        let previousBest: Double?
    }

    private(set) var workoutId: String?
    private(set) var name = ""
    private(set) var startedAt = Date()
    var exercises: [SessionExercise] = []
    var expandedExerciseId: String?
    var rest: RestState?

    var isActive: Bool { workoutId != nil }
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var completedSets: Int { exercises.reduce(0) { $0 + $1.completedCount } }
    var completedVolume: Double {
        var total: Double = 0
        for exercise in exercises {
            for set in exercise.sets where set.completed {
                let weight: Double = set.weight ?? 0
                let reps: Double = Double(set.reps ?? 0)
                total += weight * reps
            }
        }
        return total
    }

    /// True when the session has sat idle long enough that the app should offer
    /// to finish or discard it instead of silently resuming (PRD auto-timeout).
    var isStale: Bool {
        let lastActivity = exercises.flatMap(\.sets).compactMap(\.completedAt).max() ?? startedAt
        return Date().timeIntervalSince(lastActivity) > 6 * 3600
    }

    private var db: DatabaseQueue?

    func configure(db: DatabaseQueue) {
        self.db = db
    }

    // MARK: - Lifecycle

    func start(template: TemplateSummary?, name: String,
               baselines: [String: Double], exerciseNames: [String: String]) {
        guard let db else { return }
        do {
            let started = try SessionStore.start(template: template, name: name, into: db)
            load(started, baselines: baselines, exerciseNames: exerciseNames)
        } catch {
            assertionFailure("start failed: \(error)")
        }
    }

    /// Returns true if an unfinished workout was found and loaded.
    @discardableResult
    func resumeIfNeeded(baselines: [String: Double], exerciseNames: [String: String]) -> Bool {
        guard let db, workoutId == nil else { return isActive }
        do {
            guard let id = try SessionStore.activeWorkoutId(in: db),
                  let started = try SessionStore.resume(workoutId: id, from: db) else { return false }
            load(started, baselines: baselines, exerciseNames: exerciseNames)
            return true
        } catch {
            return false
        }
    }

    private func load(_ started: SessionStore.StartedWorkout,
                      baselines: [String: Double], exerciseNames: [String: String]) {
        workoutId = started.workout.id
        name = started.workout.name
        startedAt = started.workout.startedAt
        exercises = started.exercises.map { exercise in
            SessionExercise(id: exercise.item.id,
                            exerciseId: exercise.item.exerciseId,
                            name: exerciseNames[exercise.item.exerciseId] ?? "Exercise",
                            restSeconds: exercise.item.restSeconds,
                            previous: exercise.previous,
                            sets: exercise.sets.map {
                                SessionSet(id: $0.id, position: $0.position, isWarmup: $0.isWarmup,
                                           weight: $0.weight, reps: $0.reps, completedAt: $0.completedAt)
                            },
                            baselineE1RM: baselines[exercise.item.exerciseId])
        }
        expandedExerciseId = exercises.first(where: { $0.completedCount < $0.sets.count })?.id
            ?? exercises.first?.id
    }

    func finishSummary() -> (duration: Int, volume: Double, sets: Int, prs: [FinishPR]) {
        let prs = exercises.compactMap { exercise -> FinishPR? in
            let best = exercise.sets.filter { $0.completed && !$0.isWarmup }
                .compactMap(\.e1RM).max()
            guard let best else { return nil }
            if let baseline = exercise.baselineE1RM {
                guard best > baseline else { return nil }
                return FinishPR(name: exercise.name, e1RM: best, previousBest: baseline)
            }
            return FinishPR(name: exercise.name, e1RM: best, previousBest: nil)
        }
        return (Int(Date().timeIntervalSince(startedAt)), completedVolume, completedSets, prs)
    }

    func finish() {
        guard let db, let workoutId else { return }
        try? SessionStore.finish(workoutId: workoutId, in: db)
        clearRest()
        reset()
    }

    func discard() {
        guard let db, let workoutId else { return }
        try? SessionStore.discard(workoutId: workoutId, in: db)
        clearRest()
        reset()
    }

    private func reset() {
        workoutId = nil
        exercises = []
        expandedExerciseId = nil
        rest = nil
    }

    // MARK: - Set mutations (write-through)

    private func persist(_ set: SessionSet, itemId: String) {
        guard let db else { return }
        try? SessionStore.upsertSet(
            WorkoutSetRecord(id: set.id, workoutItemId: itemId, position: set.position,
                             isWarmup: set.isWarmup, weight: set.weight, reps: set.reps,
                             completedAt: set.completedAt),
            in: db)
    }

    func updateSet(exerciseId: String, setId: String, weight: Double?, reps: Int?) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseId }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setId }) else { return }
        exercises[e].sets[s].weight = weight
        exercises[e].sets[s].reps = reps
        persist(exercises[e].sets[s], itemId: exerciseId)
    }

    func toggleComplete(exerciseId: String, setId: String) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseId }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setId }) else { return }
        let wasCompleted = exercises[e].sets[s].completed
        exercises[e].sets[s].completedAt = wasCompleted ? nil : Date()
        persist(exercises[e].sets[s], itemId: exerciseId)
        if !wasCompleted {
            startRest(for: exercises[e])
        }
    }

    func addSet(exerciseId: String, warmup: Bool = false) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let last = exercises[e].sets.last
        let set = SessionSet(id: UUID().uuidString,
                             position: (last?.position ?? 0) + 1,
                             isWarmup: warmup,
                             weight: last?.weight,
                             reps: last?.reps,
                             completedAt: nil)
        exercises[e].sets.append(set)
        persist(set, itemId: exerciseId)
    }

    func deleteSet(exerciseId: String, setId: String) {
        guard let db,
              let e = exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        exercises[e].sets.removeAll { $0.id == setId }
        try? SessionStore.deleteSet(id: setId, in: db)
    }

    func addExercise(exerciseId: String, name: String, restSeconds: Int?, baseline: Double?,
                     previous: [LoadedSet]) {
        guard let db, let workoutId else { return }
        let item = WorkoutItemRecord(workoutId: workoutId, exerciseId: exerciseId,
                                     position: (exercises.count) + 1, restSeconds: restSeconds)
        try? SessionStore.insertItem(item, in: db)
        exercises.append(SessionExercise(id: item.id, exerciseId: exerciseId, name: name,
                                         restSeconds: restSeconds, previous: previous,
                                         sets: [], baselineE1RM: baseline))
        let setCount = max(previous.count, 1)
        for _ in 0..<setCount { addSet(exerciseId: item.id) }
        expandedExerciseId = item.id
    }

    func removeExercise(exerciseId: String) {
        guard let db else { return }
        exercises.removeAll { $0.id == exerciseId }
        try? SessionStore.deleteItem(id: exerciseId, in: db)
    }

    // MARK: - Rest timer

    private func startRest(for exercise: SessionExercise) {
        guard let seconds = exercise.restSeconds, seconds > 0 else { return }
        rest = RestState(exerciseName: exercise.name,
                         endDate: Date().addingTimeInterval(TimeInterval(seconds)),
                         totalSeconds: seconds)
        scheduleRestNotification()
    }

    func adjustRest(by delta: Int) {
        guard var rest else { return }
        rest.endDate = rest.endDate.addingTimeInterval(TimeInterval(delta))
        rest.totalSeconds = max(rest.totalSeconds, Int(rest.endDate.timeIntervalSinceNow.rounded()))
        if rest.endDate.timeIntervalSinceNow <= 0 {
            clearRest()
        } else {
            self.rest = rest
            scheduleRestNotification()
        }
    }

    func clearRest() {
        rest = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
    }

    private func scheduleRestNotification() {
        guard let rest else { return }
        #if DEBUG
        // Screenshot runs: skip the permission prompt (it covers the UI).
        if ProcessInfo.processInfo.environment["SKIP_NOTIF"] != nil { return }
        #endif
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Back to \(rest.exerciseName)"
        content.sound = .default
        let interval = max(rest.endDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }
}
