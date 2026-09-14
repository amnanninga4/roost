@testable import RoostCore
import XCTest

/// Sends every unpinned chore to one person, so a handoff moving it away — and moving back — is visible.
struct FixedRotation: Rotation {
    let person: Person
    func assignee(for _: Chore, periodIndex _: Int) -> Person {
        person
    }
}

final class FairnessBalancerTests: XCTestCase {
    let cal = HouseholdCalendar()
    // Four unpinned dailies, in master-list order: the walk follows this order, so the tests can predict it.
    let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)
    let tables = Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, category: .chore)
    let dishes = Chore(id: "wash-dishes", title: "Wash dishes", cadence: .daily, category: .chore)
    let water = Chore(id: "water-plants", title: "Water plants", cadence: .daily, category: .chore)
    let toilet = Chore(id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: .weekly, category: .chore)
    let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)
    let oven = Chore(id: "clean-inside-ovens", title: "Clean inside ovens", cadence: .monthly, category: .chore)

    lazy var dailies = [litter, tables, dishes, water]
    // Household starts Monday 2026-09-07. "Today" is Wednesday 2026-09-16, so the window is Sep 3 – Sep 16.
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 7, hour: 0)
    lazy var wed = cal.date(year: 2026, month: 9, day: 16, hour: 9)

    /// All four dailies done yesterday, two each: every one is due again today and the two of them start level.
    lazy var yesterdayEvenly = [
        done(litter, .anne, day: 15),
        done(tables, .anne, day: 15),
        done(dishes, .wes, day: 15),
        done(water, .wes, day: 15),
    ]

    /// Same, except Anne did all four.
    lazy var yesterdayAllAnne = dailies.map { done($0, .anne, day: 15) }

    func done(_ chore: Chore, _ person: Person, day: Int, hour: Int = 12) -> Completion {
        Completion(
            id: "\(chore.id)-\(person.rawValue)-09-\(day)-\(hour)",
            choreId: chore.id,
            person: person,
            completedAt: cal.date(year: 2026, month: 9, day: day, hour: hour)
        )
    }

    func scheduler(_ chores: [Chore], balanced: Bool = true, rotation: Rotation = RoundRobinRotation()) -> Scheduler {
        Scheduler(
            chores: chores,
            activeFrom: activeFrom,
            rotation: rotation,
            calendar: cal,
            balancer: balanced ? FairnessBalancer() : nil
        )
    }

    func ids(_ plan: [Person: [DueItem]], _ person: Person) -> Set<String> {
        Set((plan[person] ?? []).map(\.chore.id))
    }

    func holder(of chore: Chore, in plan: [Person: [DueItem]]) -> Person? {
        Person.allCases.first { ids(plan, $0).contains(chore.id) }
    }

    // MARK: the split

    func testSplitsThePeriodsWorkInsteadOfHandingItAllToOnePerson() {
        let sched = scheduler(dailies)
        let plan = sched.plan(on: wed, completions: yesterdayEvenly)

        XCTAssertEqual(
            FairnessBalancer().windowLoads(chores: dailies, completions: yesterdayEvenly, asOf: wed, calendar: cal),
            [.anne: 2, .wes: 2],
            "they go into the day level"
        )
        XCTAssertEqual(plan[.anne]?.count, 2, "two and two, not four and none")
        XCTAssertEqual(plan[.wes]?.count, 2)
        XCTAssertEqual(ids(plan, .anne).union(ids(plan, .wes)), Set(dailies.map(\.id)))

        // Each phone holds the rows in whatever order they synced in; the answer cannot depend on that.
        let permutations = [[3, 2, 1, 0], [2, 0, 3, 1], [1, 3, 0, 2]]
        for order in permutations {
            let shuffled = order.map { yesterdayEvenly[$0] }
            XCTAssertEqual(sched.plan(on: wed, completions: shuffled), plan, "row order \(order) changed the plan")
        }
    }

    func testALevelTieGoesToTheRotationsAnswer() {
        // Both of them on one, two chores due today. The first chore on the list is a tie the pass has no
        // reason to break, so it stays where the rotation put it — whichever way the rotation points.
        let roundRobin = RoundRobinRotation()
        let period = cal.periodIndex(.daily, containing: wed)
        XCTAssertNotEqual(
            roundRobin.assignee(for: litter, periodIndex: period),
            roundRobin.assignee(for: dishes, periodIndex: period),
            "the fixture has to cover a tie breaking both ways, or it proves nothing"
        )
        let completions = [done(litter, .anne, day: 15), done(dishes, .wes, day: 15)]

        for chores in [[litter, dishes], [dishes, litter]] {
            let first = chores[0]
            XCTAssertEqual(
                FairnessBalancer().backgroundLoads(chores: chores, completions: completions, asOf: wed, calendar: cal),
                [.anne: 1, .wes: 1],
                "level going in"
            )
            let plan = scheduler(chores).plan(on: wed, completions: completions)
            XCTAssertEqual(
                holder(of: first, in: plan),
                roundRobin.assignee(for: first, periodIndex: period),
                "a tie on \(first.id) is the rotation's call"
            )
            XCTAssertEqual(
                holder(of: chores[1], in: plan),
                roundRobin.assignee(for: first, periodIndex: period) == .anne ? .wes : .anne,
                "and the second one evens the day up"
            )
        }
    }

    // MARK: stability

    func testFinishingOneItemLeavesEveryOtherItemWhereItWas() throws {
        let sched = scheduler(dailies)
        let before = sched.plan(on: wed, completions: yesterdayEvenly)

        // Try it on the first chore of the list and on the last. The first one is the case a plain greedy pass
        // gets wrong: finishing it moves its weight into the load the walk starts from, and everything after it
        // shuffles.
        for chore in [litter, water] {
            let owner = holder(of: chore, in: before)
            XCTAssertNotNil(owner, "\(chore.id) is due before it is done")
            let after = try sched.plan(
                on: wed,
                completions: yesterdayEvenly + [done(chore, XCTUnwrap(owner), day: 16, hour: 11)]
            )
            XCTAssertNil(holder(of: chore, in: after), "\(chore.id) is done, so it leaves the list")
            for person in Person.allCases {
                XCTAssertEqual(
                    ids(after, person),
                    ids(before, person).subtracting([chore.id]),
                    "\(person.rawValue) keeps the rest of the day after \(chore.id) is checked off"
                )
            }
        }
    }

    // MARK: what the pass may not touch

    func testOverdueItemsAreNeverMoved() {
        // Nothing done since the household started, so all four dailies are nine days late. Anne also finished
        // the ovens this month: eight weights of work the walk sees before it reaches them, which is more than
        // enough to hand every one of them to Wes if overdue items were fair game.
        let chores = [oven] + dailies
        let completions = [done(oven, .anne, day: 14)]

        let balanced = scheduler(chores).plan(on: wed, completions: completions)
        let plain = scheduler(chores, balanced: false).plan(on: wed, completions: completions)

        XCTAssertEqual(balanced, plain, "an overdue chore stays with whoever already owed it")
        XCTAssertTrue(
            balanced.values.flatMap(\.self).allSatisfy { $0.daysOverdue >= 1 },
            "the fixture really is all overdue"
        )
        XCTAssertEqual(
            FairnessBalancer().windowLoads(chores: chores, completions: completions, asOf: wed, calendar: cal),
            [.anne: 8, .wes: 0],
            "and the pass could see how lopsided the week was"
        )
    }

    func testPinnedAndHandedOffItemsAreNeverTouched() {
        // Anne is carrying eight: last week's laundry and toilet, two dailies yesterday. The pass wants to give
        // Wes everything. It still may not move her pinned laundry, and it may not move the toilet she has
        // already handed him.
        let chores = [laundry, toilet, litter, tables]
        let completions = [
            done(laundry, .anne, day: 10), // last week, so due again this week: 3 of background
            done(toilet, .anne, day: 10), // 3
            done(litter, .anne, day: 15), // yesterday, so due again today: 1
            done(tables, .anne, day: 15), // 1
        ]
        let week = cal.periodIndex(.weekly, containing: wed)
        let accepted = Handoff(
            id: "h1",
            choreId: toilet.id,
            from: .anne,
            to: .wes,
            periodIndex: week,
            cadence: .weekly,
            createdAt: wed,
            state: .accepted
        )
        let sched = scheduler(chores, rotation: FixedRotation(person: .anne))
        let plan = sched.plan(on: wed, completions: completions, handoffs: [accepted])

        XCTAssertEqual(ids(plan, .anne), [laundry.id], "the pin holds even though she is the loaded one")
        XCTAssertEqual(
            ids(plan, .wes),
            [toilet.id, litter.id, tables.id],
            "the accepted handoff holds, and the two the pass may move both go to him"
        )
    }

    // MARK: the away case

    func testTheAbsentPersonsColumnStopsGrowing() {
        // Wes has been away: eight daily chores of his, none done, all overdue, and nothing at all in his
        // fourteen days — the lowest actual load in the house, which is the trap. Anne did the four shared
        // dailies yesterday.
        let his = (1 ... 8).map {
            Chore(
                id: "wes-chore-\($0)",
                title: "Wes chore \($0)",
                cadence: .daily,
                fixedAssignee: .wes,
                category: .chore
            )
        }
        let chores = his + dailies
        let plan = scheduler(chores).plan(on: wed, completions: yesterdayAllAnne)

        XCTAssertEqual(
            FairnessBalancer().windowLoads(chores: chores, completions: yesterdayAllAnne, asOf: wed, calendar: cal),
            [.anne: 4, .wes: 0],
            "his actual load is the low one"
        )
        XCTAssertEqual(ids(plan, .anne), Set(dailies.map(\.id)), "today's shared work is hers")
        XCTAssertEqual(ids(plan, .wes), Set(his.map(\.id)), "his column stops at what he already owed")

        // The crossover: with only one thing of his outstanding, today's work goes to him until he passes her.
        let evened = scheduler([his[0]] + dailies).plan(on: wed, completions: yesterdayAllAnne)
        XCTAssertTrue(
            ids(evened, .wes).isSuperset(of: [his[0].id, litter.id, tables.id, dishes.id]),
            "the first three of today's chores are his while he is still behind"
        )
        XCTAssertTrue(
            ids(evened, .anne).isSubset(of: [water.id]),
            "by the fourth they are level, so the rotation decides it rather than the load"
        )
    }

    // MARK: off by default

    func testWithoutABalancerEveryItemStaysWhereTheRotationPutIt() {
        let plain = scheduler(dailies, balanced: false)
        XCTAssertNil(plain.balancer, "off unless a caller asks for it")

        let plan = plain.plan(on: wed, completions: yesterdayAllAnne)
        let roundRobin = RoundRobinRotation()
        for chore in dailies {
            let item = plain.dueItem(for: chore, on: wed, completions: yesterdayAllAnne)
            XCTAssertEqual(item?.person, roundRobin.assignee(for: chore, periodIndex: item?.periodIndex ?? 0))
            XCTAssertEqual(holder(of: chore, in: plan), item?.person, "\(chore.id) is where it was before D-CORE")
        }

        // The same fixture with the balancer on moves all four, so the assertions above are not vacuous.
        let balanced = scheduler(dailies).plan(on: wed, completions: yesterdayAllAnne)
        XCTAssertEqual(ids(balanced, .wes), Set(dailies.map(\.id)), "she did all four yesterday; today they are his")
    }
    func testTogetherChoresAreNeitherMovedNorWeighed() {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        let chores = [toilet, pantry] + dailies
        let scheduler = Scheduler(chores: chores, activeFrom: cal.date(year: 2026, month: 9, day: 7, hour: 0),
                                  calendar: cal, balancer: FairnessBalancer())
        let plan = scheduler.plan(on: wed, completions: [])
        XCTAssertEqual(plan[.anne]?.filter { $0.chore.id == pantry.id }.count, 1)
        XCTAssertEqual(plan[.wes]?.filter { $0.chore.id == pantry.id }.count, 1)
        let item = plan[.anne]!.first { $0.chore.id == pantry.id }!
        XCTAssertFalse(FairnessBalancer().isReassignable(item, on: wed, calendar: cal))
        // A together completion is not a weight on anybody's side of the scale.
        let loads = FairnessBalancer().windowLoads(chores: chores, completions: [done(pantry, .wes, day: 14)],
                                                   asOf: wed, calendar: cal)
        XCTAssertEqual(loads, [.anne: 0, .wes: 0])
    }

}

/// The load numbers on their own: what a chore is worth, which days count, and which ones the walk sees up front.
final class FairnessLoadTests: XCTestCase {
    let cal = HouseholdCalendar()
    let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)
    let tables = Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, category: .chore)
    let toilet = Chore(id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: .weekly, category: .chore)

    lazy var dailies = [litter, tables]
    lazy var wed = cal.date(year: 2026, month: 9, day: 16, hour: 9)

    func done(_ chore: Chore, _ person: Person, day: Int, hour: Int = 12) -> Completion {
        Completion(
            id: "\(chore.id)-\(person.rawValue)-09-\(day)-\(hour)",
            choreId: chore.id,
            person: person,
            completedAt: cal.date(year: 2026, month: 9, day: day, hour: hour)
        )
    }

    func testProvisionalWeightsAndAWeeklyOutweighingTwoDailies() {
        let weights = FairnessWeights.provisional
        XCTAssertEqual(weights.weight(for: .daily), 1)
        XCTAssertEqual(weights.weight(for: .weekly), 3)
        XCTAssertEqual(weights.weight(for: .biweekly), 5)
        XCTAssertEqual(weights.weight(for: .monthly), 8)
        XCTAssertEqual(weights.weight(for: .bimonthly), 10)
        XCTAssertEqual(weights.weight(for: .quarterly), 13)

        let chores = [toilet] + dailies
        let completions = [
            done(toilet, .anne, day: 10), // one weekly = 3
            done(litter, .wes, day: 14), // two dailies = 2
            done(tables, .wes, day: 15),
        ]
        XCTAssertEqual(
            FairnessBalancer().windowLoads(chores: chores, completions: completions, asOf: wed, calendar: cal),
            [.anne: 3, .wes: 2],
            "two dailies is still less work than a weekly"
        )
    }

    func testWindowIsFourteenDaysAndDropsOlderCompletions() {
        XCTAssertEqual(FairnessBalancer.windowDays, 14)
        let balancer = FairnessBalancer()

        let inside = balancer.windowLoads(
            chores: dailies,
            completions: [done(litter, .anne, day: 3, hour: 0)],
            asOf: wed,
            calendar: cal
        )
        XCTAssertEqual(inside[.anne], 1, "Sep 3 00:00 is the first day counted")

        let outside = balancer.windowLoads(
            chores: dailies,
            completions: [done(litter, .anne, day: 2, hour: 23)],
            asOf: wed,
            calendar: cal
        )
        XCTAssertEqual(outside[.anne], 0, "Sep 2 is fourteen days back, outside the window")
    }

    func testBackgroundLoadLeavesOutTheCurrentPeriod() {
        let balancer = FairnessBalancer()
        let completions = [done(litter, .anne, day: 15), done(tables, .anne, day: 16, hour: 8)]

        XCTAssertEqual(
            balancer.windowLoads(chores: dailies, completions: completions, asOf: wed, calendar: cal)[.anne],
            2,
            "both count as work she has done lately"
        )
        XCTAssertEqual(
            balancer.backgroundLoads(chores: dailies, completions: completions, asOf: wed, calendar: cal)[.anne],
            1,
            "but this morning's is counted at its own slot in the walk, not up front"
        )
    }

    func testCompletionsForUnknownChoresAreIgnored() {
        let ghost = Chore(id: "not-on-the-list", title: "Ghost", cadence: .monthly, category: .chore)
        XCTAssertEqual(
            FairnessBalancer().windowLoads(
                chores: dailies,
                completions: [done(ghost, .anne, day: 15)],
                asOf: wed,
                calendar: cal
            ),
            [.anne: 0, .wes: 0],
            "nothing to weigh it by, so it does not count"
        )
    }
}
