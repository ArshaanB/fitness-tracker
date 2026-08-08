import Foundation
import Testing
@testable import FitnessKit

@Suite struct CSVTests {
    @Test func parsesQuotedFieldsWithCommas() {
        let rows = CSV.parse("a,\"b, with comma\",c\n1,2,3\n")
        #expect(rows == [["a", "b, with comma", "c"], ["1", "2", "3"]])
    }

    @Test func parsesEscapedQuotes() {
        let rows = CSV.parse("\"say \"\"hi\"\"\",x\n")
        #expect(rows == [["say \"hi\"", "x"]])
    }

    @Test func handlesCRLFAndMissingTrailingNewline() {
        let rows = CSV.parse("a,b\r\n1,2")
        #expect(rows == [["a", "b"], ["1", "2"]])
    }
}

@Suite struct DurationTests {
    @Test func parsesHoursAndMinutes() {
        #expect(StrongImport.durationSeconds("1h 5m") == 3900)
        #expect(StrongImport.durationSeconds("45m") == 2700)
        #expect(StrongImport.durationSeconds("2h") == 7200)
        #expect(StrongImport.durationSeconds("30s") == 30)
        #expect(StrongImport.durationSeconds("") == nil)
    }
}

@Suite struct StrengthTests {
    @Test func epley() {
        #expect(Strength.estimatedOneRepMax(weight: 225, reps: 8) == 285)
        let single: Double = 245 * (1 + 1.0 / 30)
        #expect(Strength.estimatedOneRepMax(weight: 245, reps: 1) == single)
        #expect(Strength.estimatedOneRepMax(weight: 0, reps: 8) == nil)
        #expect(Strength.estimatedOneRepMax(weight: 100, reps: 0) == nil)
    }

    @Test func ringZones() {
        #expect(Strength.ringZone(e1RM: 100, bestE1RM: 290) == .low)
        #expect(Strength.ringZone(e1RM: 232, bestE1RM: 290) == .mid)     // 80%
        #expect(Strength.ringZone(e1RM: 275, bestE1RM: 290) == .high)    // ~95%
        #expect(Strength.ringZone(e1RM: 290, bestE1RM: 290) == .personalRecord)
        #expect(Strength.ringZone(e1RM: 297, bestE1RM: 290) == .personalRecord)
    }
}

@Suite struct ExerciseKindTests {
    @Test func inference() {
        #expect(ExerciseKind.infer(fromStrongName: "Bench Press (Barbell)") == .barbell)
        #expect(ExerciseKind.infer(fromStrongName: "Bicep Curl (Dumbbell)") == .dumbbell)
        #expect(ExerciseKind.infer(fromStrongName: "Triceps Extension (Cable)") == .machine)
        #expect(ExerciseKind.infer(fromStrongName: "Running (Treadmill)") == .machine)
        #expect(ExerciseKind.infer(fromStrongName: "Pull Up") == .bodyweight)
        #expect(ExerciseKind.infer(fromStrongName: "Push Up") == .bodyweight)
    }
}

let sampleCSV = """
Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
2026-08-08 09:02:00,"Push Day",51m,"Bench Press (Barbell)",W,135.0,5.0,0,0.0,,,
2026-08-08 09:02:00,"Push Day",51m,"Bench Press (Barbell)",1,205.0,8.0,0,0.0,"","felt strong",
2026-08-08 09:02:00,"Push Day",51m,"Bench Press (Barbell)",Rest Timer,0,0.0,0,90.0,,,
2026-08-08 09:02:00,"Push Day",51m,"Bench Press (Barbell)",2,215.0,8.0,0,0.0,,,
2026-08-08 09:02:00,"Push Day",51m,"Bench Press (Barbell)",Rest Timer,0,0.0,0,90.0,,,
2026-08-08 09:02:00,"Push Day",51m,"Pull Up",1,0.0,10.0,0,0.0,"slow negatives",,
2026-08-08 09:02:00,"Push Day",51m,"Plank",1,0.0,0.0,0,60.0,,,
2026-08-06 08:47:00,"Pull Day",1h 2m,"Deadlift (Barbell)",1,315.0,5.0,0,0.0,,,
"""

@Suite struct StrongParseTests {
    @Test func parsesSampleExport() throws {
        let workouts = try StrongImport.parse(csv: sampleCSV)
        #expect(workouts.count == 2)

        // Sorted ascending by date.
        #expect(workouts[0].name == "Pull Day")
        #expect(workouts[0].durationSeconds == 3720)

        let push = workouts[1]
        #expect(push.name == "Push Day")
        #expect(push.durationSeconds == 3060)
        #expect(push.notes == "felt strong")
        #expect(push.exercises.count == 3)

        let bench = push.exercises[0]
        #expect(bench.name == "Bench Press (Barbell)")
        #expect(bench.sets.count == 3)  // W + 2 working; Rest Timer rows are not sets
        #expect(bench.restSeconds == 90)
        #expect(bench.sets[0].isWarmup)
        #expect(bench.sets[0].weight == 135)
        #expect(bench.sets.map(\.position) == [1, 2, 3])
        #expect(bench.sets[1].weight == 205)
        #expect(bench.sets[1].reps == 8)
        #expect(bench.sets[1].isWarmup == false)

        let pullUp = push.exercises[1]
        #expect(pullUp.sets[0].weight == nil)  // bodyweight: zero weight becomes nil
        #expect(pullUp.sets[0].reps == 10)
        #expect(pullUp.sets[0].notes == "slow negatives")

        let plank = push.exercises[2]
        #expect(plank.sets[0].reps == nil)
        #expect(plank.sets[0].seconds == 60)
    }

    @Test func rejectsUnknownFormat() {
        #expect(throws: StrongImportError.self) {
            try StrongImport.parse(csv: "Foo,Bar\n1,2\n")
        }
    }
}

@Suite struct ImporterTests {
    @Test func importsAndIsIdempotent() throws {
        let db = try AppDatabase.inMemory()
        let workouts = try StrongImport.parse(csv: sampleCSV)

        let first = try StrongImporter.run(workouts, into: db)
        #expect(first.workoutsImported == 2)
        #expect(first.workoutsSkipped == 0)
        #expect(first.setsImported == 6)
        #expect(first.exercisesCreated == 4)

        let second = try StrongImporter.run(workouts, into: db)
        #expect(second.workoutsImported == 0)
        #expect(second.workoutsSkipped == 2)
        #expect(second.setsImported == 0)

        let (workoutCount, setCount, exerciseCount) = try db.read { d in
            (try WorkoutRecord.fetchCount(d),
             try WorkoutSetRecord.fetchCount(d),
             try ExerciseRecord.fetchCount(d))
        }
        #expect(workoutCount == 2)
        #expect(setCount == 6)
        #expect(exerciseCount == 4)
    }
}
