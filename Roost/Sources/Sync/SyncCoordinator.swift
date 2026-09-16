// Main-actor face of SyncClient for the views: fire-and-forget syncs, pairing, and a little status.
import Foundation
import Observation
import RoostCore
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {
    let client: SyncClient
    let notifications: NotificationScheduler
    /// Remote notifications: the APNs token this phone registered, and where an arriving push sends it.
    let push: PushService
    /// The widget's side of the app: one JSON file in the App Group container, rewritten after every pass.
    let snapshots: SnapshotWriter
    private(set) var isSyncing = false
    private(set) var lastOutcome: SyncOutcome?
    private(set) var lastSyncAt: Date?
    /// True until the first run's onboarding is finished, and true again after an unpair.
    ///
    /// Seeded from the Keychain, not from SwiftData: a token is what the server accepts, so a phone that has
    /// one has nothing to ask for. Pairing does not clear this — the flow does, once it has also asked about
    /// notifications — so the tabs never appear mid-flow.
    private(set) var needsOnboarding: Bool

    init(container: ModelContainer, tokenStore: TokenStore = KeychainTokenStore()) {
        let client = SyncClient(modelContainer: container)
        self.client = client
        notifications = NotificationScheduler(container: container)
        push = PushService(sender: client)
        snapshots = SnapshotWriter(container: container)
        needsOnboarding = ((try? tokenStore.read()) ?? nil) == nil
        // An arriving push carries nothing the app needs — it is a hint that the store is behind. Weakly,
        // because the service is owned here.
        push.onPushArrived = { [weak self] in self?.syncSoon() }
        PushService.current = push
    }

    /// Kick a sync without waiting. Safe to call from any tap; the actor coalesces overlapping calls.
    func syncSoon() {
        Task { await syncNow() }
    }

    @discardableResult
    func syncNow() async -> SyncOutcome {
        isSyncing = true
        let outcome = await client.syncNow()
        isSyncing = false
        lastOutcome = outcome
        if case .synced = outcome {
            lastSyncAt = Date()
            await notifications.replan()
        }
        // Whatever the pass returned. The plan is local, so a check-off made with no signal still reaches
        // the Home Screen — and a failed pass is exactly when the widget's own timestamp starts mattering.
        snapshots.write()
        return outcome
    }

    // MARK: pairing

    /// The server this phone talks to: the DEBUG launch-argument override, else whatever pairing stored,
    /// else production.
    func endpoint() async -> URL {
        await ServerEndpoint.resolved(stored: client.storedBaseURL())
    }

    /// What the server says this device is (`GET /me`), for Settings. nil when this phone has nothing stored
    /// to ask with; throws what the call threw, so the screen can fall back to the name it knows locally.
    func identity() async throws -> DeviceIdentity? {
        try await client.identity()
    }

    /// The code path: six digits from `mkcode` for a real token. Notifications are asked for later, by the
    /// onboarding step that explains them.
    func pair(code: String, deviceName: String) async throws -> Person {
        let person = try await client.pair(baseURL: endpoint(), code: code, deviceName: deviceName)
        lastOutcome = nil
        lastSyncAt = nil
        syncSoon()
        return person
    }

    /// The fallback path: a token minted by hand with `mktoken.js`, validated by a real `/sync` before it is kept.
    func pair(token: String) async throws -> Person {
        let person = try await client.pair(baseURL: endpoint(), token: token)
        lastOutcome = .synced(posted: 0, deleted: 0, received: 0)
        lastSyncAt = Date()
        return person
    }

    /// Asks iOS for notification permission and plans the first set. Called by the onboarding step, so the
    /// system prompt always arrives after a screen that says what it is for.
    ///
    /// A "yes" is also the moment to ask APNs for an address: the server's red alerts and handoff pushes
    /// have nowhere to go until this phone has registered one, and registering before permission would get
    /// a token that cannot show anything.
    func askForNotifications() async {
        if await notifications.enableAfterPairing() {
            push.registerAfterGrant()
        }
    }

    /// Launch and every foreground. APNs can rotate a token at any time and asking is the only way to
    /// hear about it; `PushService` sends it on only when it is new.
    func registerForPushIfAllowed() async {
        await push.registerIfAuthorized()
    }

    /// Onboarding is done: show the tabs.
    func finishOnboarding() {
        needsOnboarding = false
    }

    /// Tells the server to forget this device and clears the local token. The app stays on the tabs until
    /// `returnToOnboarding()`, so Settings can explain a 403 or a failed call first.
    func unpairDevice() async -> UnpairOutcome {
        // First, while there is still a bearer to authenticate it with: the server cannot be told to drop
        // this phone's APNs token afterwards, and a row left behind keeps getting pushes until APNs
        // answers 410 for it. Best effort — an unreachable server does not stop the unpair.
        await push.unregisterBeforeUnpair()
        let outcome = await client.unpairDevice()
        lastOutcome = .unpaired
        lastSyncAt = nil
        await notifications.replan()
        // The widget's "not paired yet" state is a written snapshot, not a missing file.
        snapshots.write()
        return outcome
    }

    /// Send the app back to the first-run flow.
    func returnToOnboarding() {
        needsOnboarding = true
    }

    /// The line under every tab header. The wording is in `Strings.Sync`; how long ago a successful
    /// pass reads as is `SyncStatusCopy`.
    var statusLine: String {
        if isSyncing {
            return Strings.Sync.syncing
        }
        switch lastOutcome {
        case .none: return Strings.Sync.neverSynced
        case .unpaired: return Strings.Sync.notPaired
        case .coalesced: return Strings.Sync.syncing
        case let .failed(message): return Strings.Sync.offline(message)
        case .synced:
            guard let lastSyncAt else { return Strings.Sync.synced }
            return SyncStatusCopy.synced(at: lastSyncAt)
        }
    }

    /// The sync notice both Home and the board draw, from the four things it is decided by.
    ///
    /// The rule itself is `TodayBoard.notice` and stays there, with no store and no SwiftUI in it. What
    /// lives here is the wiring — three of the four inputs are this object's own, and the fourth is the
    /// pairing state. Two screens draw this line, so the wiring is written once: a second copy is how
    /// they would start disagreeing about what offline means.
    func notice(for syncStates: [SyncState], now: Date = Date()) -> TodayBoard.Notice {
        TodayBoard.notice(
            isPaired: syncStates.first?.isPaired ?? false,
            outcome: lastOutcome,
            lastSyncAt: lastSyncAt,
            // The same line the list tabs print, so no two screens disagree about the last pass.
            statusLine: statusLine,
            now: now
        )
    }
}
