// Every local write the Tasks tab makes about a handoff: write to the store first, let the sync pass
// tell the server, save. The screen calls these and then `SyncCoordinator.syncSoon()`; the tests call
// the same functions, so an offer in a test is the offer a tap makes.
//
// Whether a chore may be offered is `RoostCore.HandoffRules`'s answer, never one worked out here or in a
// view: `offer` goes through `HandoffRules.offer`, which is `canOffer` plus the row it would create.
import Foundation
import RoostCore
import SwiftData

enum HandoffActions {
    /// Offers `chore` to the other person for its current period. Nil when `HandoffRules` says this
    /// person cannot offer it — someone else owns the period, or an offer for it is already open.
    ///
    /// The id is a client-generated UUID, so the queued `POST /handoffs` can be replayed safely: the
    /// server returns `200` with the row it already has rather than making a second one.
    @discardableResult
    static func offer(
        _ chore: Chore,
        from person: Person,
        to other: Person,
        rules: HandoffRules,
        on date: Date,
        in context: ModelContext
    ) throws -> HandoffRecord? {
        guard let handoff = rules.offer(chore, from: person, to: other, on: date, id: UUID().uuidString) else {
            return nil
        }
        let record = HandoffRecord(
            id: handoff.id,
            choreId: handoff.choreId,
            fromPerson: handoff.from.rawValue,
            toPerson: handoff.to.rawValue,
            periodIndex: handoff.periodIndex,
            cadence: handoff.cadence.rawValue,
            state: handoff.state.rawValue,
            createdAt: handoff.createdAt
        )
        context.insert(record)
        try context.save()
        return record
    }

    /// Answers an offer. The row takes the answer at once — so the item moves columns under the finger
    /// rather than after a round trip — and `pendingAnswer` is what the sync pass owes the server. If the
    /// server refuses it (the period ended, somebody already answered), the replay puts the server's own
    /// state back (HandoffSync.swift).
    static func answer(
        _ id: String,
        as decision: HandoffRules.Decision,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        guard let record = try find(id, in: context) else { return }
        guard record.state == Handoff.State.pending.rawValue else { return }
        record.state = (decision == .accept ? Handoff.State.accepted : .declined).rawValue
        record.queuedAnswer = decision
        record.updatedAt = now
        try context.save()
    }

    /// Takes back an offer that never left the phone. There is no withdraw endpoint — the server has
    /// `POST /handoffs` and the two answer routes, and nothing else — so this is only ever offered while
    /// the offer is still queued, and it deletes the row outright rather than soft-deleting it: nothing
    /// on the server knows about it, so there is nothing to tell.
    static func withdraw(_ id: String, in context: ModelContext) throws {
        guard let record = try find(id, in: context), !record.reachedServer else { return }
        context.delete(record)
        try context.save()
    }

    /// Marks this person's "Wes said no" and "couldn't hand that off" lines as read. Called on a
    /// check-off: the note has done its job by then, and a declined offer would otherwise sit on the row
    /// for the rest of its period.
    ///
    /// Only rows that are actually carrying a note — declined, or refused by the server — are marked. A
    /// pending offer is left alone on purpose: clearing it now would swallow the answer when it comes.
    static func clearNotices(for person: Person, in context: ModelContext) throws {
        let raw = person.rawValue
        let declined = Handoff.State.declined.rawValue
        let mine = try context.fetch(FetchDescriptor<HandoffRecord>(
            predicate: #Predicate {
                $0.fromPerson == raw && !$0.noticeCleared && !$0.removed && ($0.state == declined || $0.rejected)
            }
        ))
        guard !mine.isEmpty else { return }
        for record in mine {
            record.noticeCleared = true
        }
        try context.save()
    }

    private static func find(_ id: String, in context: ModelContext) throws -> HandoffRecord? {
        var descriptor = FetchDescriptor<HandoffRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
