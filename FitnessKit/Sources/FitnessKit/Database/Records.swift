import Foundation
import GRDB

public struct ExerciseRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "exercise"
    public var id: String
    public var name: String
    public var kind: String

    public init(id: String = UUID().uuidString, name: String, kind: ExerciseKind) {
        self.id = id
        self.name = name
        self.kind = kind.rawValue
    }
}

public struct WorkoutRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workout"
    public var id: String
    public var templateId: String?
    public var name: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var notes: String?

    public init(id: String = UUID().uuidString, templateId: String? = nil, name: String,
                startedAt: Date, finishedAt: Date? = nil, notes: String? = nil) {
        self.id = id
        self.templateId = templateId
        self.name = name
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.notes = notes
    }
}

public struct WorkoutItemRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workoutItem"
    public var id: String
    public var workoutId: String
    public var exerciseId: String
    public var position: Int
    public var supersetGroup: Int?
    public var restSeconds: Int?

    public init(id: String = UUID().uuidString, workoutId: String, exerciseId: String,
                position: Int, supersetGroup: Int? = nil, restSeconds: Int? = nil) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseId = exerciseId
        self.position = position
        self.supersetGroup = supersetGroup
        self.restSeconds = restSeconds
    }
}

public struct WorkoutSetRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "workoutSet"
    public var id: String
    public var workoutItemId: String
    public var position: Int
    public var isWarmup: Bool
    public var weight: Double?
    public var reps: Int?
    public var seconds: Double?
    public var distance: Double?
    public var notes: String?
    public var completedAt: Date?

    public init(id: String = UUID().uuidString, workoutItemId: String, position: Int,
                isWarmup: Bool = false, weight: Double? = nil, reps: Int? = nil,
                seconds: Double? = nil, distance: Double? = nil, notes: String? = nil,
                completedAt: Date? = nil) {
        self.id = id
        self.workoutItemId = workoutItemId
        self.position = position
        self.isWarmup = isWarmup
        self.weight = weight
        self.reps = reps
        self.seconds = seconds
        self.distance = distance
        self.notes = notes
        self.completedAt = completedAt
    }
}

public struct BodyWeightRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "bodyWeight"
    public var id: String
    public var measuredAt: Date
    public var weight: Double

    public init(id: String = UUID().uuidString, measuredAt: Date, weight: Double) {
        self.id = id
        self.measuredAt = measuredAt
        self.weight = weight
    }
}
