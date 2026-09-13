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
    /// The person with the strictly higher streak; nil when tied.
    let leader: Person?

    init(streak: [Person: Int], doneThisWeek: [Person: Int]) {
        sides = Person.allCases.map { Side(person: $0, streak: streak[$0] ?? 0, doneThisWeek: doneThisWeek[$0] ?? 0) }
        let anne = streak[.anne] ?? 0
        let wes = streak[.wes] ?? 0
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
}
