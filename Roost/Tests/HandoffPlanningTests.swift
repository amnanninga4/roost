// What handoffs do to the Tasks tab's plan: who a chore lands on, what the row says about it, which
// offers are waiting for an answer, and whose streak a given-away daily counts for.
//
// Everything here goes through TodayPlanner, so the assertions are the screen's own answers.
@testable import Roost
import RoostCore
import XCTest

final class HandoffPlanningTests: XCTestCase {
    private let cal = HouseholdCalendar()
    /// A Monday, so the weekly period starts today and "the current period" is unambiguous.
    private lazy var monday = cal.date(year: 2026, month: 9, day: 14, hour: 10)

    private let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne,
                                category: .chore)
    private let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare)
    private let dishes = Chore(id: "dishes", title: "Wash dishes", cadence: .daily, category: .chore)

    private var chores: [Chore] {
        [litter, dishes, laundry]
    }

    private func plan(
        completions: [Completion] = [], handoffs: [HandoffSnapshot] = [], asOf date: Date? = nil
    ) -> TodayPlan {
        let day = date ?? monday
        return TodayPlanner.plan(
            chores: chores, completions: completions, handoffs: handoffs,
            asOf: day, activeFrom: cal.startOfDay(day), calendar: cal
        )
    }

    private func snapshot(
        _ chore: Chore, from: Person, to: Person, state: Handoff.State = .pending,
        on date: Date? = nil, id: String = "h", reachedServer: Bool = true, refused: Bool = false,
        noticeCleared: Bool = false
    ) -> HandoffSnapshot {
        let day = date ?? monday
        return HandoffSnapshot(
            handoff: Handoff(
                id: id,
                choreId: chore.id,
                from: from,
                to: to,
                periodIndex: cal.periodIndex(chore.cadence, containing: day),
                cadence: chore.cadence,
                createdAt: day,
                state: state
            ),
            reachedServer: reachedServer,
            refused: refused,
            noticeCleared: noticeCleared
        )
    }

    private func row(_ chore: Chore, for person: Person, in plan: TodayPlan) -> TodayRow? {
        plan.rows(for: person).first { $0.chore.id == chore.id }
    }

    // MARK: - Scheduler.plan

    /// The pin says Laundry is Anne's. An accepted handoff outranks the pin for that one week.
    func testAnAcceptedHandoffMovesTheItemToTheAcceptorsColumn() throws {
        let plain = plan()
        XCTAssertNotNil(row(laundry, for: .anne, in: plain))
        XCTAssertNil(row(laundry, for: .wes, in: plain))

        let moved = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes, state: .accepted)])
        XCTAssertNil(row(laundry, for: .anne, in: moved))
        let wes = try XCTUnwrap(row(laundry, for: .wes, in: moved))
        XCTAssertEqual(wes.handoff, .takenFrom(.anne))
    }

    func testAPendingOfferMovesNothing() {
        let offered = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes)])
        XCTAssertNotNil(row(laundry, for: .anne, in: offered))
        XCTAssertNil(row(laundry, for: .wes, in: offered))
    }

    /// A refused offer exists on this phone and nowhere else, so it must not decide who owes a chore:
    /// the other phone has never heard of it.
    func testARefusedOfferNeverMovesAnItem() {
        let refused = plan(handoffs: [
            snapshot(laundry, from: .anne, to: .wes, state: .accepted, reachedServer: false, refused: true),
        ])
        XCTAssertNotNil(row(laundry, for: .anne, in: refused))
        XCTAssertNil(row(laundry, for: .wes, in: refused))
        XCTAssertEqual(row(laundry, for: .anne, in: refused)?.handoff, .refused(to: .wes))
    }

    /// The balancer is nil, so nothing shuffles a level day: each chore keeps the person the rotation
    /// gave it however much either of them has already done.
    func testThePlannerRunsWithoutTheBalancer() {
        let busy = (0 ..< 6).map {
            Completion(
                id: "c\($0)", choreId: dishes.id, person: .anne,
                completedAt: cal.adding(days: -1, to: monday)
            )
        }
        let level = plan()
        let lopsided = plan(completions: busy)
        for person in Person.allCases {
            XCTAssertEqual(
                level.rows(for: person).map(\.chore.id),
                lopsided.rows(for: person).filter { !$0.isDone }.map(\.chore.id),
                "yesterday's work must not move today's chores: the balancer stays off"
            )
        }
    }

    // MARK: - Tallies.streak

    /// Give a daily away and the day still counts for the offerer, because it was not theirs that day —
    /// and it counts for the receiver only once it is actually done.
    func testAGivenAwayDailyMovesTheDayBetweenTheStreaks() throws {
        let yesterday = cal.adding(days: -1, to: monday)
        let dailies = chores.filter { $0.cadence == .daily }
        let scheduler = Scheduler(chores: chores, activeFrom: cal.startOfDay(yesterday), calendar: cal)
        let day = cal.dayIndex(yesterday)

        // Yesterday's dailies, each done by whoever owed it: a clean day for both of them.
        var completions: [Completion] = []
        for chore in dailies {
            let owner = scheduler.assignee(for: chore, periodIndex: day)
            completions.append(Completion(
                id: "y-\(chore.id)", choreId: chore.id, person: owner, completedAt: yesterday
            ))
        }
        let plain = TodayPlanner.plan(
            chores: chores, completions: completions, asOf: monday,
            activeFrom: cal.startOfDay(yesterday), calendar: cal
        )
        XCTAssertEqual(plain.streak[.anne], 1)
        XCTAssertEqual(plain.streak[.wes], 1)

        // Now Anne handed hers to Wes yesterday and nobody did it. Anne's day is still complete — the
        // chore was not hers — and Wes's is not.
        let hers = try XCTUnwrap(dailies.first { scheduler.assignee(for: $0, periodIndex: day) == .anne })
        let handed = snapshot(hers, from: .anne, to: .wes, state: .accepted, on: yesterday, id: "h-y")
        let moved = TodayPlanner.plan(
            chores: chores,
            completions: completions.filter { $0.choreId != hers.id },
            handoffs: [handed],
            asOf: monday,
            activeFrom: cal.startOfDay(yesterday),
            calendar: cal
        )
        XCTAssertEqual(moved.streak[.anne], 1, "the chore was not hers that day")
        XCTAssertEqual(moved.streak[.wes], 0, "it was his, and it was not done")
    }

    // MARK: - canOffer

    func testCanOfferIsTrueOnlyOnYourOwnCurrentPeriodRow() {
        let p = plan()
        XCTAssertEqual(row(laundry, for: .anne, in: p)?.canOffer, true)
        // Wes has no Laundry row at all; every row he does have is his to offer, none of hers.
        for wesRow in p.rows(for: .wes) {
            XCTAssertTrue(wesRow.canOffer, "\(wesRow.chore.id) is his this period")
        }
    }

    func testAnOverduePeriodCannotBeOffered() {
        let start = cal.date(year: 2026, month: 9, day: 1)
        let later = cal.date(year: 2026, month: 9, day: 6)
        let overdue = TodayPlanner.plan(
            chores: chores, completions: [], asOf: later, activeFrom: cal.startOfDay(start), calendar: cal
        )
        let late = (overdue.rows(for: .anne) + overdue.rows(for: .wes)).filter { $0.daysOverdue > 0 }
        XCTAssertFalse(late.isEmpty)
        for lateRow in late {
            XCTAssertFalse(lateRow.canOffer, "\(lateRow.chore.id) belongs to a period that has closed")
        }
    }

    func testAnOpenOfferBlocksASecondOne() {
        let once = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes)])
        XCTAssertEqual(row(laundry, for: .anne, in: once)?.canOffer, false)
    }

    func testACompletedRowOffersNothingAndKeepsTheChip() {
        let done = Completion(id: "c-1", choreId: laundry.id, person: .wes, completedAt: monday)
        let p = plan(
            completions: [done], handoffs: [snapshot(laundry, from: .anne, to: .wes, state: .accepted)]
        )
        let wes = row(laundry, for: .wes, in: p)
        XCTAssertEqual(wes?.isDone, true)
        XCTAssertEqual(wes?.canOffer, false)
        XCTAssertEqual(wes?.handoff, .takenFrom(.anne))
    }

    // MARK: - the row's own state

    func testAQueuedOfferCanBeWithdrawnAndASyncedOneCannot() {
        let queued = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes, reachedServer: false)])
        XCTAssertEqual(row(laundry, for: .anne, in: queued)?.handoff, .waiting(on: .wes, id: "h", canWithdraw: true))

        let sent = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes, reachedServer: true)])
        XCTAssertEqual(row(laundry, for: .anne, in: sent)?.handoff, .waiting(on: .wes, id: "h", canWithdraw: false))
    }

    func testADeclineShowsUntilItsNoticeIsCleared() {
        let said = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes, state: .declined)])
        XCTAssertEqual(row(laundry, for: .anne, in: said)?.handoff, .declined(by: .wes))

        let read = plan(handoffs: [
            snapshot(laundry, from: .anne, to: .wes, state: .declined, noticeCleared: true),
        ])
        XCTAssertNil(row(laundry, for: .anne, in: read)?.handoff)
    }

    /// Nobody answered. Saying so days later helps no one, and the chore is simply Anne's again.
    func testAnExpiredOfferShowsNothing() {
        let lastWeek = cal.adding(days: -7, to: monday)
        let stale = snapshot(laundry, from: .anne, to: .wes, on: lastWeek, id: "h-old")
        let p = plan(handoffs: [stale])
        XCTAssertNil(row(laundry, for: .anne, in: p)?.handoff)
        XCTAssertEqual(row(laundry, for: .anne, in: p)?.canOffer, true, "a dead offer does not block a new one")
        XCTAssertTrue(p.offers(for: .wes).isEmpty)
    }

    /// A declined offer lets the offerer ask again, and the new pending offer is what the row shows.
    func testANewOfferOutranksTheOldNo() {
        let p = plan(handoffs: [
            snapshot(laundry, from: .anne, to: .wes, state: .declined, id: "h-1"),
            snapshot(laundry, from: .anne, to: .wes, id: "h-2"),
        ])
        XCTAssertEqual(row(laundry, for: .anne, in: p)?.handoff, .waiting(on: .wes, id: "h-2", canWithdraw: false))
    }

    // MARK: - incoming offers

    func testAPendingOfferIsAnIncomingCardForThePersonAsked() {
        let p = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes, id: "h-3")])
        XCTAssertTrue(p.offers(for: .anne).isEmpty)
        let offers = p.offers(for: .wes)
        XCTAssertEqual(offers.count, 1)
        XCTAssertEqual(offers.first?.id, "h-3")
        XCTAssertEqual(offers.first?.from, .anne)
        XCTAssertEqual(offers.first?.chore.title, "Laundry")
        XCTAssertEqual(offers.first?.cadence, .weekly)
    }

    func testAnAnsweredOfferIsNoLongerACard() {
        for state in [Handoff.State.accepted, .declined, .expired] {
            let p = plan(handoffs: [snapshot(laundry, from: .anne, to: .wes, state: state)])
            XCTAssertTrue(p.offers(for: .wes).isEmpty, "\(state) is not a question any more")
        }
    }

    func testARefusedOfferIsNotACard() {
        let p = plan(handoffs: [
            snapshot(laundry, from: .anne, to: .wes, reachedServer: false, refused: true),
        ])
        XCTAssertTrue(p.offers(for: .wes).isEmpty)
    }

    func testATogetherRowIsNeverOfferable() {
        let pantry = Chore(id: "pantry", title: "Clean out fridge and pantry", cadence: .weekly,
                           category: .chore, together: true)
        let plan = TodayPlanner.plan(chores: [pantry], completions: [], asOf: monday,
                                     activeFrom: cal.startOfDay(monday), calendar: cal)
        XCTAssertEqual(plan.rows(for: .anne).first?.canOffer, false)
        XCTAssertEqual(plan.rows(for: .wes).first?.canOffer, false)
    }

    /// The period phrase is the server's, so the card and the push that arrived before it agree.
    func testThePeriodPhraseMatchesTheServers() {
        XCTAssertEqual(Cadence.daily.periodPhrase, "today")
        XCTAssertEqual(Cadence.weekly.periodPhrase, "this week")
        XCTAssertEqual(Cadence.biweekly.periodPhrase, "this week")
        XCTAssertEqual(Cadence.monthly.periodPhrase, "this month")
        XCTAssertEqual(Cadence.bimonthly.periodPhrase, "these two months")
        XCTAssertEqual(Cadence.quarterly.periodPhrase, "this quarter")
        // The whole table, so the server's PERIOD_PHRASES test and this one pin the same six lines.
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: Cadence.allCases.map { ($0.rawValue, $0.periodPhrase) }),
            ["daily": "today", "weekly": "this week", "biweekly": "this week", "monthly": "this month",
             "bimonthly": "these two months", "quarterly": "this quarter"]
        )
    }
}
