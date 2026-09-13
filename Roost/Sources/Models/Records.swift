// SwiftData records for the local, offline-first store.
// These mirror RoostCore's value types; converters live in Converters.swift.
// No CloudKit. Sync bookkeeping lives on CompletionRecord and SyncState; the device token lives in the Keychain.
import Foundation
import SwiftData

enum RoostSchema {
    static let models: [any PersistentModel.Type] = [ChoreRecord.self, CompletionRecord.self, SyncState.self]
    static var schema: Schema { Schema(models) }
}

/// One row of data/chores.json, persisted. `cadence`, `category`, and `fixedAssignee` are stored as
/// their raw strings so a future value in the JSON does not crash the store; converters validate.
@Model
final class ChoreRecord {
    @Attribute(.unique) var id: String
    var title: String
    var cadence: String
    var fixedAssignee: String?
    var category: String
    var sortOrder: Int
    var retired: Bool

    init(id: String, title: String, cadence: String, fixedAssignee: String?, category: String, sortOrder: Int, retired: Bool = false) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
        self.sortOrder = sortOrder
        self.retired = retired
    }
}

/// A completion as the phone knows it. `id` is client-generated so the server can dedupe replays.
///
/// Sync state machine:
/// - `syncedAt == nil && !rejected && !removed`  → pending POST
/// - `rejected`                                   → server said 400; kept locally, never retried
/// - `removed && !deleteSynced`                   → pending DELETE (404 from the server also counts as done)
@Model
final class CompletionRecord {
    @Attribute(.unique) var id: String
    var choreId: String
    var person: String
    var completedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    /// The server's seq for this row, when known. Informational only; the cursor lives on SyncState.
    var seq: Int? = nil

    init(id: String, choreId: String, person: String, completedAt: Date, syncedAt: Date? = nil, removed: Bool = false) {
        self.id = id
        self.choreId = choreId
        self.person = person
        self.completedAt = completedAt
        self.syncedAt = syncedAt
        self.removed = removed
    }

    var needsPost: Bool { syncedAt == nil && !rejected && !removed }
    var needsDelete: Bool { removed && !deleteSynced }
}

/// Single-row sync bookkeeping. `cursor` is the server's monotonic seq; `choresVersion` is the seeded list version.
/// `person` is set by pairing (the server tells us who the token belongs to). The token itself is in the Keychain.
@Model
final class SyncState {
    var cursor: Int
    var choresVersion: Int
    var lastSyncAt: Date?
    var baseURL: String? = nil
    var person: String? = nil
    /// The day the household started using Roost; periods before it are ignored by the scheduler.
    var activeFrom: Date? = nil

    init(cursor: Int = 0, choresVersion: Int = 0, lastSyncAt: Date? = nil) {
        self.cursor = cursor
        self.choresVersion = choresVersion
        self.lastSyncAt = lastSyncAt
    }

    var isPaired: Bool { person != nil && baseURL != nil }
}
