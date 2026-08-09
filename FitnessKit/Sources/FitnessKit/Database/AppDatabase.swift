import Foundation
import GRDB

/// Owns the SQLite schema. Local store is single-user; account scoping happens
/// server-side when rows sync to Supabase.
public enum AppDatabase {
    public static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "exercise") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull().unique()
                t.column("kind", .text).notNull()
            }

            try db.create(table: "template") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("archivedAt", .datetime)
            }

            try db.create(table: "templateItem") { t in
                t.primaryKey("id", .text)
                t.belongsTo("template", onDelete: .cascade).notNull()
                t.belongsTo("exercise").notNull()
                t.column("position", .integer).notNull()
                t.column("supersetGroup", .integer)  // unused in v1, kept for later
                t.column("restSeconds", .integer)
                t.column("targetSetCount", .integer)
            }

            try db.create(table: "workout") { t in
                t.primaryKey("id", .text)
                t.belongsTo("template", onDelete: .setNull)
                t.column("name", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("notes", .text)
            }
            try db.create(indexOn: "workout", columns: ["startedAt", "name"], options: .unique)

            try db.create(table: "workoutItem") { t in
                t.primaryKey("id", .text)
                t.belongsTo("workout", onDelete: .cascade).notNull()
                t.belongsTo("exercise").notNull()
                t.column("position", .integer).notNull()
                t.column("supersetGroup", .integer)
                t.column("restSeconds", .integer)
            }
            try db.create(indexOn: "workoutItem", columns: ["exerciseId"])

            try db.create(table: "workoutSet") { t in
                t.primaryKey("id", .text)
                t.belongsTo("workoutItem", onDelete: .cascade).notNull()
                t.column("position", .integer).notNull()
                t.column("isWarmup", .boolean).notNull().defaults(to: false)
                t.column("weight", .double)
                t.column("reps", .integer)
                t.column("seconds", .double)    // imported timed history only in v1
                t.column("distance", .double)   // imported cardio history only in v1
                t.column("notes", .text)
                t.column("completedAt", .datetime)
            }

            try db.create(table: "bodyWeight") { t in
                t.primaryKey("id", .text)
                t.column("measuredAt", .datetime).notNull()
                t.column("weight", .double).notNull()
            }

            try db.create(table: "settings") { t in
                t.primaryKey("id", .integer)  // single row, id = 1
                t.column("weeklyGoal", .integer).notNull().defaults(to: 3)
                t.column("unit", .text).notNull().defaults(to: "lbs")
            }
        }

        migrator.registerMigration("v2-outbox") { db in
            // Sync outbox, fed entirely by SQLite triggers: every insert/update/
            // delete on a synced table queues here, no Swift plumbing at any
            // call site. SyncEngine drains it to Supabase when online.
            try db.create(table: "outbox") { t in
                t.autoIncrementedPrimaryKey("seq")
                t.column("tbl", .text).notNull()
                t.column("rowId", .text).notNull()
                t.column("op", .text).notNull()  // 'upsert' | 'delete'
            }
            for table in Self.syncedTables {
                try db.execute(sql: """
                    CREATE TRIGGER \(table)_outbox_i AFTER INSERT ON \(table) BEGIN
                      INSERT INTO outbox(tbl, rowId, op) VALUES('\(table)', NEW.id, 'upsert');
                    END;
                    CREATE TRIGGER \(table)_outbox_u AFTER UPDATE ON \(table) BEGIN
                      INSERT INTO outbox(tbl, rowId, op) VALUES('\(table)', NEW.id, 'upsert');
                    END;
                    CREATE TRIGGER \(table)_outbox_d AFTER DELETE ON \(table) BEGIN
                      INSERT INTO outbox(tbl, rowId, op) VALUES('\(table)', OLD.id, 'delete');
                    END;
                    """)
            }
            // Anything already in the database (e.g. an import that predates
            // this migration) still needs its first backup.
            for table in Self.syncedTables {
                try db.execute(sql:
                    "INSERT INTO outbox(tbl, rowId, op) SELECT '\(table)', id, 'upsert' FROM \(table)")
            }
        }

        return migrator
    }

    /// Tables that sync to Supabase, in foreign-key dependency order —
    /// upserts push in this order, deletes in reverse.
    public static let syncedTables = [
        "exercise", "template", "templateItem", "workout",
        "workoutItem", "workoutSet", "bodyWeight", "settings",
    ]

    public static func open(at path: String) throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(path: path)
        try makeMigrator().migrate(dbQueue)
        return dbQueue
    }

    public static func inMemory() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try makeMigrator().migrate(dbQueue)
        return dbQueue
    }
}
