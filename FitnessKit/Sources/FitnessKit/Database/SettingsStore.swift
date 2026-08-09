import Foundation
import GRDB

public struct SettingsRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "settings"
    public var id: Int
    public var weeklyGoal: Int
    public var unit: String

    public init(id: Int = 1, weeklyGoal: Int = 3, unit: String = "lbs") {
        self.id = id
        self.weeklyGoal = weeklyGoal
        self.unit = unit
    }
}

public enum SettingsStore {
    public static func load(from dbQueue: DatabaseQueue) throws -> SettingsRecord {
        try dbQueue.write { db in
            if let existing = try SettingsRecord.fetchOne(db, key: 1) {
                return existing
            }
            let record = SettingsRecord()
            try record.insert(db)
            return record
        }
    }

    public static func setWeeklyGoal(_ goal: Int, in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            var settings = try SettingsRecord.fetchOne(db, key: 1) ?? SettingsRecord()
            settings.weeklyGoal = max(1, min(goal, 7))
            try settings.save(db)
        }
    }
}

public enum BodyWeightStore {
    /// Ascending by date.
    public static func all(from dbQueue: DatabaseQueue) throws -> [BodyWeightRecord] {
        try dbQueue.read { db in
            try BodyWeightRecord.order(Column("measuredAt")).fetchAll(db)
        }
    }

    public static func log(weight: Double, at date: Date = Date(),
                           in dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try BodyWeightRecord(measuredAt: date, weight: weight).insert(db)
        }
    }

    public static func delete(id: String, in dbQueue: DatabaseQueue) throws {
        _ = try dbQueue.write { try BodyWeightRecord.deleteOne($0, key: id) }
    }
}
