import Foundation

/// One person offering their turn at a chore to the other, for a single period.
///
/// A handoff never changes whose chore it is in general — not the pin, not the rotation. It only changes who
/// owes it for `periodIndex`, and only once the other person has accepted. The next period goes back to
/// whatever the pin or the rotation says because it is a different period, not because the handoff went away:
/// an accepted handoff is a permanent fact about its own period and never expires, which is what lets a streak
/// or an overdue item still read who owed what last Tuesday. Only an offer nobody answered in time expires
/// (`hasExpired(on:)`).
public struct Handoff: Codable, Sendable, Hashable, Identifiable {
    public enum State: String, Codable, Sendable, CaseIterable, Hashable {
        /// Offered, not answered yet. Changes nothing.
        case pending
        /// Taken. Overrides the pin and the rotation for this period, for good — asked about that period a
        /// month later, this is still the answer.
        case accepted
        /// Turned down. Changes nothing, and the offerer may ask again.
        case declined
        /// The period ended with the offer unanswered. Changes nothing, and nothing can change it back.
        case expired
    }

    public let id: String
    public let choreId: String
    /// The person who owed the chore for this period and offered it away.
    public let from: Person
    /// The person being asked, and the owner for this period once they accept.
    public let to: Person
    /// The period being handed off, in `cadence`'s own period numbering (see `HouseholdCalendar`).
    public let periodIndex: Int
    /// The chore's cadence, carried on the handoff so the period math needs nothing else.
    public let cadence: Cadence
    public let createdAt: Date
    public let state: State

    public init(
        id: String,
        choreId: String,
        from: Person,
        to: Person,
        periodIndex: Int,
        cadence: Cadence,
        createdAt: Date,
        state: State = .pending
    ) {
        self.id = id
        self.choreId = choreId
        self.from = from
        self.to = to
        self.periodIndex = periodIndex
        self.cadence = cadence
        self.createdAt = createdAt
        self.state = state
    }

    /// The same handoff in another state. Fields are `let`; this is how you move one along.
    public func with(state: State) -> Handoff {
        Handoff(
            id: id,
            choreId: choreId,
            from: from,
            to: to,
            periodIndex: periodIndex,
            cadence: cadence,
            createdAt: createdAt,
            state: state
        )
    }

    /// True once `date` is in a later period than the one handed off. Period arithmetic only, no opinion about
    /// whether that matters: for an accepted handoff it does not.
    public func isPastItsPeriod(on date: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> Bool {
        calendar.periodIndex(cadence, containing: date) > periodIndex
    }

    /// True for an offer nobody answered in time. Expiry applies to `pending` and nothing else: an accepted
    /// turn is a fact about its period rather than a live offer, so it stands for good, and a declined one
    /// keeps the record that someone said no.
    public func hasExpired(on date: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> Bool {
        state == .pending && isPastItsPeriod(on: date, calendar: calendar)
    }

    /// Pending and accepted are "open": one is still waiting for an answer, the other has settled the period,
    /// and either way a second offer for the same chore and period would be a second open handoff. Declined
    /// and expired are closed, so the offerer may ask again.
    public var isOpen: Bool {
        state == .pending || state == .accepted
    }
}
