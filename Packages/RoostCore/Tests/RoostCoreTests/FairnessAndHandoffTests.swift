@testable import RoostCore
import XCTest

/// Sends every unpinned chore to one person, so a handoff moving it away — and moving back — is visible.
private struct FixedRotation: Rotation {
    let person: Person
    func assignee(for _: Chore, periodIndex _: Int) -> Person {
        person
    }
}

final class FairnessRotationTests: XCTestCase {
    let cal = HouseholdCalendar()
    let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)
    let tidy = Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, category: .chore)
    let toilet = Chore(id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: .weekly, category: .chore)
    let shower = Chore(id: "scrub-shower", title: "Scrub shower", cadence: .biweekly, category: .chore)
    let oven = Chore(id: "clean-inside-ovens", title: "Clean inside ovens", cadence: .monthly, category: .chore)

    lazy var chores = [litter, tidy, toilet, shower, oven]
    // Household starts Monday 2026-09-07. "Today" is Wednesday 2026-09-16, so the window is Sep 3 – Sep 16.
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 7, hour: 0)
    lazy var wed = cal.date(year: 2026, month: 9, day: 16, hour: 9)

    func done(_ chore: Chore, _ person: Person, day: Int, month: Int = 9, hour: Int = 12) -> Completion {
        Completion(
            id: "\(chore.id)-\(month)-\(day)-\(hour)-\(person.rawValue)",
            choreId: chore.id,
            person: person,
            completedAt: cal.date(year: 2026, month: month, day: day, hour: hour)
        )
    }

    func rotation(_ completions: [Completion], asOf date: Date? = nil) -> FairnessRotation {
        FairnessRotation(chores: chores, completions: completions, asOf: date ?? wed, calendar: cal)
    }

    func testFairnessPicksTheLowerLoadPerson() {
        // Anne scooped the litter two days running; Wes has done nothing.
        let fair = rotation([done(litter, .anne, day: 14), done(litter, .anne, day: 15)])
        XCTAssertEqual(fair.load(for: .anne), 2)
        XCTAssertEqual(fair.load(for: .wes), 0)

        let period = cal.periodIndex(.daily, containing: wed)
        XCTAssertEqual(fair.assignee(for: tidy, periodIndex: period), .wes)
        XCTAssertEqual(fair.assignee(for: tidy, periodIndex: period + 1), .wes, "no alternating while the gap stands")
        XCTAssertEqual(fair.assignee(for: toilet, periodIndex: 0), .wes, "the load is the person's, not the chore's")
    }

    func testEqualLoadsFallBackToAlternation() {
        let roundRobin = RoundRobinRotation()
        for completions in [[], [done(litter, .anne, day: 15), done(tidy, .wes, day: 15)]] {
            let fair = rotation(completions)
            XCTAssertEqual(fair.load(for: .anne), fair.load(for: .wes))
            for period in [0, 1, 2, 41] {
                XCTAssertEqual(
                    fair.assignee(for: tidy, periodIndex: period),
                    roundRobin.assignee(for: tidy, periodIndex: period),
                    "ties use the same FNV-1a seed as round robin"
                )
            }
            XCTAssertNotEqual(
                fair.assignee(for: tidy, periodIndex: 10),
                fair.assignee(for: tidy, periodIndex: 11),
                "ties still alternate period to period"
            )
        }
    }

    func testWindowIsFourteenDaysAndDropsOlderCompletions() {
        XCTAssertEqual(FairnessRotation.windowDays, 14)
        let inside = rotation([done(oven, .anne, day: 3, hour: 0)])
        XCTAssertEqual(inside.windowFirstDay, cal.dayIndex(cal.date(year: 2026, month: 9, day: 3)))
        XCTAssertEqual(inside.windowLastDay, cal.dayIndex(wed))
        XCTAssertEqual(inside.load(for: .anne), 8, "Sep 3 00:00 is the first day counted")
        XCTAssertEqual(inside.assignee(for: tidy, periodIndex: 7), .wes)

        // One day earlier and the same completion no longer counts.
        let outside = rotation([done(oven, .anne, day: 2, hour: 23)])
        XCTAssertEqual(outside.load(for: .anne), 0, "Sep 2 is 14 days back, outside the window")
        XCTAssertEqual(
            outside.assignee(for: tidy, periodIndex: 7),
            RoundRobinRotation().assignee(for: tidy, periodIndex: 7),
            "loads are level again, so the tie-breaker decides"
        )
    }

    func testOneWeeklyOutweighsTwoDailies() {
        let fair = rotation([
            done(toilet, .anne, day: 14), // weekly = 3
            done(litter, .wes, day: 15), // daily = 1
            done(tidy, .wes, day: 15), // daily = 1
        ])
        XCTAssertEqual(fair.load(for: .anne), 3)
        XCTAssertEqual(fair.load(for: .wes), 2)
        XCTAssertEqual(
            fair.assignee(for: shower, periodIndex: 18),
            .wes,
            "two dailies is still less work than a weekly"
        )
    }

    func testCompletionsForUnknownChoresAreIgnored() {
        let ghost = Chore(id: "not-in-the-list", title: "Ghost", cadence: .monthly, category: .chore)
        let fair = rotation([done(ghost, .anne, day: 15)])
        XCTAssertEqual(fair.load(for: .anne), 0, "nothing to weigh it by, so it does not count")
    }

    func testSchedulerTakesFairnessRotation() {
        // Wes did the ovens (8) on Monday; Anne did one daily (1). Unpinned work should come to Anne.
        let completions = [done(oven, .wes, day: 14), done(litter, .anne, day: 15)]
        let fair = FairnessRotation(chores: chores, completions: completions, asOf: wed, calendar: cal)
        let scheduler = Scheduler(chores: [tidy], activeFrom: activeFrom, rotation: fair, calendar: cal)
        let plan = scheduler.plan(on: wed, completions: completions)
        XCTAssertEqual(plan[.anne]?.map(\.chore.id), [tidy.id])
        XCTAssertEqual(plan[.wes]?.count, 0)
    }
}

final class HandoffTests: XCTestCase {
    let cal = HouseholdCalendar()
    let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)
    let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)

    // Household starts Monday 2026-09-07; "today" is Wednesday 2026-09-16. Unpinned work is Anne's, so a
    // handoff to Wes is easy to see and easy to see revert.
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 7, hour: 0)
    lazy var wed = cal.date(year: 2026, month: 9, day: 16, hour: 9)
    lazy var thu = cal.date(year: 2026, month: 9, day: 17, hour: 9)
    lazy var nextWeek = cal.date(year: 2026, month: 9, day: 23, hour: 9)
    lazy var scheduler = Scheduler(
        chores: [litter, laundry],
        activeFrom: activeFrom,
        rotation: FixedRotation(person: .anne),
        calendar: cal
    )
    /// Litter done Tuesday and laundry done last Thursday, so today's periods are the oldest incomplete ones.
    lazy var caughtUp = [
        Completion(id: "c1", choreId: litter.id, person: .anne, completedAt: cal.date(year: 2026, month: 9, day: 15)),
        Completion(id: "c2", choreId: laundry.id, person: .anne, completedAt: cal.date(year: 2026, month: 9, day: 10)),
    ]

    func handoff(
        _ chore: Chore,
        from: Person = .anne,
        to: Person = .wes,
        period: Int,
        state: Handoff.State,
        id: String = "h1"
    ) -> Handoff {
        Handoff(
            id: id,
            choreId: chore.id,
            from: from,
            to: to,
            periodIndex: period,
            cadence: chore.cadence,
            createdAt: wed,
            state: state
        )
    }

    func owner(_ chore: Chore, in plan: [Person: [DueItem]]) -> Person? {
        Person.allCases.first { (plan[$0] ?? []).contains { $0.chore.id == chore.id } }
    }

    func testAcceptedHandoffMovesTheChoreForOnePeriodThenReverts() {
        let today = cal.periodIndex(.daily, containing: wed)
        let accepted = handoff(litter, period: today, state: .accepted)

        let plan = scheduler.plan(on: wed, completions: caughtUp, handoffs: [accepted])
        XCTAssertEqual(owner(litter, in: plan), .wes, "Wes took today's scoop")
        XCTAssertEqual(scheduler.assignee(for: litter, periodIndex: today), .anne, "rotation itself is untouched")

        // Wes does it, and tomorrow the chore is Anne's again — the handoff covered one period.
        let after = caughtUp + [
            Completion(
                id: "c3",
                choreId: litter.id,
                person: .wes,
                completedAt: cal.date(year: 2026, month: 9, day: 16)
            ),
        ]
        let tomorrow = scheduler.plan(on: thu, completions: after, handoffs: [accepted])
        XCTAssertEqual(owner(litter, in: tomorrow), .anne)
        XCTAssertEqual(
            scheduler.assignee(for: litter, periodIndex: today + 1, on: thu, handoffs: [accepted]),
            .anne
        )
        XCTAssertTrue(accepted.hasExpired(on: thu, calendar: cal))
        XCTAssertEqual(HandoffRules.effectiveState(accepted, on: thu, calendar: cal), .expired)
    }

    func testAcceptedHandoffOverridesAPin() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let accepted = handoff(laundry, period: week, state: .accepted)

        let plan = scheduler.plan(on: wed, completions: caughtUp, handoffs: [accepted])
        XCTAssertEqual(owner(laundry, in: plan), .wes, "Anne's pinned laundry is Wes's this week")
        XCTAssertEqual(scheduler.assignee(for: laundry, periodIndex: week), .anne, "the pin itself is unchanged")
        XCTAssertEqual(
            scheduler.assignee(for: laundry, periodIndex: week + 1, on: nextWeek, handoffs: [accepted]),
            .anne,
            "next week it is hers again"
        )
    }

    func testPendingDeclinedAndExpiredHandoffsChangeNothing() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let baseline = scheduler.plan(on: wed, completions: caughtUp)
        for state in [Handoff.State.pending, .declined, .expired] {
            let offered = handoff(laundry, period: week, state: state)
            XCTAssertEqual(
                scheduler.plan(on: wed, completions: caughtUp, handoffs: [offered]),
                baseline,
                "a \(state.rawValue) handoff is not an override"
            )
            XCTAssertEqual(scheduler.assignee(for: laundry, periodIndex: week, on: wed, handoffs: [offered]), .anne)
        }
    }

    func testAcceptedHandoffForAnotherPeriodDoesNotApply() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let lastWeek = handoff(laundry, period: week - 1, state: .accepted)
        XCTAssertEqual(scheduler.assignee(for: laundry, periodIndex: week, on: wed, handoffs: [lastWeek]), .anne)
        XCTAssertEqual(
            scheduler.plan(on: wed, completions: caughtUp, handoffs: [lastWeek]),
            scheduler.plan(on: wed, completions: caughtUp)
        )
    }

    func testCanOfferOnlyTheAssignedPerson() {
        let rules = HandoffRules(scheduler: scheduler)
        XCTAssertTrue(rules.canOffer(laundry, from: .anne, on: wed), "it is pinned to her")
        XCTAssertFalse(rules.canOffer(laundry, from: .wes, on: wed), "not his chore to give away")
        XCTAssertTrue(rules.canOffer(litter, from: .anne, on: wed))
        XCTAssertFalse(rules.canOffer(litter, from: .wes, on: wed))
        XCTAssertNil(rules.offer(litter, from: .wes, to: .anne, on: wed, id: "x"))
        XCTAssertNil(rules.offer(litter, from: .anne, to: .anne, on: wed, id: "x"), "cannot hand a chore to yourself")

        let offered = rules.offer(laundry, from: .anne, to: .wes, on: wed, id: "h9")
        XCTAssertEqual(offered?.state, .pending)
        XCTAssertEqual(offered?.periodIndex, cal.periodIndex(.weekly, containing: wed))
        XCTAssertEqual(offered?.cadence, .weekly)
    }

    func testCanOfferRejectsASecondConcurrentOffer() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let pending = handoff(laundry, period: week, state: .pending)
        XCTAssertFalse(
            HandoffRules(scheduler: scheduler, handoffs: [pending]).canOffer(laundry, from: .anne, on: wed),
            "one open offer per chore per period"
        )

        // Once Wes has it, neither of them can stack another offer on the same week.
        let taken = HandoffRules(scheduler: scheduler, handoffs: [pending.with(state: .accepted)])
        XCTAssertFalse(taken.canOffer(laundry, from: .anne, on: wed))
        XCTAssertFalse(taken.canOffer(laundry, from: .wes, on: wed))

        // A no closes the offer out, so she can ask again.
        let declined = HandoffRules(scheduler: scheduler, handoffs: [pending.with(state: .declined)])
        XCTAssertTrue(declined.canOffer(laundry, from: .anne, on: wed))

        // Last week's offer does not block this week's.
        let stale = HandoffRules(scheduler: scheduler, handoffs: [handoff(laundry, period: week - 1, state: .pending)])
        XCTAssertTrue(stale.canOffer(laundry, from: .anne, on: wed))
    }

    func testResolveAnswersAndExpires() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let pending = handoff(laundry, period: week, state: .pending)
        let rules = HandoffRules(scheduler: scheduler, handoffs: [pending])

        XCTAssertEqual(rules.resolve(pending, as: .accept, on: wed).state, .accepted)
        XCTAssertEqual(rules.resolve(pending, as: .decline, on: wed).state, .declined)
        XCTAssertEqual(
            rules.resolve(pending.with(state: .accepted), as: .decline, on: wed).state,
            .accepted,
            "an answered offer keeps its answer"
        )
        XCTAssertEqual(
            rules.resolve(pending, as: .accept, on: nextWeek).state,
            .expired,
            "too late to take a turn that is over"
        )

        XCTAssertEqual(rules.resolve(on: wed).map(\.state), [.pending], "still live inside its period")
        XCTAssertEqual(rules.resolve(on: nextWeek).map(\.state), [.expired])
        let declined = HandoffRules(scheduler: scheduler, handoffs: [pending.with(state: .declined)])
        XCTAssertEqual(declined.resolve(on: nextWeek).map(\.state), [.declined], "a no stays on the record")
    }
}
