import Foundation

/// One person offering their turn at a chore to the other, for a single period.
///
/// A handoff never changes whose chore it is in general — not the pin, not the rotation. It only changes who
/// owes it for `periodIndex`, and only once the other person has accepted. When that period ends the handoff
/// is over (`hasExpired(on:)`), so next period goes back to whatever the pin or the rotation says.
public struct Handoff: Codable, Sendable, Hashable, Identifiable {
    public enum State: String, Codable, Sendable, CaseIterable, Hashable {
        /// Offered, not answered yet. Changes nothing.
        case pending
        /// Taken. Overrides the pin and the rotation for this period.
        case accepted
        /// Turned down. Changes nothing, and the offerer may ask again.
        case declined
        /// The period ended. Changes nothing, and nothing can change it back.
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

    /// True once `date` is in a later period than the one handed off.
    public func hasExpired(on date: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> Bool {
        calendar.periodIndex(cadence, containing: date) > periodIndex
    }

    /// Pending and accepted are "open": the offer is still live, so a second offer for the same chore and
    /// period would be a second open handoff. Declined and expired are closed.
    public var isOpen: Bool {
        state == .pending || state == .accepted
    }
}
