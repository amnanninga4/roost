// Roost elevation: three shadow steps, applied as a modifier, different in dark mode.
//
// iOS does not shadow much — it uses blur and depth instead — so these are deliberately
// quiet. Two rules from the house style:
//
//   1. Never a pure black shadow. Light-mode shadows are tinted with the mockup's
//      `--shadow` (rgba(31,42,34,…)), which is the ink colour, so a card's shadow looks
//      like it belongs to the page rather than floating over it.
//   2. In dark mode a shadow has almost nothing to darken. Dark mode keeps a much smaller
//      ambient shadow and separates the surface with a 1-pt white hairline instead, which
//      is how the system's own dark surfaces read.
//
// Provenance: the mockup's card shadow is `0 18px 40px -22px var(--shadow)`; `lifted`
// carries that same 0.14 alpha.
import SwiftUI

/// One elevation step. Values are light-mode CSS-style numbers; the modifier scales them for dark.
public struct RoostElevation: Sendable, Hashable {
    public let name: String
    /// Blur radius in light mode. Dark mode uses `radius * darkScale`.
    public let radius: CGFloat
    /// Downward offset in light mode. Dark mode uses `yOffset * darkScale`.
    public let yOffset: CGFloat
    public let lightOpacity: Double
    public let darkOpacity: Double
    /// Opacity of the 1-pt white hairline drawn in dark mode, when a shape is supplied.
    public let darkHairline: Double

    /// How much of the light-mode shadow geometry survives in dark mode.
    public static let darkScale: CGFloat = 0.6

    public init(
        _ name: String,
        radius: CGFloat,
        yOffset: CGFloat,
        lightOpacity: Double,
        darkOpacity: Double,
        darkHairline: Double
    ) {
        self.name = name
        self.radius = radius
        self.yOffset = yOffset
        self.lightOpacity = lightOpacity
        self.darkOpacity = darkOpacity
        self.darkHairline = darkHairline
    }

    /// Resting cards and rows. The default: if you are unsure, this is the one.
    public static let card = RoostElevation(
        "card", radius: 8, yOffset: 3, lightOpacity: 0.10, darkOpacity: 0.28, darkHairline: 0.06
    )
    /// A card the user is holding: long-press lift, drag, popover.
    public static let lifted = RoostElevation(
        "lifted", radius: 16, yOffset: 8, lightOpacity: 0.14, darkOpacity: 0.36, darkHairline: 0.08
    )
    /// Something that floats over the content: a glass bar, a floating add button.
    public static let floating = RoostElevation(
        "floating", radius: 24, yOffset: 12, lightOpacity: 0.18, darkOpacity: 0.45, darkHairline: 0.10
    )

    public static let all: [RoostElevation] = [card, lifted, floating]

    /// The shadow colour for a scheme: ink-tinted in light, black in dark, never fully opaque.
    public func shadowColor(_ scheme: ColorScheme) -> Color {
        let rgb = RoostColor.shadowToken.rgba(scheme)
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
            .opacity(scheme == .dark ? darkOpacity : lightOpacity)
    }

    public func blurRadius(_ scheme: ColorScheme) -> CGFloat {
        scheme == .dark ? radius * Self.darkScale : radius
    }

    public func offsetY(_ scheme: ColorScheme) -> CGFloat {
        scheme == .dark ? yOffset * Self.darkScale : yOffset
    }
}

private struct RoostElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let level: RoostElevation
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        content
            .shadow(
                color: level.shadowColor(scheme),
                radius: level.blurRadius(scheme),
                x: 0,
                y: level.offsetY(scheme)
            )
            .overlay {
                if scheme == .dark, let cornerRadius {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(level.darkHairline), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

public extension View {
    /// Applies one elevation step. Pass the shape's corner radius so dark mode can draw its hairline.
    ///
    ///     card
    ///         .background(RoostColor.Role.surface.color, in: RoostRadius.cardShape)
    ///         .roostElevation(.card, cornerRadius: RoostRadius.card)
    func roostElevation(_ level: RoostElevation = .card, cornerRadius: CGFloat? = nil) -> some View {
        modifier(RoostElevationModifier(level: level, cornerRadius: cornerRadius))
    }
}
