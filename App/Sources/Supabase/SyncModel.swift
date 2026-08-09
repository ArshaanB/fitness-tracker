import Foundation
import FitnessKit
import GRDB
import Observation
import Supabase

/// Auth + backup sync against Supabase. Offline-first: the app only ever
/// writes locally; SQLite triggers queue every change into `outbox`, and this
/// engine drains it whenever we're signed in and online.
///
/// Account identity: the id of the account this device's data belongs to is
/// stored locally. Signing in as a DIFFERENT account wipes local data and
/// restores that account's cloud data — never uploads one person's history
/// into another person's account. Local data that predates any sign-in gets
/// an explicit user choice (upload it, or replace it with the account's cloud
/// data) instead of a silent guess.
@MainActor
@Observable
final class SyncModel {
    enum Status: Equatable {
        case signedOut
        case idle
        case syncing
        case error(String)
    }

    /// Set after verify() when the app can't safely decide what the local
    /// data means for this account. AuthSheet presents the choice.
    enum PendingDecision {
        /// Device has unowned local data AND the account has cloud data.
        case mergeConflict(localWorkouts: Int)
    }

    private(set) var status: Status = .signedOut
    private(set) var email: String?
    private(set) var pendingDecision: PendingDecision?
    private(set) var lastSyncedAt: Date? =
        UserDefaults.standard.object(forKey: "lastSyncedAt") as? Date

    /// The account id the local database belongs to (nil = never synced).
    private var ownerUserId: String? {
        get { UserDefaults.standard.string(forKey: "syncOwnerUserId") }
        set { UserDefaults.standard.set(newValue, forKey: "syncOwnerUserId") }
    }

    private let client = SupabaseClient(supabaseURL: SupabaseConfig.url,
                                        supabaseKey: SupabaseConfig.publishableKey)
    private var db: DatabaseQueue?
    private var pushTask: Task<Void, Never>?

    func configure(db: DatabaseQueue) async {
        self.db = db
        // currentSession is the locally cached session: no network, so a dead
        // wifi moment at launch can't sign the user out of the UI. Token
        // refresh happens inside the SDK when requests are made.
        if let session = client.auth.currentSession {
            email = session.user.email
            status = .idle
        }
    }

    // MARK: - Auth (email one-time code; no deep links needed)

    func sendCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email, shouldCreateUser: true)
    }

    /// Verifies the emailed code, then decides how local and cloud data meet.
    /// Returns true when fully signed in; false when AuthSheet must present
    /// the merge choice first.
    @discardableResult
    func verify(email: String, code: String, appModel: AppModel) async throws -> Bool {
        let session = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        self.email = session.user.email
        status = .idle
        let userId = session.user.id.uuidString

        guard let db else { return true }
        do {
            let localWorkouts = try await db.read { try WorkoutRecord.fetchCount($0) }
            let serverWorkouts = try await serverWorkoutCount()

            switch (ownerUserId, localWorkouts) {
            case (userId, _):
                // Same account as before: business as usual.
                pushSoon()
            case (.some, _):
                // Different account owns the local data. That data is theirs
                // (already in their cloud if they ever synced); this account
                // gets its own cloud state.
                try await replaceLocalWithCloud(userId: userId, appModel: appModel)
            case (nil, 0):
                ownerUserId = userId
                if serverWorkouts > 0 {
                    try await restoreAll()
                    appModel.refresh()
                }
                touchSyncDate()
            case (nil, _) where serverWorkouts == 0:
                // Their own first backup: claim the local data and push it.
                ownerUserId = userId
                await push()
            case (nil, let count):
                // Unowned local data AND existing cloud data: only the user
                // knows which one is truth.
                pendingDecision = .mergeConflict(localWorkouts: count)
                return false
            }
        } catch {
            status = .error(friendly(error))
        }
        return true
    }

    /// Resolves the merge choice from AuthSheet.
    func resolveDecision(uploadLocal: Bool, appModel: AppModel) async {
        guard case .mergeConflict = pendingDecision,
              let userId = client.auth.currentSession?.user.id.uuidString else {
            pendingDecision = nil
            return
        }
        pendingDecision = nil
        do {
            if uploadLocal {
                ownerUserId = userId
                await push()
            } else {
                try await replaceLocalWithCloud(userId: userId, appModel: appModel)
            }
        } catch {
            status = .error(friendly(error))
        }
    }

    func signOut() async {
        pushTask?.cancel()
        pushTask = nil
        pendingDecision = nil
        try? await client.auth.signOut()
        email = nil
        status = .signedOut
        // Local data and its owner marker stay: the same user signing back in
        // continues seamlessly; a different user triggers the wipe path.
    }

    // MARK: - Sync orchestration

    /// Debounced push — safe to call from anywhere, any number of times.
    func pushSoon() {
        guard status != .signedOut, pushTask == nil else { return }
        pushTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
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
                setStatusIfSignedIn(.idle)
                return
            }
            let maxSeq = entries.map(\.seq).max()!

            // Last op per row wins; a delete supersedes queued upserts.
            var finalOp: [String: OutboxEntry] = [:]
            for entry in entries { finalOp["\(entry.tbl)/\(entry.rowId)"] = entry }
            let ops = Array(finalOp.values)

            // Deletes first (reverse dependency order), so delete-then-recreate
            // under a server unique constraint doesn't collide with the ghost
            // of the deleted row.
            for table in AppDatabase.syncedTables.reversed() {
                let ids = ops.filter { $0.tbl == table && $0.op == "delete" }.map(\.rowId)
                guard !ids.isEmpty else { continue }
                for chunk in ids.chunked(400) {
                    try await client.from(table).delete().in("id", values: chunk).execute()
                }
            }
            for table in AppDatabase.syncedTables {
                let ids = ops.filter { $0.tbl == table && $0.op == "upsert" }.map(\.rowId)
                try await upsert(table: table, ids: ids, db: db)
            }

            try await db.write { try $0.execute(sql: "DELETE FROM outbox WHERE seq <= ?", arguments: [maxSeq]) }
            touchSyncDate()
            setStatusIfSignedIn(.idle)
        } catch {
            setStatusIfSignedIn(.error(friendly(error)))
        }
    }

    /// A sign-out during an in-flight push must stay signed out.
    private func setStatusIfSignedIn(_ new: Status) {
        guard status != .signedOut else { return }
        status = new
    }

    private func upsert(table: String, ids: [String], db: DatabaseQueue) async throws {
        guard !ids.isEmpty else { return }
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

    // MARK: - Restore

    private func serverWorkoutCount() async throws -> Int {
        try await client.from("workout")
            .select("id", head: true, count: .exact).execute().count ?? 0
    }

    /// Wipes local data and pulls this account's cloud state.
    private func replaceLocalWithCloud(userId: String, appModel: AppModel) async throws {
        guard let db else { return }
        try await Task.detached { try AppDatabase.wipeAllData(in: db) }.value
        ownerUserId = userId
        try await restoreAll()
        appModel.refresh()
        touchSyncDate()
    }

    /// Full pull into an EMPTY local store (callers wipe first when needed).
    /// Paginates: PostgREST caps un-ranged selects at 1000 rows, which would
    /// silently truncate an 8-year history.
    private func restoreAll() async throws {
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
            // The restore's own inserts re-triggered the outbox; the server
            // already has these rows. (Callers guarantee the store was empty,
            // so nothing else can be queued.)
            try d.execute(sql: "DELETE FROM outbox")
        }
    }

    private func fetchAll<T: Codable & Sendable>(_ table: String) async throws -> [T] {
        var all: [T] = []
        var from = 0
        let pageSize = 1000
        while true {
            let page: [T] = try await client.from(table).select()
                .order("id")
                .range(from: from, to: from + pageSize - 1)
                .execute().value
            all.append(contentsOf: page)
            if page.count < pageSize { break }
            from += pageSize
        }
        return all
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

extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
