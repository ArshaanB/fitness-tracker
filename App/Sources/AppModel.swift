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
    private(set) var monthSections: [MonthSection] = []
    private(set) var prCounts: [String: Int] = [:]
    private(set) var exercises: [ExerciseHistory] = []  // sorted by last done, most recent first
    private(set) var bestE1RMByExerciseId: [String: Double] = [:]

    func bootstrap() async {
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.loadEverything()
            }.value
            monthSections = result.sections
            prCounts = result.prCounts
            exercises = result.exercises
            bestE1RMByExerciseId = result.bestE1RM
            state = .ready
        } catch {
            state = .failed("\(error)")
        }
    }

    private struct Loaded: Sendable {
        let sections: [MonthSection]
        let prCounts: [String: Int]
        let exercises: [ExerciseHistory]
        let bestE1RM: [String: Double]
    }

    private nonisolated static func loadEverything() throws -> Loaded {
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

        let workouts = try HistoryStore.loadAll(from: db)  // ascending
        let prCounts = Stats.prCounts(workoutsAscending: workouts)
        let histories = Stats.exerciseHistories(workoutsAscending: workouts)
            .sorted { ($0.lastDone ?? .distantPast) > ($1.lastDone ?? .distantPast) }
        let bestE1RM = Dictionary(uniqueKeysWithValues: histories.compactMap { history in
            history.bestE1RM.map { (history.id, $0) }
        })

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
                      exercises: histories, bestE1RM: bestE1RM)
    }
}
