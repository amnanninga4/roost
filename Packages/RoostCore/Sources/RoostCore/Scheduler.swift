import Foundation

/// One thing someone should do today.
public struct DueItem: Sendable, Hashable, Identifiable {
    /// `"<choreId>#<periodIndex>"`, and for a together chore `"<choreId>#<periodIndex>#<person>"`, so its two
    /// rows are two ids and every other id is unchanged.
    public var id: String {
        chore.together ? "\(chore.id)#\(periodIndex)#\(person.rawValue)" : "\(chore.id)#\(periodIndex)"
    }

    public let chore: Chore
    public let person: Person
    /// The period this item belongs to (the oldest incomplete one for the chore).
    public let periodIndex: Int
    /// Start of the first day of that period.
    public let periodStart: Date
    /// Start of the last day of that period.
    public let periodLastDay: Date
    /// The first and last day the chore is actually due inside that period — the period itself unless the
    /// chore has a window (`weekdays` or `dueDay`). Overdue counting begins the day after `dueLastDay`.
    public let dueFirstDay: Date
    public let dueLastDay: Date
    /// 0 while the window (or period) is still open; otherwise whole days past `dueLastDay`.
    public let daysOverdue: Int
    public var stage: EscalationStage {
        EscalationStage.stage(daysOverdue: daysOverdue)
    }
}

extension DueItem {
    /// The same item owed by the other person. Only the balancing pass uses this.
    func with(person: Person) -> DueItem {
        DueItem(
            chore: chore,
            person: person,
            periodIndex: periodIndex,
            periodStart: periodStart,
            periodLastDay: periodLastDay,
            dueFirstDay: dueFirstDay,
            dueLastDay: dueLastDay,
            daysOverdue: daysOverdue
        )
    }
}

/// Computes what is due for each person on a given day.
///
/// Model: every chore has integer periods per its cadence (see `HouseholdCalendar`). A chore is complete
/// for a period if any completion falls inside that period. The scheduler surfaces the OLDEST incomplete
/// period on or after `activeFrom`, carried forward until someone completes the chore. Completing it in
/// the current period clears all older missed periods (one nag, not a backlog).
///
/// Due windows (`Chore.weekdays` / `Chore.dueDay`) narrow when a chore is due inside its period and move
/// when "late" starts (`daysOverdue` counts from `dueLastDay`). Two extra rules: **never owed** — a window
/// that closed before `activeFrom` bumps the floor to the next period; **not yet** — when the oldest
/// incomplete period is the current one and today is before `dueFirstDay`, the chore is not returned.
///
/// Assignment, in order: an accepted `Handoff` for that exact period wins; otherwise the chore's pin; otherwise
/// the `Rotation`. Handoffs are optional everywhere, so a caller that does not use them behaves as before.
///
/// `plan(on:completions:handoffs:)` then runs the optional `balancer` over the whole day's list, which can move
/// an item that is unpinned, un-handed-off, and still inside its period. Nothing else consults the balancer:
/// `assignee(for:periodIndex:)` and `dueItem(...)` answer for one chore at a time and cannot balance a list
/// they cannot see, so `Tallies` and anything else walking history gets the unbalanced answer: handoff, then
/// pin, then rotation.
public struct Scheduler: Sendable {
    public let chores: [Chore]
    public let rotation: Rotation
    public let calendar: HouseholdCalendar
    /// Periods before this date are ignored. Set it to the day the household started using Roost.
    public let activeFrom: Date
    /// nil is today's behaviour: no balancing pass, every item stays where handoff, pin, or rotation put it.
    public let balancer: FairnessBalancer?

    public init(
        chores: [Chore],
        activeFrom: Date,
        rotation: Rotation = RoundRobinRotation(),
        calendar: HouseholdCalendar = HouseholdCalendar(),
        balancer: FairnessBalancer? = nil
    ) {
        self.chores = chores
        self.activeFrom = activeFrom
        self.rotation = rotation
        self.calendar = calendar
        self.balancer = balancer
    }

    public func assignee(for chore: Chore, periodIndex: Int) -> Person {
        chore.fixedAssignee ?? rotation.assignee(for: chore, periodIndex: periodIndex)
    }

    /// Same, except an accepted handoff for that exact period outranks both the pin and the rotation — whether
    /// that period is the current one or one long past, because an accepted turn does not expire. That is what
    /// keeps an overdue item with the person who took it, and what lets `Tallies.streak` read history. Pending,
    /// declined, and expired handoffs change nothing; `date` is only what a pending offer is judged against.
    public func assignee(for chore: Chore, periodIndex: Int, on date: Date, handoffs: [Handoff]) -> Person {
        let override = HandoffRules.acceptedOverride(
            choreId: chore.id,
            periodIndex: periodIndex,
            in: handoffs,
            on: date,
            calendar: calendar
        )
        return override?.to ?? assignee(for: chore, periodIndex: periodIndex)
    }

    /// Everything due on `date`, keyed by person. Items are ordered most overdue first, then by chore order.
    /// With a `balancer`, the day's reassignable items are spread across the two of them before the split.
    public func plan(on date: Date, completions: [Completion], handoffs: [Handoff] = []) -> [Person: [DueItem]] {
        let byChore = Dictionary(grouping: completions, by: \.choreId)
        var items: [DueItem] = []
        for chore in chores {
            let forChore = byChore[chore.id] ?? []
            items += dueItems(for: chore, on: date, completions: forChore, handoffs: handoffs)
        }
        if let balancer {
            items = balancer.balance(
                items,
                chores: chores,
                completions: completions,
                handoffs: handoffs,
                on: date,
                calendar: calendar
            )
        }
        var result: [Person: [DueItem]] = [.anne: [], .wes: []]
        for item in items {
            result[item.person, default: []].append(item)
        }
        for person in Person.allCases {
            result[person]?.sort { lhs, rhs in
                if lhs.daysOverdue != rhs.daysOverdue {
                    return lhs.daysOverdue > rhs.daysOverdue
                }
                return (chores.firstIndex(of: lhs.chore) ?? 0) < (chores.firstIndex(of: rhs.chore) ?? 0)
            }
        }
        return result
    }

    /// The older name for `plan(on:completions:handoffs:)`. Kept so existing callers keep working.
    public func due(on date: Date, completions: [Completion], handoffs: [Handoff] = []) -> [Person: [DueItem]] {
        plan(on: date, completions: completions, handoffs: handoffs)
    }

    /// Every row `chore` puts on the day: none when it is done for the period or out of season, one for an
    /// ordinary chore, and one per person — Anne's then Wes's, same period, same days overdue — for a
    /// together chore. `plan` reads this; `dueItem` is the one-row view of the same answer.
    public func dueItems(
        for chore: Chore,
        on date: Date,
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> [DueItem] {
        guard let item = dueItem(for: chore, on: date, completions: completions, handoffs: handoffs) else { return [] }
        guard chore.together else { return [item] }
        return Person.allCases.map { item.with(person: $0) }
    }

    /// The oldest incomplete period for `chore` as of `date`, or nil if it is done for the current period —
    /// or, for a chore with a season, if the current period started out of season. Inside a season the
    /// floor is the season's first period, so last year's missed weeks never carry into this spring.
    /// For a together chore the row comes back as Anne's; `dueItems` is the call that knows there are two.
    public func dueItem(
        for chore: Chore,
        on date: Date,
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> DueItem? {
        let current = calendar.periodIndex(chore.cadence, containing: date)
        var floor = calendar.periodIndex(chore.cadence, containing: activeFrom)
        // A window that closed before the household started was never owed: start at the next period.
        if chore.hasWindow,
           calendar.dueWindow(for: chore, periodIndex: floor).lastDay < calendar.startOfDay(activeFrom) {
            floor += 1
        }
        if let season = chore.season {
            guard let start = firstPeriod(inSeason: season, endingAt: current, notBefore: floor, cadence: chore.cadence)
            else { return nil }
            floor = max(floor, start)
        }
        let lastDone = completions
            .filter { $0.choreId == chore.id }
            .map { calendar.periodIndex(chore.cadence, containing: $0.completedAt) }
            .max()
        let oldestIncomplete = max((lastDone.map { $0 + 1 }) ?? floor, floor)
        guard oldestIncomplete <= current else { return nil }

        let bounds = calendar.periodBounds(chore.cadence, index: oldestIncomplete)
        let window = calendar.dueWindow(for: chore, periodIndex: oldestIncomplete)
        // Not yet: this period's window has not opened. A missed window from an older period still shows.
        if oldestIncomplete == current, calendar.startOfDay(date) < window.firstDay { return nil }
        let daysOverdue = max(0, calendar.dayIndex(date) - calendar.dayIndex(window.lastDay))
        return DueItem(
            chore: chore,
            person: chore.together
                ? .anne // both of them owe it; `dueItems` hands out the second row
                : assignee(for: chore, periodIndex: oldestIncomplete, on: date, handoffs: handoffs),
            periodIndex: oldestIncomplete,
            periodStart: bounds.firstDay,
            periodLastDay: bounds.lastDay,
            dueFirstDay: window.firstDay,
            dueLastDay: window.lastDay,
            daysOverdue: daysOverdue
        )
    }

    /// The first period of the run of in-season periods that ends at `current`: `current` itself when the
    /// period before it started out of season, earlier when the season has been running. Nil when `current`
    /// started out of season. The walk stops at `floor`, so a season that never ends still starts where the
    /// household did.
    func firstPeriod(inSeason season: Season, endingAt current: Int, notBefore floor: Int, cadence: Cadence) -> Int? {
        func inSeason(_ index: Int) -> Bool {
            season.contains(month: calendar.month(of: calendar.periodBounds(cadence, index: index).firstDay))
        }
        guard inSeason(current) else { return nil }
        var start = current
        while start - 1 >= floor, inSeason(start - 1) {
            start -= 1
        }
        return start
    }
}
