// SwiftData records for the local, offline-first store.
// These mirror RoostCore's value types; converters live in Converters.swift.
// No CloudKit. Sync bookkeeping lives on CompletionRecord and SyncState; the device token lives in the Keychain.
// The shared lists (shopping items, wishlist items, meals, projects, subtasks) are in ListRecords.swift, handoffs in
// HandoffRecords.swift.
import Foundation
import SwiftData

enum RoostSchema {
    static let models: [any PersistentModel.Type] = [
        ChoreRecord.self, CompletionRecord.self, SyncState.self,
        ShoppingItemRecord.self, WishlistItemRecord.self, MealRecord.self, ProjectRecord.self, SubtaskRecord.self,
        HandoffRecord.self,
    ]
    static var schema: Schema {
        Schema(models)
    }
}

/// One row of data/chores.json, persisted. `cadence`, `category`, and `fixedAssignee` are stored as
/// their raw strings so a future value in the JSON does not crash the store; converters validate.
/// `season` is the JSON text of a `RoostCore.Season` (`{"months":[4,5,6,7,8,9,10]}`), nil for the rest.
@Model
final class ChoreRecord {
    @Attribute(.unique) var id: String
    var title: String
    var cadence: String
    var fixedAssignee: String?
    var category: String
    var sortOrder: Int
    var retired: Bool
    var season: String?
    var together: Bool = false
    /// JSON text of the weekday list (`[5,6]`), the `season` pattern; nil for a whole-week chore.
    var weekdays: String?
    /// 1...28, the day of the period's last month the chore is due by; nil for a whole-period chore.
    var dueDay: Int?
    /// JSON text of a `RoostCore.ChoreRotation`, the `season` pattern; nil when the default round-robin applies.
    var rotation: String?
    /// JSON text of a `RoostCore.MissPenalty`, the `season` pattern; nil when this chore has no miss penalty.
    var missPenalty: String?

    init(
        id: String,
        title: String,
        cadence: String,
        fixedAssignee: String?,
        category: String,
        sortOrder: Int,
        retired: Bool = false,
        season: String? = nil,
        together: Bool = false,
        weekdays: String? = nil,
        dueDay: Int? = nil,
        rotation: String? = nil,
        missPenalty: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
        self.sortOrder = sortOrder
        self.retired = retired
        self.season = season
        self.together = together
        self.weekdays = weekdays
        self.dueDay = dueDay
        self.rotation = rotation
        self.missPenalty = missPenalty
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
    var seq: Int?

    init(id: String, choreId: String, person: String, completedAt: Date, syncedAt: Date? = nil, removed: Bool = false) {
        self.id = id
        self.choreId = choreId
        self.person = person
        self.completedAt = completedAt
        self.syncedAt = syncedAt
        self.removed = removed
    }

    var needsPost: Bool {
        syncedAt == nil && !rejected && !removed
    }

    var needsDelete: Bool {
        removed && !deleteSynced
    }
}

/// Single-row sync bookkeeping. `cursor` is the server's monotonic seq; `choresVersion` is the seeded list version.
/// `person` is set by pairing (the server tells us who the token belongs to). The token itself is in the Keychain.
@Model
final class SyncState {
    var cursor: Int
    var choresVersion: Int
    var lastSyncAt: Date?
    var baseURL: String?
    var person: String?
    /// The day the household started using Roost; periods before it are ignored by the scheduler.
    ///
    /// The server owns it and every `/sync` carries it (`activeFrom`, a Chicago calendar day), so both
    /// phones agree on the floor however long after the household started the second one was set up.
    /// Nil until the first sync lands, which the screens read as today: a phone that has never synced
    /// shows no backlog at all rather than a guess at one.
    var activeFrom: Date?

    init(cursor: Int = 0, choresVersion: Int = 0, lastSyncAt: Date? = nil) {
        self.cursor = cursor
        self.choresVersion = choresVersion
        self.lastSyncAt = lastSyncAt
    }

    var isPaired: Bool {
        person != nil && baseURL != nil
    }
}
