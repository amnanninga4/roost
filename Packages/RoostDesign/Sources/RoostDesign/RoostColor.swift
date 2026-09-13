// Roost color tokens, ported 1:1 from roost-app-mockup.html (:root light block and the dark blocks).
// Each token resolves light/dark automatically through a platform dynamic color.
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
            let c = self.rgba(traits.userInterfaceStyle == .dark ? .dark : .light)
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = self.rgba(isDark ? .dark : .light)
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
        #else
        let c = rgba(.light)
        return Color(red: c.r, green: c.g, blue: c.b, opacity: c.a)
        #endif
    }
}

/// The palette. Values are the mockup's CSS custom properties, unchanged.
public enum RoostColor {
    public static let bgToken          = RoostColorToken("bg",          light: 0xF3F6F2, dark: 0x121A15)
    public static let surfaceToken     = RoostColorToken("surface",     light: 0xFFFFFF, dark: 0x1B241D)
    public static let surface2Token    = RoostColorToken("surface2",    light: 0xFBFDFA, dark: 0x212C22)
    public static let inkToken         = RoostColorToken("ink",         light: 0x1F2A22, dark: 0xEAF2EC)
    public static let inkSoftToken     = RoostColorToken("inkSoft",     light: 0x5C6C60, dark: 0x9FB3A4)
    public static let lineToken        = RoostColorToken("line",        light: 0xDCE6DA, dark: 0x2B3830)
    public static let accentToken      = RoostColorToken("accent",      light: 0x2F6F5E, dark: 0x6FC2A6)
    public static let accentSoftToken  = RoostColorToken("accentSoft",  light: 0xDCEBE3, dark: 0x1E362E)
    public static let goldToken        = RoostColorToken("gold",        light: 0xB9812E, dark: 0xD9A754)
    public static let goldSoftToken    = RoostColorToken("goldSoft",    light: 0xF3E4C9, dark: 0x3A2D15)
    public static let infoToken        = RoostColorToken("info",        light: 0x3E6B8A, dark: 0x7FB3D9)
    public static let infoSoftToken    = RoostColorToken("infoSoft",    light: 0xDCE7EE, dark: 0x1E2E3A)
    public static let teaseToken       = RoostColorToken("tease",       light: 0xAE4568, dark: 0xE389A8)
    public static let teaseSoftToken   = RoostColorToken("teaseSoft",   light: 0xF4DEE6, dark: 0x3A2129)
    public static let alertToken       = RoostColorToken("alert",       light: 0xC81E3A, dark: 0xFF6478)
    public static let alertSoftToken   = RoostColorToken("alertSoft",   light: 0xFBDCE1, dark: 0x3D1620)
    public static let mealToken        = RoostColorToken("meal",        light: 0xC2571F, dark: 0xE8935A)
    public static let mealSoftToken    = RoostColorToken("mealSoft",    light: 0xF5DCC8, dark: 0x3A2415)
    public static let assignToken      = RoostColorToken("assign",      light: 0x6B4FA0, dark: 0xB79EE0)
    public static let assignSoftToken  = RoostColorToken("assignSoft",  light: 0xE6DFF5, dark: 0x332750)
    /// rgba(31,42,34,0.14) light, rgba(0,0,0,0.45) dark
    public static let shadowToken      = RoostColorToken("shadow",      light: 0x1F2A22, dark: 0x000000, lightAlpha: 0.14, darkAlpha: 0.45)

    public static var bg: Color         { bgToken.color }
    public static var surface: Color    { surfaceToken.color }
    public static var surface2: Color   { surface2Token.color }
    public static var ink: Color        { inkToken.color }
    public static var inkSoft: Color    { inkSoftToken.color }
    public static var line: Color       { lineToken.color }
    public static var accent: Color     { accentToken.color }
    public static var accentSoft: Color { accentSoftToken.color }
    public static var gold: Color       { goldToken.color }
    public static var goldSoft: Color   { goldSoftToken.color }
    public static var info: Color       { infoToken.color }
    public static var infoSoft: Color   { infoSoftToken.color }
    public static var tease: Color      { teaseToken.color }
    public static var teaseSoft: Color  { teaseSoftToken.color }
    public static var alert: Color      { alertToken.color }
    public static var alertSoft: Color  { alertSoftToken.color }
    public static var meal: Color       { mealToken.color }
    public static var mealSoft: Color   { mealSoftToken.color }
    public static var assign: Color     { assignToken.color }
    public static var assignSoft: Color { assignSoftToken.color }
    public static var shadow: Color     { shadowToken.color }

    /// Every token, in the order the mockup declares them. Used by the swatchbook and tests.
    public static let all: [RoostColorToken] = [
        bgToken, surfaceToken, surface2Token, inkToken, inkSoftToken, lineToken,
        accentToken, accentSoftToken, goldToken, goldSoftToken, infoToken, infoSoftToken,
        teaseToken, teaseSoftToken, alertToken, alertSoftToken, mealToken, mealSoftToken,
        assignToken, assignSoftToken, shadowToken,
    ]

    /// Semantic pairs the mockup uses together: a strong color and its soft background.
    public static let pairs: [(strong: RoostColorToken, soft: RoostColorToken)] = [
        (accentToken, accentSoftToken), (goldToken, goldSoftToken), (infoToken, infoSoftToken),
        (teaseToken, teaseSoftToken), (alertToken, alertSoftToken), (mealToken, mealSoftToken),
        (assignToken, assignSoftToken),
    ]
}
