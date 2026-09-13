// Which server this phone talks to.
//
// Production is the Cloudflare Tunnel in front of theoldone. A DEBUG build can be pointed somewhere else,
// which is how the pairing flow gets walked against a server running on the Mac:
//
//     xcrun simctl launch --console booted xyz.hinescreative.roost -roostServer http://127.0.0.1:8790
//
// A leading-dash launch argument lands in UserDefaults, so there is nothing to parse. Release builds ignore
// it entirely — the override is compiled out, not just unread.
import Foundation

enum ServerEndpoint {
    /// The public path for both phones. See `server/README.md`.
    static let production = URL(string: "https://roost.hinescreative.xyz")!

    /// `-roostServer <url>`, DEBUG only.
    static let launchArgumentName = "roostServer"

    /// The DEBUG override, when one was passed and parses as an absolute URL.
    static var override: URL? {
        #if DEBUG
            let raw = UserDefaults.standard.string(forKey: launchArgumentName)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.flatMap(absoluteURL(from:))
        #else
            return nil
        #endif
    }

    /// The override first, then what pairing stored, then production.
    static func resolved(stored: String?) -> URL {
        override ?? stored.flatMap(absoluteURL(from:)) ?? production
    }

    /// "roost.hinescreative.xyz", or "127.0.0.1:8790" when the port is not the scheme's default.
    static func display(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        guard let port = url.port else { return host }
        return "\(host):\(port)"
    }

    /// A URL only counts if it names a scheme and a host; "127.0.0.1:8790" on its own parses but is not usable.
    static func absoluteURL(from raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme != nil, url.host() != nil else { return nil }
        return url
    }
}
