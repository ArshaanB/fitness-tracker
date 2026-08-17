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
        // One specific workout, then one specific item within it: never merge
        // sets across tied-timestamp workouts or across duplicate items for
        // the same exercise in one workout.
        guard let workoutId = try String.fetchOne(db, sql: """
            SELECT w.id FROM workout w
            WHERE w.finishedAt IS NOT NULL AND EXISTS (
              SELECT 1 FROM workoutItem wi
              WHERE wi.workoutId = w.id AND wi.exerciseId = ?)
            ORDER BY w.startedAt DESC, w.id DESC
            LIMIT 1
            """, arguments: [exerciseId]) else { return [] }
        guard let itemId = try String.fetchOne(db, sql: """
            SELECT id FROM workoutItem
            WHERE workoutId = ? AND exerciseId = ?
            ORDER BY position DESC
            LIMIT 1
            """, arguments: [workoutId, exerciseId]) else { return [] }
        let rows = try Row.fetchAll(db, sql: """
            SELECT * FROM workoutSet
            WHERE workoutItemId = ? AND isWarmup = 0
            ORDER BY position
            """, arguments: [itemId])
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
            // Only one active session ever exists by design. Unfinished
            // workouts stranded by crashes/kills are invisible to every view,
            // so clean them up rather than let ghost rows accumulate (and sync).
            try db.execute(sql: "DELETE FROM workout WHERE finishedAt IS NULL")

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

    /// Starts a workout that re-performs a past one: the same exercises in the
    /// same order with the same rest times, and every planned set prefilled
    /// with that workout's lifts (warm-ups included).
    public static func start(repeating source: LoadedWorkout, name: String,
                             at startedAt: Date = Date(),
                             into dbQueue: DatabaseQueue) throws -> StartedWorkout {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM workout WHERE finishedAt IS NULL")

            let workout = WorkoutRecord(templateId: nil, name: name, startedAt: startedAt)
            try workout.insert(db)

            var exercises: [StartedExercise] = []
            for (index, exercise) in source.exercises.enumerated() {
                let itemRecord = WorkoutItemRecord(workoutId: workout.id,
                                                   exerciseId: exercise.exerciseId,
                                                   position: index + 1,
                                                   restSeconds: exercise.restSeconds)
                try itemRecord.insert(db)

                var sets: [WorkoutSetRecord] = []
                for (setIndex, sourceSet) in exercise.sets.enumerated() {
                    let set = WorkoutSetRecord(workoutItemId: itemRecord.id,
                                               position: setIndex + 1,
                                               isWarmup: sourceSet.isWarmup,
                                               weight: sourceSet.weight,
                                               reps: sourceSet.reps)
                    try set.insert(db)
                    sets.append(set)
                }
                if sets.isEmpty {
                    let set = WorkoutSetRecord(workoutItemId: itemRecord.id, position: 1)
                    try set.insert(db)
                    sets.append(set)
                }
                exercises.append(StartedExercise(
                    item: itemRecord, sets: sets,
                    previous: try previousWorkingSets(exerciseId: exercise.exerciseId, in: db)))
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

    /// Persists a drag-reorder of a workout's exercises in one write.
    public static func updateItemPositions(_ positions: [(id: String, position: Int)],
                                           in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            for (id, position) in positions {
                try db.execute(sql: "UPDATE workoutItem SET position = ? WHERE id = ?",
                               arguments: [position, id])
            }
        }
    }

    /// Finishing deletes never-completed planned sets and exercises left with
    /// no sets, then stamps finishedAt.
    ///
    /// Returns false — after deleting the whole workout — when no completed
    /// sets remain: an empty workout must not pollute history. Otherwise
    /// returns true; if `finishedAt` is more than an hour after the last
    /// completed set (a stale session finished from the recovery prompt), the
    /// last set's completedAt is stored instead so the recorded duration
    /// isn't inflated.
    @discardableResult
    public static func finish(workoutId: String, at finishedAt: Date = Date(),
                              in dbQueue: DatabaseQueue) throws -> Bool {
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM workoutSet WHERE completedAt IS NULL AND workoutItemId IN
                  (SELECT id FROM workoutItem WHERE workoutId = ?)
                """, arguments: [workoutId])
            try db.execute(sql: """
                DELETE FROM workoutItem WHERE workoutId = ? AND id NOT IN
                  (SELECT DISTINCT workoutItemId FROM workoutSet)
                """, arguments: [workoutId])

            let remainingSets = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM workoutSet WHERE workoutItemId IN
                  (SELECT id FROM workoutItem WHERE workoutId = ?)
                """, arguments: [workoutId]) ?? 0
            if remainingSets == 0 {
                _ = try WorkoutRecord.deleteOne(db, key: workoutId)
                return false
            }

            // All surviving sets have completedAt (the NULLs were just deleted).
            let maxCompleted = try Date.fetchOne(db, sql: """
                SELECT MAX(completedAt) FROM workoutSet WHERE workoutItemId IN
                  (SELECT id FROM workoutItem WHERE workoutId = ?)
                """, arguments: [workoutId])
            var stamp = finishedAt
            if let maxCompleted, finishedAt.timeIntervalSince(maxCompleted) > 3600 {
                stamp = maxCompleted
            }
            if var workout = try WorkoutRecord.fetchOne(db, key: workoutId) {
                workout.finishedAt = stamp
                try workout.update(db)
            }
            return true
        }
    }

    public static func discard(workoutId: String, in dbQueue: DatabaseQueue) throws {
        _ = try dbQueue.write { try WorkoutRecord.deleteOne($0, key: workoutId) }
    }
}
