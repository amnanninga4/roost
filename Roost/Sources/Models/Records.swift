// SwiftData records for the local, offline-first store.
// These mirror RoostCore's value types; converters live in Converters.swift.
// No CloudKit, no networking. Sync (R-8) will fill `syncedAt` and `SyncState`.
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
/// `syncedAt` is nil until the server has acknowledged the row. `deleted` is a soft flag, matching the server.
@Model
final class CompletionRecord {
    @Attribute(.unique) var id: String
    var choreId: String
    var person: String
    var completedAt: Date
    var syncedAt: Date?
    var deleted: Bool

    init(id: String, choreId: String, person: String, completedAt: Date, syncedAt: Date? = nil, deleted: Bool = false) {
        self.id = id
        self.choreId = choreId
        self.person = person
        self.completedAt = completedAt
        self.syncedAt = syncedAt
        self.deleted = deleted
    }
}

/// Single-row sync bookkeeping. `cursor` is the server's monotonic seq; `choresVersion` is the seeded list version.
@Model
final class SyncState {
    var cursor: Int
    var choresVersion: Int
    var lastSyncAt: Date?

    init(cursor: Int = 0, choresVersion: Int = 0, lastSyncAt: Date? = nil) {
        self.cursor = cursor
        self.choresVersion = choresVersion
        self.lastSyncAt = lastSyncAt
    }
}
