// What the Home screen says, decided here rather than in the view. The screen's whole job is to
// orient someone in one glance, so the sentence is the screen — and a sentence assembled inside a
// SwiftUI body is a sentence no test can reach. Everything user-visible on Home comes through
// this struct.
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
    }

    let sentence: String
    let columns: [Column]
    let doors: [Door]

    /// Every row on the matchup, for the check-off celebration rule.
    var allRows: [TodayRow] {
        columns.flatMap(\.rows)
    }

    init(plan: TodayPlan, me: Person?, doorCounts: DoorCounts) {
        let other = me.map { $0 == .anne ? Person.wes : Person.anne }
        let mine = me.map { plan.dueCount(for: $0) } ?? 0
        let theirs = other.map { plan.dueCount(for: $0) } ?? 0

        columns = TodayBoard.columnPeople(me: me).map { person in
            Column(
                person: person,
                rows: TodayBoard.ordered(plan.rows(for: person)),
                dueCount: plan.dueCount(for: person),
                isMine: person == me
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
