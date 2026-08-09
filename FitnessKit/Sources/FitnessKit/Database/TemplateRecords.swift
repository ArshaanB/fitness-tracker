import Foundation
import GRDB

public struct TemplateRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "template"
    public var id: String
    public var name: String
    public var position: Int
    public var archivedAt: Date?

    public init(id: String = UUID().uuidString, name: String, position: Int, archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.position = position
        self.archivedAt = archivedAt
    }
}

public struct TemplateItemRecord: Codable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "templateItem"
    public var id: String
    public var templateId: String
    public var exerciseId: String
    public var position: Int
    public var supersetGroup: Int?
    public var restSeconds: Int?
    public var targetSetCount: Int?

    public init(id: String = UUID().uuidString, templateId: String, exerciseId: String,
                position: Int, supersetGroup: Int? = nil, restSeconds: Int? = nil,
                targetSetCount: Int? = nil) {
        self.id = id
        self.templateId = templateId
        self.exerciseId = exerciseId
        self.position = position
        self.supersetGroup = supersetGroup
        self.restSeconds = restSeconds
        self.targetSetCount = targetSetCount
    }
}

/// A template with resolved exercise names, ready for display.
public struct TemplateSummary: Identifiable, Sendable, Equatable {
    public struct Item: Identifiable, Sendable, Equatable {
        public let id: String
        public let exerciseId: String
        public let exerciseName: String
        public let position: Int
        public let restSeconds: Int?
        public let targetSetCount: Int

        public init(id: String, exerciseId: String, exerciseName: String,
                    position: Int, restSeconds: Int?, targetSetCount: Int) {
            self.id = id
            self.exerciseId = exerciseId
            self.exerciseName = exerciseName
            self.position = position
            self.restSeconds = restSeconds
            self.targetSetCount = targetSetCount
        }
    }

    public let id: String
    public let name: String
    public let position: Int
    public let items: [Item]

    public init(id: String, name: String, position: Int, items: [Item]) {
        self.id = id
        self.name = name
        self.position = position
        self.items = items
    }
}

public enum TemplateStore {
    public static func loadAll(from dbQueue: DatabaseQueue) throws -> [TemplateSummary] {
        try dbQueue.read { db in
            let exercisesById = Dictionary(
                uniqueKeysWithValues: try ExerciseRecord.fetchAll(db).map { ($0.id, $0.name) })
            let itemsByTemplate = Dictionary(
                grouping: try TemplateItemRecord.fetchAll(db), by: \.templateId)
            return try TemplateRecord
                .filter(Column("archivedAt") == nil)
                .order(Column("position"))
                .fetchAll(db)
                .map { template in
                    let items = (itemsByTemplate[template.id] ?? [])
                        .sorted { $0.position < $1.position }
                        .map { item in
                            TemplateSummary.Item(id: item.id,
                                                 exerciseId: item.exerciseId,
                                                 exerciseName: exercisesById[item.exerciseId] ?? "Unknown",
                                                 position: item.position,
                                                 restSeconds: item.restSeconds,
                                                 targetSetCount: item.targetSetCount ?? 3)
                        }
                    return TemplateSummary(id: template.id, name: template.name,
                                           position: template.position, items: items)
                }
        }
    }

    public struct ItemDraft: Sendable, Equatable {
        public var exerciseId: String
        public var restSeconds: Int?
        public var targetSetCount: Int

        public init(exerciseId: String, restSeconds: Int?, targetSetCount: Int) {
            self.exerciseId = exerciseId
            self.restSeconds = restSeconds
            self.targetSetCount = targetSetCount
        }
    }

    /// Creates or fully replaces a template's content.
    @discardableResult
    public static func save(id: String? = nil, name: String, items: [ItemDraft],
                            into dbQueue: DatabaseQueue) throws -> String {
        try dbQueue.write { db in
            let templateId: String
            if let id, var existing = try TemplateRecord.fetchOne(db, key: id) {
                existing.name = name
                try existing.update(db)
                try TemplateItemRecord.filter(Column("templateId") == id).deleteAll(db)
                templateId = id
            } else {
                let position = (try TemplateRecord.select(max(Column("position")), as: Int.self)
                    .fetchOne(db) ?? 0) + 1
                let record = TemplateRecord(name: name, position: position)
                try record.insert(db)
                templateId = record.id
            }
            for (index, item) in items.enumerated() {
                try TemplateItemRecord(templateId: templateId,
                                       exerciseId: item.exerciseId,
                                       position: index + 1,
                                       restSeconds: item.restSeconds,
                                       targetSetCount: item.targetSetCount).insert(db)
            }
            return templateId
        }
    }

    public static func delete(id: String, from dbQueue: DatabaseQueue) throws {
        _ = try dbQueue.write { db in
            try TemplateRecord.deleteOne(db, key: id)
        }
    }
}
