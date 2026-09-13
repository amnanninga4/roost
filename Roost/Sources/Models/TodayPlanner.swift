// Pure planning for the Today screen: turns records into per-person rows using RoostCore.
// No SwiftUI, no SwiftData types leak out, so it is trivially testable.
import Foundation
import RoostCore

struct TodayRow: Identifiable, Hashable {
    enum Kind: Hashable { case due(DueItem), done(completionId: String) }
    let chore: Chore
    let person: Person
    let kind: Kind

    var id: String {
        switch kind {
        case .due(let item): return "due:\(item.id)"
        case .done(let cid): return "done:\(cid)"
        }
    }
    var isDone: Bool { if case .done = kind { return true } else { return false } }
    var daysOverdue: Int { if case .due(let item) = kind { return item.daysOverdue } else { return 0 } }
    var stage: EscalationStage { if case .due(let item) = kind { return item.stage } else { return .dueToday } }
}

struct TodayPlan {
    let date: Date
    let rows: [Person: [TodayRow]]
    let doneThisWeek: [Person: Int]
    let streak: [Person: Int]

    func rows(for person: Person) -> [TodayRow] { rows[person] ?? [] }
    func dueCount(for person: Person) -> Int { rows(for: person).filter { !$0.isDone }.count }
}

enum TodayPlanner {
    /// `activeFrom` is the household start; periods before it are ignored. Cat-care rows sort first within a person,
    /// then most-overdue first (RoostCore's order). Rows completed today follow the due rows so they can be un-checked.
    static func plan(chores: [Chore], completions: [Completion], asOf date: Date, activeFrom: Date,
                     calendar: HouseholdCalendar = HouseholdCalendar()) -> TodayPlan {
        let scheduler = Scheduler(chores: chores, activeFrom: activeFrom, calendar: calendar)
        let due = scheduler.due(on: date, completions: completions)
        let tallies = Tallies(scheduler: scheduler)

        let dayStart = calendar.startOfDay(date)
        let dayEnd = calendar.endOfDay(date)
        let byId = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })
        let doneToday = completions
            .filter { $0.completedAt >= dayStart && $0.completedAt < dayEnd }
            .sorted { $0.completedAt > $1.completedAt }

        var rows: [Person: [TodayRow]] = [:]
        for person in Person.allCases {
            let dueRows = (due[person] ?? []).map { TodayRow(chore: $0.chore, person: person, kind: .due($0)) }
            let doneRows = doneToday
                .filter { $0.person == person }
                .compactMap { c in byId[c.choreId].map { TodayRow(chore: $0, person: person, kind: .done(completionId: c.id)) } }
            let all = dueRows + doneRows
            // stable partition: cat care first, then the rest, preserving each group's order
            rows[person] = all.filter { $0.chore.category == .catCare } + all.filter { $0.chore.category != .catCare }
        }

        return TodayPlan(
            date: date,
            rows: rows,
            doneThisWeek: tallies.doneThisWeek(asOf: date, completions: completions),
            streak: Dictionary(uniqueKeysWithValues: Person.allCases.map { ($0, tallies.streak(for: $0, asOf: date, completions: completions)) })
        )
    }
}
