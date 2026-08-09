import Foundation
import FitnessKit
import GRDB
import Observation

@MainActor
@Observable
final class AppModel {
    enum LoadState {
        case loading
        case ready
        case failed(String)
    }

    struct MonthSection: Identifiable {
        let id: String
        let title: String
        let workoutCount: Int
        let totalSeconds: Int
        let workouts: [LoadedWorkout]
    }

    private(set) var state: LoadState = .loading
    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    private(set) var monthSections: [MonthSection] = []
    private(set) var prCounts: [String: Int] = [:]
    private(set) var exercises: [ExerciseHistory] = []  // sorted by last done, most recent first
    private(set) var bestE1RMByExerciseId: [String: Double] = [:]
    private(set) var exerciseNames: [String: String] = [:]
    private(set) var lastRestByExerciseId: [String: Int] = [:]
    private(set) var templates: [TemplateSummary] = []
    private(set) var db: DatabaseQueue?

    func bootstrap() async {
        do {
            let db = try await Task.detached(priority: .userInitiated) {
                try Self.openAndSeed()
            }.value
            self.db = db
            try await reload()
        } catch {
            state = .failed("\(error)")
        }
    }

    /// Reloads history-derived state; call after finishing a workout or editing
    /// templates so records, rings, and lists reflect the database.
    func reload() async throws {
        guard let db else { return }
        let result = try await Task.detached(priority: .userInitiated) {
            try Self.loadEverything(db: db)
        }.value
        monthSections = result.sections
        prCounts = result.prCounts
        exercises = result.exercises
        bestE1RMByExerciseId = result.bestE1RM
        exerciseNames = result.exerciseNames
        lastRestByExerciseId = result.lastRest
        templates = result.templates
        state = .ready
    }

    func refresh() {
        Task { try? await reload() }
    }

    func previousWorkingSets(exerciseId: String) -> [LoadedSet] {
        guard let db else { return [] }
        return (try? db.read { try SessionStore.previousWorkingSets(exerciseId: exerciseId, in: $0) }) ?? []
    }

    // MARK: - Loading

    private nonisolated static func openAndSeed() throws -> DatabaseQueue {
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
                                                  in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let db = try AppDatabase.open(at: support.appendingPathComponent("fitness.sqlite").path)
        let workoutCount = try db.read { try WorkoutRecord.fetchCount($0) }
        if workoutCount == 0,
           let url = Bundle.main.url(forResource: "strong_workouts", withExtension: "csv") {
            let text = try String(contentsOf: url, encoding: .utf8)
            try StrongImporter.run(try StrongImport.parse(csv: text), into: db)
        }
        return db
    }

    private struct Loaded: Sendable {
        let sections: [MonthSection]
        let prCounts: [String: Int]
        let exercises: [ExerciseHistory]
        let bestE1RM: [String: Double]
        let exerciseNames: [String: String]
        let lastRest: [String: Int]
        let templates: [TemplateSummary]
    }

    private nonisolated static func loadEverything(db: DatabaseQueue) throws -> Loaded {
        let workouts = try HistoryStore.loadAll(from: db)  // ascending, finished + active
            .filter { $0.finishedAt != nil }
        let prCounts = Stats.prCounts(workoutsAscending: workouts)
        let histories = Stats.exerciseHistories(workoutsAscending: workouts)
            .sorted { ($0.lastDone ?? .distantPast) > ($1.lastDone ?? .distantPast) }
        let bestE1RM = Dictionary(uniqueKeysWithValues: histories.compactMap { history in
            history.bestE1RM.map { (history.id, $0) }
        })

        var exerciseNames: [String: String] = [:]
        var lastRest: [String: Int] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                exerciseNames[exercise.exerciseId] = exercise.name
                if let rest = exercise.restSeconds {
                    lastRest[exercise.exerciseId] = rest
                }
            }
        }

        let calendar = Calendar.current
        let monthTitle: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "MMMM yyyy"
            return f
        }()
        var sections: [MonthSection] = []
        var monthKey = ""
        var monthTitleText = ""
        var monthWorkouts: [LoadedWorkout] = []
        var monthSeconds = 0
        func flushMonth() {
            guard !monthWorkouts.isEmpty else { return }
            sections.append(MonthSection(id: monthKey, title: monthTitleText,
                                         workoutCount: monthWorkouts.count,
                                         totalSeconds: monthSeconds,
                                         workouts: monthWorkouts))
        }
        for workout in workouts.reversed() {
            let comps = calendar.dateComponents([.year, .month], from: workout.startedAt)
            let key = "\(comps.year ?? 0)-\(comps.month ?? 0)"
            if key != monthKey {
                flushMonth()
                monthKey = key
                monthTitleText = monthTitle.string(from: workout.startedAt)
                monthWorkouts = []
                monthSeconds = 0
            }
            monthWorkouts.append(workout)
            monthSeconds += workout.durationSeconds ?? 0
        }
        flushMonth()

        return Loaded(sections: sections, prCounts: prCounts,
                      exercises: histories, bestE1RM: bestE1RM,
                      exerciseNames: exerciseNames, lastRest: lastRest,
                      templates: try TemplateStore.loadAll(from: db))
    }
}
