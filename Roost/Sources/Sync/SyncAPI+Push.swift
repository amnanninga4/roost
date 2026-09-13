// `POST /push/token` and `DELETE /push/token` — the two calls that put this phone's APNs address on the
// server and take it off again. See the Push section of `server/README.md`.
//
// Both carry the bearer. The server stores the token against the device the bearer names, which is why
// unregistering has to happen *before* the token is cleared on unpair: afterwards there is nothing to
// authenticate with, and the row would sit there until APNs answered 410 for it.
import Foundation

extension SyncAPI {
    /// The only platform Roost has. Spelled out because the server validates it.
    static let pushPlatform = "ios"

    /// Upserts this device's APNs token. 200 or 201; a token that is not 64 hex characters is a 400.
    func registerPushToken(_ token: String) async throws {
        let body = try JSONEncoder().encode(["token": token, "platform": Self.pushPlatform])
        let (data, status) = try await send(
            method: "POST",
            url: baseURL.appending(path: "push/token"),
            body: body
        )
        try Self.check(status, data)
    }

    /// Removes this device's APNs token. Own tokens only — the bearer decides which.
    func unregisterPushToken(_ token: String) async throws {
        let body = try JSONEncoder().encode(["token": token])
        let (data, status) = try await send(
            method: "DELETE",
            url: baseURL.appending(path: "push/token"),
            body: body
        )
        try Self.check(status, data)
    }
}
