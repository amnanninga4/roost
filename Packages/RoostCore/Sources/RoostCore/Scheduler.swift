import Foundation

/// One thing someone should do today.
public struct DueItem: Sendable, Hashable, Identifiable {
    public var id: String { "\(chore.id)#\(periodIndex)" }
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
    public var stage: EscalationStage { EscalationStage.stage(daysOverdue: daysOverdue) }
}

/// Computes what is due for each person on a given day.
///
/// Model: every chore has integer periods per its cadence (see `HouseholdCalendar`). A chore is complete
/// for a period if any completion falls inside that period. The scheduler surfaces the OLDEST incomplete
/// period on or after `activeFrom`, carried forward until someone completes the chore. Completing it in
/// the current period clears all older missed periods (one nag, not a backlog).
public struct Scheduler: Sendable {
    public let chores: [Chore]
    public let rotation: Rotation
    public let calendar: HouseholdCalendar
    /// Periods before this date are ignored. Set it to the day the household started using Roost.
    public let activeFrom: Date

    public init(chores: [Chore], activeFrom: Date, rotation: Rotation = RoundRobinRotation(), calendar: HouseholdCalendar = HouseholdCalendar()) {
        self.chores = chores
        self.activeFrom = activeFrom
        self.rotation = rotation
        self.calendar = calendar
    }

    public func assignee(for chore: Chore, periodIndex: Int) -> Person {
        chore.fixedAssignee ?? rotation.assignee(for: chore, periodIndex: periodIndex)
    }

    /// Everything due on `date`, keyed by person. Items are ordered most overdue first, then by chore order.
    public func due(on date: Date, completions: [Completion]) -> [Person: [DueItem]] {
        let byChore = Dictionary(grouping: completions, by: \.choreId)
        var result: [Person: [DueItem]] = [.anne: [], .wes: []]
        for chore in chores {
            guard let item = dueItem(for: chore, on: date, completions: byChore[chore.id] ?? []) else { continue }
            result[item.person, default: []].append(item)
        }
        for person in Person.allCases {
            result[person]?.sort { a, b in
                if a.daysOverdue != b.daysOverdue { return a.daysOverdue > b.daysOverdue }
                return (chores.firstIndex(of: a.chore) ?? 0) < (chores.firstIndex(of: b.chore) ?? 0)
            }
        }
        return result
    }

    /// The oldest incomplete period for `chore` as of `date`, or nil if it is done for the current period.
    public func dueItem(for chore: Chore, on date: Date, completions: [Completion]) -> DueItem? {
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
            person: assignee(for: chore, periodIndex: oldestIncomplete),
            periodIndex: oldestIncomplete,
            periodStart: bounds.firstDay,
            periodLastDay: bounds.lastDay,
            daysOverdue: daysOverdue
        )
    }
}
