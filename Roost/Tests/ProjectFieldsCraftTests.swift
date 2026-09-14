// Project due-day and step-owner craft tests (tasks 9–10). Split out of ListCraftTests so
// swiftlint type_body_length stays under the limit.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

@MainActor
final class ProjectFieldsCraftTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext {
        container.mainContext
    }

    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: project due days

    func testDueDayReadsAsDueMonthDayAndKnowsWhenItHasPassed() throws {
        let cal = HouseholdCalendar()
        let us = Locale(identifier: "en_US")
        let sep10 = cal.date(year: 2026, month: 9, day: 10, hour: 9)
        XCTAssertEqual(ProjectDates.label("2026-09-20", now: sep10, locale: us, calendar: cal), "Due Sep 20")
        XCTAssertEqual(ProjectDates.label("2027-01-05", now: sep10, locale: us, calendar: cal), "Due Jan 5, 2027", "another year says so")
        XCTAssertNil(ProjectDates.label("next tuesday", now: sep10, locale: us, calendar: cal))
        XCTAssertFalse(ProjectDates.isPast("2026-09-20", now: sep10, calendar: cal))
        XCTAssertFalse(ProjectDates.isPast("2026-09-20", now: cal.date(year: 2026, month: 9, day: 20, hour: 23), calendar: cal), "the day itself is not past")
        XCTAssertTrue(ProjectDates.isPast("2026-09-20", now: cal.date(year: 2026, month: 9, day: 21, hour: 0), calendar: cal))
        XCTAssertFalse(ProjectDates.isPast("garbage", now: sep10, calendar: cal))
        XCTAssertEqual(ProjectDates.dayString(cal.date(year: 2026, month: 9, day: 20, hour: 23), calendar: cal), "2026-09-20")
        XCTAssertEqual(ProjectDates.day(from: "2026-09-20", calendar: cal), cal.startOfDay(cal.date(year: 2026, month: 9, day: 20)))
    }

    func testSettingAndClearingTheDueDayFlagsOnlyThatField() throws {
        let project = ProjectRecord(id: "p-1", title: "Garage trash", createdAt: clock, syncedAt: clock)
        context.insert(project)
        try context.save()
        try ListActions.setDueOn(project, "2026-09-20", in: context, now: clock)
        XCTAssertEqual(project.dueOn, "2026-09-20")
        XCTAssertEqual(project.pendingFields, [.dueOn])
        try ListActions.setDueOn(project, nil, in: context, now: clock)
        XCTAssertNil(project.dueOn)
        XCTAssertEqual(project.pendingFields, [.dueOn])
    }



    // MARK: step owners

    func testAddingAStepWithAnOwnerFlagsTheOwnerAndSettingItLaterFlagsOnlyThat() throws {
        let project = try XCTUnwrap(try ListActions.startProject("Garage", in: context, now: clock))
        let owned = try XCTUnwrap(try ListActions.addSubtask("Bag it", to: project, assignee: "wes", in: context, now: clock))
        XCTAssertEqual(owned.assignee, "wes")
        XCTAssertEqual(owned.pendingFields, [.assignee], "flagged, so it reaches the server whichever create carries the step")
        let plain = try XCTUnwrap(try ListActions.addSubtask("Haul it", to: project, in: context, now: clock))
        XCTAssertNil(plain.assignee)
        XCTAssertEqual(plain.pendingFields, [])
        plain.syncedAt = clock
        try ListActions.setAssignee(plain, "anne", in: context, now: clock)
        XCTAssertEqual(plain.pendingFields, [.assignee])
        try ListActions.setAssignee(plain, nil, in: context, now: clock)
        XCTAssertNil(plain.assignee)
    }

    func testUndoOfAnOwnedStepAfterTheDeleteWentOutKeepsTheOwnerAndFlagsIt() throws {
        let step = SubtaskRecord(id: "st-1", projectId: "p", title: "Bag it", sortOrder: 0, assignee: "wes",
                                 done: true, doneBy: "anne", doneAt: clock, createdAt: clock, syncedAt: clock)
        context.insert(step)
        try context.save()
        try ListActions.removeSubtask(step, in: context, now: clock)
        step.deleteSynced = true
        let copy = try ListActions.restoreSubtask(step, in: context, now: clock)
        XCTAssertEqual(copy.assignee, "wes")
        XCTAssertEqual(copy.pendingFields, [.done, .assignee])
    }
}
