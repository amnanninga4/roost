// The SwiftData record for a handoff: one person offering their turn at a chore to the other for a
// single period. It mirrors the server row field for field (`shapeHandoff` in server/src/handoffs.js)
// and carries the same sync bookkeeping the list records do — `syncedAt`, `rejected`, and `removed`
// for the server's `deleted` — so it conforms to `ListRecord` and the outbound policy in ListSync.swift
// works on it unchanged.
//
// Two fields are the phone's own and never go on the wire:
//
//   pendingAnswer   the accept or decline this phone made but has not sent yet. `state` already holds
//                   that answer locally, so the Tasks tab moves the item the moment it is tapped; a
//                   `/sync` delta leaves the state alone until the answer has actually gone out.
//   noticeCleared   the "Wes said no" line has been read, so the next check-off stops showing it. The
//                   server has no such fact: a declined offer simply stays declined for its period.
//
// There is no PATCH and no DELETE for a handoff — the only writes are `POST /handoffs` and
// `POST /handoffs/:id/{accept,decline}` — so `pendingPatch` is only here to satisfy `ListRecord` and
// stays 0, and nothing local ever sets `removed`, so no DELETE is ever queued.
import Foundation
import RoostCore
import SwiftData

@Model
final class HandoffRecord: ListRecord {
    @Attribute(.unique) var id: String
    var choreId: String
    /// The person who owed the chore for this period and offered it away (`from` on the wire).
    var fromPerson: String
    /// The person being asked, and the owner for this period once they accept (`to` on the wire).
    var toPerson: String
    /// The period being handed off, in the cadence's own numbering (RoostCore.HouseholdCalendar).
    var periodIndex: Int
    /// The chore's cadence, carried on the row so the period maths needs nothing else.
    var cadence: String
    /// `pending` / `accepted` / `declined` / `expired`, stored raw so a value this build does not know
    /// cannot break the store.
    var state: String
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0
    /// The answer this phone made but has not sent: `accept` or `decline`. Nil once it has gone out,
    /// or once the server refused it and the row took the server's own state back.
    var pendingAnswer: String?
    /// Local only: the "Wes said no" / "couldn't hand that off" line has been read.
    var noticeCleared: Bool = false

    init(
        id: String,
        choreId: String,
        fromPerson: String,
        toPerson: String,
        periodIndex: Int,
        cadence: String,
        state: String = Handoff.State.pending.rawValue,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.choreId = choreId
        self.fromPerson = fromPerson
        self.toPerson = toPerson
        self.periodIndex = periodIndex
        self.cadence = cadence
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }

    /// The answer waiting to be sent, typed. Setting it to nil is how the replay says "sent, or refused".
    var queuedAnswer: HandoffRules.Decision? {
        get { pendingAnswer.flatMap(HandoffRules.Decision.init(rawValue:)) }
        set { pendingAnswer = newValue?.rawValue }
    }

    /// An accept or decline this phone still owes the server.
    var needsAnswer: Bool {
        pendingAnswer != nil && !removed && !rejected
    }

    /// The offer is on the server, so it can no longer be taken back: there is no withdraw endpoint.
    var reachedServer: Bool {
        syncedAt != nil
    }
}
