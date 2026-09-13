// Main-actor face of SyncClient for the views: fire-and-forget syncs, pairing, and a little status.
import Foundation
import SwiftData
import Observation
import RoostCore

@MainActor
@Observable
final class SyncCoordinator {
    let client: SyncClient
    let notifications: NotificationScheduler
    private(set) var isSyncing = false
    private(set) var lastOutcome: SyncOutcome?
    private(set) var lastSyncAt: Date?

    init(container: ModelContainer) {
        client = SyncClient(modelContainer: container)
        notifications = NotificationScheduler(container: container)
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

    func pair(baseURL: URL, token: String) async throws -> Person {
        let person = try await client.pair(baseURL: baseURL, token: token)
        lastOutcome = .synced(posted: 0, deleted: 0, received: 0)
        lastSyncAt = Date()
        await notifications.enableAfterPairing()
        return person
    }

    func unpair() async throws {
        try await client.unpair()
        lastOutcome = .unpaired
        await notifications.replan()
    }

    var statusLine: String {
        if isSyncing { return "Syncing…" }
        switch lastOutcome {
        case .none: return "Not synced yet"
        case .unpaired: return "Not paired · tap the gear"
        case .coalesced: return "Syncing…"
        case .failed(let m): return "Offline · will retry (\(m))"
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
