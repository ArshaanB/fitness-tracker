import Foundation

public enum StrongImportError: Error, Equatable {
    case emptyFile
    case missingColumns([String])
}

/// Parses a Strong app CSV export ("Export workouts" in Strong's settings) into
/// domain objects. Pure function: CSV text in, workouts out, no I/O.
public enum StrongImport {
    static let requiredColumns = [
        "Date", "Workout Name", "Duration", "Exercise Name", "Set Order",
        "Weight", "Reps", "Distance", "Seconds",
    ]

    public static func parse(csv text: String) throws -> [ImportedWorkout] {
        let rows = CSV.parse(text)
        guard let header = rows.first else { throw StrongImportError.emptyFile }

        var col: [String: Int] = [:]
        for (i, name) in header.enumerated() {
            col[name.trimmingCharacters(in: .whitespaces)] = i
        }
        let missing = requiredColumns.filter { col[$0] == nil }
        guard missing.isEmpty else { throw StrongImportError.missingColumns(missing) }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        dateFormatter.timeZone = .current

        func field(_ row: [String], _ name: String) -> String {
            guard let i = col[name], i < row.count else { return "" }
            return row[i]
        }
        func positiveDouble(_ s: String) -> Double? {
            guard let v = Double(s), v > 0 else { return nil }
            return v
        }

        // A workout is identified by (date, workout name). Preserve first-seen
        // order for workouts and for exercises within a workout.
        struct WorkoutKey: Hashable {
            let date: String
            let name: String
        }
        var order: [WorkoutKey] = []
        var workoutsByKey: [WorkoutKey: ImportedWorkout] = [:]
        var exerciseIndexByKey: [WorkoutKey: [String: Int]] = [:]

        for row in rows.dropFirst() {
            let dateString = field(row, "Date")
            let exerciseName = field(row, "Exercise Name")
            guard !dateString.isEmpty, !exerciseName.isEmpty,
                  let date = dateFormatter.date(from: dateString) else { continue }

            let key = WorkoutKey(date: dateString, name: field(row, "Workout Name"))
            if workoutsByKey[key] == nil {
                order.append(key)
                workoutsByKey[key] = ImportedWorkout(
                    startedAt: date,
                    name: key.name,
                    durationSeconds: durationSeconds(field(row, "Duration")),
                    exercises: []
                )
                exerciseIndexByKey[key] = [:]
            }

            let workoutNotes = field(row, "Workout Notes")
            if !workoutNotes.isEmpty, workoutsByKey[key]?.notes == nil {
                workoutsByKey[key]?.notes = workoutNotes
            }

            let position: Int
            if let orderValue = Double(field(row, "Set Order")) {
                position = Int(orderValue)
            } else {
                position = (exerciseIndexByKey[key]?[exerciseName]).map {
                    workoutsByKey[key]!.exercises[$0].sets.count + 1
                } ?? 1
            }
            let notes = field(row, "Notes")
            let set = ImportedSet(
                position: position,
                weight: positiveDouble(field(row, "Weight")),
                reps: positiveDouble(field(row, "Reps")).map { Int($0) },
                seconds: positiveDouble(field(row, "Seconds")),
                distance: positiveDouble(field(row, "Distance")),
                notes: notes.isEmpty ? nil : notes
            )

            if let i = exerciseIndexByKey[key]?[exerciseName] {
                workoutsByKey[key]?.exercises[i].sets.append(set)
            } else {
                exerciseIndexByKey[key]?[exerciseName] = workoutsByKey[key]!.exercises.count
                workoutsByKey[key]?.exercises.append(ImportedExercise(name: exerciseName, sets: [set]))
            }
        }

        return order.compactMap { workoutsByKey[$0] }.sorted { $0.startedAt < $1.startedAt }
    }

    /// Strong duration strings look like "1h 5m", "45m", "2h".
    static func durationSeconds(_ s: String) -> Int? {
        var total = 0
        var matched = false
        if let h = s.firstMatch(of: /(\d+)\s*h/) {
            total += (Int(h.1) ?? 0) * 3600
            matched = true
        }
        if let m = s.firstMatch(of: /(\d+)\s*m/) {
            total += (Int(m.1) ?? 0) * 60
            matched = true
        }
        if let sec = s.firstMatch(of: /(\d+)\s*s/) {
            total += Int(sec.1) ?? 0
            matched = true
        }
        return matched ? total : nil
    }
}
