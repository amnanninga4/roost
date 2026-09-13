// The idempotency rule, and the one thing it needs to remember.
//
// iOS calls `didRegisterForRemoteNotificationsWithDeviceToken` on every launch and on every foreground once
// the app has registered, usually with the same token. `POST /push/token` is an upsert, so sending it every
// time would be harmless but pointless: a household of two phones on a home tunnel does not need four
// needless round trips a day. So the phone remembers the token it last got an acknowledged 2xx for and
// stays quiet until something changes.
//
// Three things change it: a token Apple rotated, an unpair (the server dropped the row with the device), and
// a re-pair as somebody else. The first is visible in the token itself; the other two clear the memory,
// which is why `forget()` is called from the unpair path rather than being inferred here.
import Foundation

enum PushRegistration {
    enum Decision: Equatable {
        /// Send this token to the server.
        case send(String)
        /// The server already has exactly this token from this phone. Do nothing.
        case alreadyRegistered
        /// Not 64 hex characters, so the server would answer 400. Never sent.
        case malformed
    }

    static func decide(token: String, lastRegistered: String?) -> Decision {
        guard PushToken.isWellFormed(token) else { return .malformed }
        return token == lastRegistered ? .alreadyRegistered : .send(token)
    }
}

/// What the phone remembers between launches: the token the server acknowledged.
///
/// Not the Keychain. A device token is not a secret — it is an address APNs will only deliver to this app —
/// and it has to be readable the moment iOS hands over a token, which is before anything has unlocked.
protocol PushTokenMemory: AnyObject, Sendable {
    var lastRegistered: String? { get }
    func remember(_ token: String)
    func forget()
}

/// The real one. One key in the app's own defaults.
final class DefaultsPushTokenMemory: PushTokenMemory, @unchecked Sendable {
    private let key = "roost.push.registeredToken"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastRegistered: String? {
        defaults.string(forKey: key)
    }

    func remember(_ token: String) {
        defaults.set(token, forKey: key)
    }

    func forget() {
        defaults.removeObject(forKey: key)
    }
}

/// Test double.
final class InMemoryPushTokenMemory: PushTokenMemory, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(_ token: String? = nil) {
        self.token = token
    }

    var lastRegistered: String? {
        lock.withLock { token }
    }

    func remember(_ token: String) {
        lock.withLock { self.token = token }
    }

    func forget() {
        lock.withLock { token = nil }
    }
}
