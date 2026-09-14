@testable import Roost
import RoostCore
import RoostDesign
import XCTest

/// The Tasks tab's own rules: the card's order, the week bar's split, the escalation ladder's roles,
/// the celebration gate, and the status line.
///
/// Rows come out of `TodayPlanner` rather than being hand-built, because `DueItem` is RoostCore's to
/// make — which also means the stages under test are the real ones.
final class TodayBoardTests: XCTestCase {
    private let cal = HouseholdCalendar()

    // MARK: - Fixture

    /// Everything daily and pinned, so assignment is fixed, on a household that started Sep 1 2026.
    /// Read on Sep 7, the completions below put one chore at every stage at once.
    private let chores: [Chore] = [
        Chore(id: "never-done", title: "Clean the oven", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "late-five", title: "Mop floors", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "late-three", title: "Wipe tables", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "late-one", title: "Scoop litter", cadence: .daily, fixedAssignee: .anne, category: .catCare),
        Chore(id: "due-today", title: "Water plants", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "done-today", title: "Laundry", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "wes-chore", title: "Garbage out", cadence: .daily, fixedAssignee: .wes, category: .chore),
    ]

    private var activeFrom: Date {
        cal.startOfDay(cal.date(year: 2026, month: 9, day: 1))
    }

    private var today: Date {
        cal.date(year: 2026, month: 9, day: 7, hour: 18)
    }

    /// A completion of `choreId` on September `day`, which makes that day's period complete and moves the
    /// chore's oldest incomplete period to the day after.
    private func completion(_ choreId: String, day: Int, person: Person = .anne) -> Completion {
        Completion(id: "c-\(choreId)", choreId: choreId, person: person,
                   completedAt: cal.date(year: 2026, month: 9, day: day, hour: 9))
    }

    private func plan() -> TodayPlan {
        TodayPlanner.plan(
            chores: chores,
            completions: [
                completion("late-five", day: 1), // oldest incomplete Sep 2 -> 5 days late
                completion("late-three", day: 3), // -> Sep 4 -> 3 days late
                completion("late-one", day: 5), // -> Sep 6 -> 1 day late
                completion("due-today", day: 6), // -> Sep 7 -> due today
                completion("done-today", day: 7), // today: a done row, nothing due
            ],
            asOf: today,
            activeFrom: activeFrom,
            calendar: cal
        )
    }

    private func row(_ choreId: String, of person: Person = .anne) throws -> TodayRow {
        try XCTUnwrap(plan().rows(for: person).first { $0.chore.id == choreId }, choreId)
    }

    func testTheFixtureCoversEveryStage() throws {
        XCTAssertEqual(try row("never-done").stage, .alert)
        XCTAssertEqual(try row("never-done").daysOverdue, 6)
        XCTAssertEqual(try row("late-five").stage, .alert)
        XCTAssertEqual(try row("late-five").daysOverdue, 5)
        XCTAssertEqual(try row("late-three").stage, .pointed)
        XCTAssertEqual(try row("late-one").stage, .nudge)
        XCTAssertEqual(try row("due-today").stage, .dueToday)
        XCTAssertTrue(try row("done-today").isDone)
    }

    // MARK: - Order

    func testAlertRowsMoveToTheTop() {
        let planned = plan().rows(for: .anne)
        let ordered = TodayBoard.ordered(planned)

        XCTAssertNotEqual(planned.first?.stage, .alert, "the planner leads with cat care, not with the loudest row")
        XCTAssertEqual(ordered.prefix(2).map(\.chore.id).sorted(), ["late-five", "never-done"])
        XCTAssertTrue(ordered.prefix(2).allSatisfy { $0.stage == .alert })
        XCTAssertFalse(ordered.dropFirst(2).contains { !$0.isDone && $0.stage == .alert })
    }

    /// The whole point of the order: going down the card, the colour only ever gets calmer. A row that is
    /// merely due today never sits between two overdue ones, whatever the planner's own preference.
    func testTheDueRowsRunLoudestFirst() {
        let ordered = TodayBoard.ordered(plan().rows(for: .anne)).filter { !$0.isDone }
        let stages = ordered.map(\.stage)

        XCTAssertEqual(stages, stages.sorted(by: >), "\(stages)")
        XCTAssertEqual(stages.first, .alert)
        XCTAssertEqual(stages.last, .dueToday)
    }

    func testDoneRowsSinkToTheBottom() throws {
        let ordered = TodayBoard.ordered(plan().rows(for: .anne))
        let firstDone = ordered.firstIndex(where: \.isDone)
        XCTAssertNotNil(firstDone)
        XCTAssertTrue(try ordered[XCTUnwrap(firstDone?...)].allSatisfy(\.isDone))
    }

    /// Inside one stage nothing is re-shuffled: the planner's cat-care-first, most-days-late-next order
    /// still decides, so two rows that are equally late keep the order the rest of the app gives them.
    func testWithinOneStageThePlannersOrderStands() {
        let planned = plan().rows(for: .anne)
        let ordered = TodayBoard.ordered(planned)

        for stage in EscalationStage.allCases {
            let sameStage = { (rows: [TodayRow]) in
                rows.filter { !$0.isDone && $0.stage == stage }.map(\.chore.id)
            }
            XCTAssertEqual(sameStage(ordered), sameStage(planned), "\(stage)")
        }
    }

    func testOrderLosesNothing() {
        let planned = plan().rows(for: .anne)
        XCTAssertEqual(TodayBoard.ordered(planned).count, planned.count)
        XCTAssertEqual(Set(TodayBoard.ordered(planned).map(\.id)), Set(planned.map(\.id)))
        XCTAssertTrue(TodayBoard.ordered([]).isEmpty)
    }

    // MARK: - Week bar

    func testWeekShareSplitsTheBar() throws {
        let share = try XCTUnwrap(TodayBoard.anneShare(doneThisWeek: [.anne: 14, .wes: 11]))
        XCTAssertEqual(share, 14.0 / 25.0, accuracy: 0.0001)
        XCTAssertEqual(TodayBoard.anneShare(doneThisWeek: [.anne: 3, .wes: 0]), 1)
        XCTAssertEqual(TodayBoard.anneShare(doneThisWeek: [.wes: 3]), 0)
    }

    func testWeekShareIsNilBeforeAnybodyHasDoneAnything() {
        XCTAssertNil(TodayBoard.anneShare(doneThisWeek: [:]))
        XCTAssertNil(TodayBoard.anneShare(doneThisWeek: [.anne: 0, .wes: 0]))
    }

    // MARK: - The escalation ladder

    func testEachStageWearsItsOwnRole() {
        XCTAssertEqual(EscalationStage.dueToday.role, .textPrimary)
        XCTAssertEqual(EscalationStage.nudge.role, .nudge)
        XCTAssertEqual(EscalationStage.pointed.role, .warning)
        XCTAssertEqual(EscalationStage.alert.role, .danger)

        XCTAssertNil(EscalationStage.dueToday.fillRole, "a row that is only due today carries no colour")
        XCTAssertEqual(EscalationStage.nudge.fillRole, .nudgeSoft)
        XCTAssertEqual(EscalationStage.pointed.fillRole, .warningSoft)
        XCTAssertEqual(EscalationStage.alert.fillRole, .dangerSoft)
    }

    func testSharedWithTheOtherFromThreeDaysLate() {
        XCTAssertFalse(EscalationStage.dueToday.isSharedWithTheOther)
        XCTAssertFalse(EscalationStage.nudge.isSharedWithTheOther)
        XCTAssertTrue(EscalationStage.pointed.isSharedWithTheOther)
        XCTAssertTrue(EscalationStage.alert.isSharedWithTheOther)
    }

    func testEachPersonHasTheirOwnColour() {
        XCTAssertEqual(Person.anne.design, .anne)
        XCTAssertEqual(Person.wes.design, .wes)
        XCTAssertNotEqual(RoostPerson.anne.role, RoostPerson.wes.role)
    }

    // MARK: - Celebration

    func testTheLastCheckOffClearsTheList() throws {
        let last = try row("due-today")
        XCTAssertTrue(try TodayBoard.clearsTheList([row("done-today"), last], checking: last))
        XCTAssertFalse(try TodayBoard.clearsTheList([row("never-done"), last], checking: last),
                       "something else is still due")
        XCTAssertFalse(TodayBoard.clearsTheList(plan().rows(for: .anne), checking: last))
    }

    func testUnCheckingNeverClearsTheList() throws {
        let done = try row("done-today")
        XCTAssertFalse(TodayBoard.clearsTheList([done], checking: done))
    }

    func testCelebrationFiresOncePerDayForYourOwnColumn() throws {
        let day = cal.startOfDay(today)
        let mine = try row("due-today")
        var gate = TodayBoard.Celebration()

        XCTAssertTrue(gate.fires(when: [mine], checking: mine, as: .anne, on: day))
        XCTAssertFalse(gate.fires(when: [mine], checking: mine, as: .anne, on: day),
                       "un-checking and checking again the same day must not fire twice")

        let tomorrow = cal.startOfDay(cal.date(year: 2026, month: 9, day: 8))
        XCTAssertTrue(gate.fires(when: [mine], checking: mine, as: .anne, on: tomorrow))
        XCTAssertEqual(gate.celebratedDay, tomorrow)
    }

    func testCelebrationIgnoresTheOtherPersonAndAnUnpairedPhone() throws {
        let day = cal.startOfDay(today)
        let theirs = try row("wes-chore", of: .wes)
        var gate = TodayBoard.Celebration()

        XCTAssertFalse(gate.fires(when: [theirs], checking: theirs, as: .anne, on: day),
                       "clearing the other person's column is not your moment")
        XCTAssertFalse(gate.fires(when: [theirs], checking: theirs, as: nil, on: day),
                       "an unpaired phone has no column of its own")
        XCTAssertNil(gate.celebratedDay)
    }

    // MARK: - Status line

    /// What `SyncCoordinator.statusLine` would hand the screen. The Tasks header prints it verbatim in
    /// every ordinary state, which is what keeps it in step with the three list tabs.
    private let coordinatorLine = "Synced 28 sec. ago"

    func testUnpairedPointsAtTheGearMenu() {
        let notice = TodayBoard.notice(isPaired: false, outcome: nil, lastSyncAt: nil,
                                       statusLine: coordinatorLine, now: Date())
        XCTAssertEqual(notice, TodayBoard.Notice(tone: .notice, text: Strings.Tasks.notPaired))
        XCTAssertTrue(Strings.Tasks.notPaired.contains(Strings.Settings.title),
                      "the line has to name the gear-menu item that actually exists")
        XCTAssertTrue(Strings.Tasks.notPaired.contains(Strings.Tabs.more), "the line points at the More tab now")
        XCTAssertEqual(Strings.Tasks.notPaired, "Not paired yet · More → Settings")
        XCTAssertEqual(Strings.Sync.notPaired, "Not paired · More → Settings")

        let unpaired = TodayBoard.notice(isPaired: true, outcome: .unpaired, lastSyncAt: Date(),
                                         statusLine: coordinatorLine, now: Date())
        XCTAssertEqual(unpaired.tone, .notice)
    }

    func testAFailedSyncIsANoticeCarryingTheLastSyncedTime() {
        let now = Date()
        let never = TodayBoard.notice(isPaired: true, outcome: .failed("timed out"), lastSyncAt: nil,
                                      statusLine: coordinatorLine, now: now)
        XCTAssertEqual(never, TodayBoard.Notice(tone: .notice, text: "Not synced yet · offline, will retry"))

        let earlier = TodayBoard.notice(isPaired: true, outcome: .failed("timed out"),
                                        lastSyncAt: now.addingTimeInterval(-300),
                                        statusLine: coordinatorLine, now: now)
        XCTAssertEqual(earlier, TodayBoard.Notice(tone: .notice, text: "Synced 5 min. ago · offline, will retry"))
        XCTAssertNotEqual(earlier.text, coordinatorLine,
                          "a failed pass is the one state that does not take the coordinator's wording")
    }

    /// The point of the whole arrangement: on any ordinary state the Tasks header says exactly what the
    /// list tabs say, because it is the same string. If this stops holding, the two tabs disagree.
    func testAnOrdinarySyncPrintsTheCoordinatorsOwnLine() {
        let now = Date()
        for outcome in [SyncOutcome.synced(posted: 1, deleted: 0, received: 2), .coalesced, nil] {
            let notice = TodayBoard.notice(isPaired: true, outcome: outcome, lastSyncAt: now,
                                           statusLine: coordinatorLine, now: now)
            XCTAssertEqual(
                notice,
                TodayBoard.Notice(tone: .quiet, text: coordinatorLine),
                "\(String(describing: outcome))"
            )
        }
    }

    /// The offline line words "when" with `SyncStatusCopy`, the same helper the coordinator's own line
    /// uses, rather than reaching for a formatter of its own.
    func testTheOfflineLineWordsWhenLikeTheRestOfTheApp() {
        let now = Date()
        for seconds in [0.0, 4.0, 30.0, 300.0, 7200.0] {
            let then = now.addingTimeInterval(-seconds)
            let notice = TodayBoard.notice(isPaired: true, outcome: .failed("timed out"), lastSyncAt: then,
                                           statusLine: coordinatorLine, now: now)
            XCTAssertTrue(notice.text.hasPrefix(SyncStatusCopy.synced(at: then, now: now)), notice.text)
        }

        let never = TodayBoard.notice(isPaired: true, outcome: .failed("timed out"), lastSyncAt: nil,
                                      statusLine: coordinatorLine, now: now)
        XCTAssertTrue(never.text.hasPrefix(Strings.Sync.neverSynced), never.text)
    }


    // MARK: - Column order

    func testOwnColumnComesFirst() {
        XCTAssertEqual(TodayBoard.columnPeople(me: .wes), [.wes, .anne])
        XCTAssertEqual(TodayBoard.columnPeople(me: .anne), [.anne, .wes])
        XCTAssertEqual(TodayBoard.columnPeople(me: nil), [.anne, .wes], "unpaired keeps Anne then Wes")
    }

    // MARK: - The overdue badge

    func testDaysLateWordingIsSharedWithKitchenMode() {
        XCTAssertEqual(Strings.daysLate(1), "1 DAY LATE")
        XCTAssertEqual(Strings.daysLate(3), "3 DAYS LATE")
        XCTAssertEqual(Strings.Kitchen.daysLate(4), Strings.daysLate(4))
        XCTAssertEqual(Strings.Tasks.stateLate(1), "1 day late")
        XCTAssertEqual(Strings.Tasks.stateLate(5), "5 days late")
        XCTAssertEqual(RoostCopy.daysLate(1), Strings.daysLate(1))
        XCTAssertEqual(RoostCopy.daysLate(3), Strings.daysLate(3))
        XCTAssertEqual(WidgetStrings.late(2), Strings.daysLate(2),
                       "widget lateness uses the app wording, not a shorter dialect")
    }
}
