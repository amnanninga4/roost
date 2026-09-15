import Foundation

/// What one chore is worth when weighing up how much of a period someone is carrying.
///
/// PROVISIONAL. Nobody has agreed these numbers; they are a guess that a bigger, rarer job should count for
/// more than a two-minute one (cleaning inside the ovens is most of an evening, scooping the litter is not).
/// They are the one knob that changes how `FairnessBalancer` behaves, so they live in one place: change them
/// here and the balancer, the README table, and eventually the Node mirror all follow.
public struct FairnessWeights: Codable, Sendable, Hashable {
    public var daily: Int
    public var weekly: Int
    public var biweekly: Int
    public var monthly: Int
    public var bimonthly: Int
    public var quarterly: Int

    public init(daily: Int, weekly: Int, biweekly: Int, monthly: Int, bimonthly: Int, quarterly: Int) {
        self.daily = daily
        self.weekly = weekly
        self.biweekly = biweekly
        self.monthly = monthly
        self.bimonthly = bimonthly
        self.quarterly = quarterly
    }

    /// daily 1, weekly 3, biweekly 5, monthly 8, bimonthly 10, quarterly 13.
    public static let provisional = FairnessWeights(
        daily: 1,
        weekly: 3,
        biweekly: 5,
        monthly: 8,
        bimonthly: 10,
        quarterly: 13
    )

    public func weight(for cadence: Cadence) -> Int {
        switch cadence {
        case .daily: daily
        case .weekly: weekly
        case .biweekly: biweekly
        case .monthly: monthly
        case .bimonthly: bimonthly
        case .quarterly: quarterly
        }
    }
}

/// Splits a period's work between the two of them instead of alternating chore by chore.
///
/// The unit is the whole list, not one chore. `Scheduler.plan(on:completions:handoffs:)` builds the day's items
/// the normal way — an accepted handoff wins, then the pin, then the rotation — and then, if it was given a
/// balancer, walks the master chore list in order and gives each *reassignable* item to whoever is carrying
/// less so far. An item is reassignable only when all four hold:
///
/// - it is unpinned,
/// - no accepted handoff covers it,
/// - it is still inside its own period (`daysOverdue == 0`),
/// - it is not a together chore (those are not weighed either: nobody's side of the scale is the right one).
///
/// Everything else keeps the person it already had. Overdue items in particular are never moved: that person
/// was already told it was theirs and probably notified about it, and shuffling a nag between columns is how
/// an app loses trust.
///
/// Each of them starts the walk carrying a background load — weighted completions over the trailing
/// `windowDays` Chicago days, minus whatever they did inside a chore's *current* period, which is counted at
/// that chore's own slot in the walk instead. That split is the whole trick behind stability: finishing
/// something turns it from a chosen item into a fixed one at the same position with the same weight, so every
/// other item on the list keeps its person. Without it, checking one thing off at lunchtime would reshuffle
/// the rest of the day.
///
/// Pure and deterministic: the walk follows `chores`, which is the same on both phones, so neither the order
/// of the completion rows nor the order of the due items can change the answer.
public struct FairnessBalancer: Sendable {
    /// How many trailing Chicago days count toward the load, today included. PROVISIONAL, like the weights.
    public static let windowDays = 14

    public let weights: FairnessWeights

    public init(weights: FairnessWeights = .provisional) {
        self.weights = weights
    }

    /// Weighted completions per person over the trailing `windowDays` Chicago days — what each of them has
    /// actually done lately, which is the number worth showing in the app. The walk starts from
    /// `backgroundLoads` instead, which is this minus the current period.
    public func windowLoads(
        chores: [Chore],
        completions: [Completion],
        asOf date: Date,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> [Person: Int] {
        loads(chores: chores, completions: completions, asOf: date, calendar: calendar, dropCurrentPeriod: false)
    }

    /// Whether the pass is allowed to move this item.
    public func isReassignable(
        _ item: DueItem,
        handoffs: [Handoff] = [],
        on date: Date,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> Bool {
        guard !item.chore.isPinned, !item.chore.together, item.daysOverdue == 0,
              item.chore.rotation == nil, item.chore.missPenalty == nil else { return false }
        return HandoffRules.acceptedOverride(
            choreId: item.chore.id,
            periodIndex: item.periodIndex,
            in: handoffs,
            on: date,
            calendar: calendar
        ) == nil
    }

    /// The pass. `items` is one plan's worth of due items; the result is the same items, some of them now owed
    /// by the other person. Items whose chore is not in `chores` are returned untouched.
    public func balance(
        _ items: [DueItem],
        chores: [Chore],
        completions: [Completion],
        handoffs: [Handoff] = [],
        on date: Date,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> [DueItem] {
        var projected = backgroundLoads(chores: chores, completions: completions, asOf: date, calendar: calendar)
        let itemByChore = Dictionary(items.map { ($0.chore.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reassigned: [String: Person] = [:]

        for chore in chores {
            if chore.together { continue } // owed by both, moved by nobody, weighed by nobody
            let weight = weights.weight(for: chore.cadence)

            // Already done for this period: it is nobody's item any more, but it was this period's work and it
            // counts for whoever did it, at this slot.
            if let finisher = currentPeriodFinisher(chore, completions: completions, on: date, calendar: calendar) {
                projected[finisher, default: 0] += weight
                continue
            }
            guard let item = itemByChore[chore.id] else { continue }
            guard isReassignable(item, handoffs: handoffs, on: date, calendar: calendar) else {
                projected[item.person, default: 0] += weight
                continue
            }

            let anne = projected[.anne] ?? 0
            let wes = projected[.wes] ?? 0
            // Level means the rotation decides, which is round robin's answer for this chore and period.
            let owner: Person = anne == wes ? item.person : (anne < wes ? .anne : .wes)
            projected[owner, default: 0] += weight
            reassigned[item.id] = owner
        }

        return items.map { item in
            guard let owner = reassigned[item.id], owner != item.person else { return item }
            return item.with(person: owner)
        }
    }

    /// The window minus anything done inside a chore's current period. Those completions are not lost: the walk
    /// counts them at their own slot, so the totals match `windowLoads` and only the position differs.
    func backgroundLoads(
        chores: [Chore],
        completions: [Completion],
        asOf date: Date,
        calendar: HouseholdCalendar
    ) -> [Person: Int] {
        loads(chores: chores, completions: completions, asOf: date, calendar: calendar, dropCurrentPeriod: true)
    }

    /// Whoever finished `chore` inside its current period, or nil. The latest completion wins, ties break on
    /// id, so two phones looking at the same rows agree.
    func currentPeriodFinisher(
        _ chore: Chore,
        completions: [Completion],
        on date: Date,
        calendar: HouseholdCalendar
    ) -> Person? {
        let current = calendar.periodIndex(chore.cadence, containing: date)
        return completions
            .filter {
                $0.choreId == chore.id
                    && calendar.periodIndex(chore.cadence, containing: $0.completedAt) == current
            }
            .max {
                $0.completedAt < $1.completedAt || ($0.completedAt == $1.completedAt && $0.id < $1.id)
            }?
            .person
    }

    private func loads(
        chores: [Chore],
        completions: [Completion],
        asOf date: Date,
        calendar: HouseholdCalendar,
        dropCurrentPeriod: Bool
    ) -> [Person: Int] {
        let lastDay = calendar.dayIndex(date)
        let windowStart = calendar.day(at: lastDay - (FairnessBalancer.windowDays - 1))
        let windowEnd = calendar.day(at: lastDay + 1)
        // A completion whose chore is not in the list cannot be weighted, and guessing would make the answer
        // depend on data we do not have, so it is skipped.
        let cadenceByChore = Dictionary(chores.map { ($0.id, $0.cadence) }, uniquingKeysWith: { first, _ in first })
        let together = Set(chores.filter(\.together).map(\.id))

        var loads: [Person: Int] = [:]
        for person in Person.allCases {
            loads[person] = 0
        }
        for completion in completions {
            guard completion.completedAt >= windowStart, completion.completedAt < windowEnd else { continue }
            guard !together.contains(completion.choreId) else { continue }
            guard let cadence = cadenceByChore[completion.choreId] else { continue }
            let itsPeriod = calendar.periodIndex(cadence, containing: completion.completedAt)
            let currentPeriod = calendar.periodIndex(cadence, containing: date)
            if dropCurrentPeriod, itsPeriod == currentPeriod {
                continue
            }
            loads[completion.person, default: 0] += weights.weight(for: cadence)
        }
        return loads
    }
}
