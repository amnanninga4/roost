// The slice of UIKit and UserNotifications that remote registration needs, behind a protocol so the push
// service can be tested without iOS.
//
// Deliberately separate from `NotificationCenterClient` (Notifications/): that one is about *scheduling*
// local notifications and is owned by the scheduler. This one is about asking APNs for an address. Keeping
// them apart means the local-notification tests never have to know push exists.
import Foundation
import UIKit
import UserNotifications

@MainActor
protocol RemoteNotificationRegistrar: AnyObject {
    /// Asks iOS for an APNs device token. The answer arrives later, at
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`, or not at all.
    func registerForRemoteNotifications()
    /// Whether the reader has allowed notifications. Registering without permission gets a token that
    /// cannot show anything, so Roost does not ask for one until there is a point.
    func isAuthorized() async -> Bool
}

/// The real thing.
final class SystemRemoteNotifications: RemoteNotificationRegistrar {
    nonisolated init() {}

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        @unknown default: return false
        }
    }
}
