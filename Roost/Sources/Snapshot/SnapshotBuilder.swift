// A `TodayPlan` turned into the small thing the widget reads. Pure: no store, no file, no WidgetKit.
//
// The whole point is that the widget agrees with the Tasks tab. So the ranking is not its own idea of
// "important" — it is `TodayBoard.ordered`, the order the Tasks tab draws a person's card in, cut to three.
// If the tab ever changes that order the widget follows it without an edit here.
import Foundation
import RoostCore

enum SnapshotBuilder {
    /// How many rows each person's `top` carries. Three is what fits the medium family at the largest
    /// accessibility size and still leaves the counts room.
    static let topCount = 3

    static func snapshot(from plan: TodayPlan, me: Person?, generatedAt: Date) -> RoostSnapshot {
        RoostSnapshot(
            generatedAt: generatedAt,
            me: me?.rawValue,
            // Anne first, always: `Person.allCases` is declared in that order and the medium family is a
            // comparison, so a stable side per person matters more than putting the reader first.
            people: Person.allCases.map { person($0, in: plan) }
        )
    }

    private static func person(_ person: Person, in plan: TodayPlan) -> RoostSnapshot.Person {
        let rows = plan.rows(for: person)
        let due = rows.filter { !$0.isDone }
        return RoostSnapshot.Person(
            id: person.rawValue,
            name: person.displayName,
            due: due.count,
            overdue: due.count { $0.stage > .dueToday },
            streak: plan.streak[person] ?? 0,
            top: top(rows)
        )
    }

    /// The three loudest rows: the Tasks tab's own order (alert, then pointed, then nudge, then merely due;
    /// cat care first inside a stage), with the rows already checked off left out — a widget is for what is
    /// left, not for what is done.
    static func top(_ rows: [TodayRow]) -> [RoostSnapshot.Item] {
        TodayBoard.ordered(rows)
            .filter { !$0.isDone }
            .prefix(topCount)
            .map { row in
                RoostSnapshot.Item(
                    title: row.chore.title,
                    stage: RoostSnapshot.Stage(row.stage),
                    daysOverdue: row.daysOverdue
                )
            }
    }
}

extension RoostSnapshot.Stage {
    /// The app's side of the mapping the widget reads back.
    init(_ stage: EscalationStage) {
        switch stage {
        case .dueToday: self = .dueToday
        case .nudge: self = .nudge
        case .pointed: self = .pointed
        case .alert: self = .alert
        }
    }
}
