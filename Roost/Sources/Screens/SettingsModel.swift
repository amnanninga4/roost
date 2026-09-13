// What Settings knows about this phone, and where it got it.
//
// Two of the rows have a fallback, which is the whole reason this type exists. The device line is the
// label the household reads in `devices.js list` — "Anne test · iPhone 17 Pro", the `mkcode` label joined
// to the name the phone sent — and that line only exists on the server, so a phone that cannot reach it
// shows its own name instead. The date below it is a date for a phone that paired with a code, a sentence
// for one set up by hand, and nothing at all until the server answers. Three outcomes, testable without a
// server.
import Foundation
import Observation
import RoostCore

/// The one call Settings makes for itself. `SyncCoordinator` is the real implementation.
@MainActor
protocol IdentityService: AnyObject {
    func identity() async throws -> DeviceIdentity?
}

@MainActor
@Observable
final class SettingsModel {
    /// The server's answer, once there is one.
    private(set) var identity: DeviceIdentity?
    private(set) var isLoading = false
    /// True after a call that failed: the screen is showing what it knows locally.
    private(set) var didFail = false

    private let service: any IdentityService
    private let localName: String
    private var load: Task<Void, Never>?

    init(service: any IdentityService, localName: String = DeviceName.current) {
        self.service = service
        self.localName = localName
    }

    /// The device line: the server's label, or this phone's own name until — or unless — the server says.
    var deviceLine: String {
        identity?.label ?? localName
    }

    /// True while that line is the local fallback rather than the server's label.
    var isLocalOnly: Bool {
        identity?.label == nil
    }

    /// The paired-since value: a date for a phone that used a code, a sentence for one from the tokens file,
    /// and nil while the server has not answered — the row is not shown at all then, because "unknown" in a
    /// settings screen reads as a fault.
    var pairedSince: String? {
        guard let identity else { return nil }
        if identity.isHandMinted {
            return Strings.Settings.pairedHandMinted
        }
        guard let at = identity.pairedAt else { return nil }
        return at.formatted(date: .abbreviated, time: .omitted)
    }

    /// The person the server has this device down as. The local copy is whatever pairing wrote; this is the
    /// one the server will act on.
    var person: Person? {
        identity?.person
    }

    /// Asks the server who this device is. A second call while the first is in flight joins it instead of
    /// starting another, so appearing and pulling at the same time is one request.
    func refresh() async {
        if let load {
            return await load.value
        }
        let task = Task { @MainActor in await run() }
        load = task
        await task.value
    }

    private func run() async {
        isLoading = true
        do {
            if let fresh = try await service.identity() {
                identity = fresh
                didFail = false
            }
        } catch {
            didFail = true
        }
        isLoading = false
        load = nil
    }
}

extension SyncCoordinator: IdentityService {}
