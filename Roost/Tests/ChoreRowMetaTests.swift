// The two-slot urgency pick for a chore row's meta line: at most two elements, days-late first,
// then a handoff still in motion, then whose the chore is. "From X" is the giver's name chip in the
// giver's own colour, never text; "On the other phone" is gone entirely.
@testable import Roost
import RoostCore
import XCTest

final class ChoreRowMetaTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(
        daysOverdue: Int = 0,
        together: Bool = false,
        pinned: Person? = nil,
        handoff: RowHandoff? = nil,
        done: Bool = false
    ) -> TodayRow {
        let chore = Chore(
            id: "c-1", title: "Scoop litter", cadence: .daily,
            fixedAssignee: pinned, category: .catCare, together: together
        )
        let kind: TodayRow.Kind = done
            ? .done(completionId: "done-1")
            : .due(DueItem(
                chore: chore, person: .anne, periodIndex: 1,
                periodStart: day, periodLastDay: day, daysOverdue: daysOverdue
            ))
        return TodayRow(chore: chore, person: .anne, kind: kind, handoff: handoff)
    }

    func testDueTodayWithNothingElseIsAnEmptyLine() {
        XCTAssertEqual(ChoreRowMeta.elements(for: row()), [])
    }

    func testTheCapIsTwoAndTheOrderIsLateNoteChip() {
        let r = row(daysOverdue: 3, pinned: .anne, handoff: .waiting(on: .wes, id: "h-1", canWithdraw: true))
        XCTAssertEqual(
            ChoreRowMeta.elements(for: r),
            [.daysLate(3), .handoffNote(Strings.Handoffs.waiting("Wes"))],
            "the name chip is the third urgency, so it falls off"
        )
    }

    func testTheNoteBeatsTheChipButLosesToTheLateCount() {
        let r = row(daysOverdue: 1, together: true, handoff: .declined(by: .wes))
        XCTAssertEqual(
            ChoreRowMeta.elements(for: r),
            [.daysLate(1), .handoffNote(Strings.Handoffs.saidNo("Wes"))]
        )
    }

    func testTheChipSlotIsTogetherThenTheGiverThenThePin() {
        XCTAssertEqual(ChoreRowMeta.elements(for: row(together: true)), [.together])
        XCTAssertEqual(
            ChoreRowMeta.elements(for: row(pinned: .wes, handoff: .takenFrom(.wes))),
            [.taken(.wes)],
            "the giver's chip says what the pin would, so the pin never reaches the line"
        )
        XCTAssertEqual(ChoreRowMeta.elements(for: row(pinned: .anne)), [.pinned(.anne)])
    }

    func testASettledHandoffIsTheGiversChipNotFromText() {
        let r = row(daysOverdue: 5, handoff: .takenFrom(.wes))
        XCTAssertEqual(ChoreRowMeta.elements(for: r), [.daysLate(5), .taken(.wes)])
    }

    func testADoneRowKeepsItsChipButHasNoLateCount() {
        XCTAssertEqual(ChoreRowMeta.elements(for: row(pinned: .anne, done: true)), [.pinned(.anne)])
    }

    func testARefusedOfferStillGetsItsNote() {
        let r = row(daysOverdue: 2, handoff: .refused(to: .wes))
        XCTAssertEqual(
            ChoreRowMeta.elements(for: r),
            [.daysLate(2), .handoffNote(Strings.Handoffs.refused)]
        )
    }
}
