@testable import Roost
import RoostCore
import XCTest

final class TodayPlannerTests: XCTestCase {
    private let cal = HouseholdCalendar()

    private func chores() throws -> [Chore] {
        try ChoreList.load(from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self))).chores
    }

    func testPinnedChoresLandOnTheRightPerson() throws {
        let sunday = cal.date(year: 2026, month: 9, day: 13) // a Sunday: weekly items still open for the week
        let plan = try TodayPlanner.plan(
            chores: chores(),
            completions: [],
            asOf: sunday,
            activeFrom: cal.startOfDay(sunday),
            calendar: cal
        )

        let anne = plan.rows(for: .anne).map(\.chore.id)
        let wes = plan.rows(for: .wes).map(\.chore.id)
        XCTAssertTrue(anne.contains("laundry"))
        XCTAssertFalse(wes.contains("laundry"))
        XCTAssertTrue(wes.contains("garbage-can-to-street-sunday"))
        XCTAssertFalse(anne.contains("garbage-can-to-street-sunday"))

        // every active chore is due for exactly one person on day one
        XCTAssertEqual(Set(anne).intersection(wes).count, 0)
        XCTAssertEqual(anne.count + wes.count, 31)
        XCTAssertEqual(plan.dueCount(for: .anne) + plan.dueCount(for: .wes), 31)
    }

    func testCatCareRowsComeFirstWithinEachPerson() throws {
        let day = cal.date(year: 2026, month: 9, day: 14)
        let plan = try TodayPlanner.plan(
            chores: chores(),
            completions: [],
            asOf: day,
            activeFrom: cal.startOfDay(day),
            calendar: cal
        )
        for person in Person.allCases {
            let cats = plan.rows(for: person).map { $0.chore.category == .catCare }
            if let firstNonCat = cats.firstIndex(of: false) {
                XCTAssertFalse(cats[firstNonCat...].contains(true), "\(person): cat-care rows must precede the rest")
            }
        }
    }

    func testCompletedTodayShowsAsDoneRowAndCountsInTally() throws {
        let day = cal.date(year: 2026, month: 9, day: 14, hour: 18)
        let chores = try chores()
        let done = Completion(
            id: "c-1",
            choreId: "scoop-litter",
            person: .anne,
            completedAt: cal.date(year: 2026, month: 9, day: 14, hour: 9)
        )
        let plan = TodayPlanner.plan(
            chores: chores,
            completions: [done],
            asOf: day,
            activeFrom: cal.startOfDay(day),
            calendar: cal
        )

        let row = try XCTUnwrap(plan.rows(for: .anne).first { $0.chore.id == "scoop-litter" })
        XCTAssertTrue(row.isDone)
        XCTAssertEqual(row.kind, .done(completionId: "c-1"))
        XCTAssertFalse(plan.rows(for: .wes).contains { $0.chore.id == "scoop-litter" })
        XCTAssertEqual(plan.doneThisWeek[.anne], 1)
        XCTAssertEqual(plan.doneThisWeek[.wes], 0)
    }

    func testOverdueStageFlowsThrough() throws {
        let chores = try chores()
        let start = cal.date(year: 2026, month: 9, day: 1)
        let later = cal.date(year: 2026, month: 9, day: 6) // dailies from Sep 1 are 5 days late
        let plan = TodayPlanner.plan(
            chores: chores,
            completions: [],
            asOf: later,
            activeFrom: cal.startOfDay(start),
            calendar: cal
        )
        let daily = try XCTUnwrap((plan.rows(for: .anne) + plan.rows(for: .wes)).first { $0.chore.cadence == .daily })
        XCTAssertEqual(daily.daysOverdue, 5)
        XCTAssertEqual(daily.stage, .alert)
    }

    func testTogetherChoreIsARowForBothAndOneCheckOffClearsBoth() throws {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, fixedAssignee: .anne,
                           category: .catCare)
        let day = cal.date(year: 2026, month: 9, day: 14, hour: 10)
        let plan = TodayPlanner.plan(chores: [litter, pantry], completions: [], asOf: day,
                                     activeFrom: cal.startOfDay(day), calendar: cal)
        let anne = try XCTUnwrap(plan.rows(for: .anne).first { $0.chore.id == pantry.id })
        let wes = try XCTUnwrap(plan.rows(for: .wes).first { $0.chore.id == pantry.id })
        XCTAssertNotEqual(anne.id, wes.id, "two rows, two ids")
        XCTAssertFalse(anne.canOffer)
        XCTAssertFalse(wes.canOffer)
        XCTAssertEqual(plan.dueCount(for: .anne), 2)
        XCTAssertEqual(plan.dueCount(for: .wes), 1)

        let done = Completion(id: "p1", choreId: pantry.id, person: .wes, completedAt: day)
        let after = TodayPlanner.plan(chores: [litter, pantry], completions: [done], asOf: day,
                                      activeFrom: cal.startOfDay(day), calendar: cal)
        XCTAssertFalse(after.rows(for: .anne).contains { $0.chore.id == pantry.id && !$0.isDone })
        XCTAssertEqual(after.rows(for: .wes).first { $0.chore.id == pantry.id }?.isDone, true, "the done row sits in the tapper's column")
        XCTAssertEqual(after.doneThisWeek, [.anne: 1, .wes: 1], "credit for both")
    }
}
