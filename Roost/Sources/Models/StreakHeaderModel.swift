// The head-to-head block at the top of Tasks: each person's streak, who is ahead, and the weekly tallies.
// Pure so the leader rule is testable without SwiftUI.
import Foundation
import RoostCore

struct StreakHeaderModel: Equatable {
    struct Side: Equatable {
        let person: Person
        let streak: Int
        let doneThisWeek: Int
    }

    let sides: [Side]
    /// The person with the strictly higher week tally — the same number the week bar uses — so the
    /// AHEAD badge and the bar never disagree. Nil when tied.
    let leader: Person?

    init(streak: [Person: Int], doneThisWeek: [Person: Int]) {
        sides = Person.allCases.map { Side(person: $0, streak: streak[$0] ?? 0, doneThisWeek: doneThisWeek[$0] ?? 0) }
        let anne = doneThisWeek[.anne] ?? 0
        let wes = doneThisWeek[.wes] ?? 0
        leader = anne == wes ? nil : (anne > wes ? .anne : .wes)
    }

    init(plan: TodayPlan) {
        self.init(streak: plan.streak, doneThisWeek: plan.doneThisWeek)
    }

    func isLeading(_ person: Person) -> Bool {
        leader == person
    }

    /// "Anne · 14   Wes · 11"
    var tallyLine: String {
        sides
            .map { "\($0.person.displayName)\(Strings.Streak.tallySeparator)\($0.doneThisWeek)" }
            .joined(separator: Strings.Streak.tallyGap)
    }

    /// What the collapsed streak line prints: the two week scores, this phone's person first and
    /// called "You", and the household's longest running streak — nil when neither person has one
    /// going, so the line drops the clause rather than saying "0-day streak".
    struct ScoreLine: Equatable {
        struct Half: Equatable {
            let person: Person
            /// "You" for this phone's person; the display name otherwise.
            let label: String
            let score: Int
        }

        let first: Half
        let second: Half
        let streak: Int?
    }

    func scoreLine(me: Person?) -> ScoreLine {
        let streak = sides.map(\.streak).max() ?? 0
        let halves = sides.map {
            ScoreLine.Half(person: $0.person, label: $0.person.displayName, score: $0.doneThisWeek)
        }
        guard let me,
              let mine = halves.first(where: { $0.person == me }),
              let other = halves.first(where: { $0.person != me })
        else {
            return ScoreLine(first: halves[0], second: halves[1], streak: streak > 0 ? streak : nil)
        }
        return ScoreLine(
            first: ScoreLine.Half(person: mine.person, label: Strings.Streak.lineYou, score: mine.score),
            second: other,
            streak: streak > 0 ? streak : nil
        )
    }
}
