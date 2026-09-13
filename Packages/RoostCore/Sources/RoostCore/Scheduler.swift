import Foundation

/// One thing someone should do today.
public struct DueItem: Sendable, Hashable, Identifiable {
    public var id: String {
        "\(chore.id)#\(periodIndex)"
    }

    public let chore: Chore
    public let person: Person
    /// The period this item belongs to (the oldest incomplete one for the chore).
    public let periodIndex: Int
    /// Start of the first day of that period.
    public let periodStart: Date
    /// Start of the last day of that period. Overdue counting begins the day after.
    public let periodLastDay: Date
    /// 0 while the period is still open; otherwise whole days past its last day.
    public let daysOverdue: Int
    public var stage: EscalationStage {
        EscalationStage.stage(daysOverdue: daysOverdue)
    }
}

/// Computes what is due for each person on a given day.
///
/// Model: every chore has integer periods per its cadence (see `HouseholdCalendar`). A chore is complete
/// for a period if any completion falls inside that period. The scheduler surfaces the OLDEST incomplete
/// period on or after `activeFrom`, carried forward until someone completes the chore. Completing it in
/// the current period clears all older missed periods (one nag, not a backlog).
///
/// Assignment, in order: an accepted `Handoff` for that exact period wins; otherwise the chore's pin; otherwise
/// the `Rotation`. Handoffs are optional everywhere, so a caller that does not use them behaves as before.
public struct Scheduler: Sendable {
    public let chores: [Chore]
    public let rotation: Rotation
    public let calendar: HouseholdCalendar
    /// Periods before this date are ignored. Set it to the day the household started using Roost.
    public let activeFrom: Date

    public init(
        chores: [Chore],
        activeFrom: Date,
        rotation: Rotation = RoundRobinRotation(),
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) {
        self.chores = chores
        self.activeFrom = activeFrom
        self.rotation = rotation
        self.calendar = calendar
    }

    public func assignee(for chore: Chore, periodIndex: Int) -> Person {
        chore.fixedAssignee ?? rotation.assignee(for: chore, periodIndex: periodIndex)
    }

    /// Same, except an accepted handoff for that exact period — still live on `date` — outranks both the pin
    /// and the rotation. Pending, declined, and expired handoffs change nothing.
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
    public func plan(on date: Date, completions: [Completion], handoffs: [Handoff] = []) -> [Person: [DueItem]] {
        let byChore = Dictionary(grouping: completions, by: \.choreId)
        var result: [Person: [DueItem]] = [.anne: [], .wes: []]
        for chore in chores {
            let forChore = byChore[chore.id] ?? []
            guard let item = dueItem(for: chore, on: date, completions: forChore, handoffs: handoffs) else {
                continue
            }
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

    /// The oldest incomplete period for `chore` as of `date`, or nil if it is done for the current period.
    public func dueItem(
        for chore: Chore,
        on date: Date,
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> DueItem? {
        let current = calendar.periodIndex(chore.cadence, containing: date)
        let floor = calendar.periodIndex(chore.cadence, containing: activeFrom)
        let lastDone = completions
            .filter { $0.choreId == chore.id }
            .map { calendar.periodIndex(chore.cadence, containing: $0.completedAt) }
            .max()
        let oldestIncomplete = max((lastDone.map { $0 + 1 }) ?? floor, floor)
        guard oldestIncomplete <= current else { return nil }

        let bounds = calendar.periodBounds(chore.cadence, index: oldestIncomplete)
        let daysOverdue = max(0, calendar.dayIndex(date) - calendar.dayIndex(bounds.lastDay))
        return DueItem(
            chore: chore,
            person: assignee(for: chore, periodIndex: oldestIncomplete, on: date, handoffs: handoffs),
            periodIndex: oldestIncomplete,
            periodStart: bounds.firstDay,
            periodLastDay: bounds.lastDay,
            daysOverdue: daysOverdue
        )
    }
}
