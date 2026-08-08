import Foundation

public struct ImportedSet: Equatable, Sendable {
    public var position: Int
    public var weight: Double?
    public var reps: Int?
    public var seconds: Double?
    public var distance: Double?
    public var notes: String?

    public init(position: Int, weight: Double? = nil, reps: Int? = nil,
                seconds: Double? = nil, distance: Double? = nil, notes: String? = nil) {
        self.position = position
        self.weight = weight
        self.reps = reps
        self.seconds = seconds
        self.distance = distance
        self.notes = notes
    }
}

public struct ImportedExercise: Equatable, Sendable {
    public var name: String
    public var sets: [ImportedSet]

    public init(name: String, sets: [ImportedSet]) {
        self.name = name
        self.sets = sets
    }
}

public struct ImportedWorkout: Equatable, Sendable {
    public var startedAt: Date
    public var name: String
    public var durationSeconds: Int?
    public var notes: String?
    public var exercises: [ImportedExercise]

    public init(startedAt: Date, name: String, durationSeconds: Int? = nil,
                notes: String? = nil, exercises: [ImportedExercise]) {
        self.startedAt = startedAt
        self.name = name
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.exercises = exercises
    }
}
