import Foundation
import FitnessKit
import GRDB
import Observation
import Supabase

/// Auth + backup sync against Supabase. Offline-first: the app only ever
/// writes locally; SQLite triggers queue every change into `outbox`, and this
/// engine drains it whenever we're signed in and online. Sign-in on a fresh
/// install restores everything from the server.
@MainActor
@Observable
final class SyncModel {
    enum Status: Equatable {
        case signedOut
        case idle
        case syncing
        case error(String)
    }

    private(set) var status: Status = .signedOut
    private(set) var email: String?
    private(set) var lastSyncedAt: Date? =
        UserDefaults.standard.object(forKey: "lastSyncedAt") as? Date

    private let client = SupabaseClient(supabaseURL: SupabaseConfig.url,
                                        supabaseKey: SupabaseConfig.publishableKey)
    private var db: DatabaseQueue?
    private var pushTask: Task<Void, Never>?

    func configure(db: DatabaseQueue) async {
        self.db = db
        if let session = try? await client.auth.session {
            email = session.user.email
            status = .idle
        }
    }

    // MARK: - Auth (email one-time code; no deep links needed)

    func sendCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    /// Verifies the emailed code. On success, restores from the server if this
    /// install is empty, otherwise pushes local history up.
    func verify(email: String, code: String, appModel: AppModel) async throws {
        let session = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        self.email = session.user.email
        status = .idle
        await initialSync(appModel: appModel)
    }

    func signOut() async {
        try? await client.auth.signOut()
        email = nil
        status = .signedOut
    }

    // MARK: - Sync orchestration

    private func initialSync(appModel: AppModel) async {
        guard let db else { return }
        do {
            let localWorkouts = try await db.read { try WorkoutRecord.fetchCount($0) }
            let serverWorkouts = try await client.from("workout")
                .select("id", head: true, count: .exact).execute().count ?? 0
            if localWorkouts == 0 && serverWorkouts > 0 {
                try await restore()
                appModel.refresh()
            } else {
                await push()
            }
        } catch {
            status = .error(friendly(error))
        }
    }

    /// Debounced push — safe to call from anywhere, any number of times.
    func pushSoon() {
        guard status != .signedOut, pushTask == nil else { return }
        pushTask = Task {
            try? await Task.sleep(for: .seconds(2))
            await push()
            pushTask = nil
        }
    }

    struct OutboxEntry {
        let seq: Int64
        let tbl: String
        let rowId: String
        let op: String
    }

    func push() async {
        guard let db, status != .signedOut, status != .syncing else { return }
        status = .syncing
        do {
            let entries: [OutboxEntry] = try await db.read { d in
                try Row.fetchAll(d, sql: "SELECT seq, tbl, rowId, op FROM outbox ORDER BY seq").map {
                    OutboxEntry(seq: $0["seq"], tbl: $0["tbl"], rowId: $0["rowId"], op: $0["op"])
                }
            }
            guard !entries.isEmpty else {
                touchSyncDate()
                status = .idle
                return
            }
            let maxSeq = entries.map(\.seq).max()!

            // Last op per row wins; a delete supersedes queued upserts.
            var finalOp: [String: OutboxEntry] = [:]
            for entry in entries { finalOp["\(entry.tbl)/\(entry.rowId)"] = entry }
            let ops = Array(finalOp.values)

            for table in AppDatabase.syncedTables {
                let ids = ops.filter { $0.tbl == table && $0.op == "upsert" }.map(\.rowId)
                try await upsert(table: table, ids: ids, db: db)
            }
            for table in AppDatabase.syncedTables.reversed() {
                let ids = ops.filter { $0.tbl == table && $0.op == "delete" }.map(\.rowId)
                guard !ids.isEmpty else { continue }
                for chunk in ids.chunked(400) {
                    try await client.from(table).delete().in("id", values: chunk).execute()
                }
            }

            try await db.write { try $0.execute(sql: "DELETE FROM outbox WHERE seq <= ?", arguments: [maxSeq]) }
            touchSyncDate()
            status = .idle
        } catch {
            status = .error(friendly(error))
        }
    }

    private func upsert(table: String, ids: [String], db: DatabaseQueue) async throws {
        guard !ids.isEmpty || table == "settings" else { return }
        switch table {
        case "exercise":
            try await push(ExerciseRecord.self, table, ids, db)
        case "template":
            try await push(TemplateRecord.self, table, ids, db)
        case "templateItem":
            try await push(TemplateItemRecord.self, table, ids, db)
        case "workout":
            // A workout may reference a template deleted before this push ever
            // ran; null the reference rather than trip the server FK.
            var records = try await db.read { d in
                try WorkoutRecord.filter(ids.contains(Column("id"))).fetchAll(d)
            }
            let templateIds = Set(try await db.read { d in
                try String.fetchAll(d, sql: "SELECT id FROM template")
            })
            for i in records.indices where records[i].templateId.map({ !templateIds.contains($0) }) == true {
                records[i].templateId = nil
            }
            for chunk in records.chunked(400) {
                try await client.from(table).upsert(chunk).execute()
            }
        case "workoutItem":
            try await push(WorkoutItemRecord.self, table, ids, db)
        case "workoutSet":
            try await push(WorkoutSetRecord.self, table, ids, db)
        case "bodyWeight":
            try await push(BodyWeightRecord.self, table, ids, db)
        case "settings":
            guard !ids.isEmpty else { return }
            let settings = try SettingsStore.load(from: db)
            try await client.from("settings")
                .upsert(ServerSettings(weeklyGoal: settings.weeklyGoal, unit: settings.unit))
                .execute()
        default:
            break
        }
    }

    private func push<T: FetchableRecord & PersistableRecord & Codable & Sendable>(
        _ type: T.Type, _ table: String, _ ids: [String], _ db: DatabaseQueue) async throws {
        guard !ids.isEmpty else { return }
        let records = try await db.read { d in
            try T.filter(ids.contains(Column("id"))).fetchAll(d)
        }
        for chunk in records.chunked(400) {
            try await client.from(table).upsert(chunk).execute()
        }
    }

    private struct ServerSettings: Codable, Sendable {
        let weeklyGoal: Int
        let unit: String
    }

    /// Fresh-install restore: pulls every table and rebuilds the local store.
    private func restore() async throws {
        guard let db else { return }
        let exercises: [ExerciseRecord] = try await fetchAll("exercise")
        let templates: [TemplateRecord] = try await fetchAll("template")
        let templateItems: [TemplateItemRecord] = try await fetchAll("templateItem")
        let workouts: [WorkoutRecord] = try await fetchAll("workout")
        let workoutItems: [WorkoutItemRecord] = try await fetchAll("workoutItem")
        let workoutSets: [WorkoutSetRecord] = try await fetchAll("workoutSet")
        let bodyWeights: [BodyWeightRecord] = try await fetchAll("bodyWeight")
        let serverSettings: [ServerSettings] = try await fetchAll("settings")

        try await db.write { d in
            for record in exercises { try record.save(d) }
            for record in templates { try record.save(d) }
            for record in templateItems { try record.save(d) }
            for record in workouts { try record.save(d) }
            for record in workoutItems { try record.save(d) }
            for record in workoutSets { try record.save(d) }
            for record in bodyWeights { try record.save(d) }
            if let s = serverSettings.first {
                try SettingsRecord(weeklyGoal: s.weeklyGoal, unit: s.unit).save(d)
            }
            // The restore itself re-triggered the outbox; the server already
            // has these rows.
            try d.execute(sql: "DELETE FROM outbox")
        }
        touchSyncDate()
    }

    private func fetchAll<T: Codable & Sendable>(_ table: String) async throws -> [T] {
        try await client.from(table).select().execute().value
    }

    private func touchSyncDate() {
        lastSyncedAt = Date()
        UserDefaults.standard.set(lastSyncedAt, forKey: "lastSyncedAt")
    }

    private func friendly(_ error: Error) -> String {
        let text = "\(error)"
        return text.count > 140 ? String(text.prefix(140)) + "…" : text
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
