// Liquid Glass, wrapped so screens cannot misuse it.
//
// iOS 26 rules, and the reason each wrapper is shaped the way it is:
//   1. Glass is for the floating control layer only — a bottom bar, an add button, a toolbar.
//      Cards and page backgrounds stay opaque: glass shows the content behind it, so if
//      everything is glass there is nothing to show.
//   2. Exactly one tinted glass surface per screen — the primary action. Everything else is
//      clear glass. `.primary` is the only style that carries a tint, which is why there is no
//      `tint:` parameter to pass by accident.
//   3. Tappable glass is `.interactive()`, so it picks up the system's bounce and shimmer.
//   4. Reduce Transparency means the reader asked for opaque. Both wrappers fall back to a
//      solid surface fill, not a thinner blur.
//
// Why the `#if os(iOS)`: the package's macOS floor is 26, so a macOS 26-only SwiftUI symbol
// links strongly and `swift test` (and Mac previews) cannot load on an older Mac — an
// `#available` check does not weaken that link. The `#available` inside the iOS branch is
// belt-and-braces for previews and is free.
import SwiftUI

/// How a glass surface reads. Two of them, because rule 2 above only allows two.
public struct RoostGlassStyle: Sendable, Hashable {
    public let name: String
    /// Non-nil on exactly one style: the primary action.
    public let tint: Color?
    public let isInteractive: Bool

    public init(name: String, tint: Color?, isInteractive: Bool) {
        self.name = name
        self.tint = tint
        self.isInteractive = isInteractive
    }

    /// Clear glass. Floating bars, secondary controls, anything tappable that is not *the* action.
    public static let clear = RoostGlassStyle(name: "clear", tint: nil, isInteractive: true)
    /// Accent-tinted glass. One per screen: the primary action.
    public static let primary = RoostGlassStyle(
        name: "primary",
        tint: RoostColor.Role.accent.color,
        isInteractive: true
    )
    /// Clear and inert. Chrome that is not tappable — a floating label, a status strip.
    public static let quiet = RoostGlassStyle(name: "quiet", tint: nil, isInteractive: false)

    public static let all: [RoostGlassStyle] = [clear, primary, quiet]
}

private struct RoostGlassModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let style: RoostGlassStyle
    let shape: AnyShape

    func body(content: Content) -> some View {
        if reduceTransparency {
            // The reader asked for opaque. A tinted primary keeps its soft accent so the
            // hierarchy survives; everything else becomes a plain surface.
            content.background(
                style.tint == nil ? RoostColor.Role.surface.color : RoostColor.Role.accentSoft.color,
                in: shape
            )
        } else {
            #if os(iOS)
                if #available(iOS 26, *) {
                    content.glassEffect(glass, in: shape)
                } else {
                    content.background(.thinMaterial, in: shape)
                }
            #else
                content.background(.thinMaterial, in: shape)
            #endif
        }
    }

    #if os(iOS)
        @available(iOS 26, *)
        private var glass: Glass {
            var glass = Glass.regular
            if let tint = style.tint {
                glass = glass.tint(tint)
            }
            if style.isInteractive {
                glass = glass.interactive()
            }
            return glass
        }
    #endif
}

public extension View {
    /// Puts the view on a glass surface, with a plain-material (or opaque) fallback.
    ///
    ///     HStack { … }
    ///         .padding(.horizontal, RoostSpacing.lg)
    ///         .padding(.vertical, RoostSpacing.md)
    ///         .roostGlass(.clear)
    ///         .roostElevation(.floating)
    func roostGlass(_ style: RoostGlassStyle = .clear, in shape: AnyShape = RoostRadius.pillShape) -> some View {
        modifier(RoostGlassModifier(style: style, shape: shape))
    }
}

/// Groups glass surfaces that sit near each other so they share one blur, one light direction,
/// and can merge as they move. Wrap a floating bar's buttons in this, not each button on its own.
public struct RoostGlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = RoostSpacing.sm, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        #if os(iOS)
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: spacing) { content }
            } else {
                content
            }
        #else
            content
        #endif
    }
}
