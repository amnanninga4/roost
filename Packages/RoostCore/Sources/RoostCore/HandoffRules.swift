import Foundation

/// Who may offer a chore away, and what an answer does to the offer.
///
/// The rules are deliberately thin: only the person who owes the chore right now can offer it, and there can be
/// one open offer per chore per period. Everything else is the `Scheduler`'s job — see
/// `Scheduler.plan(on:completions:handoffs:)` for how an accepted handoff lands on the day's list.
public struct HandoffRules: Sendable {
    /// What the person being asked said.
    public enum Decision: String, Sendable, Hashable, CaseIterable {
        case accept
        case decline
    }

    public let scheduler: Scheduler
    /// Every handoff the caller knows about, any state, any period.
    public let handoffs: [Handoff]

    public var calendar: HouseholdCalendar {
        scheduler.calendar
    }

    public init(scheduler: Scheduler, handoffs: [Handoff] = []) {
        self.scheduler = scheduler
        self.handoffs = handoffs
    }

    /// The period an offer made on `date` would cover: the chore's current one.
    public func currentPeriod(for chore: Chore, on date: Date) -> Int {
        calendar.periodIndex(chore.cadence, containing: date)
    }

    /// Only the person who owes the chore for the current period may offer it, and only if no offer for that
    /// chore and period is already open. An accepted handoff makes `to` the owner, so they are the one who
    /// could offer it onward — except that the accepted handoff is itself still open, so nobody can stack a
    /// second offer on the same period.
    public func canOffer(_ chore: Chore, from person: Person, on date: Date) -> Bool {
        let period = currentPeriod(for: chore, on: date)
        guard scheduler.assignee(for: chore, periodIndex: period, on: date, handoffs: handoffs) == person else {
            return false
        }
        return openHandoff(for: chore, on: date) == nil
    }

    /// The handoff `person` would be creating, or nil if `canOffer` says they cannot.
    /// `id` is the caller's to mint (the app and the server both generate their own row ids).
    public func offer(
        _ chore: Chore,
        from person: Person,
        to other: Person,
        on date: Date,
        id: String
    ) -> Handoff? {
        guard person != other, canOffer(chore, from: person, on: date) else { return nil }
        return Handoff(
            id: id,
            choreId: chore.id,
            from: person,
            to: other,
            periodIndex: currentPeriod(for: chore, on: date),
            cadence: chore.cadence,
            createdAt: date,
            state: .pending
        )
    }

    /// The open offer for `chore`'s current period, if there is one.
    public func openHandoff(for chore: Chore, on date: Date) -> Handoff? {
        HandoffRules.openHandoff(
            choreId: chore.id,
            periodIndex: currentPeriod(for: chore, on: date),
            in: handoffs,
            on: date,
            calendar: calendar
        )
    }

    /// Answering one offer. Answering after its period ended expires it instead — too late to take a turn that
    /// is already over. An offer that was already answered keeps its answer.
    public func resolve(_ handoff: Handoff, as decision: Decision, on date: Date) -> Handoff {
        if handoff.hasExpired(on: date, calendar: calendar) {
            return handoff.state == .expired ? handoff : handoff.with(state: .expired)
        }
        guard handoff.state == .pending else { return handoff }
        return handoff.with(state: decision == .accept ? .accepted : .declined)
    }

    /// The whole set with every open handoff whose period has ended marked `.expired`. Run it when the day
    /// rolls over. Declined handoffs are left alone: the record that someone said no is worth keeping.
    public func resolve(on date: Date) -> [Handoff] {
        handoffs.map { handoff in
            guard handoff.isOpen, handoff.hasExpired(on: date, calendar: calendar) else { return handoff }
            return handoff.with(state: .expired)
        }
    }

    /// What a handoff counts as on `date`: its stored state, or `.expired` once its period has ended.
    public static func effectiveState(
        _ handoff: Handoff,
        on date: Date,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> Handoff.State {
        if handoff.isOpen, handoff.hasExpired(on: date, calendar: calendar) {
            return .expired
        }
        return handoff.state
    }

    /// The accepted handoff that decides who owes `choreId` for `periodIndex`, or nil if rotation and pins win.
    /// Pending and declined handoffs are not overrides, and an accepted one stops being one when its period ends.
    public static func acceptedOverride(
        choreId: String,
        periodIndex: Int,
        in handoffs: [Handoff],
        on date: Date,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> Handoff? {
        handoffs
            .filter { $0.choreId == choreId && $0.periodIndex == periodIndex }
            .filter { effectiveState($0, on: date, calendar: calendar) == .accepted }
            .min { $0.createdAt < $1.createdAt || ($0.createdAt == $1.createdAt && $0.id < $1.id) }
    }

    /// The open (pending or accepted, not past its period) handoff for one chore and period.
    public static func openHandoff(
        choreId: String,
        periodIndex: Int,
        in handoffs: [Handoff],
        on date: Date,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> Handoff? {
        handoffs
            .filter { $0.choreId == choreId && $0.periodIndex == periodIndex }
            .filter { effectiveState($0, on: date, calendar: calendar).isOpenState }
            .min { $0.createdAt < $1.createdAt || ($0.createdAt == $1.createdAt && $0.id < $1.id) }
    }
}

extension Handoff.State {
    /// Same idea as `Handoff.isOpen`, for a state on its own.
    var isOpenState: Bool {
        self == .pending || self == .accepted
    }
}
