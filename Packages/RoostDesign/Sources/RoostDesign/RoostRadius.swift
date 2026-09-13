// Roost corner radii, sized for iOS 26's concentric corners.
//
// iOS 26 nests rounded shapes concentrically: a shape inset inside another keeps the same
// visual corner by *subtracting* the inset from the outer radius. So the scale below is
// spaced far enough apart that a row inset inside a card lands on a real step of the scale
// rather than a number someone invented. Always draw with `.continuous` corners — the
// system's own shapes are continuous, and a circular corner next to a continuous one is
// the kind of mismatch the eye notices without being able to name it.
//
// Provenance (roost-app-mockup.html, `.app-shell` where it overrides): tags and checkboxes
// 5-7px, rows `.item` 14px, panels `.streak-side` 18px, cards `.phone`/`.screen-card` 22px.
import SwiftUI

public enum RoostRadius {
    /// 6 — tags, badges, the check control. The mockup's 5-7 px family.
    public static let sm: CGFloat = 6
    /// 10 — small controls, chips, inline buttons.
    public static let md: CGFloat = 10
    /// 14 — list rows and anything row-shaped. The mockup's `.item`.
    public static let lg: CGFloat = 14
    /// 18 — inset panels inside a card. The mockup's `.streak-side`.
    public static let xl: CGFloat = 18
    /// 22 — cards and sheets. The mockup's phone frame.
    public static let card: CGFloat = 22
    /// A radius large enough to always resolve to a capsule. Prefer `pillShape`/`Capsule()`.
    public static let pill: CGFloat = 999

    /// The scale in order, for the swatchbook and the tests.
    public static let scale: [(name: String, value: CGFloat)] = [
        ("sm", sm), ("md", md), ("lg", lg), ("xl", xl), ("card", card), ("pill", pill),
    ]

    /// The concentric inner radius for a shape inset inside a rounded container.
    ///
    /// iOS 26's rule: inner radius = outer radius − inset. Anything smaller than `minimum`
    /// clamps, because a 1-pt corner reads as a square corner that failed.
    ///
    ///     let inner = RoostRadius.concentricInner(outer: RoostRadius.card, inset: RoostSpacing.sm)  // 14
    ///
    /// A row that sits *flush* to a card's edge is not inset, so it keeps `lg` and the card
    /// clips it; a row inset by `sm` inside a `card`-radius card lands exactly on `lg`.
    public static func concentricInner(outer: CGFloat, inset: CGFloat, minimum: CGFloat = 4) -> CGFloat {
        max(minimum, outer - inset)
    }

    /// A continuous-corner rounded rectangle, type-erased so it can be passed around and defaulted.
    public static func shape(_ radius: CGFloat) -> AnyShape {
        AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// The capsule, for pills and floating bars.
    public static var pillShape: AnyShape {
        AnyShape(Capsule())
    }

    /// The card shape, since screens ask for it constantly.
    public static var cardShape: AnyShape {
        shape(card)
    }

    /// The row shape.
    public static var rowShape: AnyShape {
        shape(lg)
    }
}
