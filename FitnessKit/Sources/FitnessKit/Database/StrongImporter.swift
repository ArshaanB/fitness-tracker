import Foundation
import GRDB

public struct ImportSummary: Equatable, Sendable {
    public var workoutsImported: Int
    public var workoutsSkipped: Int
    public var setsImported: Int
    public var exercisesCreated: Int
}

/// Writes parsed Strong workouts into the database. Idempotent: a workout whose
/// (startedAt, name) already exists is skipped, so re-running an import is safe.
public enum StrongImporter {
    @discardableResult
    public static func run(_ workouts: [ImportedWorkout], into dbQueue: DatabaseQueue) throws -> ImportSummary {
        try dbQueue.write { db in
            var summary = ImportSummary(workoutsImported: 0, workoutsSkipped: 0,
                                        setsImported: 0, exercisesCreated: 0)

            var exerciseIds: [String: String] = [:]
            for exercise in try ExerciseRecord.fetchAll(db) {
                exerciseIds[exercise.name] = exercise.id
            }

            for workout in workouts {
                let exists = try WorkoutRecord
                    .filter(Column("startedAt") == workout.startedAt && Column("name") == workout.name)
                    .fetchCount(db) > 0
                if exists {
                    summary.workoutsSkipped += 1
                    continue
                }

                let finishedAt = workout.durationSeconds.map {
                    workout.startedAt.addingTimeInterval(TimeInterval($0))
                }
                let workoutRecord = WorkoutRecord(name: workout.name,
                                                  startedAt: workout.startedAt,
                                                  finishedAt: finishedAt,
                                                  notes: workout.notes)
                try workoutRecord.insert(db)
                summary.workoutsImported += 1

                for (index, exercise) in workout.exercises.enumerated() {
                    let exerciseId: String
                    if let id = exerciseIds[exercise.name] {
                        exerciseId = id
                    } else {
                        let record = ExerciseRecord(name: exercise.name,
                                                    kind: ExerciseKind.infer(fromStrongName: exercise.name))
                        try record.insert(db)
                        exerciseIds[exercise.name] = record.id
                        exerciseId = record.id
                        summary.exercisesCreated += 1
                    }

                    let item = WorkoutItemRecord(workoutId: workoutRecord.id,
                                                 exerciseId: exerciseId,
                                                 position: index + 1,
                                                 restSeconds: exercise.restSeconds)
                    try item.insert(db)

                    for set in exercise.sets {
                        try WorkoutSetRecord(workoutItemId: item.id,
                                             position: set.position,
                                             isWarmup: set.isWarmup,
                                             weight: set.weight,
                                             reps: set.reps,
                                             seconds: set.seconds,
                                             distance: set.distance,
                                             notes: set.notes,
                                             completedAt: workout.startedAt).insert(db)
                        summary.setsImported += 1
                    }
                }
            }
            return summary
        }
    }
}
