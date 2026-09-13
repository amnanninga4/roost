// The pairing state machine, with no SwiftUI and no network in it.
//
// Everything the code screen can do goes through `input(_:)`: typing a digit, deleting one, and pasting a
// whole code are the same event, because the field underneath the boxes is one text field and that is all it
// reports. Six digits submit themselves — a "Pair" button would be a second thing to explain and a second
// thing to tap. What happens next is one of four answers from the server, and the difference between them is
// the only reason this type exists: a wrong code clears the boxes, a rate limit and a dead connection keep
// them, because the code was probably right and retyping it would be the app's fault, not the reader's.
import Foundation
import Observation
import RoostCore
#if canImport(UIKit)
    import UIKit
#endif

/// The pairing calls the code screen needs, so the screen can be tested without SwiftData, the Keychain,
/// or a server. `SyncCoordinator` is the real implementation.
@MainActor
protocol PairingService: AnyObject {
    func pair(code: String, deviceName: String) async throws -> Person
    func unpairDevice() async -> UnpairOutcome
}

/// This phone's name, as `POST /pair` wants it: 1-60 characters, or the server answers 400.
enum DeviceName {
    /// The server's `DEVICE_NAME_MAX`.
    static let maxLength = 60

    /// Trimmed, then cut to 60 characters. A name that trims to nothing falls back, because an empty
    /// `deviceName` is a 400 and "this phone" is more use in `devices.js list` than a failed pairing.
    static func trimmed(_ raw: String) -> String {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            return fallback
        }
        return String(clean.prefix(maxLength))
    }

    static let fallback = "iPhone"

    static var current: String {
        #if canImport(UIKit)
            return trimmed(UIDevice.current.name)
        #else
            return fallback
        #endif
    }
}

@MainActor
@Observable
final class PairingModel {
    /// Where the screen is. `paired` is terminal: the flow moves on.
    enum Phase: Equatable {
        case entering
        case submitting
        case paired(Person)
    }

    /// Why the last attempt failed, which decides both the wording and whether the code survives.
    enum Failure: Equatable {
        /// 404 — unknown, already used, or expired. The server will not say which.
        case invalidCode
        /// 429 — too many attempts, from this address or across all of them.
        case rateLimited
        /// 400 — the server would not read it. The field only ever sends six digits, so this means the server
        /// changed its mind about what a code is.
        case rejected
        /// No answer: offline, the tunnel is down, or the URL is wrong.
        case offline

        var text: String {
            switch self {
            case .invalidCode: Strings.Onboarding.codeInvalid
            case .rateLimited: Strings.Onboarding.codeRateLimited
            case .rejected: Strings.Onboarding.codeRejected
            case .offline: Strings.Onboarding.codeOffline
            }
        }

        /// True when the code is probably fine and the attempt is worth repeating as typed.
        var keepsCode: Bool {
            switch self {
            case .rateLimited, .offline: true
            case .invalidCode, .rejected: false
            }
        }
    }

    static let codeLength = 6

    private(set) var code = ""
    private(set) var phase: Phase = .entering
    private(set) var failure: Failure?
    /// Bumped once per rejected attempt. The boxes shake on the change; nothing else reads it.
    private(set) var rejectionCount = 0

    private let service: any PairingService
    private let deviceName: String
    private var attempt: Task<Void, Never>?

    init(service: any PairingService, deviceName: String = DeviceName.current) {
        self.service = service
        self.deviceName = DeviceName.trimmed(deviceName)
    }

    var isSubmitting: Bool {
        phase == .submitting
    }

    var isComplete: Bool {
        code.count == Self.codeLength
    }

    /// A failure the reader can act on by tapping once, rather than by retyping.
    var canRetry: Bool {
        failure?.keepsCode == true && isComplete && phase != .submitting
    }

    /// Everything the field reports: a digit, a deletion, or a paste. Non-digits are dropped, so
    /// "04 82 13" and "code: 048213" both land as 048213; anything past the sixth digit is ignored.
    func input(_ raw: String) {
        guard phase != .submitting else { return }
        let digits = String(raw.filter(\.isNumber).prefix(Self.codeLength))
        guard digits != code else { return }
        code = digits
        failure = nil
        if digits.count == Self.codeLength {
            submit()
        }
    }

    /// Starts an attempt. Synchronous on purpose: `phase` is `.submitting` before this returns, so a second
    /// digit event or a double-tapped retry cannot start a second POST.
    func submit() {
        guard isComplete, phase != .submitting else { return }
        phase = .submitting
        failure = nil
        attempt = Task { await run() }
    }

    /// Awaits the attempt in flight. The screen never needs this; the tests do.
    func settle() async {
        await attempt?.value
    }

    func unpair() async -> UnpairOutcome {
        await service.unpairDevice()
    }

    private func run() async {
        do {
            let person = try await service.pair(code: code, deviceName: deviceName)
            phase = .paired(person)
        } catch let error as SyncAPIError {
            fail(Self.failure(for: error))
        } catch {
            fail(.offline)
        }
    }

    private func fail(_ reason: Failure) {
        phase = .entering
        failure = reason
        rejectionCount += 1
        if !reason.keepsCode {
            code = ""
        }
    }

    /// The server's status codes, as the four things the screen can say. Anything unexpected reads as
    /// "couldn't reach the server", which is true enough: whatever answered was not the pairing route.
    nonisolated static func failure(for error: SyncAPIError) -> Failure {
        switch error {
        case .notFound: .invalidCode
        case .rateLimited: .rateLimited
        case .badRequest: .rejected
        case .transport, .decoding, .http, .unauthorized, .forbidden: .offline
        }
    }
}

extension SyncCoordinator: PairingService {}
