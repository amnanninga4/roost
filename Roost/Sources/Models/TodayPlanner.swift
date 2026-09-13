// Pure planning for the Today screen: turns records into per-person rows using RoostCore.
// No SwiftUI, no SwiftData types leak out, so it is trivially testable.
import Foundation
import RoostCore

struct TodayRow: Identifiable, Hashable {
    enum Kind: Hashable { case due(DueItem), done(completionId: String) }
    let chore: Chore
    let person: Person
    let kind: Kind
    /// What a handoff is doing to this row. Nil for almost every row; `HandoffPresentation` decides it.
    var handoff: RowHandoff?
    /// True only when this is the person's own row for the chore's current period and
    /// `RoostCore.HandoffRules.canOffer` says they may hand it over. The view never re-derives this.
    var canOffer: Bool = false

    var id: String {
        switch kind {
        case let .due(item): "due:\(item.id)"
        case let .done(cid): "done:\(cid)"
        }
    }

    var isDone: Bool {
        if case .done = kind {
            true
        } else {
            false
        }
    }

    var daysOverdue: Int {
        if case let .due(item) = kind {
            item.daysOverdue
        } else {
            0
        }
    }

    var stage: EscalationStage {
        if case let .due(item) = kind {
            item.stage
        } else {
            .dueToday
        }
    }
}

struct TodayPlan {
    let date: Date
    let rows: [Person: [TodayRow]]
    let doneThisWeek: [Person: Int]
    let streak: [Person: Int]
    /// Pending offers each person has been asked to answer: the card at the top of their column.
    let offers: [Person: [IncomingOffer]]

    func rows(for person: Person) -> [TodayRow] {
        rows[person] ?? []
    }

    func dueCount(for person: Person) -> Int {
        rows(for: person).filter { !$0.isDone }.count
    }

    func offers(for person: Person) -> [IncomingOffer] {
        offers[person] ?? []
    }
}

enum TodayPlanner {
    /// `activeFrom` is the household start (the server's `activeFrom`); periods before it are ignored.
    /// Cat-care rows sort first within a person, then most-overdue first (RoostCore's order). Rows
    /// completed today follow the due rows so they can be un-checked.
    ///
    /// `handoffs` are the phone's handoffs. Only the live ones reach RoostCore — a `Scheduler` that had a
    /// refused offer in hand would put a chore in the wrong column — and they reach both the scheduler,
    /// which is what moves an accepted turn between the columns, and `Tallies.streak`, which is what
    /// keeps a given-away daily out of the offerer's streak and inside the receiver's for that day. The
    /// balancer stays nil: turning it on is a separate, deliberate change (see RoostCore's README).
    static func plan(chores: [Chore], completions: [Completion], handoffs: [HandoffSnapshot] = [],
                     asOf date: Date, activeFrom: Date,
                     calendar: HouseholdCalendar = HouseholdCalendar()) -> TodayPlan
    {
        let live = HandoffPresentation.live(handoffs)
        let scheduler = Scheduler(chores: chores, activeFrom: activeFrom, calendar: calendar, balancer: nil)
        let due = scheduler.plan(on: date, completions: completions, handoffs: live)
        let tallies = Tallies(scheduler: scheduler)
        let rules = HandoffRules(scheduler: scheduler, handoffs: live)

        let dayStart = calendar.startOfDay(date)
        let dayEnd = calendar.endOfDay(date)
        let byId = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })
        let doneToday = completions
            .filter { $0.completedAt >= dayStart && $0.completedAt < dayEnd }
            .sorted { $0.completedAt > $1.completedAt }

        var rows: [Person: [TodayRow]] = [:]
        for person in Person.allCases {
            let dueRows = (due[person] ?? []).map { item in
                dueRow(item, person: person, snapshots: handoffs, rules: rules, on: date, calendar: calendar)
            }
            let doneRows = doneToday
                .filter { $0.person == person }
                .compactMap { c in
                    byId[c.choreId].map {
                        doneRow($0, completion: c, person: person, snapshots: handoffs, on: date, calendar: calendar)
                    }
                }
            let all = dueRows + doneRows
            // stable partition: cat care first, then the rest, preserving each group's order
            rows[person] = all.filter { $0.chore.category == .catCare } + all.filter { $0.chore.category != .catCare }
        }

        return TodayPlan(
            date: date,
            rows: rows,
            doneThisWeek: tallies.doneThisWeek(asOf: date, completions: completions),
            streak: Dictionary(uniqueKeysWithValues: Person.allCases.map {
                ($0, tallies.streak(for: $0, asOf: date, completions: completions, handoffs: live))
            }),
            offers: Dictionary(uniqueKeysWithValues: Person.allCases.map {
                ($0, HandoffPresentation.incomingOffers(
                    for: $0, chores: byId, snapshots: handoffs, on: date, calendar: calendar
                ))
            })
        )
    }

    private static func dueRow(
        _ item: DueItem,
        person: Person,
        snapshots: [HandoffSnapshot],
        rules: HandoffRules,
        on date: Date,
        calendar: HouseholdCalendar
    ) -> TodayRow {
        // "The current period" is the point: an overdue row belongs to a period that has already closed,
        // and offering it would hand over a period nobody can still be the owner of.
        let isCurrentPeriod = item.periodIndex == calendar.periodIndex(item.chore.cadence, containing: date)
        return TodayRow(
            chore: item.chore,
            person: person,
            kind: .due(item),
            handoff: HandoffPresentation.rowHandoff(
                chore: item.chore,
                person: person,
                periodIndex: item.periodIndex,
                snapshots: snapshots,
                on: date,
                calendar: calendar
            ),
            canOffer: isCurrentPeriod && rules.canOffer(item.chore, from: person, on: date)
        )
    }

    /// A finished row keeps the "from Anne" chip — the period it belongs to is the one the completion
    /// falls in — but nothing else: there is no turn left to offer, and no answer left to wait for.
    private static func doneRow(
        _ chore: Chore,
        completion: Completion,
        person: Person,
        snapshots: [HandoffSnapshot],
        on date: Date,
        calendar: HouseholdCalendar
    ) -> TodayRow {
        let period = calendar.periodIndex(chore.cadence, containing: completion.completedAt)
        let taken = HandoffRules.acceptedOverride(
            choreId: chore.id,
            periodIndex: period,
            in: HandoffPresentation.live(snapshots),
            on: date,
            calendar: calendar
        )
        return TodayRow(
            chore: chore,
            person: person,
            kind: .done(completionId: completion.id),
            handoff: taken?.to == person ? taken.map { .takenFrom($0.from) } : nil
        )
    }
}
