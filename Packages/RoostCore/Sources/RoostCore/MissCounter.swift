import Foundation

/// Counts the days someone owed a chore and nobody did it. Pure: no storage, no clock beyond `asOf`.
///
/// A day is a miss when its period ended before today, started on or after `activeFrom`, was owed by
/// that person (an accepted handoff, then the pin, then the chore's own rotation, then the fallback),
/// and carries no completion by anyone. A partner's cover clears the chore but does not un-miss the
/// day for whoever owed it — the rule is about the person who owed it.
public enum MissCounter {
    // Plan interface: watched + bounds + asOf + activeFrom + completions + handoffs + calendar + fallback.
    // swiftlint:disable:next function_parameter_count
    public static func misses(
        watched: Chore, from: Date, through: Date, asOf: Date,
        activeFrom: Date, completions: [Completion], handoffs: [Handoff],
        calendar: HouseholdCalendar, fallback: Rotation
    ) -> [Person: Int] {
        let floor = calendar.periodIndex(watched.cadence, containing: activeFrom)
        let today = calendar.periodIndex(watched.cadence, containing: asOf)
        let first = max(calendar.periodIndex(watched.cadence, containing: from), floor)
        let last = min(calendar.periodIndex(watched.cadence, containing: through), today - 1)
        guard first <= last else { return [:] }

        var donePeriods = Set<Int>()
        for completion in completions where completion.choreId == watched.id {
            donePeriods.insert(calendar.periodIndex(watched.cadence, containing: completion.completedAt))
        }

        var counts: [Person: Int] = [:]
        for period in first ... last where !donePeriods.contains(period) {
            let owner = HandoffRules.acceptedOverride(
                choreId: watched.id,
                periodIndex: period,
                in: handoffs,
                on: asOf,
                calendar: calendar
            )?.to
                ?? watched.fixedAssignee
                ?? watched.rotation?.assignee(periodIndex: period)
                ?? fallback.assignee(for: watched, periodIndex: period)
            counts[owner, default: 0] += 1
        }
        return counts
    }

    /// The person a penalty moves the chore to: the only one over the line, or the one further over.
    /// Nil when neither is over or they are tied, which leaves the rotation's answer standing.
    public static func penalised(_ counts: [Person: Int], overMisses: Int) -> Person? {
        let over = Person.allCases.filter { (counts[$0] ?? 0) > overMisses }
        guard let first = over.first else { return nil }
        guard over.count > 1 else { return first }
        let ranked = over.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        guard (counts[ranked[0]] ?? 0) != (counts[ranked[1]] ?? 0) else { return nil }
        return ranked[0]
    }
}
