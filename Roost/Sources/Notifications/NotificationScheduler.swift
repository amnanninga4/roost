// Reads the store, asks RoostCore what the paired person owes, and rewrites the pending local notifications.
//
// replan() runs after every successful sync (SyncCoordinator) and whenever the app becomes active
// (launch and foreground, observed here so no screen has to remember to call it). Overlapping calls
// coalesce into at most one extra pass, the same way SyncClient does it.
//
// Horizon: today and tomorrow. Tomorrow's set assumes nothing else gets done; the next replan replaces it.
// Without tomorrow, a phone opened after 18:00 would never get an overdue ping.
import Foundation
import SwiftData
import UserNotifications
import UIKit
import RoostCore

@MainActor
final class NotificationScheduler {
    static let authorizationOptions: UNAuthorizationOptions = [.alert, .sound, .badge]

    private let container: ModelContainer
    private let center: NotificationCenterClient
    private let now: () -> Date
    private let horizonDays: Int
    private let calendar = HouseholdCalendar()
    private var inFlight = false
    private var rerunRequested = false
    private var foregroundObserver: (any NSObjectProtocol)?

    /// `observesForeground` is off in tests so the host app's lifecycle cannot trigger a replan mid-test.
    init(container: ModelContainer,
         center: NotificationCenterClient = SystemNotificationCenter(),
         now: @escaping () -> Date = { Date() },
         horizonDays: Int = 2,
         observesForeground: Bool = true) {
        self.container = container
        self.center = center
        self.now = now
        self.horizonDays = max(1, horizonDays)
        if observesForeground {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in await self?.replan() }
            }
        }
    }

    /// Called once pairing succeeds (never on first launch): ask for permission, then plan.
    func enableAfterPairing() async {
        do {
            let granted = try await center.requestAuthorization(options: Self.authorizationOptions)
            if !granted { print("Roost: notifications not granted") }
        } catch {
            print("Roost: notification authorization failed (\(error))")
        }
        await replan()
    }

    /// Clears every pending Roost notification and schedules the current plan. Unpaired phones get nothing.
    func replan() async {
        if inFlight {
            rerunRequested = true
            return
        }
        inFlight = true
        defer { inFlight = false }
        await runOnce()
        while rerunRequested {
            rerunRequested = false
            await runOnce()
        }
    }

    private func runOnce() async {
        let (planned, badge) = (try? currentPlan()) ?? ([], 0)
        center.removeAllPendingRequests()
        for item in planned {
            do {
                try await center.add(NotificationPlanner.request(for: item, calendar: calendar))
            } catch {
                print("Roost: could not schedule \(item.id) (\(error))")
            }
        }
        do {
            try await center.setBadgeCount(badge)
        } catch {
            print("Roost: could not set badge (\(error))")
        }
    }

    /// Today's plus tomorrow's notifications for the paired person, and today's overdue count.
    private func currentPlan() throws -> ([PlannedNotification], Int) {
        let context = ModelContext(container)
        guard let state = try context.fetch(FetchDescriptor<SyncState>()).first,
              let person = state.person.flatMap(Person.init(rawValue:)) else { return ([], 0) }

        let chores = try context.fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)]
        )).compactMap { try? $0.toChore() }
        let completions = try context.fetch(FetchDescriptor<CompletionRecord>(
            predicate: #Predicate { !$0.removed }
        )).compactMap { try? $0.toCompletion() }

        let now = self.now()
        let activeFrom = state.activeFrom ?? calendar.startOfDay(now)
        let scheduler = Scheduler(chores: chores, activeFrom: activeFrom, calendar: calendar)

        var planned: [PlannedNotification] = []
        var badge = 0
        for offset in 0..<horizonDays {
            let day = calendar.adding(days: offset, to: now)
            let due = scheduler.due(on: day, completions: completions)
            planned += NotificationPlanner.plan(due: due, for: person, on: day, now: now, calendar: calendar)
            if offset == 0 { badge = NotificationPlanner.badgeCount(due: due, for: person) }
        }
        return (planned, badge)
    }
}
