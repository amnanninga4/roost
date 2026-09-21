// Light, dark, or whatever the phone says.
//
// Every colour in `RoostDesign` has always had both values — the tokens are dynamic colours, so the app has
// drawn itself in dark mode since the first screen. What it had no way to do was disagree with the phone.
// This is that switch: one key in `UserDefaults`, read by `RoostApp` as a single `.preferredColorScheme` on
// the window's content, which is why every screen turns over at once — the Settings sheet it is set from,
// the Tasks tab behind it, and Kitchen mode's full-screen cover, all in the same frame.
//
// It is a per-device preference and it is deliberately not synced. Two phones, two people, two ideas about
// what a screen should look like at midnight; the server has nothing to say about it.
//
// The widget is the one thing it cannot reach. A widget is a separate process rendered by WidgetKit in the
// system's appearance, and nothing an app writes changes that — see `Roost/README.md`.
import SwiftUI

enum Appearance: String, CaseIterable, Identifiable, Sendable {
    /// Follow iOS when explicitly selected.
    case system
    case light
    case dark

    /// The `@AppStorage` key, spelled once so the app, the tests, and a future migration cannot disagree.
    static let storageKey = "appearance"
    static let defaultChoice: Appearance = .dark

    var id: String {
        rawValue
    }

    /// What the window is told. `nil` is "do not override", which is what following the phone means.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: Strings.Settings.appearanceSystem
        case .light: Strings.Settings.appearanceLight
        case .dark: Strings.Settings.appearanceDark
        }
    }

    /// New installs use dark. Explicit choices survive; unknown values follow the system.
    static func stored(_ raw: String?) -> Appearance {
        guard let raw else { return defaultChoice }
        return Appearance(rawValue: raw) ?? .system
    }
}
