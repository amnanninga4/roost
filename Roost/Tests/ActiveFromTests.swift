// The household start date: the server owns it, `/sync` carries it, and it is the floor the scheduler
// counts periods from. Before D-8 each phone fixed its own on first render, which meant a phone set up
// a week later than the other disagreed with it about what was overdue.
@testable import Roost
import RoostCore
import XCTest

final class ActiveFromTests: ListSyncTestCase {
    private let cal = HouseholdCalendar()

    func testSyncStoresTheServersActiveFromAsAChicagoDay() async throws {
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 3, activeFrom: "2026-09-07")) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")

        let stored = try XCTUnwrap(try state().activeFrom)
        XCTAssertEqual(stored, cal.startOfDay(cal.date(year: 2026, month: 9, day: 7)))
        // Midnight in Chicago, not in whatever zone the phone happens to be in.
        XCTAssertEqual(cal.dayIndex(stored), cal.dayIndex(cal.date(year: 2026, month: 9, day: 7)))
    }

    func testAResponseWithoutActiveFromKeepsTheStoredValue() async throws {
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 3, activeFrom: "2026-09-07")) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")
        let first = try XCTUnwrap(try state().activeFrom)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 4)) }
        _ = await client.syncNow()
        XCTAssertEqual(try state().activeFrom, first, "an older server does not reset the household start")
    }

    func testTheServerCanMoveTheStartDate() async throws {
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 3, activeFrom: "2026-09-07")) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 4, activeFrom: "2026-09-01")) }
        _ = await client.syncNow()
        XCTAssertEqual(try state().activeFrom, cal.startOfDay(cal.date(year: 2026, month: 9, day: 1)))
    }

    func testNonsenseIsIgnoredRatherThanStored() async throws {
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 3, activeFrom: "not-a-day")) }
        _ = try await client.pair(baseURL: base, token: "anne-token-0123456789abcdef")
        XCTAssertNil(try state().activeFrom)
        XCTAssertNil(SyncAPI.parseActiveFrom("2026-13-01"))
        XCTAssertNil(SyncAPI.parseActiveFrom("2026-09"))
    }

    // MARK: - what the floor does to the plan

    private var chores: [Chore] {
        [
            Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare),
            Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore),
            Chore(id: "clean-oven", title: "Clean the oven", cadence: .monthly, category: .chore),
        ]
    }

    /// A phone joining a household that started a week ago sees a week of backlog and not a day more.
    /// No period that closed before the start day is ever surfaced, whatever the cadence: the floor is
    /// the period `activeFrom` falls in, so a monthly the household joined mid-month is simply due.
    func testAPhoneJoiningAWeekLateShowsNoBacklogBeforeTheStartDay() throws {
        let start = cal.date(year: 2026, month: 9, day: 7) // a Monday
        let today = cal.date(year: 2026, month: 9, day: 14, hour: 10) // the Monday after
        let floor = cal.startOfDay(start)
        let plan = TodayPlanner.plan(
            chores: chores, completions: [], asOf: today, activeFrom: floor, calendar: cal
        )

        let rows = plan.rows(for: .anne) + plan.rows(for: .wes)
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            guard case let .due(item) = row.kind else { return XCTFail("\(row.chore.id) should be due") }
            XCTAssertGreaterThanOrEqual(
                item.periodIndex,
                cal.periodIndex(row.chore.cadence, containing: floor),
                "\(row.chore.id) reaches back past the day the household started"
            )
        }
        // A week of it, exactly: Sep 7 for the daily, the Sep 7 week for the weekly, and September's
        // monthly period still open, so nothing to answer for there yet.
        let daily = try XCTUnwrap(rows.first { $0.chore.cadence == .daily })
        XCTAssertEqual(daily.daysOverdue, 7)
        let weekly = try XCTUnwrap(rows.first { $0.chore.cadence == .weekly })
        XCTAssertEqual(weekly.daysOverdue, 1)
        let monthly = try XCTUnwrap(rows.first { $0.chore.cadence == .monthly })
        XCTAssertEqual(monthly.daysOverdue, 0)

        // And the floor is what bounds it: with none, the same phone reads months of nagging off the
        // household calendar's own anchor.
        let unbounded = TodayPlanner.plan(
            chores: chores, completions: [], asOf: today, activeFrom: cal.day(at: 0), calendar: cal
        )
        let ancient = try XCTUnwrap(
            (unbounded.rows(for: .anne) + unbounded.rows(for: .wes)).first { $0.chore.cadence == .daily }
        )
        XCTAssertGreaterThan(ancient.daysOverdue, 200)
    }

    /// A phone with nothing stored is read as starting today, which is what the screens pass. Nothing is
    /// overdue on day one, so a fresh phone never opens on a wall of red.
    func testAPhoneWithNoStoredStartBehavesAsToday() throws {
        XCTAssertNil(try state().activeFrom, "a phone that has never synced has no start date")

        let today = cal.date(year: 2026, month: 9, day: 14, hour: 10)
        let fallback = try state().activeFrom ?? cal.startOfDay(today)
        let plan = TodayPlanner.plan(
            chores: chores, completions: [], asOf: today, activeFrom: fallback, calendar: cal
        )
        let rows = plan.rows(for: .anne) + plan.rows(for: .wes)
        XCTAssertEqual(rows.count, 3)
        for row in rows {
            XCTAssertEqual(row.daysOverdue, 0, "\(row.chore.id) cannot be late on the first day")
            XCTAssertEqual(row.stage, .dueToday)
        }
    }
}
