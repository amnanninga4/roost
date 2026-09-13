// The only UIKit in the app, and the reason it is here: the two APNs callbacks and the notification-center
// delegate have no SwiftUI equivalent. `@UIApplicationDelegateAdaptor` in `RoostApp` installs it.
//
// It holds no state and makes no decisions. Everything it hears is handed to `PushService.current`, which
// `SyncCoordinator` owns — so an arriving push goes through the same sync the rest of the app uses, and a
// build with no service wired (a test host, a preview) is simply quiet.
import Foundation
import UIKit
import UserNotifications

final class RoostAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set here rather than in `RoostApp.init`: iOS delivers a tap that launched the app as soon as a
        // delegate exists, and a delegate set later would miss it.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - APNs

    func application(
        _: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            await PushService.current?.deviceTokenArrived(deviceToken)
        }
    }

    func application(
        _: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Normal on a simulator with no Apple ID signed in, and on a build whose provisioning has no push
        // capability. Nothing to do about it here, and nothing the reader can fix.
        print("Roost: APNs registration failed (\(error.localizedDescription))")
    }
}

// MARK: - arriving notifications

extension RoostAppDelegate: UNUserNotificationCenterDelegate {
    /// A notification arrived while Roost was in front. Without a delegate iOS drops it silently, which is
    /// the wrong answer for a red alert the other phone just raised: show the banner, and sync, because the
    /// push is a hint that the store is behind.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        PushService.current?.pushArrivedInForeground()
        return [.banner, .sound, .badge]
    }

    /// The reader tapped one. Land on the Tasks tab and sync.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse
    ) async {
        PushService.current?.pushTapped()
    }
}
