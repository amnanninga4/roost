import Foundation

/// Weekly counts and streaks. Both are provisional rules; see README.
public struct Tallies: Sendable {
    public let scheduler: Scheduler
    public var calendar: HouseholdCalendar { scheduler.calendar }

    public init(scheduler: Scheduler) {
        self.scheduler = scheduler
    }

    /// Completions per person in the Monday-to-Sunday (Chicago) week containing `date`.
    public func doneThisWeek(asOf date: Date, completions: [Completion]) -> [Person: Int] {
        let week = calendar.weekBounds(containing: date)
        var counts: [Person: Int] = [.anne: 0, .wes: 0]
        for c in completions where c.completedAt >= week.start && c.completedAt < week.end {
            counts[c.person, default: 0] += 1
        }
        return counts
    }

    /// Consecutive days, ending today or yesterday, on which `person` completed every daily chore assigned
    /// to them. Today counts only once it is fully done; an unfinished today does not break the streak.
    /// A day with no daily chores assigned counts as complete. Days before `activeFrom` are not counted.
    public func streak(for person: Person, asOf date: Date, completions: [Completion]) -> Int {
        let dailies = scheduler.chores.filter { $0.cadence == .daily }
        let firstDay = calendar.dayIndex(scheduler.activeFrom)
        let today = calendar.dayIndex(date)

        var day = today
        var streak = 0
        if !isDayComplete(person, dayIndex: today, dailies: dailies, completions: completions) {
            day = today - 1 // today still in progress
        }
        while day >= firstDay {
            guard isDayComplete(person, dayIndex: day, dailies: dailies, completions: completions) else { break }
            streak += 1
            day -= 1
        }
        return streak
    }

    func isDayComplete(_ person: Person, dayIndex: Int, dailies: [Chore], completions: [Completion]) -> Bool {
        let start = calendar.day(at: dayIndex)
        let end = calendar.day(at: dayIndex + 1)
        let mine = dailies.filter { scheduler.assignee(for: $0, periodIndex: dayIndex) == person }
        for chore in mine {
            let done = completions.contains {
                $0.choreId == chore.id && $0.completedAt >= start && $0.completedAt < end
            }
            if !done { return false }
        }
        return true
    }
}
