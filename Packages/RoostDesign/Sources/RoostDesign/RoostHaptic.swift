// Haptics, as five named moments.
//
// `.sensoryFeedback` is the SwiftUI-native API and the only one the app needs. The list is
// short on purpose: haptics work because they are rare. The rule is user-initiated and
// meaningful only — never on cold launch (the engine is asleep and lags), never per scrolled
// row, never to confirm something the user already watched happen.
import SwiftUI

public enum RoostHaptic: String, Sendable, CaseIterable, Identifiable {
    /// A chore is done. The app's most-felt haptic, so it is the definitive one.
    case checkOff
    /// The check came back off. Softer than the check, and clearly not a success.
    case undo
    /// The action failed — a sync that could not reach the server, a claim someone else won.
    case error
    /// A threshold was crossed: a streak milestone, the week's winner settling.
    case milestone
    /// Moving between tabs, days, or people. The lightest one.
    case selection

    public var id: String {
        rawValue
    }

    public var feedback: SensoryFeedback {
        switch self {
        case .checkOff: .success
        case .undo: .impact(flexibility: .soft)
        case .error: .error
        case .milestone: .levelChange
        case .selection: .selection
        }
    }

    public var usage: String {
        switch self {
        case .checkOff: "A chore checked off."
        case .undo: "A chore un-checked."
        case .error: "The action failed."
        case .milestone: "A streak milestone or a week decided."
        case .selection: "Tab, day, or person changed."
        }
    }
}

public extension View {
    /// Fires the haptic whenever `trigger` changes.
    ///
    ///     row.roostHaptic(.checkOff, trigger: isDone)
    ///
    /// Pair it with the visual change on the same state so the tap, the feel, and the animation
    /// are one event rather than three.
    func roostHaptic(_ haptic: RoostHaptic, trigger: some Equatable) -> some View {
        sensoryFeedback(haptic.feedback, trigger: trigger)
    }

    /// Fires a haptic only when the trigger changes to a value the closure names, so a row can
    /// feel like a success on check and an undo on uncheck without two modifiers fighting.
    ///
    ///     row.roostHaptic(trigger: isDone) { _, now in now ? .checkOff : .undo }
    func roostHaptic<T: Equatable>(
        trigger: T,
        _ haptic: @escaping (T, T) -> RoostHaptic?
    ) -> some View {
        sensoryFeedback(trigger: trigger) { old, new in haptic(old, new)?.feedback }
    }
}
