@testable import RoostCore
import XCTest

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
        // Tomorrow reverts because it is a different period, not because the handoff died: the turn Wes took
        // is still on the record for the day he took it.
        XCTAssertTrue(accepted.isPastItsPeriod(on: thu, calendar: cal), "its day is over")
        XCTAssertFalse(accepted.hasExpired(on: thu, calendar: cal), "a turn that was taken does not expire")
        XCTAssertEqual(HandoffRules.effectiveState(accepted, on: thu, calendar: cal), .accepted)
        XCTAssertEqual(
            scheduler.assignee(for: litter, periodIndex: today, on: thu, handoffs: [accepted]),
            .wes,
            "asked about yesterday, it is still his"
        )
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

        let accepted = pending.with(state: .accepted)
        XCTAssertEqual(
            rules.resolve(accepted, as: .decline, on: nextWeek).state,
            .accepted,
            "a late answer cannot take back a turn that was taken"
        )
    }

    func testSweepLeavesAnAcceptedHandoffAlone() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let accepted = handoff(laundry, period: week, state: .accepted)
        let swept = HandoffRules(scheduler: scheduler, handoffs: [accepted]).resolve(on: nextWeek)

        XCTAssertEqual(swept.map(\.state), [.accepted], "the week ended; the turn Wes took did not")
        XCTAssertTrue(accepted.isPastItsPeriod(on: nextWeek, calendar: cal), "its period is over")
        XCTAssertFalse(accepted.hasExpired(on: nextWeek, calendar: cal), "which is not the same as expired")
        XCTAssertEqual(HandoffRules.effectiveState(accepted, on: nextWeek, calendar: cal), .accepted)

        // Still the override for its own period, asked from next week, before and after the sweep.
        for handoffs in [[accepted], swept] {
            XCTAssertEqual(
                scheduler.assignee(for: laundry, periodIndex: week, on: nextWeek, handoffs: handoffs),
                .wes
            )
        }
        XCTAssertEqual(
            scheduler.assignee(for: laundry, periodIndex: week + 1, on: nextWeek, handoffs: swept),
            .anne,
            "next week is a different period, so the pin has it again"
        )
    }

    func testSweepExpiresAnOfferNobodyAnswered() {
        let week = cal.periodIndex(.weekly, containing: wed)
        let pending = handoff(laundry, period: week, state: .pending)
        let swept = HandoffRules(scheduler: scheduler, handoffs: [pending]).resolve(on: nextWeek)

        XCTAssertEqual(swept.map(\.state), [.expired])
        XCTAssertTrue(pending.hasExpired(on: nextWeek, calendar: cal))
        XCTAssertEqual(HandoffRules.effectiveState(pending, on: nextWeek, calendar: cal), .expired)
        XCTAssertEqual(
            scheduler.assignee(for: laundry, periodIndex: week, on: nextWeek, handoffs: swept),
            .anne,
            "an offer nobody took never moved anything"
        )
    }

    func testOverdueItemStaysWithTheAcceptor() {
        // Laundry was done in the week of Sep 7 and handed to Wes for the week of Sep 14, which he accepted —
        // then neither of them did it. By Wednesday Sep 23 that week is the oldest incomplete one, and the nag
        // belongs to the person who took the turn, not back to the pin.
        let week = cal.periodIndex(.weekly, containing: wed)
        let accepted = handoff(laundry, period: week, state: .accepted)
        let later = cal.date(year: 2026, month: 9, day: 23, hour: 9)

        let item = scheduler.dueItem(for: laundry, on: later, completions: caughtUp, handoffs: [accepted])
        XCTAssertEqual(item?.periodIndex, week, "the handed-off week is the oldest incomplete one")
        XCTAssertEqual(item?.daysOverdue, 3)
        XCTAssertEqual(item?.person, .wes)
        XCTAssertEqual(
            scheduler.dueItem(for: laundry, on: later, completions: caughtUp)?.person,
            .anne,
            "with the handoff ignored it falls back to her pin"
        )

        XCTAssertEqual(owner(laundry, in: scheduler.plan(on: later, completions: caughtUp, handoffs: [accepted])), .wes)
        let swept = HandoffRules(scheduler: scheduler, handoffs: [accepted]).resolve(on: later)
        XCTAssertEqual(
            owner(laundry, in: scheduler.plan(on: later, completions: caughtUp, handoffs: swept)),
            .wes,
            "and a sweep in between does not hand the nag back"
        )
    }

    func testATogetherChoreCannotBeOffered() {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        let rules = HandoffRules(scheduler: Scheduler(
            chores: [pantry], activeFrom: activeFrom, rotation: FixedRotation(person: .anne), calendar: cal
        ))
        XCTAssertFalse(rules.canOffer(pantry, from: .anne, on: wed))
        XCTAssertFalse(rules.canOffer(pantry, from: .wes, on: wed))
        XCTAssertNil(rules.offer(pantry, from: .anne, to: .wes, on: wed, id: "h1"))
    }
}
