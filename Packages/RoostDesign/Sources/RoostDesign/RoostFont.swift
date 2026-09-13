// Roost type: Fraunces for display, Nunito Sans for body, IBM Plex Mono for labels.
// Custom fonts are used when registered (see RoostFonts.register()); otherwise system fallbacks
// that match the mockup's CSS fallback stacks (Georgia / system sans / system mono).
import SwiftUI
import CoreText

public enum RoostFont {
    /// PostScript family names as they appear in the bundled files.
    public enum Family {
        public static let display = "Fraunces"
        public static let body = "Nunito Sans"
        public static let mono = "IBM Plex Mono"
    }

    /// True when the named family is available to CoreText in this process.
    public static func isAvailable(_ family: String) -> Bool {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return names.contains(family)
    }

    /// Fraunces. Headline sizes; falls back to a serif design when not registered.
    public static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if isAvailable(Family.display) {
            return Font.custom(Family.display, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight, design: .serif)
    }

    /// Nunito Sans. Body copy; falls back to the system sans.
    public static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if isAvailable(Family.body) {
            return Font.custom(Family.body, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight, design: .default)
    }

    /// IBM Plex Mono. Eyebrows, counts, badges; falls back to the system mono.
    public static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if isAvailable(Family.mono) {
            return Font.custom(Family.mono, size: size).weight(weight)
        }
        return Font.system(size: size, weight: weight, design: .monospaced)
    }

    /// The mockup's recurring sizes, so screens don't invent new ones.
    public enum Size {
        public static let eyebrow: CGFloat = 11.5
        public static let badge: CGFloat = 10
        public static let caption: CGFloat = 12
        public static let meta: CGFloat = 13.5
        public static let body: CGFloat = 15
        public static let sectionTitle: CGFloat = 19
        public static let title: CGFloat = 30
        public static let titleLarge: CGFloat = 38
    }
}
