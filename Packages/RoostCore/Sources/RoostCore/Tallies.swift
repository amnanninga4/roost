import Foundation

/// Weekly counts and streaks. Both are provisional rules; see README.
public struct Tallies: Sendable {
    public let scheduler: Scheduler
    public var calendar: HouseholdCalendar {
        scheduler.calendar
    }

    public init(scheduler: Scheduler) {
        self.scheduler = scheduler
    }

    /// Completions per person in the Monday-to-Sunday (Chicago) week containing `date`. A together chore's
    /// completion is one row credited to both of them: it was both their turn.
    public func doneThisWeek(asOf date: Date, completions: [Completion]) -> [Person: Int] {
        let week = calendar.weekBounds(containing: date)
        let together = Set(scheduler.chores.filter(\.together).map(\.id))
        var counts: [Person: Int] = [.anne: 0, .wes: 0]
        for c in completions where c.completedAt >= week.start && c.completedAt < week.end {
            if together.contains(c.choreId) {
                for person in Person.allCases {
                    counts[person, default: 0] += 1
                }
            } else {
                counts[c.person, default: 0] += 1
            }
        }
        return counts
    }

    /// Consecutive days, ending today or yesterday, on which `person` completed every daily chore assigned
    /// to them. Today counts only once it is fully done; an unfinished today does not break the streak.
    /// A day with no daily chores assigned counts as complete. Days before `activeFrom` are not counted.
    ///
    /// Who owed a chore on a past day uses the pure `Scheduler.assignee(for:periodIndex:)` path
    /// (pin → rotation) via the handoff-aware overload with an empty completion list — Tallies must
    /// not re-derive miss penalties from a partial history. Historically:
    /// `Scheduler.assignee(for:periodIndex:on:handoffs:)`
    /// decides it — accepted handoff, then pin, then rotation — so handing a daily to the other person moves
    /// that day for both of them: the offerer's streak survives, and the chore has to be done for the
    /// receiver's day to count. An accepted handoff never expires, so this keeps reading the same answer for a
    /// day months ago, and running the sweep changes nothing. The balancer stays out of it; see the README.
    /// `handoffs` defaults to empty, which is the old behaviour.
    public func streak(
        for person: Person,
        asOf date: Date,
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> Int {
        let dailies = scheduler.chores.filter { $0.cadence == .daily }
        let firstDay = calendar.dayIndex(scheduler.activeFrom)
        let today = calendar.dayIndex(date)

        var day = today
        var streak = 0
        if !isDayComplete(person, dayIndex: today, dailies: dailies, completions: completions, handoffs: handoffs) {
            day = today - 1 // today still in progress
        }
        while day >= firstDay {
            guard isDayComplete(
                person,
                dayIndex: day,
                dailies: dailies,
                completions: completions,
                handoffs: handoffs
            ) else { break }
            streak += 1
            day -= 1
        }
        return streak
    }

    func isDayComplete(
        _ person: Person,
        dayIndex: Int,
        dailies: [Chore],
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> Bool {
        let start = calendar.day(at: dayIndex)
        let end = calendar.day(at: dayIndex + 1)
        // The walk asks who owed the chore *on that day*, so Tuesday's accepted handoff counts on Tuesday
        // however long ago Tuesday was: an accepted turn never expires and the sweep leaves it alone. `start`
        // is still the date passed down, so a pending offer is judged against its own day rather than today.
        // A together daily is everybody's; the completion check below is already credit-blind.
        let mine = dailies.filter {
            $0.together || scheduler.assignee(for: $0, periodIndex: dayIndex, on: start, handoffs: handoffs) == person
        }
        for chore in mine {
            let done = completions.contains {
                $0.choreId == chore.id && $0.completedAt >= start && $0.completedAt < end
            }
            if !done {
                return false
            }
        }
        return true
    }
}
