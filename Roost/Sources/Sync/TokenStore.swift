// Where the device token lives. Keychain in the app, memory in tests. Never UserDefaults, never logs.
import Foundation
import Security

protocol TokenStore: Sendable {
    func read() throws -> String?
    func write(_ token: String) throws
    func clear() throws
}

struct KeychainError: Error, CustomStringConvertible {
    let status: OSStatus
    var description: String { "keychain error \(status)" }
}

/// Generic-password item, this device only, available after first unlock so background sync can read it.
struct KeychainTokenStore: TokenStore {
    let service: String
    let account: String

    init(service: String = "xyz.hinescreative.roost", account: String = "device-token") {
        self.service = service
        self.account = account
    }

    private var base: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { throw KeychainError(status: status) }
        return String(data: data, encoding: .utf8)
    }

    func write(_ token: String) throws {
        let data = Data(token.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func clear() throws {
        let status = SecItemDelete(base as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Test double. Also handy for previews.
final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    init(_ token: String? = nil) { self.token = token }

    func read() throws -> String? { lock.withLock { token } }
    func write(_ token: String) throws { lock.withLock { self.token = token } }
    func clear() throws { lock.withLock { token = nil } }
}
