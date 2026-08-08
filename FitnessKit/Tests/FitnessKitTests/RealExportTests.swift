import Foundation
import GRDB
import Testing
@testable import FitnessKit

/// Integration tests against the owner's real Strong export. The file is
/// gitignored (personal data), so these tests skip cleanly when it's absent —
/// e.g. on CI or another machine.
@Suite struct RealExportTests {
    static var exportURL: URL {
        // Tests/FitnessKitTests/RealExportTests.swift -> repo root is four levels up.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("data/strong_workouts.csv")
    }

    @Test func parsesFullExport() throws {
        guard let text = try? String(contentsOf: Self.exportURL, encoding: .utf8) else {
            return  // real export not present on this machine
        }
        let workouts = try StrongImport.parse(csv: text)

        #expect(workouts.count == 736)
        #expect(workouts.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } } == 12596)

        let exerciseNames = Set(workouts.flatMap { $0.exercises.map(\.name) })
        #expect(exerciseNames.count == 91)

        // Chronological order preserved end to end.
        #expect(workouts.first!.startedAt < workouts.last!.startedAt)
    }

    @Test func importsFullExportAndComputesRecords() throws {
        guard let text = try? String(contentsOf: Self.exportURL, encoding: .utf8) else {
            return
        }
        let workouts = try StrongImport.parse(csv: text)
        let db = try AppDatabase.inMemory()
        let summary = try StrongImporter.run(workouts, into: db)

        #expect(summary.workoutsImported == 736)
        #expect(summary.setsImported == 12596)
        #expect(summary.exercisesCreated == 91)

        // Best bench e1RM must exist and be plausible — this is the intensity
        // ring's baseline, the number the whole app hangs off.
        let bestBench = try db.read { d -> Double in
            let rows = try Row.fetchAll(d, sql: """
                SELECT ws.weight, ws.reps FROM workoutSet ws
                JOIN workoutItem wi ON wi.id = ws.workoutItemId
                JOIN exercise e ON e.id = wi.exerciseId
                WHERE e.name = 'Bench Press (Barbell)' AND ws.weight IS NOT NULL AND ws.reps IS NOT NULL
                """)
            return rows.compactMap { row in
                Strength.estimatedOneRepMax(weight: row["weight"], reps: row["reps"])
            }.max() ?? 0
        }
        #expect(bestBench > 100)
        #expect(bestBench < 1000)
    }
}
