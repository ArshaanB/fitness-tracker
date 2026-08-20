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
        var position: Int
        var restSeconds: Int?
        var previous: [LoadedSet]
        var sets: [SessionSet]
        var baselineE1RM: Double?
        var baselineReps: Int?

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
    var expandedExerciseIds: Set<String> = []
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

    /// One set scored against its exercise's record: e1RM for weighted sets;
    /// reps against the rep record for bodyweight sets (weight empty OR an
    /// explicit 0 — "just the machine / just me" still deserves a color).
    static func setRatio(_ set: SessionSet, in exercise: SessionExercise) -> Double? {
        if let weight = set.weight, weight > 0 {
            guard let e1RM = set.e1RM, let baseline = exercise.baselineE1RM,
                  baseline > 0 else { return nil }
            return e1RM / baseline
        }
        if let reps = set.reps, let baseline = exercise.baselineReps, baseline > 0 {
            return Double(reps) / Double(baseline)
        }
        return nil
    }

    /// Overall session intensity for the header ring: a live PROJECTION over
    /// every working set as planned — the ring assumes the entered weights and
    /// reps are what you'll lift, so it's colored from the first second and
    /// moves up or down as numbers are edited. The ring shows the mean of the
    /// per-set ratios: red < 70% — coasting below your records; yellow 70–90%
    /// — honest working weight; green ≥ 90% — pushing at your limits.
    var sessionIntensity: Double? {
        var ratios: [Double] = []
        for exercise in exercises {
            for set in exercise.sets where !set.isWarmup {
                if let ratio = Self.setRatio(set, in: exercise) { ratios.append(ratio) }
            }
        }
        guard !ratios.isEmpty else { return nil }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    /// True once a COMPLETED working set strictly beats its exercise's record
    /// — never a tie, never merely planned numbers.
    var sessionHasPR: Bool {
        exercises.contains { exercise in
            exercise.sets.contains { set in
                guard set.completed, !set.isWarmup,
                      let ratio = Self.setRatio(set, in: exercise) else { return false }
                return ratio > 1
            }
        }
    }

    /// The session ring wears rainbow only when a PR actually happened AND the
    /// session as a whole is in the green zone. One PR inside an otherwise-red
    /// workout stays a per-set celebration; the overall ring keeps telling the
    /// honest average.
    var sessionIsRecord: Bool {
        sessionHasPR && (sessionIntensity ?? 0) >= 0.9
    }

    /// True when the session has sat idle long enough that the app should offer
    /// to finish or discard it instead of silently resuming (PRD auto-timeout).
    var isStale: Bool {
        let lastActivity = exercises.flatMap(\.sets).compactMap(\.completedAt).max() ?? startedAt
        return Date().timeIntervalSince(lastActivity) > 6 * 3600
    }

    private var db: DatabaseQueue?
    private var pendingSaves: [String: Task<Void, Never>] = [:]

    func configure(db: DatabaseQueue) {
        self.db = db
    }

    // MARK: - Lifecycle

    func start(template: TemplateSummary?, name: String,
               baselines: [String: Double], repBaselines: [String: Int],
               exerciseNames: [String: String]) {
        guard let db else { return }
        do {
            let started = try SessionStore.start(template: template, name: name, into: db)
            load(started, baselines: baselines, repBaselines: repBaselines,
                 exerciseNames: exerciseNames)
        } catch {
            assertionFailure("start failed: \(error)")
        }
    }

    /// Re-performs a past workout: same exercises, sets prefilled with its
    /// lifts. Any in-progress session is replaced (callers confirm first).
    func startRepeating(_ workout: LoadedWorkout,
                        baselines: [String: Double], repBaselines: [String: Int],
                        exerciseNames: [String: String]) {
        guard let db else { return }
        pendingSaves.values.forEach { $0.cancel() }
        pendingSaves = [:]
        clearRest()
        do {
            let started = try SessionStore.start(repeating: workout, name: workout.name, into: db)
            load(started, baselines: baselines, repBaselines: repBaselines,
                 exerciseNames: exerciseNames)
        } catch {
            assertionFailure("start repeating failed: \(error)")
        }
    }

    /// Returns true if an unfinished workout was found and loaded.
    @discardableResult
    func resumeIfNeeded(baselines: [String: Double], repBaselines: [String: Int],
                        exerciseNames: [String: String]) -> Bool {
        guard let db, workoutId == nil else { return isActive }
        do {
            guard let id = try SessionStore.activeWorkoutId(in: db),
                  let started = try SessionStore.resume(workoutId: id, from: db) else { return false }
            load(started, baselines: baselines, repBaselines: repBaselines,
                 exerciseNames: exerciseNames)
            return true
        } catch {
            return false
        }
    }

    private func load(_ started: SessionStore.StartedWorkout,
                      baselines: [String: Double], repBaselines: [String: Int],
                      exerciseNames: [String: String]) {
        workoutId = started.workout.id
        name = started.workout.name
        startedAt = started.workout.startedAt
        exercises = started.exercises.map { exercise in
            SessionExercise(id: exercise.item.id,
                            exerciseId: exercise.item.exerciseId,
                            name: exerciseNames[exercise.item.exerciseId] ?? "Exercise",
                            position: exercise.item.position,
                            restSeconds: exercise.item.restSeconds,
                            previous: exercise.previous,
                            sets: exercise.sets.map {
                                SessionSet(id: $0.id, position: $0.position, isWarmup: $0.isWarmup,
                                           weight: $0.weight, reps: $0.reps, completedAt: $0.completedAt)
                            },
                            baselineE1RM: baselines[exercise.item.exerciseId],
                            baselineReps: repBaselines[exercise.item.exerciseId])
        }
        // Open on the first unfinished exercise; the user can expand more.
        if let focus = exercises.first(where: { $0.completedCount < $0.sets.count })?.id
            ?? exercises.first?.id {
            expandedExerciseIds = [focus]
        }
        restoreRestTimer()
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
        flushPendingSaves()
        try? SessionStore.finish(workoutId: workoutId, in: db)
        clearRest()
        reset()
    }

    func discard() {
        guard let db, let workoutId else { return }
        pendingSaves.values.forEach { $0.cancel() }
        pendingSaves = [:]
        try? SessionStore.discard(workoutId: workoutId, in: db)
        clearRest()
        reset()
    }

    private func reset() {
        workoutId = nil
        exercises = []
        expandedExerciseIds = []
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

    /// Weight/reps keystrokes persist debounced (writing SQLite per keystroke
    /// on the main actor is wasteful); everything structural stays immediate.
    private func schedulePersist(setId: String, itemId: String) {
        pendingSaves[setId]?.cancel()
        pendingSaves[setId] = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self else { return }
            self.pendingSaves[setId] = nil
            if let exercise = self.exercises.first(where: { $0.id == itemId }),
               let set = exercise.sets.first(where: { $0.id == setId }) {
                self.persist(set, itemId: itemId)
            }
        }
    }

    /// Persists any debounced edits immediately (finish, app backgrounding).
    func flushPendingSaves() {
        let pending = pendingSaves
        pendingSaves = [:]
        for (setId, task) in pending {
            task.cancel()
            for exercise in exercises {
                if let set = exercise.sets.first(where: { $0.id == setId }) {
                    persist(set, itemId: exercise.id)
                    break
                }
            }
        }
    }

    func updateSet(exerciseId: String, setId: String, weight: Double?, reps: Int?) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseId }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setId }) else { return }
        exercises[e].sets[s].weight = weight
        exercises[e].sets[s].reps = reps
        schedulePersist(setId: setId, itemId: exerciseId)
    }

    func toggleComplete(exerciseId: String, setId: String) {
        guard let e = exercises.firstIndex(where: { $0.id == exerciseId }),
              let s = exercises[e].sets.firstIndex(where: { $0.id == setId }) else { return }
        let wasCompleted = exercises[e].sets[s].completed
        exercises[e].sets[s].completedAt = wasCompleted ? nil : Date()
        pendingSaves[setId]?.cancel()
        pendingSaves[setId] = nil
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
        pendingSaves[setId]?.cancel()
        pendingSaves[setId] = nil
        exercises[e].sets.removeAll { $0.id == setId }
        try? SessionStore.deleteSet(id: setId, in: db)
        // Renumber so the visible set numbers stay 1…n after a deletion.
        for i in exercises[e].sets.indices where exercises[e].sets[i].position != i + 1 {
            exercises[e].sets[i].position = i + 1
            persist(exercises[e].sets[i], itemId: exerciseId)
        }
    }

    func addExercise(exerciseId: String, name: String, restSeconds: Int?, baseline: Double?,
                     repBaseline: Int?, previous: [LoadedSet]) {
        guard let db, let workoutId else { return }
        let position = (exercises.map(\.position).max() ?? 0) + 1
        let item = WorkoutItemRecord(workoutId: workoutId, exerciseId: exerciseId,
                                     position: position, restSeconds: restSeconds)
        try? SessionStore.insertItem(item, in: db)
        exercises.append(SessionExercise(id: item.id, exerciseId: exerciseId, name: name,
                                         position: position,
                                         restSeconds: restSeconds, previous: previous,
                                         sets: [], baselineE1RM: baseline,
                                         baselineReps: repBaseline))
        // Prefill planned sets from the previous session, exactly like a
        // template start: position-matched, extras copy the last previous set.
        let setCount = max(previous.count, 1)
        let index = exercises.count - 1
        for position in 1...setCount {
            let prev = position <= previous.count ? previous[position - 1] : previous.last
            let set = SessionSet(id: UUID().uuidString, position: position, isWarmup: false,
                                 weight: prev?.weight, reps: prev?.reps, completedAt: nil)
            exercises[index].sets.append(set)
            persist(set, itemId: item.id)
        }
        expandedExerciseIds.insert(item.id)
    }

    /// Live reorder while a card is dragged over another; persists immediately
    /// so the order survives however the drag ends.
    func reorderExercise(draggedId: String, over targetId: String) {
        guard draggedId != targetId,
              let from = exercises.firstIndex(where: { $0.id == draggedId }),
              let to = exercises.firstIndex(where: { $0.id == targetId }) else { return }
        let moved = exercises.remove(at: from)
        exercises.insert(moved, at: to)
        guard let db else { return }
        var changed: [(id: String, position: Int)] = []
        for i in exercises.indices where exercises[i].position != i + 1 {
            exercises[i].position = i + 1
            changed.append((exercises[i].id, i + 1))
        }
        if !changed.isEmpty { try? SessionStore.updateItemPositions(changed, in: db) }
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
        persistRestTimer()
        scheduleRestNotification()
    }

    /// The rest timer survives app termination like the rest of the session.
    private func persistRestTimer() {
        let defaults = UserDefaults.standard
        if let rest {
            defaults.set(rest.endDate, forKey: "restEndDate")
            defaults.set(rest.totalSeconds, forKey: "restTotalSeconds")
        } else {
            defaults.removeObject(forKey: "restEndDate")
            defaults.removeObject(forKey: "restTotalSeconds")
        }
    }

    private func restoreRestTimer() {
        let defaults = UserDefaults.standard
        guard let end = defaults.object(forKey: "restEndDate") as? Date, end > Date() else {
            persistRestTimer()
            return
        }
        rest = RestState(exerciseName: "",
                         endDate: end,
                         totalSeconds: max(defaults.integer(forKey: "restTotalSeconds"), 1))
    }

    func adjustRest(by delta: Int) {
        guard var rest else { return }
        rest.endDate = rest.endDate.addingTimeInterval(TimeInterval(delta))
        rest.totalSeconds = max(rest.totalSeconds, Int(rest.endDate.timeIntervalSinceNow.rounded()))
        if rest.endDate.timeIntervalSinceNow <= 0 {
            clearRest()
        } else {
            self.rest = rest
            persistRestTimer()
            scheduleRestNotification()
        }
    }

    func clearRest() {
        rest = nil
        persistRestTimer()
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
        // Time-sensitive so the alert breaks through Focus/DND mid-workout —
        // a silently-delivered rest timer defeats its purpose. Requires the
        // matching entitlement (project.yml), and the user can still turn
        // Time Sensitive delivery off per-Focus in Settings.
        content.interruptionLevel = .timeSensitive
        let interval = max(rest.endDate.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        center.add(UNNotificationRequest(identifier: "rest", content: content, trigger: trigger))
    }
}
