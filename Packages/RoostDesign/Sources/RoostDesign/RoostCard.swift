// The card, as one modifier: the surface fill, the `card` radius, and the `card` elevation together.
// Screens used to spell the three out as a `.background(Role.surface.color, in: RoostRadius.cardShape)`
// + `.roostElevation(.card, cornerRadius: RoostRadius.card)` pair; two of the three parts were always
// the same, and a screen that got one wrong was a card that did not match the others.
//
// Padding stays the caller's: a card of rows pads differently from a card of text, and iOS 26's
// concentric corners care about the inset (see RoostRadius).
import SwiftUI

private struct RoostCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoostColor.Role.surface.color, in: RoostRadius.cardShape)
            .roostElevation(.card, cornerRadius: RoostRadius.card)
    }
}

public extension View {
    /// The card surface: fill, radius and elevation as one step.
    ///
    ///     rows
    ///         .padding(RoostSpacing.sm)
    ///         .roostCard()
    func roostCard() -> some View {
        modifier(RoostCardModifier())
    }
}
