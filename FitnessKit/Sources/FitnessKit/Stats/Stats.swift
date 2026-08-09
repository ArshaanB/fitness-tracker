import Foundation

/// One exercise's complete story, derived from workout history.
public struct ExerciseHistory: Identifiable, Sendable {
    public struct Session: Identifiable, Sendable {
        public let id: String  // workout id
        public let date: Date
        public let sets: [LoadedSet]
        public let bestE1RM: Double?
        public let volume: Double
        public let heaviest: Double?
        /// Best working-set rep count — the record axis for bodyweight movements.
        public let bestReps: Int?
    }

    public let id: String  // exercise id
    public let name: String
    public let kind: ExerciseKind
    public let sessions: [Session]  // ascending by date

    public let bestE1RM: Double?
    public let heaviestWeight: Double?
    /// The set behind bestE1RM.
    public let bestSet: (weight: Double, reps: Int)?
    public let bestReps: Int?

    /// True when this exercise has no weighted history (pull-ups, push-ups…):
    /// records and rings run on reps instead of estimated 1RM.
    public var isRepOnly: Bool { bestE1RM == nil }

    public var lastDone: Date? { sessions.last?.date }
    public var sessionCount: Int { sessions.count }
}

public enum Stats {
    /// Number of exercise PRs (new best e1RM) each workout set, keyed by workout id.
    /// The first e1RM-bearing session of an exercise counts — it did set the record.
    public static func prCounts(workoutsAscending workouts: [LoadedWorkout]) -> [String: Int] {
        var best: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for workout in workouts {
            for exercise in workout.exercises {
                guard let sessionBest = exercise.bestE1RM else { continue }
                if sessionBest > (best[exercise.exerciseId] ?? 0) {
                    best[exercise.exerciseId] = sessionBest
                    counts[workout.id, default: 0] += 1
                }
            }
        }
        return counts
    }

    public static func exerciseHistories(workoutsAscending workouts: [LoadedWorkout]) -> [ExerciseHistory] {
        struct Builder {
            var name: String
            var kind: ExerciseKind
            var sessions: [ExerciseHistory.Session] = []
        }
        var builders: [String: Builder] = [:]
        var order: [String] = []

        for workout in workouts {
            for exercise in workout.exercises {
                if builders[exercise.exerciseId] == nil {
                    builders[exercise.exerciseId] = Builder(name: exercise.name, kind: exercise.kind)
                    order.append(exercise.exerciseId)
                }
                let volume = exercise.sets.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
                let workingSets = exercise.sets.filter { !$0.isWarmup }
                builders[exercise.exerciseId]?.sessions.append(
                    ExerciseHistory.Session(id: workout.id,
                                            date: workout.startedAt,
                                            sets: exercise.sets,
                                            bestE1RM: exercise.bestE1RM,
                                            volume: volume,
                                            heaviest: workingSets.compactMap(\.weight).max(),
                                            bestReps: workingSets.compactMap(\.reps).max()))
            }
        }

        return order.compactMap { id in
            guard let builder = builders[id] else { return nil }
            // Records only ever come from working sets.
            let allSets = builder.sessions.flatMap(\.sets).filter { !$0.isWarmup }
            let bestSet = allSets
                .compactMap { set -> (Double, Int, Double)? in
                    guard let w = set.weight, let r = set.reps, let e = set.e1RM else { return nil }
                    return (w, r, e)
                }
                .max { $0.2 < $1.2 }
            return ExerciseHistory(
                id: id,
                name: builder.name,
                kind: builder.kind,
                sessions: builder.sessions,
                bestE1RM: allSets.compactMap(\.e1RM).max(),
                heaviestWeight: allSets.compactMap(\.weight).max(),
                bestSet: bestSet.map { ($0.0, $0.1) },
                bestReps: allSets.compactMap(\.reps).max())
        }
    }
}
