// SwiftData records for the shared lists: shopping items, wishlist items, meal ideas, projects and their subtasks.
// Each mirrors its server row field for field (server/README.md, "Model") and carries the same sync
// bookkeeping CompletionRecord does, plus `pendingPatch` for edits. Subtasks point at their project by
// id, like the server; there are no SwiftData relationships here. `removed` is the soft-delete flag
// (a property named `deleted` breaks SwiftData predicates).
import Foundation
import SwiftData

/// Which mutable fields hold a local edit the server has not seen. Stored on each record as a bitmask
/// (`pendingPatch`) so a predicate can find rows to PATCH (`pendingPatch != 0`), and the replay sends
/// only the fields that changed here, never a stale copy of a field the other phone may have edited.
struct PatchFields: OptionSet, Sendable, Hashable {
    let rawValue: Int
    static let title = PatchFields(rawValue: 1 << 0)
    static let bought = PatchFields(rawValue: 1 << 1)
    static let tag = PatchFields(rawValue: 1 << 2)
    static let lastMadeAt = PatchFields(rawValue: 1 << 3)
    static let nextUp = PatchFields(rawValue: 1 << 4)
    static let done = PatchFields(rawValue: 1 << 5)
    static let sortOrder = PatchFields(rawValue: 1 << 6)
    static let price = PatchFields(rawValue: 1 << 7)
}

/// The sync state machine every list record shares (the one CompletionRecord documents, plus PATCH):
/// - `syncedAt == nil && !rejected && !removed`   → pending POST
/// - `syncedAt != nil && pendingPatch != 0`        → pending PATCH, only the flagged fields are sent
/// - `rejected`                                    → the server said 400; kept locally, never retried
/// - `removed && !deleteSynced`                    → pending DELETE (404 from the server also counts as done)
protocol ListRecord: AnyObject {
    var id: String { get }
    var updatedAt: Date { get set }
    var syncedAt: Date? { get set }
    var removed: Bool { get set }
    var deleteSynced: Bool { get set }
    var rejected: Bool { get set }
    var seq: Int? { get set }
    var pendingPatch: Int { get set }
}

extension ListRecord {
    var needsPost: Bool {
        syncedAt == nil && !rejected && !removed
    }

    var needsPatch: Bool {
        syncedAt != nil && pendingPatch != 0 && !rejected && !removed
    }

    var needsDelete: Bool {
        removed && !deleteSynced
    }

    var pendingFields: PatchFields {
        get { PatchFields(rawValue: pendingPatch) }
        set { pendingPatch = newValue.rawValue }
    }

    /// Flags `fields` for the next PATCH. The caller has already changed the values.
    func markEdited(_ fields: PatchFields, at date: Date = Date()) {
        pendingFields = pendingFields.union(fields)
        updatedAt = date
    }

    /// Soft delete. A row the server never took needs no DELETE, so it is acknowledged on the spot.
    func markRemoved(at date: Date = Date()) {
        removed = true
        updatedAt = date
        if syncedAt == nil {
            deleteSynced = true
        }
    }

    /// True when the server has been told the row is gone. Undo then cannot un-delete it there —
    /// the server soft-deletes for good and a POST with the same id replays onto the dead row — so
    /// the only honest answer is a fresh row with a new id (`ListActions.restore*`).
    ///
    /// `syncedAt == nil` is the other half of the pair: the row never reached the server at all, so
    /// `markRemoved` acknowledged the delete on the spot and nothing was sent.
    var deleteReachedServer: Bool {
        syncedAt != nil && deleteSynced
    }

    /// Undo of a soft delete that never left the phone: the row goes back to what it was, whether
    /// that was a pending POST (never synced) or a synced row (its DELETE was still queued).
    func unremove(at date: Date = Date()) {
        removed = false
        deleteSynced = false
        updatedAt = date
    }
}

/// One line of the shopping list. `addedBy` is the raw `Person` value; empty until the server stamps it
/// from the token, because an unpaired phone does not know who it is.
@Model
final class ShoppingItemRecord: ListRecord {
    @Attribute(.unique) var id: String
    var title: String
    var addedBy: String
    var bought: Bool
    var boughtBy: String?
    var boughtAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0

    init(
        id: String,
        title: String,
        addedBy: String,
        bought: Bool = false,
        boughtBy: String? = nil,
        boughtAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.addedBy = addedBy
        self.bought = bought
        self.boughtBy = boughtBy
        self.boughtAt = boughtAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }
}


/// One line of the wishlist: a shopping item with a price. `priceCents` is whole cents, nil when the
/// row has no price (nil and 0 are different: "free" is a price). `addedBy` as on a shopping item.
@Model
final class WishlistItemRecord: ListRecord {
    @Attribute(.unique) var id: String
    var title: String
    var priceCents: Int?
    var addedBy: String
    var bought: Bool
    var boughtBy: String?
    var boughtAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0

    init(
        id: String,
        title: String,
        priceCents: Int? = nil,
        addedBy: String,
        bought: Bool = false,
        boughtBy: String? = nil,
        boughtAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.priceCents = priceCents
        self.addedBy = addedBy
        self.bought = bought
        self.boughtBy = boughtBy
        self.boughtAt = boughtAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }
}

/// A saved meal idea. `tag` is freeform ("Weeknight"), empty by default. `nextUp` is exclusive: the
/// server clears it on every other meal, and the app mirrors that locally so the badge moves at once.
@Model
final class MealRecord: ListRecord {
    @Attribute(.unique) var id: String
    var title: String
    var tag: String
    var lastMadeAt: Date?
    var nextUp: Bool
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0

    init(id: String, title: String, tag: String = "", lastMadeAt: Date? = nil, nextUp: Bool = false,
         createdAt: Date, updatedAt: Date? = nil, syncedAt: Date? = nil, removed: Bool = false)
    {
        self.id = id
        self.title = title
        self.tag = tag
        self.lastMadeAt = lastMadeAt
        self.nextUp = nextUp
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }
}

/// A multi-step job. Removing a project removes its subtasks locally too; the server cascades the same way.
@Model
final class ProjectRecord: ListRecord {
    @Attribute(.unique) var id: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0

    init(
        id: String,
        title: String,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }
}

/// One step of a project. `sortOrder` is the position within the project; `doneBy`/`doneAt` are stamped
/// locally on check-off and replaced by the server's stamp when the PATCH is acknowledged.
@Model
final class SubtaskRecord: ListRecord {
    @Attribute(.unique) var id: String
    var projectId: String
    var title: String
    var sortOrder: Int
    var done: Bool
    var doneBy: String?
    var doneAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0

    init(
        id: String,
        projectId: String,
        title: String,
        sortOrder: Int,
        done: Bool = false,
        doneBy: String? = nil,
        doneAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.sortOrder = sortOrder
        self.done = done
        self.doneBy = doneBy
        self.doneAt = doneAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }
}
