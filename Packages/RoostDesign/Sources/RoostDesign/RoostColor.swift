// Roost household palette: navy and slate, teal actions, mint Anne, pink Wes.
// Light appearance uses pale slate surfaces and darker accessible accents.
import SwiftUI
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// One token: a light hex and a dark hex, plus an alpha (only `shadow` is translucent).
public struct RoostColorToken: Sendable, Hashable {
    public let name: String
    public let light: UInt32
    public let dark: UInt32
    public let lightAlpha: Double
    public let darkAlpha: Double

    public init(_ name: String, light: UInt32, dark: UInt32, lightAlpha: Double = 1, darkAlpha: Double = 1) {
        self.name = name
        self.light = light
        self.dark = dark
        self.lightAlpha = lightAlpha
        self.darkAlpha = darkAlpha
    }

    /// Hex string for a scheme, e.g. "#F3F6F2".
    public func hex(_ scheme: ColorScheme) -> String {
        String(format: "#%06X", scheme == .dark ? dark : light)
    }

    /// Resolved RGBA components for a scheme, each 0...1.
    public func rgba(_ scheme: ColorScheme) -> (r: Double, g: Double, b: Double, a: Double) {
        let v = scheme == .dark ? dark : light
        let a = scheme == .dark ? darkAlpha : lightAlpha
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, a)
    }

    /// A SwiftUI Color that follows the current appearance.
    public var color: Color {
        #if canImport(UIKit)
            return Color(UIColor { traits in
                let c = rgba(traits.userInterfaceStyle == .dark ? .dark : .light)
                return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
            })
        #elseif canImport(AppKit)
            return Color(NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let c = rgba(isDark ? .dark : .light)
                return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
            })
        #else
            let c = rgba(.light)
            return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
        #endif
    }
}

/// Semantic palette for the approved household screens.
public enum RoostColor {
    public static let bgToken = RoostColorToken("bg", light: 0xF1F5F9, dark: 0x071323)
    public static let surfaceToken = RoostColorToken("surface", light: 0xFFFFFF, dark: 0x0E1D30)
    public static let surface2Token = RoostColorToken("surface2", light: 0xE7EEF5, dark: 0x16283D)
    public static let inkToken = RoostColorToken("ink", light: 0x102137, dark: 0xF4F7FC)
    public static let inkSoftToken = RoostColorToken("inkSoft", light: 0x506680, dark: 0x91AACC)
    public static let lineToken = RoostColorToken("line", light: 0xC5D2E1, dark: 0x2C4663)
    public static let accentToken = RoostColorToken("accent", light: 0x00776F, dark: 0x00DDD3)
    public static let accentSoftToken = RoostColorToken("accentSoft", light: 0xD5F3EE, dark: 0x103B40)
    public static let goldToken = RoostColorToken("gold", light: 0x916000, dark: 0xFFC247)
    public static let goldSoftToken = RoostColorToken("goldSoft", light: 0xFFF0D1, dark: 0x392E1C)
    public static let infoToken = RoostColorToken("info", light: 0x42648D, dark: 0x91B4E0)
    public static let infoSoftToken = RoostColorToken("infoSoft", light: 0xE4EDF8, dark: 0x1A304C)
    public static let teaseToken = RoostColorToken("tease", light: 0x925700, dark: 0xFFB746)
    public static let teaseSoftToken = RoostColorToken("teaseSoft", light: 0xFFF0D1, dark: 0x392E1C)
    public static let alertToken = RoostColorToken("alert", light: 0xA45100, dark: 0xFFA24B)
    public static let alertSoftToken = RoostColorToken("alertSoft", light: 0xFFF0D1, dark: 0x392E1C)
    public static let mealToken = RoostColorToken("meal", light: 0x935327, dark: 0xF2AB77)
    public static let mealSoftToken = RoostColorToken("mealSoft", light: 0xFBEBDD, dark: 0x382C27)
    public static let assignToken = RoostColorToken("assign", light: 0x7250A4, dark: 0xC2ACE9)
    public static let assignSoftToken = RoostColorToken("assignSoft", light: 0xEEE7F7, dark: 0x2F2945)
    // Person identity stays independent from action and status colors.
    public static let anneToken = RoostColorToken("anne", light: 0x16765D, dark: 0xA0ECD5)
    public static let anneSoftToken = RoostColorToken("anneSoft", light: 0xD6F3E9, dark: 0x153B36)
    public static let wesToken = RoostColorToken("wes", light: 0xA42E66, dark: 0xF3A0C1)
    public static let wesSoftToken = RoostColorToken("wesSoft", light: 0xFBE2EE, dark: 0x41233A)
    public static let nudgeToken = RoostColorToken("nudge", light: 0x886000, dark: 0xFFD06A)
    public static let nudgeSoftToken = RoostColorToken("nudgeSoft", light: 0xFFF0D1, dark: 0x392E1C)
    /// rgba(31,42,34,0.14) light, rgba(0,0,0,0.45) dark
    public static let shadowToken = RoostColorToken(
        "shadow",
        light: 0x1F2A22,
        dark: 0x000000,
        lightAlpha: 0.14,
        darkAlpha: 0.45
    )

    public static var bg: Color {
        bgToken.color
    }

    public static var surface: Color {
        surfaceToken.color
    }

    public static var surface2: Color {
        surface2Token.color
    }

    public static var ink: Color {
        inkToken.color
    }

    public static var inkSoft: Color {
        inkSoftToken.color
    }

    public static var line: Color {
        lineToken.color
    }

    public static var accent: Color {
        accentToken.color
    }

    public static var accentSoft: Color {
        accentSoftToken.color
    }

    public static var gold: Color {
        goldToken.color
    }

    public static var goldSoft: Color {
        goldSoftToken.color
    }

    public static var info: Color {
        infoToken.color
    }

    public static var infoSoft: Color {
        infoSoftToken.color
    }

    public static var tease: Color {
        teaseToken.color
    }

    public static var teaseSoft: Color {
        teaseSoftToken.color
    }

    public static var alert: Color {
        alertToken.color
    }

    public static var alertSoft: Color {
        alertSoftToken.color
    }

    public static var meal: Color {
        mealToken.color
    }

    public static var mealSoft: Color {
        mealSoftToken.color
    }

    public static var assign: Color {
        assignToken.color
    }

    public static var assignSoft: Color {
        assignSoftToken.color
    }

    public static var anne: Color {
        anneToken.color
    }

    public static var anneSoft: Color {
        anneSoftToken.color
    }

    public static var wes: Color {
        wesToken.color
    }

    public static var wesSoft: Color {
        wesSoftToken.color
    }

    public static var nudge: Color {
        nudgeToken.color
    }

    public static var nudgeSoft: Color {
        nudgeSoftToken.color
    }

    public static var shadow: Color {
        shadowToken.color
    }

    /// Every token, in the order the mockup declares them. Used by the swatchbook and tests.
    public static let all: [RoostColorToken] = [
        bgToken, surfaceToken, surface2Token, inkToken, inkSoftToken, lineToken,
        accentToken, accentSoftToken, goldToken, goldSoftToken, infoToken, infoSoftToken,
        teaseToken, teaseSoftToken, alertToken, alertSoftToken, mealToken, mealSoftToken,
        assignToken, assignSoftToken, anneToken, anneSoftToken, wesToken, wesSoftToken,
        nudgeToken, nudgeSoftToken, shadowToken,
    ]

    /// Semantic pairs the mockup uses together: a strong color and its soft background.
    public static let pairs: [(strong: RoostColorToken, soft: RoostColorToken)] = [
        (accentToken, accentSoftToken), (goldToken, goldSoftToken), (infoToken, infoSoftToken),
        (teaseToken, teaseSoftToken), (alertToken, alertSoftToken), (mealToken, mealSoftToken),
        (assignToken, assignSoftToken), (anneToken, anneSoftToken), (wesToken, wesSoftToken),
        (nudgeToken, nudgeSoftToken),
    ]

    /// The marketing page's light palette (`:root`), for the ten tokens `.app-shell` overrides.
    /// Retained for historical marketing content. Not used by app screens.
    public enum Page {
        public static let accentToken = RoostColorToken("page.accent", light: 0x2F6F5E, dark: 0x6FC2A6)
        public static let accentSoftToken = RoostColorToken("page.accentSoft", light: 0xDCEBE3, dark: 0x1E362E)
        public static let goldToken = RoostColorToken("page.gold", light: 0xB9812E, dark: 0xD9A754)
        public static let goldSoftToken = RoostColorToken("page.goldSoft", light: 0xF3E4C9, dark: 0x3A2D15)
        public static let infoToken = RoostColorToken("page.info", light: 0x3E6B8A, dark: 0x7FB3D9)
        public static let infoSoftToken = RoostColorToken("page.infoSoft", light: 0xDCE7EE, dark: 0x1E2E3A)
        public static let teaseToken = RoostColorToken("page.tease", light: 0xAE4568, dark: 0xE389A8)
        public static let teaseSoftToken = RoostColorToken("page.teaseSoft", light: 0xF4DEE6, dark: 0x3A2129)
        public static let alertToken = RoostColorToken("page.alert", light: 0xC81E3A, dark: 0xFF6478)
        public static let alertSoftToken = RoostColorToken("page.alertSoft", light: 0xFBDCE1, dark: 0x3D1620)

        public static var accent: Color {
            accentToken.color
        }

        public static var accentSoft: Color {
            accentSoftToken.color
        }

        public static var gold: Color {
            goldToken.color
        }

        public static var goldSoft: Color {
            goldSoftToken.color
        }

        public static var info: Color {
            infoToken.color
        }

        public static var infoSoft: Color {
            infoSoftToken.color
        }

        public static var tease: Color {
            teaseToken.color
        }

        public static var teaseSoft: Color {
            teaseSoftToken.color
        }

        public static var alert: Color {
            alertToken.color
        }

        public static var alertSoft: Color {
            alertSoftToken.color
        }

        public static let all: [RoostColorToken] = [
            accentToken, accentSoftToken, goldToken, goldSoftToken, infoToken, infoSoftToken,
            teaseToken, teaseSoftToken, alertToken, alertSoftToken,
        ]
    }
}
