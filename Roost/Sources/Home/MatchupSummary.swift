import Foundation
import RoostCore

/// Presentation data shared by the scoreboard and its activity feed. Retired chores remain in the
/// title lookup, but only active chores participate in today's schedule and streaks.
struct MatchupSummary {
    struct Activity: Identifiable {
        let id: String
        let title: String
        let person: Person
        let completedAt: Date
    }

    let plan: TodayPlan
    let recent: [Activity]

    init(chores: [ChoreRecord], completions: [CompletionRecord], handoffs: [HandoffSnapshot],
         asOf now: Date, activeFrom: Date, calendar: HouseholdCalendar = HouseholdCalendar())
    {
        let live = completions.filter { !$0.removed && $0.completedAt <= now }
            .compactMap { try? $0.toCompletion() }
        plan = TodayPlanner.plan(
            chores: chores.filter { !$0.retired }.compactMap { try? $0.toChore() },
            completions: live, handoffs: handoffs, asOf: now, activeFrom: activeFrom, calendar: calendar
        )
        let titles = Dictionary(chores.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        recent = live.sorted {
            $0.completedAt == $1.completedAt ? $0.id < $1.id : $0.completedAt > $1.completedAt
        }.prefix(8).map {
            Activity(id: $0.id, title: titles[$0.choreId] ?? Strings.Matchup.unknownChore,
                     person: $0.person, completedAt: $0.completedAt)
        }
    }
}
