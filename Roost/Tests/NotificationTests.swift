@testable import Roost
import RoostCore
import SwiftData
import UserNotifications
import XCTest

/// Records what the scheduler asks of the notification center. Never talks to iOS.
@MainActor
final class FakeNotificationCenter: NotificationCenterClient {
    private(set) var pending: [UNNotificationRequest] = []
    private(set) var clearCount = 0
    private(set) var badge: Int?
    private(set) var authorizationRequests: [UNAuthorizationOptions] = []
    var grant = true
    /// Slows `add` so overlapping replans can be observed.
    var addDelay: Duration?

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        authorizationRequests.append(options)
        return grant
    }

    func removeAllPendingRequests() {
        clearCount += 1
        pending.removeAll()
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let addDelay {
            try await Task.sleep(for: addDelay)
        }
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func setBadgeCount(_ count: Int) async throws {
        badge = count
    }
}

// MARK: - fixture

/// Five pinned chores so assignment is fixed: four for Anne, one for Wes. Household started Sep 1, 2026;
/// as of Sep 6 07:00 Chicago with the completions below, Anne owes one chore per escalation stage.
private enum Fixture {
    static let cal = HouseholdCalendar()
    static let activeFrom = cal.startOfDay(cal.date(year: 2026, month: 9, day: 1))
    static let morning = cal.date(year: 2026, month: 9, day: 6, hour: 7)
    static let evening = cal.date(year: 2026, month: 9, day: 6, hour: 19)

    static let chores: [Chore] = [
        Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, fixedAssignee: .anne, category: .catCare),
        Chore(
            id: "refill-cat-water",
            title: "Refill cat water",
            cadence: .daily,
            fixedAssignee: .anne,
            category: .catCare
        ),
        Chore(id: "wipe-tables", title: "Wipe down tables", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "vacuum-basement", title: "Vacuum basement", cadence: .daily, fixedAssignee: .anne, category: .chore),
        Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore),
        Chore(id: "garbage", title: "Garbage can to street", cadence: .daily, fixedAssignee: .wes, category: .chore),
    ]

    /// scoop-litter done Sep 4 → Sep 5 missed → 1 day late (nudge, cat)
    /// refill-cat-water done Sep 2 → Sep 3 missed → 3 days late (pointed, cat)
    /// wipe-tables done Sep 2 → 3 days late (pointed, home)
    /// vacuum-basement never → Sep 1 missed → 5 days late (alert)
    /// laundry: week of Aug 31–Sep 6 still open → due today
    /// garbage (Wes): never → 5 days late, but not Anne's
    static let completions: [Completion] = [
        Completion(
            id: "c1",
            choreId: "scoop-litter",
            person: .anne,
            completedAt: cal.date(year: 2026, month: 9, day: 4)
        ),
        Completion(
            id: "c2",
            choreId: "refill-cat-water",
            person: .anne,
            completedAt: cal.date(year: 2026, month: 9, day: 2)
        ),
        Completion(
            id: "c3",
            choreId: "wipe-tables",
            person: .anne,
            completedAt: cal.date(year: 2026, month: 9, day: 2)
        ),
    ]

    static func due(on date: Date = morning, completions: [Completion] = completions) -> [Person: [DueItem]] {
        Scheduler(chores: chores, activeFrom: activeFrom, calendar: cal).due(on: date, completions: completions)
    }

    static let nineAM = cal.date(year: 2026, month: 9, day: 6, hour: 9)
    static let sixPM = cal.date(year: 2026, month: 9, day: 6, hour: 18)
}

// MARK: - planner

final class NotificationPlannerTests: XCTestCase {
    func testFixturePlanProducesExpectedSet() throws {
        let planned = NotificationPlanner.plan(
            due: Fixture.due(),
            for: .anne,
            on: Fixture.morning,
            now: Fixture.morning,
            calendar: Fixture.cal
        )
        let byId = Dictionary(uniqueKeysWithValues: planned.map { ($0.id, $0) })

        XCTAssertEqual(Set(byId.keys), [
            "roost.digest.2026-09-06",
            "roost.overdue.scoop-litter.2026-09-06",
            "roost.overdue.refill-cat-water.2026-09-06",
            "roost.overdue.wipe-tables.2026-09-06",
            "roost.overdue.vacuum-basement.2026-09-06",
        ])

        let digest = try XCTUnwrap(byId["roost.digest.2026-09-06"])
        XCTAssertEqual(digest.title, "Due today")
        XCTAssertEqual(digest.fireAt, Fixture.nineAM)
        XCTAssertTrue(digest.body.hasSuffix(" and 2 more"), digest.body)
        XCTAssertTrue(digest.body.contains("Vacuum basement"), "most overdue listed first: \(digest.body)")

        XCTAssertEqual(byId["roost.overdue.scoop-litter.2026-09-06"]?.title, "Still no Scoop litter…")
        XCTAssertEqual(byId["roost.overdue.refill-cat-water.2026-09-06"]?.title, "The cat has feelings about this.")
        XCTAssertEqual(byId["roost.overdue.wipe-tables.2026-09-06"]?.title, "Getting overdue.")
        XCTAssertEqual(byId["roost.overdue.vacuum-basement.2026-09-06"]?.title, "Vacuum basement emergency")
        for id in byId.keys where id.hasPrefix("roost.overdue.") {
            XCTAssertEqual(byId[id]?.fireAt, Fixture.sixPM, id)
        }
        XCTAssertNil(byId["roost.overdue.laundry.2026-09-06"], "due today is not overdue")
    }

    func testNothingDueSkipsTheDigest() {
        let allDone = Fixture.chores.filter { $0.fixedAssignee == .anne }.enumerated().map {
            Completion(
                id: "d\($0.offset)",
                choreId: $0.element.id,
                person: .anne,
                completedAt: Fixture.cal.date(year: 2026, month: 9, day: 6, hour: 6)
            )
        }
        let planned = NotificationPlanner.plan(
            due: Fixture.due(completions: allDone),
            for: .anne,
            on: Fixture.morning,
            now: Fixture.morning,
            calendar: Fixture.cal
        )
        XCTAssertEqual(planned, [])
    }

    func testFireTimesAlreadyPassedAreDropped() {
        let planned = NotificationPlanner.plan(
            due: Fixture.due(),
            for: .anne,
            on: Fixture.morning,
            now: Fixture.evening,
            calendar: Fixture.cal
        )
        XCTAssertEqual(planned, [], "at 19:00 both today's 09:00 and 18:00 have passed")

        let noon = Fixture.cal.date(year: 2026, month: 9, day: 6, hour: 12)
        let afternoon = NotificationPlanner.plan(
            due: Fixture.due(),
            for: .anne,
            on: Fixture.morning,
            now: noon,
            calendar: Fixture.cal
        )
        XCTAssertEqual(afternoon.count, 4, "digest gone, the four 18:00 pings remain")
        XCTAssertFalse(afternoon.contains { $0.id.hasPrefix("roost.digest.") })
    }

    func testOtherPersonsChoresAreNeverIncluded() {
        let due = Fixture.due()
        XCTAssertEqual(due[.wes]?.map(\.chore.id), ["garbage"], "fixture sanity: Wes has an alert-stage chore")

        let anne = NotificationPlanner.plan(
            due: due,
            for: .anne,
            on: Fixture.morning,
            now: Fixture.morning,
            calendar: Fixture.cal
        )
        XCTAssertFalse(anne.contains { $0.id.contains("garbage") })
        XCTAssertFalse(anne.contains { $0.body.contains("Garbage") || $0.title.contains("Garbage") })

        let wes = NotificationPlanner.plan(
            due: due,
            for: .wes,
            on: Fixture.morning,
            now: Fixture.morning,
            calendar: Fixture.cal
        )
        XCTAssertEqual(Set(wes.map(\.id)), ["roost.digest.2026-09-06", "roost.overdue.garbage.2026-09-06"])
        XCTAssertEqual(wes.first { $0.id.hasPrefix("roost.overdue.") }?.title, "Garbage can to street emergency")
    }

    func testBadgeCountsOverdueForThePairedPersonOnly() {
        let due = Fixture.due()
        XCTAssertEqual(NotificationPlanner.badgeCount(due: due, for: .anne), 4)
        XCTAssertEqual(NotificationPlanner.badgeCount(due: due, for: .wes), 1)
    }

    func testRequestTriggersAtChicagoWallClock() throws {
        let planned = PlannedNotification(
            id: "roost.overdue.x.2026-09-06",
            title: "t",
            body: "b",
            fireAt: Fixture.sixPM
        )
        let request = NotificationPlanner.request(for: planned, calendar: Fixture.cal)
        XCTAssertEqual(request.identifier, "roost.overdue.x.2026-09-06")
        XCTAssertEqual(request.content.title, "t")
        XCTAssertEqual(request.content.threadIdentifier, "roost")

        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        let c = trigger.dateComponents
        XCTAssertEqual(c.timeZone?.identifier, "America/Chicago")
        XCTAssertEqual([c.year, c.month, c.day, c.hour, c.minute], [2026, 9, 6, 18, 0])
        XCTAssertEqual(Fixture.cal.calendar.date(from: c), Fixture.sixPM)
    }
}

// MARK: - scheduler

@MainActor
final class NotificationSchedulerTests: XCTestCase {
    private var container: ModelContainer!
    private var center: FakeNotificationCenter!
    private var now = Fixture.morning

    override func setUpWithError() throws {
        container = try ModelContainer(
            for: RoostSchema.schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        center = FakeNotificationCenter()
        now = Fixture.morning
        let ctx = ModelContext(container)
        try ChoreSeeder.seed(ChoreList(version: 1, chores: Fixture.chores), into: ctx)
        for c in Fixture.completions {
            ctx.insert(CompletionRecord(c, syncedAt: Date()))
        }
        try ctx.save()
    }

    private func scheduler(horizonDays: Int = 1) -> NotificationScheduler {
        NotificationScheduler(
            container: container,
            center: center,
            now: { [self] in now },
            horizonDays: horizonDays,
            observesForeground: false
        )
    }

    private func pair(as person: Person) throws {
        let ctx = ModelContext(container)
        let state = try ChoreSeeder.syncState(in: ctx)
        state.person = person.rawValue
        state.baseURL = "https://stub.local"
        state.activeFrom = Fixture.activeFrom
        try ctx.save()
    }

    func testUnpairedReplanSchedulesNothingAndZeroesBadge() async {
        await scheduler().replan()
        XCTAssertEqual(center.clearCount, 1)
        XCTAssertEqual(center.pending, [])
        XCTAssertEqual(center.badge, 0)
    }

    func testReplanSchedulesThePairedPersonsPlanAndBadge() async throws {
        try pair(as: .anne)
        await scheduler().replan()
        XCTAssertEqual(center.clearCount, 1)
        XCTAssertEqual(Set(center.pending.map(\.identifier)), [
            "roost.digest.2026-09-06",
            "roost.overdue.scoop-litter.2026-09-06",
            "roost.overdue.refill-cat-water.2026-09-06",
            "roost.overdue.wipe-tables.2026-09-06",
            "roost.overdue.vacuum-basement.2026-09-06",
        ])
        XCTAssertEqual(center.badge, 4)
        XCTAssertFalse(
            center.pending.contains { $0.identifier.contains("garbage") },
            "Wes's chore never reaches Anne's phone"
        )
    }

    /// Reminding somebody about a chore they handed away is the one thing a reminder must not do, so the
    /// plan reads the handoffs too: the row leaves Anne's set and Wes's phone picks it up.
    func testAHandedOverChoreLeavesTheOfferersReminders() async throws {
        try pair(as: .anne)
        let ctx = ModelContext(container)
        // vacuum-basement is Anne's, never done, and its oldest open daily period is Sep 1.
        let day = Fixture.cal.date(year: 2026, month: 9, day: 1, hour: 9)
        ctx.insert(HandoffRecord(
            id: "h-notify",
            choreId: "vacuum-basement",
            fromPerson: Person.anne.rawValue,
            toPerson: Person.wes.rawValue,
            periodIndex: Fixture.cal.periodIndex(.daily, containing: day),
            cadence: Cadence.daily.rawValue,
            state: Handoff.State.accepted.rawValue,
            createdAt: day,
            syncedAt: day
        ))
        try ctx.save()

        await scheduler().replan()
        XCTAssertFalse(
            center.pending.contains { $0.identifier.contains("vacuum-basement") },
            "Wes took that turn, so it is not on Anne's phone any more"
        )
        XCTAssertEqual(center.badge, 3)

        // The same store on Wes's phone: now it is his.
        try pair(as: .wes)
        center = FakeNotificationCenter()
        await scheduler().replan()
        XCTAssertTrue(center.pending.contains { $0.identifier.contains("vacuum-basement") })
    }

    func testReplanClearsThePreviousSet() async throws {
        try pair(as: .anne)
        let s = scheduler()
        await s.replan()
        XCTAssertEqual(center.pending.count, 5)

        // Anne vacuums: the alert disappears, the badge drops, nothing is duplicated.
        let ctx = ModelContext(container)
        ctx.insert(CompletionRecord(
            id: "c4",
            choreId: "vacuum-basement",
            person: "anne",
            completedAt: Fixture.cal.date(year: 2026, month: 9, day: 6, hour: 7, minute: 30)
        ))
        try ctx.save()
        await s.replan()

        XCTAssertEqual(center.clearCount, 2)
        XCTAssertEqual(center.pending.count, 4)
        XCTAssertEqual(Set(center.pending.map(\.identifier)).count, 4, "ids are unique after a replan")
        XCTAssertFalse(center.pending.contains { $0.identifier == "roost.overdue.vacuum-basement.2026-09-06" })
        XCTAssertEqual(center.badge, 3)
    }

    func testHorizonCoversTomorrow() async throws {
        try pair(as: .anne)
        await scheduler(horizonDays: 2).replan()
        let ids = Set(center.pending.map(\.identifier))
        XCTAssertTrue(ids.contains("roost.digest.2026-09-07"))
        XCTAssertTrue(
            ids.contains("roost.overdue.laundry.2026-09-07"),
            "the open week ends Sunday the 6th; Monday it is a nudge"
        )
        XCTAssertTrue(ids.contains("roost.overdue.scoop-litter.2026-09-07"))
        XCTAssertEqual(center.badge, 4, "badge is today's count, not tomorrow's")
    }

    func testEnableAfterPairingRequestsAlertSoundBadgeThenPlans() async throws {
        try pair(as: .wes)
        await scheduler().enableAfterPairing()
        XCTAssertEqual(center.authorizationRequests, [[.alert, .sound, .badge]])
        XCTAssertEqual(
            Set(center.pending.map(\.identifier)),
            ["roost.digest.2026-09-06", "roost.overdue.garbage.2026-09-06"]
        )
        XCTAssertEqual(center.badge, 1)
    }

    func testOverlappingReplansCoalesce() async throws {
        try pair(as: .anne)
        center.addDelay = .milliseconds(40)
        let s = scheduler()
        async let a: Void = s.replan()
        try await Task.sleep(for: .milliseconds(10))
        async let b: Void = s.replan()
        async let c: Void = s.replan()
        _ = await (a, b, c)
        XCTAssertEqual(center.clearCount, 2, "one pass plus exactly one rerun")
        XCTAssertEqual(center.pending.count, 5)
    }
}
