// What the Tasks tab needs to know about handoffs, worked out here rather than in a view.
//
// `HandoffSnapshot` is one handoff as the phone knows it: RoostCore's value plus the three facts only
// the phone has — whether the offer ever reached the server, whether the server refused it, and whether
// its one-line note has been read. Everything else below is derived from a list of those, and every
// question about eligibility goes through `RoostCore.HandoffRules`, never through a rule spelled out
// again here.
import Foundation
import RoostCore

struct HandoffSnapshot: Hashable, Sendable, Identifiable {
    let handoff: Handoff
    /// The offer is on the server. Also the answer to "can this still be taken back": it cannot, because
    /// there is no withdraw endpoint.
    let reachedServer: Bool
    /// The server refused the offer (400, 403, or 409). It exists on this phone only, and always will.
    let refused: Bool
    /// The "Wes said no" line has been read, so it is not shown again.
    let noticeCleared: Bool

    init(handoff: Handoff, reachedServer: Bool = true, refused: Bool = false, noticeCleared: Bool = false) {
        self.handoff = handoff
        self.reachedServer = reachedServer
        self.refused = refused
        self.noticeCleared = noticeCleared
    }

    var id: String {
        handoff.id
    }
}

/// What a handoff is doing to one row of the Tasks tab. Nil for the overwhelming majority of rows.
enum RowHandoff: Hashable, Sendable {
    /// You offered it and nobody has answered yet. `canWithdraw` is false the moment the offer is on the
    /// server, because there is nothing there to withdraw it with.
    case waiting(on: Person, id: String, canWithdraw: Bool)
    /// You are doing this turn because the other person handed it over: the chip says who from.
    case takenFrom(Person)
    /// They said no. Clears on the next check-off, and on its own when the period ends.
    case declined(by: Person)
    /// The server would not take the offer. One line, then it is gone.
    case refused(to: Person)
}

/// A pending offer waiting for this person's answer: the card at the top of their column.
struct IncomingOffer: Identifiable, Hashable, Sendable {
    let id: String
    let chore: Chore
    let from: Person
    let cadence: Cadence
}

extension Cadence {
    /// Which period an offer covers, in words: "today", "this week", "this month". The same mapping
    /// `periodPhrase` in server/src/push.js uses, biweekly reading as "this week" there too, so the card
    /// on the phone and the notification that arrived before it say the same thing.
    var periodPhrase: String {
        switch self {
        case .daily: Strings.Handoffs.periodToday
        case .weekly, .biweekly: Strings.Handoffs.periodWeek
        case .monthly: Strings.Handoffs.periodMonth
        }
    }
}

enum HandoffPresentation {
    /// The live handoffs, in RoostCore's terms: everything the server has or will have. A refused offer
    /// is not one of them — it exists on this phone and nowhere else, so letting it decide who owes a
    /// chore would put the two phones out of step.
    static func live(_ snapshots: [HandoffSnapshot]) -> [Handoff] {
        snapshots.filter { !$0.refused }.map(\.handoff)
    }

    /// What to show on `person`'s row for `chore` in `periodIndex`, in priority order: a turn that was
    /// taken (a settled fact), then an offer still waiting, then a refusal, then a no. An expired offer
    /// shows nothing at all — nobody answered, and saying so a week later helps no one.
    static func rowHandoff(
        chore: Chore,
        person: Person,
        periodIndex: Int,
        snapshots: [HandoffSnapshot],
        on date: Date,
        calendar: HouseholdCalendar
    ) -> RowHandoff? {
        let mine = snapshots.filter { $0.handoff.choreId == chore.id && $0.handoff.periodIndex == periodIndex }

        if let taken = HandoffRules.acceptedOverride(
            choreId: chore.id,
            periodIndex: periodIndex,
            in: live(mine),
            on: date,
            calendar: calendar
        ), taken.to == person {
            return .takenFrom(taken.from)
        }

        let state = { (snapshot: HandoffSnapshot) in
            HandoffRules.effectiveState(snapshot.handoff, on: date, calendar: calendar)
        }
        let byNewest = mine.sorted { $0.handoff.createdAt > $1.handoff.createdAt }

        if let waiting = byNewest.first(where: {
            !$0.refused && $0.handoff.from == person && state($0) == .pending
        }) {
            return .waiting(on: waiting.handoff.to, id: waiting.handoff.id, canWithdraw: !waiting.reachedServer)
        }
        if let refused = byNewest.first(where: { $0.refused && $0.handoff.from == person && !$0.noticeCleared }) {
            return .refused(to: refused.handoff.to)
        }
        if let declined = byNewest.first(where: {
            !$0.refused && $0.handoff.from == person && !$0.noticeCleared && state($0) == .declined
        }) {
            return .declined(by: declined.handoff.to)
        }
        return nil
    }

    /// Offers `person` has been asked to answer: pending, still inside their period, for a chore this
    /// phone knows about. One card each, newest last so the order does not jump as answers land.
    static func incomingOffers(
        for person: Person,
        chores: [String: Chore],
        snapshots: [HandoffSnapshot],
        on date: Date,
        calendar: HouseholdCalendar
    ) -> [IncomingOffer] {
        snapshots
            .filter { !$0.refused && $0.handoff.to == person }
            .filter { HandoffRules.effectiveState($0.handoff, on: date, calendar: calendar) == .pending }
            .sorted { $0.handoff.createdAt < $1.handoff.createdAt }
            .compactMap { snapshot in
                guard let chore = chores[snapshot.handoff.choreId] else { return nil }
                return IncomingOffer(
                    id: snapshot.handoff.id,
                    chore: chore,
                    from: snapshot.handoff.from,
                    cadence: snapshot.handoff.cadence
                )
            }
    }
}
