// The press vocabulary, as one button style: scale to 0.97 and opacity to 0.85 on touch-down with
// the `quick` spring, back on release, and `RoostHaptic.press` on touch-down only. The README has
// specified this press since the motion work; every hand-rolled copy of it in the app is deleted in
// favour of this one.
//
// The haptic is tied to `isPressed`, not to the tap's outcome: a press is felt when the finger
// lands, whatever the button later does. Rows whose tap already carries its own haptic — a check-off
// fires `.checkOff` on the same touch — use `.roostPressQuiet`, because two haptics for one finger
// is one too many.
//
// Under Reduce Motion the `quick` spring is already an instant change, so the press simply happens;
// the haptic is untouched (haptics are not motion).
import SwiftUI

public struct RoostButtonStyle: ButtonStyle {
    /// How far a view gives under a finger. Three percent is enough to register and no more.
    public static let pressedScale: CGFloat = 0.97
    public static let pressedOpacity: Double = 0.85

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// False on a row whose tap already feels like something (a check-off's `.checkOff`).
    public let firesHaptic: Bool

    public init(haptic: Bool = true) {
        firesHaptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .opacity(configuration.isPressed ? Self.pressedOpacity : 1)
            .animation(
                RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .sensoryFeedback(
                RoostHaptic.press.feedback,
                trigger: configuration.isPressed,
                condition: { [firesHaptic] _, now in firesHaptic && now }
            )
    }
}

public extension ButtonStyle where Self == RoostButtonStyle {
    /// The press: scale, opacity, and the touch-down haptic.
    static var roostPress: RoostButtonStyle {
        RoostButtonStyle()
    }

    /// The press without the haptic, for a row whose tap already carries one.
    static var roostPressQuiet: RoostButtonStyle {
        RoostButtonStyle(haptic: false)
    }
}
