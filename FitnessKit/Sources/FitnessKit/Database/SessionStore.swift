import Foundation
import GRDB

/// Database operations for a live workout session. The app keeps the session in
/// memory and writes through here on every mutation, so an in-progress workout
/// survives app termination (PRD: resume + auto-timeout).
public enum SessionStore {
    /// A planned exercise in a freshly started workout, with the previous
    /// session's numbers to chase.
    public struct StartedExercise: Sendable {
        public let item: WorkoutItemRecord
        public let sets: [WorkoutSetRecord]
        public let previous: [LoadedSet]
    }

    public struct StartedWorkout: Sendable {
        public let workout: WorkoutRecord
        public let exercises: [StartedExercise]
    }

    /// The most recent unfinished workout, if any.
    public static func activeWorkoutId(in dbQueue: DatabaseQueue) throws -> String? {
        try dbQueue.read { db in
            try WorkoutRecord
                .filter(Column("finishedAt") == nil)
                .order(Column("startedAt").desc)
                .fetchOne(db)?.id
        }
    }

    /// The working (non-warm-up) sets of the most recent finished workout that
    /// included this exercise — the numbers shown in the "previous" column.
    public static func previousWorkingSets(exerciseId: String, in db: Database) throws -> [LoadedSet] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT ws.* FROM workoutSet ws
            JOIN workoutItem wi ON wi.id = ws.workoutItemId
            JOIN workout w ON w.id = wi.workoutId
            WHERE wi.exerciseId = ? AND w.finishedAt IS NOT NULL
              AND w.startedAt = (
                SELECT MAX(w2.startedAt) FROM workout w2
                JOIN workoutItem wi2 ON wi2.workoutId = w2.id
                WHERE wi2.exerciseId = ? AND w2.finishedAt IS NOT NULL)
              AND ws.isWarmup = 0
            ORDER BY ws.position
            """, arguments: [exerciseId, exerciseId])
        return rows.map { row in
            LoadedSet(id: row["id"], position: row["position"], isWarmup: false,
                      weight: row["weight"], reps: row["reps"], seconds: row["seconds"])
        }
    }

    /// Starts a workout. From a template: one item per template exercise with
    /// its rest time, and planned sets prefilled from the previous session
    /// (falling back to the template's target set count). Empty start: no items.
    public static func start(template: TemplateSummary?, name: String,
                             at startedAt: Date = Date(),
                             into dbQueue: DatabaseQueue) throws -> StartedWorkout {
        try dbQueue.write { db in
            let workout = WorkoutRecord(templateId: template?.id, name: name, startedAt: startedAt)
            try workout.insert(db)

            var exercises: [StartedExercise] = []
            for (index, item) in (template?.items ?? []).enumerated() {
                let previous = try previousWorkingSets(exerciseId: item.exerciseId, in: db)
                let itemRecord = WorkoutItemRecord(workoutId: workout.id,
                                                   exerciseId: item.exerciseId,
                                                   position: index + 1,
                                                   restSeconds: item.restSeconds)
                try itemRecord.insert(db)

                let setCount = max(previous.count, item.targetSetCount, 1)
                var sets: [WorkoutSetRecord] = []
                for position in 1...setCount {
                    let prev = position <= previous.count ? previous[position - 1] : previous.last
                    let set = WorkoutSetRecord(workoutItemId: itemRecord.id,
                                               position: position,
                                               weight: prev?.weight,
                                               reps: prev?.reps)
                    try set.insert(db)
                    sets.append(set)
                }
                exercises.append(StartedExercise(item: itemRecord, sets: sets, previous: previous))
            }
            return StartedWorkout(workout: workout, exercises: exercises)
        }
    }

    /// Loads an unfinished workout back into session shape (app relaunch).
    public static func resume(workoutId: String, from dbQueue: DatabaseQueue) throws -> StartedWorkout? {
        try dbQueue.read { db in
            guard let workout = try WorkoutRecord.fetchOne(db, key: workoutId) else { return nil }
            let items = try WorkoutItemRecord
                .filter(Column("workoutId") == workoutId)
                .order(Column("position"))
                .fetchAll(db)
            let exercises = try items.map { item in
                let sets = try WorkoutSetRecord
                    .filter(Column("workoutItemId") == item.id)
                    .order(Column("position"))
                    .fetchAll(db)
                return StartedExercise(item: item,
                                       sets: sets,
                                       previous: try previousWorkingSets(exerciseId: item.exerciseId, in: db))
            }
            return StartedWorkout(workout: workout, exercises: exercises)
        }
    }

    // MARK: - Write-through mutations

    public static func upsertSet(_ set: WorkoutSetRecord, in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { try set.save($0) }
    }

    public static func deleteSet(id: String, in dbQueue: DatabaseQueue) throws {
        _ = try dbQueue.write { try WorkoutSetRecord.deleteOne($0, key: id) }
    }

    public static func insertItem(_ item: WorkoutItemRecord, in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { try item.insert($0) }
    }

    public static func deleteItem(id: String, in dbQueue: DatabaseQueue) throws {
        _ = try dbQueue.write { try WorkoutItemRecord.deleteOne($0, key: id) }
    }

    /// Finishing deletes never-completed planned sets, stamps finishedAt, and
    /// removes exercises left with no sets.
    public static func finish(workoutId: String, at finishedAt: Date = Date(),
                              in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM workoutSet WHERE completedAt IS NULL AND workoutItemId IN
                  (SELECT id FROM workoutItem WHERE workoutId = ?)
                """, arguments: [workoutId])
            try db.execute(sql: """
                DELETE FROM workoutItem WHERE workoutId = ? AND id NOT IN
                  (SELECT DISTINCT workoutItemId FROM workoutSet)
                """, arguments: [workoutId])
            if var workout = try WorkoutRecord.fetchOne(db, key: workoutId) {
                workout.finishedAt = finishedAt
                try workout.update(db)
            }
        }
    }

    public static func discard(workoutId: String, in dbQueue: DatabaseQueue) throws {
        _ = try dbQueue.write { try WorkoutRecord.deleteOne($0, key: workoutId) }
    }
}
