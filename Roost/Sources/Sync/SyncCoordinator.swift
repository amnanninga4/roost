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
        client = SyncClient(modelContainer: container)
        notifications = NotificationScheduler(container: container)
        needsOnboarding = ((try? tokenStore.read()) ?? nil) == nil
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
        return outcome
    }

    // MARK: pairing

    /// The server this phone talks to: the DEBUG launch-argument override, else whatever pairing stored,
    /// else production.
    func endpoint() async -> URL {
        await ServerEndpoint.resolved(stored: client.storedBaseURL())
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
    func askForNotifications() async {
        await notifications.enableAfterPairing()
    }

    /// Onboarding is done: show the tabs.
    func finishOnboarding() {
        needsOnboarding = false
    }

    /// Tells the server to forget this device and clears the local token. The app stays on the tabs until
    /// `returnToOnboarding()`, so Settings can explain a 403 or a failed call first.
    func unpairDevice() async -> UnpairOutcome {
        let outcome = await client.unpairDevice()
        lastOutcome = .unpaired
        lastSyncAt = nil
        await notifications.replan()
        return outcome
    }

    /// Send the app back to the first-run flow.
    func returnToOnboarding() {
        needsOnboarding = true
    }

    var statusLine: String {
        if isSyncing {
            return "Syncing…"
        }
        switch lastOutcome {
        case .none: return "Not synced yet"
        case .unpaired: return "Not paired · tap the gear"
        case .coalesced: return "Syncing…"
        case let .failed(m): return "Offline · will retry (\(m))"
        case .synced:
            if let t = lastSyncAt {
                let f = RelativeDateTimeFormatter()
                f.unitsStyle = .short
                return "Synced \(f.localizedString(for: t, relativeTo: Date()))"
            }
            return "Synced"
        }
    }
}
