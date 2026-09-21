// What the Home screen says, decided here rather than in the view. The screen's whole job is to
// orient someone in one glance, so the sentence is the screen — and a sentence assembled inside a
// SwiftUI body is a sentence no test can reach. Everything user-visible on Home comes through
// this struct.
import Foundation
import RoostCore

struct HomeSummary {
    /// How many items each list holds. Passed in rather than queried here so this stays free of
    /// SwiftData and testable with plain integers.
    struct DoorCounts {
        let shopping: Int
        let meals: Int
        let projects: Int
        let wishlist: Int
    }

    /// One room, as the strip draws it. `count` is nil when the room is empty: the door is always
    /// shown, the number is not.
    struct Door: Identifiable {
        let id: String
        let title: String
        let count: Int?
    }

    /// One person on the Home matchup. Left is this phone; right is the other.
    struct Column: Identifiable {
        var id: Person {
            person
        }

        let person: Person
        let rows: [TodayRow]
        let dueCount: Int
        let isMine: Bool
        let doneThisWeek: Int
    }

    let date: Date
    let sentence: String
    let columns: [Column]
    let doors: [Door]

    /// Every row on the matchup, for the check-off celebration rule.
    var allRows: [TodayRow] {
        columns.flatMap(\.rows)
    }

    /// One row per open chore; together chores appear on both personal boards but only once here.
    var openRows: [TodayRow] {
        var together = Set<String>()
        let rows = allRows.filter { row in
            guard !row.isDone else { return false }
            return !row.chore.together || together.insert(row.chore.id).inserted
        }
        func rank(_ row: TodayRow) -> Int {
            switch HomeRowBuckets.bucket(for: row, calendar: HouseholdCalendar(), on: date) {
            case .overdue: 0
            case .today: 1
            case .later: 2
            }
        }
        return rows.enumerated().sorted {
            let left = rank($0.element), right = rank($1.element)
            if left != right {
                return left < right
            }
            return $0.element.daysOverdue == $1.element.daysOverdue
                ? $0.offset < $1.offset
                : $0.element.daysOverdue > $1.element.daysOverdue
        }.map(\.element)
    }

    init(plan: TodayPlan, me: Person?, doorCounts: DoorCounts) {
        date = plan.date
        let other = me.map { $0 == .anne ? Person.wes : Person.anne }
        let mine = me.map { plan.dueCount(for: $0) } ?? 0
        let theirs = other.map { plan.dueCount(for: $0) } ?? 0

        columns = TodayBoard.columnPeople(me: me).map { person in
            Column(
                person: person,
                rows: TodayBoard.ordered(plan.rows(for: person)),
                dueCount: plan.dueCount(for: person),
                isMine: person == me,
                doneThisWeek: plan.doneThisWeek[person] ?? 0
            )
        }

        // Order matters: an unpaired phone has no "you", so it can never reach the first three.
        if me == nil {
            sentence = Strings.Home.nothingDue
        } else if mine > 0 {
            sentence = Strings.Home.split(mine, theirs, other: other?.displayName ?? "")
        } else if theirs > 0 {
            sentence = Strings.Home.clearForYou(theirs, other: other?.displayName ?? "")
        } else {
            sentence = Strings.Home.allCaught
        }

        doors = [
            Door(id: "shopping", title: Strings.Tabs.shopping, count: Self.shown(doorCounts.shopping)),
            Door(id: "meals", title: Strings.Tabs.meals, count: Self.shown(doorCounts.meals)),
            Door(id: "projects", title: Strings.Tabs.projects, count: Self.shown(doorCounts.projects)),
            Door(id: "wishlist", title: Strings.Tabs.wishlist, count: Self.shown(doorCounts.wishlist)),
        ]
    }

    private static func shown(_ count: Int) -> Int? {
        count > 0 ? count : nil
    }
}
