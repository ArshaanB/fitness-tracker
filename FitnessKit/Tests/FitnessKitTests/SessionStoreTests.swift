import Foundation
import GRDB
import Testing
@testable import FitnessKit

/// Whole-second dates so values survive the SQLite datetime round-trip exactly.
private func date(_ secondsSince1970: TimeInterval) -> Date {
    Date(timeIntervalSince1970: secondsSince1970.rounded())
}

private let t0 = date(1_750_000_000)

private func insertExercise(_ name: String, in dbQueue: DatabaseQueue) throws -> String {
    let record = ExerciseRecord(name: name, kind: .barbell)
    try dbQueue.write { try record.insert($0) }
    return record.id
}

@discardableResult
private func insertWorkout(id: String = UUID().uuidString, name: String,
                           startedAt: Date, finishedAt: Date?,
                           in dbQueue: DatabaseQueue) throws -> String {
    let record = WorkoutRecord(id: id, name: name, startedAt: startedAt, finishedAt: finishedAt)
    try dbQueue.write { try record.insert($0) }
    return record.id
}

@discardableResult
private func insertItem(workoutId: String, exerciseId: String, position: Int,
                        in dbQueue: DatabaseQueue) throws -> String {
    let record = WorkoutItemRecord(workoutId: workoutId, exerciseId: exerciseId, position: position)
    try dbQueue.write { try record.insert($0) }
    return record.id
}

@discardableResult
private func insertSet(itemId: String, position: Int, isWarmup: Bool = false,
                       weight: Double?, reps: Int? = 5, completedAt: Date?,
                       in dbQueue: DatabaseQueue) throws -> String {
    let record = WorkoutSetRecord(workoutItemId: itemId, position: position, isWarmup: isWarmup,
                                  weight: weight, reps: reps, completedAt: completedAt)
    try dbQueue.write { try record.insert($0) }
    return record.id
}

@Suite struct SessionFinishTests {
    @Test func finishWithZeroCompletedSetsDeletesWorkout() throws {
        let db = try AppDatabase.inMemory()
        let exerciseId = try insertExercise("Bench Press (Barbell)", in: db)
        let workoutId = try insertWorkout(name: "Push", startedAt: t0, finishedAt: nil, in: db)
        let itemId = try insertItem(workoutId: workoutId, exerciseId: exerciseId, position: 1, in: db)
        try insertSet(itemId: itemId, position: 1, weight: 135, completedAt: nil, in: db)
        try insertSet(itemId: itemId, position: 2, weight: 135, completedAt: nil, in: db)

        let survived = try SessionStore.finish(workoutId: workoutId, at: date(1_750_003_600), in: db)
        #expect(survived == false)

        let (workouts, items, sets) = try db.read { d in
            (try WorkoutRecord.fetchCount(d),
             try WorkoutItemRecord.fetchCount(d),
             try WorkoutSetRecord.fetchCount(d))
        }
        #expect(workouts == 0)
        #expect(items == 0)
        #expect(sets == 0)
    }

    @Test func finishEmptyStartedWorkoutDeletesIt() throws {
        let db = try AppDatabase.inMemory()
        let started = try SessionStore.start(template: nil, name: "Empty", at: t0, into: db)
        let survived = try SessionStore.finish(workoutId: started.workout.id, in: db)
        #expect(survived == false)
        let workouts = try db.read { try WorkoutRecord.fetchCount($0) }
        #expect(workouts == 0)
    }

    @Test func finishStaleUsesLastCompletedSetTimestamp() throws {
        let db = try AppDatabase.inMemory()
        let exerciseId = try insertExercise("Squat (Barbell)", in: db)
        let workoutId = try insertWorkout(name: "Legs", startedAt: t0, finishedAt: nil, in: db)
        let itemId = try insertItem(workoutId: workoutId, exerciseId: exerciseId, position: 1, in: db)
        let lastCompleted = date(1_750_001_800)  // t0 + 30 min
        try insertSet(itemId: itemId, position: 1, weight: 225, completedAt: date(1_750_000_600), in: db)
        try insertSet(itemId: itemId, position: 2, weight: 225, completedAt: lastCompleted, in: db)
        try insertSet(itemId: itemId, position: 3, weight: 225, completedAt: nil, in: db)

        // "Finished" 8 hours later from the stale-session prompt.
        let survived = try SessionStore.finish(workoutId: workoutId, at: date(1_750_028_800), in: db)
        #expect(survived == true)

        let workout = try db.read { try WorkoutRecord.fetchOne($0, key: workoutId) }
        #expect(workout?.finishedAt == lastCompleted)
        let sets = try db.read { try WorkoutSetRecord.fetchCount($0) }
        #expect(sets == 2)  // the never-completed planned set was pruned
    }

    @Test func finishRecentKeepsGivenTimestamp() throws {
        let db = try AppDatabase.inMemory()
        let exerciseId = try insertExercise("Deadlift (Barbell)", in: db)
        let workoutId = try insertWorkout(name: "Pull", startedAt: t0, finishedAt: nil, in: db)
        let itemId = try insertItem(workoutId: workoutId, exerciseId: exerciseId, position: 1, in: db)
        try insertSet(itemId: itemId, position: 1, weight: 315, completedAt: date(1_750_001_800), in: db)

        let finishedAt = date(1_750_002_400)  // 10 min after the last set: not stale
        let survived = try SessionStore.finish(workoutId: workoutId, at: finishedAt, in: db)
        #expect(survived == true)

        let workout = try db.read { try WorkoutRecord.fetchOne($0, key: workoutId) }
        #expect(workout?.finishedAt == finishedAt)
    }
}

@Suite struct PreviousWorkingSetsTests {
    @Test func picksOnlyTheLatestWorkoutsLatestItem() throws {
        let db = try AppDatabase.inMemory()
        let exerciseId = try insertExercise("Bench Press (Barbell)", in: db)

        // Older finished workout: must be ignored.
        let older = try insertWorkout(name: "Push A", startedAt: date(1_749_900_000),
                                      finishedAt: date(1_749_903_600), in: db)
        let olderItem = try insertItem(workoutId: older, exerciseId: exerciseId, position: 1, in: db)
        try insertSet(itemId: olderItem, position: 1, weight: 100, completedAt: date(1_749_900_600), in: db)

        // Tied-timestamp finished workout with a LOWER id: id DESC must break the tie.
        let tiedLowId = try insertWorkout(id: "aaaaaaaa-tied", name: "Push tied",
                                          startedAt: t0, finishedAt: date(1_750_003_600), in: db)
        let tiedItem = try insertItem(workoutId: tiedLowId, exerciseId: exerciseId, position: 1, in: db)
        try insertSet(itemId: tiedItem, position: 1, weight: 111, completedAt: t0, in: db)

        // The winning workout: same startedAt, higher id. Contains the
        // exercise TWICE; only the highest-position item may be used.
        let latest = try insertWorkout(id: "zzzzzzzz-tied", name: "Push B",
                                       startedAt: t0, finishedAt: date(1_750_003_600), in: db)
        let firstSlot = try insertItem(workoutId: latest, exerciseId: exerciseId, position: 1, in: db)
        try insertSet(itemId: firstSlot, position: 1, weight: 135, completedAt: t0, in: db)
        let secondSlot = try insertItem(workoutId: latest, exerciseId: exerciseId, position: 3, in: db)
        try insertSet(itemId: secondSlot, position: 1, isWarmup: true, weight: 95,
                      completedAt: t0, in: db)
        try insertSet(itemId: secondSlot, position: 2, weight: 185, completedAt: t0, in: db)
        try insertSet(itemId: secondSlot, position: 3, weight: 190, completedAt: t0, in: db)

        // Newer but UNFINISHED workout: must be ignored.
        let unfinished = try insertWorkout(name: "Push C", startedAt: date(1_750_100_000),
                                           finishedAt: nil, in: db)
        let unfinishedItem = try insertItem(workoutId: unfinished, exerciseId: exerciseId,
                                            position: 1, in: db)
        try insertSet(itemId: unfinishedItem, position: 1, weight: 999, completedAt: nil, in: db)

        let previous = try db.read { d in
            try SessionStore.previousWorkingSets(exerciseId: exerciseId, in: d)
        }
        #expect(previous.map(\.weight) == [185, 190])  // second slot only, warm-up excluded
        #expect(previous.map(\.position) == [2, 3])
    }
}

@Suite struct SessionStartTests {
    @Test func startDeletesStrandedUnfinishedWorkouts() throws {
        let db = try AppDatabase.inMemory()
        try insertWorkout(name: "Stray 1", startedAt: date(1_749_900_000), finishedAt: nil, in: db)
        try insertWorkout(name: "Stray 2", startedAt: date(1_749_950_000), finishedAt: nil, in: db)
        let finished = try insertWorkout(name: "Done", startedAt: date(1_749_960_000),
                                         finishedAt: date(1_749_963_600), in: db)

        let started = try SessionStore.start(template: nil, name: "Fresh", at: t0, into: db)

        let ids = try db.read { try WorkoutRecord.fetchAll($0).map(\.id) }
        #expect(Set(ids) == Set([finished, started.workout.id]))
    }
}

@Suite struct ItemReorderTests {
    @Test func updateItemPositionsPersistsNewOrder() throws {
        let db = try AppDatabase.inMemory()
        let workout = try insertWorkout(name: "Legs", startedAt: t0, finishedAt: nil, in: db)
        let a = try insertItem(workoutId: workout, exerciseId: insertExercise("A", in: db),
                               position: 1, in: db)
        let b = try insertItem(workoutId: workout, exerciseId: insertExercise("B", in: db),
                               position: 2, in: db)
        let c = try insertItem(workoutId: workout, exerciseId: insertExercise("C", in: db),
                               position: 3, in: db)

        // C dragged to the top: c→1, a→2, b→3.
        try SessionStore.updateItemPositions([(c, 1), (a, 2), (b, 3)], in: db)

        let ordered = try db.read {
            try WorkoutItemRecord
                .filter(Column("workoutId") == workout)
                .order(Column("position"))
                .fetchAll($0)
                .map(\.id)
        }
        #expect(ordered == [c, a, b])
    }
}

@Suite struct WipeAllDataTests {
    @Test func wipeEmptiesEveryTableAndTheOutbox() throws {
        let db = try AppDatabase.inMemory()

        // Populate every synced table.
        let workouts = try StrongImport.parse(csv: sampleCSV)
        _ = try StrongImporter.run(workouts, into: db)
        let exerciseId = try db.read { try ExerciseRecord.fetchAll($0).first!.id }
        try TemplateStore.save(name: "Push Day",
                               items: [.init(exerciseId: exerciseId, restSeconds: 90, targetSetCount: 3)],
                               into: db)
        try BodyWeightStore.log(weight: 180, at: t0, in: db)
        _ = try SettingsStore.load(from: db)

        for table in AppDatabase.syncedTables {
            let count = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
            #expect(count > 0, "expected seed data in \(table)")
        }
        let outboxBefore = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") ?? 0 }
        #expect(outboxBefore > 0)

        try AppDatabase.wipeAllData(in: db)

        for table in AppDatabase.syncedTables {
            let count = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM \(table)") ?? 0 }
            #expect(count == 0, "expected \(table) to be empty after wipe")
        }
        let outboxAfter = try db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox") ?? 0 }
        #expect(outboxAfter == 0)
    }
}
