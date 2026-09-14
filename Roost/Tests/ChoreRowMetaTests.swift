// The two-slot urgency pick for a chore row's meta line: at most two elements, days-late first,
// then a handoff still in motion, then whose the chore is. "From X" is the giver's name chip in the
// giver's own colour, never text; "On the other phone" is gone entirely.
@testable import Roost
import RoostCore
import XCTest

final class ChoreRowMetaTests: XCTestCase {
    private let cal = HouseholdCalendar()

    /// The planner is the only thing that builds a DueItem: a daily chore never done, asked about
    /// `daysOverdue` days after activeFrom, is exactly that many days late.
    private func row(
        daysOverdue: Int = 0,
        together: Bool = false,
        pinned: Person? = nil,
        handoff: RowHandoff? = nil,
        done: Bool = false
    ) throws -> TodayRow {
        let chore = Chore(
            id: "c-1", title: "Scoop litter", cadence: .daily,
            fixedAssignee: pinned, category: .catCare, together: together
        )
        let activeFrom = cal.startOfDay(cal.date(year: 2026, month: 9, day: 1))
        let plan = TodayPlanner.plan(
            chores: [chore],
            completions: [],
            asOf: cal.date(year: 2026, month: 9, day: 1 + daysOverdue, hour: 18),
            activeFrom: activeFrom,
            calendar: cal
        )
        let due = try XCTUnwrap((plan.rows(for: .anne) + plan.rows(for: .wes)).first, "no row planned")
        let kind: TodayRow.Kind = done ? .done(completionId: "done-1") : due.kind
        return TodayRow(chore: chore, person: .anne, kind: kind, handoff: handoff)
    }

    func testDueTodayWithNothingElseIsAnEmptyLine() throws {
        XCTAssertEqual(try ChoreRowMeta.elements(for: row()), [])
    }

    func testTheCapIsTwoAndTheOrderIsLateNoteChip() throws {
        let r = try row(daysOverdue: 3, pinned: .anne, handoff: .waiting(on: .wes, id: "h-1", canWithdraw: true))
        XCTAssertEqual(
            ChoreRowMeta.elements(for: r),
            [.daysLate(3), .handoffNote(Strings.Handoffs.waiting("Wes"))],
            "the name chip is the third urgency, so it falls off"
        )
    }

    func testTheNoteBeatsTheChipButLosesToTheLateCount() throws {
        let r = try row(daysOverdue: 1, together: true, handoff: .declined(by: .wes))
        XCTAssertEqual(
            ChoreRowMeta.elements(for: r),
            [.daysLate(1), .handoffNote(Strings.Handoffs.saidNo("Wes"))]
        )
    }

    func testTheChipSlotIsTogetherThenTheGiverThenThePin() throws {
        XCTAssertEqual(try ChoreRowMeta.elements(for: row(together: true)), [.together])
        XCTAssertEqual(
            try ChoreRowMeta.elements(for: row(pinned: .wes, handoff: .takenFrom(.wes))),
            [.taken(.wes)],
            "the giver's chip says what the pin would, so the pin never reaches the line"
        )
        XCTAssertEqual(try ChoreRowMeta.elements(for: row(pinned: .anne)), [.pinned(.anne)])
    }

    func testASettledHandoffIsTheGiversChipNotFromText() throws {
        let r = try row(daysOverdue: 5, handoff: .takenFrom(.wes))
        XCTAssertEqual(ChoreRowMeta.elements(for: r), [.daysLate(5), .taken(.wes)])
    }

    func testADoneRowKeepsItsChipButHasNoLateCount() throws {
        XCTAssertEqual(try ChoreRowMeta.elements(for: row(pinned: .anne, done: true)), [.pinned(.anne)])
    }

    func testARefusedOfferStillGetsItsNote() throws {
        let r = try row(daysOverdue: 2, handoff: .refused(to: .wes))
        XCTAssertEqual(
            ChoreRowMeta.elements(for: r),
            [.daysLate(2), .handoffNote(Strings.Handoffs.refused)]
        )
    }
}
