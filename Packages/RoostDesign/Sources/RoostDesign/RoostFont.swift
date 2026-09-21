import CoreText

// Native font helpers for explicitly scaled drawing. Screens use RoostType.
import SwiftUI

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

    /// Native sans display at a caller-scaled point size.
    public static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// Native sans body at a caller-scaled point size.
    public static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }

    /// Native sans with fixed-width digits for caller-scaled counts.
    public static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        Font.system(size: size, weight: weight).monospacedDigit()
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
