// Remote notifications, end to end on the phone's side.
//
// What the server sends is in the Push section of `server/README.md`: a "Roost" alert when the other person
// finishes something, a red alert with `apns-collapse-id: red-<choreId>` from three days late, and the
// handoff pushes. None of it carries data the app needs — the payload is for the reader, and the store
// catches up through the ordinary `GET /sync`. So every arriving push does the same two things: kick a sync,
// and (on a tap) put the reader on the Tasks tab where the answer will be.
//
// Registration is the other half. `registerIfAuthorized()` runs at launch and on every foreground; iOS
// answers with a device token through the app delegate; `PushRegistration` decides whether the server
// already has it. Failures are not retried on a timer — the next foreground re-registers.
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PushService {
    /// The app delegate is created by UIKit, not by us, so it cannot be handed a reference. It reaches the
    /// live service through here. Set once, by `SyncCoordinator.init`.
    nonisolated(unsafe) weak static var current: PushService?

    private let sender: any PushSender
    private let memory: any PushTokenMemory
    private let registrar: any RemoteNotificationRegistrar

    /// Bumped every time a push should put the reader on the Tasks tab. `RootTabView` watches it rather
    /// than a `Bool`, so two taps in a row both land even if the reader had already wandered off.
    private(set) var openTasksRequests = 0
    /// When the last push arrived, foreground or tapped. Only used for the widget's freshness and for tests.
    private(set) var lastPushAt: Date?
    /// The token the server has acknowledged in this launch, for Settings and for tests. Never logged.
    private(set) var registeredToken: String?

    /// Set by `SyncCoordinator` to `syncSoon()`. Weakly captured there, so this is not a retain cycle.
    var onPushArrived: (() -> Void)?

    private var registering = false
    private let now: () -> Date

    init(
        sender: any PushSender,
        memory: any PushTokenMemory = DefaultsPushTokenMemory(),
        registrar: any RemoteNotificationRegistrar = SystemRemoteNotifications(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.sender = sender
        self.memory = memory
        self.registrar = registrar
        self.now = now
        registeredToken = memory.lastRegistered
    }

    // MARK: - registration

    /// Ask iOS for a token, but only once the reader has allowed notifications. Called at launch and on
    /// every foreground: APNs can rotate a token at any time and the only way to hear about it is to ask.
    func registerIfAuthorized() async {
        guard await registrar.isAuthorized() else { return }
        registrar.registerForRemoteNotifications()
    }

    /// The onboarding step just got a "yes" from the system prompt. No need to check the status again.
    func registerAfterGrant() {
        registrar.registerForRemoteNotifications()
    }

    /// iOS handed over a device token (`didRegisterForRemoteNotificationsWithDeviceToken`). Hex-encode it
    /// and send it, unless the server already has exactly this one.
    @discardableResult
    func deviceTokenArrived(_ data: Data) async -> PushRegistration.Decision {
        await deviceTokenArrived(PushToken.hex(data))
    }

    @discardableResult
    func deviceTokenArrived(_ token: String) async -> PushRegistration.Decision {
        let decision = PushRegistration.decide(token: token, lastRegistered: memory.lastRegistered)
        switch decision {
        case .alreadyRegistered:
            registeredToken = token
        case .malformed:
            print("Roost: ignoring a device token that is not 64 hex characters")
        case let .send(token):
            await send(token)
        }
        return decision
    }

    /// One in-flight registration at a time. Two foregrounds in a second should not be two POSTs.
    private func send(_ token: String) async {
        guard !registering else { return }
        registering = true
        defer { registering = false }
        switch await sender.registerPushToken(token) {
        case .sent:
            memory.remember(token)
            registeredToken = token
        case .unpaired:
            // Nothing to tell yet. Pairing does not re-ask iOS for a token, but the next foreground does.
            break
        case let .failed(reason):
            // Nothing is remembered, so the next foreground tries again with the same token.
            print("Roost: could not register for push (\(reason))")
        }
    }

    // MARK: - unpairing

    /// Tell the server to drop this phone's token, then forget it locally. Best effort, and it has to run
    /// **before** the bearer is cleared — afterwards there is nothing to authenticate the DELETE with.
    ///
    /// Forgetting locally is what makes an unpair-then-pair re-register: the token iOS hands over next is
    /// the same one, and without this it would look already-registered to a server that no longer has it.
    func unregisterBeforeUnpair() async {
        defer {
            memory.forget()
            registeredToken = nil
        }
        guard let token = memory.lastRegistered else { return }
        if case let .failed(reason) = await sender.unregisterPushToken(token) {
            print("Roost: could not unregister for push (\(reason))")
        }
    }

    // MARK: - arriving pushes

    /// A push landed while the app was in front. The banner is shown by the notification delegate; this is
    /// the part that goes and gets what the push was about.
    func pushArrivedInForeground() {
        lastPushAt = now()
        onPushArrived?()
    }

    /// The reader tapped a push from the background or from the lock screen. Same sync, plus the Tasks tab:
    /// every push Roost sends is about a chore, and that is where chores are.
    func pushTapped() {
        lastPushAt = now()
        openTasksRequests += 1
        onPushArrived?()
    }
}
