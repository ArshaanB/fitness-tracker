import Foundation
import GRDB

/// Fully loaded workout history, ordered ascending by start date.
/// 8 years of training is ~13k sets — cheap to hold in memory, and it keeps
/// records/PRs derived rather than stored (edits recompute for free).
public struct LoadedSet: Identifiable, Sendable {
    public let id: String
    public let position: Int
    public let isWarmup: Bool
    public let weight: Double?
    public let reps: Int?
    public let seconds: Double?

    public var e1RM: Double? {
        guard let weight, let reps else { return nil }
        return Strength.estimatedOneRepMax(weight: weight, reps: reps)
    }
}

public struct LoadedExercise: Identifiable, Sendable {
    public let id: String  // workoutItem id
    public let exerciseId: String
    public let name: String
    public let kind: ExerciseKind
    public let restSeconds: Int?
    public let sets: [LoadedSet]

    /// Warm-up sets never count toward records.
    public var bestE1RM: Double? { sets.filter { !$0.isWarmup }.compactMap(\.e1RM).max() }
}

public struct LoadedWorkout: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let startedAt: Date
    public let finishedAt: Date?
    public let exercises: [LoadedExercise]

    public var durationSeconds: Int? {
        finishedAt.map { Int($0.timeIntervalSince(startedAt)) }
    }
    /// Total volume in lbs: Σ weight × reps over weighted sets.
    public var volume: Double {
        exercises.reduce(0) { total, exercise in
            total + exercise.sets.reduce(0) { sum, set in
                sum + (set.weight ?? 0) * Double(set.reps ?? 0)
            }
        }
    }
}

public enum HistoryStore {
    public static func loadAll(from dbQueue: DatabaseQueue) throws -> [LoadedWorkout] {
        try dbQueue.read { db in
            let exercisesById = Dictionary(
                uniqueKeysWithValues: try ExerciseRecord.fetchAll(db).map { ($0.id, $0) })
            let itemsByWorkout = Dictionary(
                grouping: try WorkoutItemRecord.fetchAll(db), by: \.workoutId)
            let setsByItem = Dictionary(
                grouping: try WorkoutSetRecord.fetchAll(db), by: \.workoutItemId)

            return try WorkoutRecord
                .order(Column("startedAt"))
                .fetchAll(db)
                .map { workout in
                    let items = (itemsByWorkout[workout.id] ?? []).sorted { $0.position < $1.position }
                    let exercises = items.map { item in
                        let exercise = exercisesById[item.exerciseId]
                        let sets = (setsByItem[item.id] ?? [])
                            .sorted { $0.position < $1.position }
                            .map { LoadedSet(id: $0.id, position: $0.position,
                                             isWarmup: $0.isWarmup, weight: $0.weight,
                                             reps: $0.reps, seconds: $0.seconds) }
                        return LoadedExercise(
                            id: item.id,
                            exerciseId: item.exerciseId,
                            name: exercise?.name ?? "Unknown",
                            kind: exercise.flatMap { ExerciseKind(rawValue: $0.kind) } ?? .bodyweight,
                            restSeconds: item.restSeconds,
                            sets: sets)
                    }
                    return LoadedWorkout(id: workout.id, name: workout.name,
                                         startedAt: workout.startedAt,
                                         finishedAt: workout.finishedAt,
                                         exercises: exercises)
                }
        }
    }
}
