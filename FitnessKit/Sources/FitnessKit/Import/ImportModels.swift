import Foundation

public struct ImportedSet: Equatable, Sendable {
    public var position: Int
    public var isWarmup: Bool
    public var weight: Double?
    public var reps: Int?
    public var seconds: Double?
    public var distance: Double?
    public var notes: String?

    public init(position: Int, isWarmup: Bool = false, weight: Double? = nil, reps: Int? = nil,
                seconds: Double? = nil, distance: Double? = nil, notes: String? = nil) {
        self.position = position
        self.isWarmup = isWarmup
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
    /// Rest duration from Strong's "Rest Timer" rows — the user's configured
    /// per-exercise rest, which later seeds template rest times.
    public var restSeconds: Int?

    public init(name: String, sets: [ImportedSet], restSeconds: Int? = nil) {
        self.name = name
        self.sets = sets
        self.restSeconds = restSeconds
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
