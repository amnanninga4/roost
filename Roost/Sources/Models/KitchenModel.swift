// Kitchen mode's view of the day: both people at once, overdue only, loudest first.
// Built from the same TodayPlan the Tasks tab uses, so the two screens can never disagree about who owes what.
// No SwiftUI here; the grouping, sorting, and the caught-up rule are testable on their own.
import Foundation
import RoostCore
import SwiftData

struct KitchenModel: Equatable {
    /// Close is the only dismiss control. A tap on the board itself must not leave Kitchen mode —
    /// that used to steal taps meant for scrolling the counter.
    static let backgroundTapDismisses = false

    /// One overdue chore. `copy` is the row's escalation subtitle from EscalationCopy; it is never nil here
    /// because only overdue, not-yet-done rows become items.
    struct Item: Identifiable, Hashable {
        let chore: Chore
        let person: Person
        let stage: EscalationStage
        let daysOverdue: Int
        let copy: String
        /// Who handed this turn over, when somebody did. The same "from Anne" chip the Tasks tab shows:
        /// an overdue chore on the counter should say whose turn it actually was.
        let handedOverBy: Person?

        var id: String {
            "\(person.rawValue):\(chore.id)"
        }
    }

    struct Column: Equatable {
        let person: Person
        /// Everything the person owes today, overdue included: the Tasks tab's "N DUE".
        let dueCount: Int
        /// Overdue rows only, stage descending (alert, pointed, nudge). Within a stage the Tasks tab's order
        /// is kept: cat care first, then most days late first.
        let overdue: [Item]
    }

    let date: Date
    /// Anne then Wes, always both.
    let columns: [Column]
    /// Every alert-stage item from either person, most days late first (Anne before Wes on a tie).
    let alerts: [Item]

    /// True when neither person has anything overdue. Due-today rows do not count; the screen stays calm.
    var isCaughtUp: Bool {
        columns.allSatisfy(\.overdue.isEmpty)
    }

    func column(for person: Person) -> Column {
        columns.first { $0.person == person } ?? Column(person: person, dueCount: 0, overdue: [])
    }

    init(plan: TodayPlan) {
        date = plan.date
        columns = Person.allCases.map { person in
            let overdue = plan.rows(for: person).enumerated()
                .compactMap { index, row -> (order: Int, item: Item)? in
                    guard !row.isDone, row.stage > .dueToday,
                          let copy = EscalationCopy.subtitle(for: row) else { return nil }
                    var handedOverBy: Person?
                    if case let .takenFrom(giver) = row.handoff {
                        handedOverBy = giver
                    }
                    return (
                        index,
                        Item(
                            chore: row.chore,
                            person: person,
                            stage: row.stage,
                            daysOverdue: row.daysOverdue,
                            copy: copy,
                            handedOverBy: handedOverBy
                        )
                    )
                }
                .sorted { a, b in
                    if a.item.stage != b.item.stage {
                        return a.item.stage > b.item.stage
                    }
                    return a.order < b.order
                }
                .map(\.item)
            return Column(person: person, dueCount: plan.dueCount(for: person), overdue: overdue)
        }
        // A together chore sits in both columns; the banner is one shout, so it is listed once (Anne's copy).
        var togetherSeen: Set<String> = []
        let loud = columns
            .flatMap { $0.overdue.filter { $0.stage == .alert } }
            .filter { item in !item.chore.together || togetherSeen.insert(item.chore.id).inserted }
        alerts = loud
            .enumerated()
            .sorted { a, b in
                if a.element.daysOverdue != b.element.daysOverdue {
                    return a.element.daysOverdue > b.element.daysOverdue
                }
                return a.offset < b.offset
            }
            .map(\.element)
    }

    /// The store path, identical to the Tasks tab: active chores, live completions and live handoffs
    /// through TodayPlanner, with `activeFrom` falling back to today for a phone that has not synced yet.
    init(chores: [ChoreRecord], completions: [CompletionRecord], handoffs: [HandoffRecord] = [],
         activeFrom: Date?, asOf now: Date,
         calendar: HouseholdCalendar = HouseholdCalendar())
    {
        let plan = TodayPlanner.plan(
            chores: chores.compactMap { try? $0.toChore() },
            completions: completions.compactMap { try? $0.toCompletion() },
            handoffs: handoffs.compactMap { try? $0.toSnapshot() },
            asOf: now,
            activeFrom: activeFrom ?? calendar.startOfDay(now),
            calendar: calendar
        )
        self.init(plan: plan)
    }

    /// "Synced just now" inside a minute, "Synced 5 minutes ago" after, "Not synced yet" before the first sync.
    static func syncedLine(lastSyncAt: Date?, now: Date = Date()) -> String {
        guard let lastSyncAt else { return Strings.Kitchen.neverSynced }
        if now.timeIntervalSince(lastSyncAt) < 60 {
            return Strings.Kitchen.syncedJustNow
        }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return Strings.Kitchen.synced(f.localizedString(for: lastSyncAt, relativeTo: now))
    }
}
