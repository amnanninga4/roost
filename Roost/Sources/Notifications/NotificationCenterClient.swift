// The slice of UNUserNotificationCenter that Roost uses, behind a protocol so tests can use a fake.
// Local notifications only. Cross-person pushes (APNs) are ticket R-6b.
import Foundation
import UserNotifications

@MainActor
protocol NotificationCenterClient: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func removeAllPendingRequests()
    func add(_ request: UNNotificationRequest) async throws
    func setBadgeCount(_ count: Int) async throws
}

/// The real thing.
final class SystemNotificationCenter: NotificationCenterClient {
    private let center = UNUserNotificationCenter.current()

    nonisolated init() {}

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await center.requestAuthorization(options: options)
    }

    func removeAllPendingRequests() {
        center.removeAllPendingNotificationRequests()
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func setBadgeCount(_ count: Int) async throws {
        try await center.setBadgeCount(count)
    }
}
