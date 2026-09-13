// D-5: the file the widget reads.
//
// Two things are worth pinning. The **ranking**, because the widget's promise is that it agrees with the
// Tasks tab: `SnapshotBuilder.top` is `TodayBoard.ordered` cut to three, so the fixture here puts one row
// at every escalation stage at once and checks the three that survive are the three loudest. And the
// **encoding**, because the app and the widget are separate binaries that only ever meet through this JSON:
// a field renamed on one side and not the other is a blank widget, not a compile error.
@testable import Roost
import RoostCore
import SwiftData
import XCTest

final class SnapshotTests: XCTestCase {
    private let cal = HouseholdCalendar()

    // MARK: - fixture

    /// Everything daily and pinned so assignment is fixed. Read on Sep 7 against the completions below,
    /// Anne has one row at every stage plus one already checked off today.
    private let chores: [Chore] = [
        Chore(id: "late-six", title: "Clean the oven", cadence: .daily, fixedAssignee: .anne, category: .chore),
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

    private func completion(_ choreId: String, day: Int, person: Person = .anne) -> Completion {
        Completion(
            id: "c-\(choreId)", choreId: choreId, person: person,
            completedAt: cal.date(year: 2026, month: 9, day: day, hour: 9)
        )
    }

    private func plan() -> TodayPlan {
        TodayPlanner.plan(
            chores: chores,
            completions: [
                completion("late-five", day: 1), // -> 5 days late, alert
                completion("late-three", day: 3), // -> 3 days late, pointed
                completion("late-one", day: 5), // -> 1 day late, nudge
                completion("due-today", day: 6), // -> due today
                completion("done-today", day: 7), // today: a done row
            ],
            asOf: today,
            activeFrom: activeFrom,
            calendar: cal
        )
    }

    private func snapshot(me: Person? = .anne) -> RoostSnapshot {
        SnapshotBuilder.snapshot(from: plan(), me: me, generatedAt: today)
    }

    private func anne(_ snapshot: RoostSnapshot) throws -> RoostSnapshot.Person {
        try XCTUnwrap(snapshot.people.first { $0.id == "anne" })
    }

    // MARK: - the ranking

    /// Loudest first, cut to three: the two alert rows, then the pointed one. The nudge and the merely-due
    /// rows do not make the widget, which is the point of three.
    func testTheTopThreeAreTheLoudestThree() throws {
        let top = try anne(snapshot()).top
        XCTAssertEqual(top.count, SnapshotBuilder.topCount)
        XCTAssertEqual(top.map(\.stage), [.alert, .alert, .pointed])
        XCTAssertEqual(top.map(\.title), ["Clean the oven", "Mop floors", "Wipe tables"])
    }

    /// Inside one stage the planner's order stands — cat care first, then most days late — so the widget
    /// and the Tasks tab can never disagree about which of two five-day rows is first.
    func testInsideOneStageTheRankingIsThePlannersOrder() {
        let rows = plan().rows(for: .anne)
        let boardOrder = TodayBoard.ordered(rows).filter { !$0.isDone }.prefix(3).map(\.chore.title)
        XCTAssertEqual(SnapshotBuilder.top(rows).map(\.title), Array(boardOrder))
    }

    func testARowCheckedOffTodayIsNotOnTheWidget() throws {
        let top = try anne(snapshot()).top
        XCTAssertFalse(top.contains { $0.title == "Laundry" }, "a widget is for what is left")
    }

    func testTheDaysLateRideAlongWithEachRow() throws {
        let top = try anne(snapshot()).top
        XCTAssertEqual(top.map(\.daysOverdue), [6, 5, 3])
    }

    func testAPersonWithNothingDueHasAnEmptyTop() {
        let plan = TodayPlanner.plan(
            chores: [], completions: [], asOf: today, activeFrom: activeFrom, calendar: cal
        )
        let built = SnapshotBuilder.snapshot(from: plan, me: .anne, generatedAt: today)
        XCTAssertEqual(built.people.map(\.due), [0, 0])
        XCTAssertTrue(built.people.allSatisfy(\.top.isEmpty))
    }

    func testFewerThanThreeDueRowsGivesFewerThanThreeItems() {
        let plan = TodayPlanner.plan(
            chores: [chores[4]], completions: [], asOf: today, activeFrom: activeFrom, calendar: cal
        )
        let built = SnapshotBuilder.snapshot(from: plan, me: .anne, generatedAt: today)
        XCTAssertEqual(built.people.first?.top.count, 1)
    }

    // MARK: - the counts

    func testTheCountsAreTheTasksTabsCounts() throws {
        let built = snapshot()
        let anne = try anne(built)
        XCTAssertEqual(anne.due, plan().dueCount(for: .anne))
        XCTAssertEqual(anne.due, 5, "four overdue plus one due today; the done row does not count")
        XCTAssertEqual(anne.overdue, 4, "everything past its day, whatever the stage")
        XCTAssertEqual(anne.name, "Anne")
        XCTAssertEqual(anne.streak, plan().streak[.anne])
    }

    /// Anne then Wes, always. The medium family is a comparison, and a side that moves with whose phone it
    /// is would make the two columns unreadable at a glance.
    func testPeopleComeOutAnneThenWesWhoeverThePhoneBelongsTo() {
        XCTAssertEqual(snapshot(me: .anne).people.map(\.id), ["anne", "wes"])
        XCTAssertEqual(snapshot(me: .wes).people.map(\.id), ["anne", "wes"])
    }

    func testMineAndTheirsFollowThePairedPerson() {
        let asWes = snapshot(me: .wes)
        XCTAssertEqual(asWes.mine?.id, "wes")
        XCTAssertEqual(asWes.theirs?.id, "anne")
        XCTAssertTrue(asWes.isPaired)
    }

    /// An unpaired phone still gets both people's counts — it just has no "you", which is what the small
    /// and lock-screen families need, so they show the not-paired line instead.
    func testAnUnpairedPhoneHasBothPeopleAndNoMe() {
        let built = snapshot(me: nil)
        XCTAssertNil(built.me)
        XCTAssertNil(built.mine)
        XCTAssertNil(built.theirs)
        XCTAssertFalse(built.isPaired)
        XCTAssertEqual(built.people.count, 2)
    }

    // MARK: - the encoding

    func testASnapshotSurvivesTheRoundTrip() throws {
        let built = snapshot()
        let decoded = try RoostSnapshot.decoded(from: built.encoded())
        XCTAssertEqual(decoded, built)
    }

    /// The field names are the contract between two binaries. Renaming one here is a deliberate act, and
    /// this is the test that makes it one.
    func testTheJSONKeysAreTheOnesTheWidgetReads() throws {
        let data = try snapshot().encoded()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "generatedAt", "me", "people"])
        XCTAssertEqual(object["version"] as? Int, RoostSnapshot.currentVersion)
        XCTAssertEqual(object["me"] as? String, "anne")

        let people = try XCTUnwrap(object["people"] as? [[String: Any]])
        XCTAssertEqual(try Set(XCTUnwrap(people.first).keys), ["id", "name", "due", "overdue", "streak", "top"])
        let top = try XCTUnwrap(people.first?["top"] as? [[String: Any]])
        XCTAssertEqual(try Set(XCTUnwrap(top.first).keys), ["title", "stage", "daysOverdue"])
        XCTAssertEqual(top.first?["stage"] as? String, "alert", "the stage is a name, not a number")
    }

    func testEveryStageHasAName() {
        XCTAssertEqual(RoostSnapshot.Stage(EscalationStage.dueToday), .dueToday)
        XCTAssertEqual(RoostSnapshot.Stage(EscalationStage.nudge), .nudge)
        XCTAssertEqual(RoostSnapshot.Stage(EscalationStage.pointed), .pointed)
        XCTAssertEqual(RoostSnapshot.Stage(EscalationStage.alert), .alert)
    }

    /// A stage from a newer app reads as `dueToday` rather than failing the whole snapshot: one row drawn
    /// calmly beats a blank widget.
    func testAnUnknownStageDoesNotBreakTheWholeSnapshot() throws {
        let json = """
        {"version":1,"generatedAt":"2026-09-07T18:00:00Z","me":"anne","people":[
          {"id":"anne","name":"Anne","due":1,"overdue":1,"streak":0,
           "top":[{"title":"Something new","stage":"inferno","daysOverdue":9}]}]}
        """
        let decoded = try RoostSnapshot.decoded(from: Data(json.utf8))
        XCTAssertEqual(decoded.people.first?.top.first?.stage, .dueToday)
    }

    func testASnapshotFromANewerAppIsNotReadable() {
        let ahead = RoostSnapshot(
            generatedAt: today, me: "anne", people: [], version: RoostSnapshot.currentVersion + 1
        )
        XCTAssertFalse(ahead.isReadable)
        XCTAssertTrue(snapshot().isReadable)
    }

    // MARK: - the file

    private func tempStore() -> SnapshotStore {
        SnapshotStore(directory: URL.temporaryDirectory.appending(path: "roost-snapshot-\(UUID().uuidString)"))
    }

    func testWritingThenReadingGivesTheSameSnapshot() throws {
        let store = tempStore()
        defer { store.clear() }
        let built = snapshot()
        try store.write(built)
        XCTAssertEqual(store.read(), built)
        XCTAssertEqual(store.fileURL.lastPathComponent, "snapshot.json")
    }

    func testNoFileReadsAsNoSnapshotRatherThanAFailure() {
        XCTAssertNil(tempStore().read())
    }

    func testJunkOnDiskReadsAsNoSnapshot() throws {
        let store = tempStore()
        defer { store.clear() }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertNil(store.read())
    }

    func testASnapshotFromANewerAppReadsAsNoSnapshot() throws {
        let store = tempStore()
        defer { store.clear() }
        try store.write(RoostSnapshot(
            generatedAt: today, me: "anne", people: [], version: RoostSnapshot.currentVersion + 1
        ))
        XCTAssertNil(store.read(), "better the plain state than a widget drawing fields it does not know")
    }

    /// The App Group is a build-time grant. A test host has no entitlement, so this is nil here — and the
    /// writer has to cope with that rather than crash, which is what keeps CI's unsigned build green.
    func testTheAppGroupIsOptionalSoAnUnsignedBuildStillRuns() {
        _ = SnapshotStore.appGroup()
    }

    // MARK: - the writer, against a real store

    @MainActor
    func testTheWriterPlansFromTheStoreAndReloadsTheWidget() throws {
        let container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try ChoreSeeder.seedIfNeeded(
            into: context, from: ChoreSeeder.bundledChoresURL(bundle: Bundle(for: RoostAppMarker.self))
        )
        let state = try ChoreSeeder.syncState(in: context)
        state.person = "anne"
        state.activeFrom = activeFrom
        try context.save()

        let store = tempStore()
        defer { store.clear() }
        var reloads = 0
        let writer = SnapshotWriter(
            container: container, store: store, now: { self.today }, reload: { reloads += 1 }
        )

        let written = try XCTUnwrap(writer.write())
        XCTAssertEqual(written.me, "anne")
        XCTAssertEqual(written.generatedAt, today)
        XCTAssertEqual(written.people.count, 2)
        XCTAssertEqual(reloads, 1, "the app tells WidgetKit rather than waiting for the half hour")
        XCTAssertEqual(store.read(), written)
    }

    /// No container means no widget, not a crash: the plan is still made, nothing is written, and WidgetKit
    /// is not told there is anything new.
    @MainActor
    func testTheWriterWithNoContainerPlansAndWritesNothing() throws {
        let container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        var reloads = 0
        let writer = SnapshotWriter(
            container: container, store: nil, now: { self.today }, reload: { reloads += 1 }
        )
        XCTAssertNotNil(writer.write())
        XCTAssertEqual(reloads, 0)
    }
}
