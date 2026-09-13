// The APNs device token, as the server wants it: 64 lowercase hex characters.
//
// iOS hands the token over as `Data`. `server/README.md` documents `POST /push/token` as taking a 64-hex
// string, and `push.js` rejects anything else with a 400, so the encoding is worth its own tested function
// rather than an inline `map` at the call site.
import Foundation

enum PushToken {
    /// Lowercase hex, two characters per byte, no separators. An empty `Data` gives an empty string.
    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// What the server will accept: exactly 64 characters, all of them lowercase hex.
    ///
    /// A device token is 32 bytes today. This is a guard against sending something the server will only
    /// answer 400 to — not a claim that Apple can never change the length.
    static func isWellFormed(_ token: String) -> Bool {
        token.count == 64 && token.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
}
