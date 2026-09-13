// Roost motion: four springs, and the Reduce Motion answer for each.
//
// The app has one motion personality: quick and slightly springy for anything the finger
// caused, calm and non-bouncy for anything that changes the screen, and one loud spring
// reserved for a genuine win. Four names is the whole vocabulary — a fifth spring invented
// inside a screen is how an app starts feeling like several apps.
//
// Rules carried over from the motion work:
//   - Animate what the user did. Let data changes appear. (A sync that lands while the phone
//     is in a pocket does not need a spring.)
//   - Always scope `.animation(_, value:)` to the state that changed. A bare `.animation(_)`
//     animates everything, including the things you did not mean.
//   - Elements driven by the same number share one animation, so a tally bar, its digits, and
//     the crown badge move as one thing rather than three widgets.
//   - Entrances are slower than exits: `.standard` in, `.quick` out.
//   - Stagger a list's first appearance by 30-50 ms per row; never on every scroll.
import SwiftUI

public enum RoostMotion {
    /// What a resolved animation actually is. Used by tests and by code that needs to branch.
    public enum Kind: String, Sendable {
        /// A spring. The normal case.
        case spring
        /// A plain ease curve — the Reduce Motion substitute for a spring.
        case crossFade
        /// No animation at all: the change simply appears.
        case instant
    }

    /// The four springs.
    public enum Named: String, Sendable, CaseIterable, Identifiable {
        /// 0.18 s, no bounce. Touch feedback: press states, a toggle, a chip selecting.
        /// Short enough that the finger never waits for it.
        case quick
        /// 0.32 s, bounce 0.16. The default. Rows inserting and removing, a section expanding,
        /// a tab indicator sliding, a number rolling.
        case standard
        /// 0.45 s, no bounce. Screen-level and serious: a sheet arriving, a filter changing the
        /// whole list, anything that would look flippant with a bounce.
        case gentle
        /// 0.60 s, bounce 0.34. Reserved. A streak milestone, the week's winner, the confetti
        /// moment — and nothing else, or it stops meaning anything.
        case bouncyCelebration

        public var id: String {
            rawValue
        }

        /// Perceived time to settle, in seconds.
        public var duration: Double {
            switch self {
            case .quick: 0.18
            case .standard: 0.32
            case .gentle: 0.45
            case .bouncyCelebration: 0.60
            }
        }

        /// 0 is critically damped; 0.3+ visibly overshoots.
        public var bounce: Double {
            switch self {
            case .quick: 0
            case .standard: 0.16
            case .gentle: 0
            case .bouncyCelebration: 0.34
            }
        }

        /// Duration of the Reduce Motion substitute. Shorter than the spring: with no bounce to
        /// watch, the same duration feels slow.
        public var reducedDuration: Double {
            switch self {
            case .quick: 0.12
            case .standard: 0.18
            case .gentle: 0.22
            case .bouncyCelebration: 0.20
            }
        }

        /// What Reduce Motion turns this into. `quick` is already so short that it just happens.
        public var reducedKind: Kind {
            self == .quick ? .instant : .crossFade
        }

        public var animation: Animation {
            .spring(duration: duration, bounce: bounce)
        }

        /// The Reduce Motion equivalent: an instant change, or a cross-fade with no spring in it.
        public var reduced: Animation {
            switch reducedKind {
            case .instant: .linear(duration: 0)
            case .crossFade, .spring: .easeInOut(duration: reducedDuration)
            }
        }

        public var usage: String {
            switch self {
            case .quick: "Touch feedback: press, toggle, chip."
            case .standard: "Default: row insert/remove, expand, tab indicator, numbers."
            case .gentle: "Screen-level: sheets, whole-list changes."
            case .bouncyCelebration: "Milestones only. Streak win, confetti."
            }
        }
    }

    // MARK: Animations

    public static var quick: Animation {
        Named.quick.animation
    }

    public static var standard: Animation {
        Named.standard.animation
    }

    public static var gentle: Animation {
        Named.gentle.animation
    }

    public static var bouncyCelebration: Animation {
        Named.bouncyCelebration.animation
    }

    /// The animation to use, honouring Reduce Motion.
    ///
    ///     @Environment(\.accessibilityReduceMotion) private var reduceMotion
    ///     withAnimation(RoostMotion.reduceMotionAware(.standard, reduceMotion: reduceMotion)) {
    ///         done.insert(chore.id)
    ///     }
    public static func reduceMotionAware(_ named: Named, reduceMotion: Bool) -> Animation {
        reduceMotion ? named.reduced : named.animation
    }

    /// What `reduceMotionAware` will hand back, without building the animation. For tests and for
    /// code that needs to skip a decorative animation entirely rather than shorten it.
    public static func kind(_ named: Named, reduceMotion: Bool) -> Kind {
        reduceMotion ? named.reducedKind : .spring
    }

    /// Per-row delay when a list first appears: 40 ms each.
    public static let staggerStep: Double = 0.04
    /// The longest a stagger may run, so a long list never crawls in.
    public static let staggerCap: Double = 0.32

    /// Delay for row `index` on a list's first appearance — and only its first appearance, never
    /// on every scroll. Zero under Reduce Motion.
    public static func staggerDelay(index: Int, reduceMotion: Bool = false) -> Double {
        reduceMotion ? 0 : min(Double(index) * staggerStep, staggerCap)
    }
}

// MARK: - Transitions

/// The transitions rows use. Insert and remove are asymmetric on purpose: a row arrives from
/// where it will live and leaves smaller and faster, which reads as the list closing over it.
public enum RoostTransition: String, Sendable, CaseIterable {
    /// A chore row appearing in, or leaving, a list.
    case row
    /// A row leaving because it was checked off: it collapses rather than slides away, so the rows
    /// below rise into the gap instead of the row appearing to fly somewhere.
    case checkOff
    /// A badge, tag, or count that appears next to existing content. Scales from its own centre.
    case badge

    /// The transition, honouring Reduce Motion (which flattens all three to a fade).
    public func transition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        switch self {
        case .row:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .scale(scale: 0.96).combined(with: .opacity)
            )
        case .checkOff:
            return .asymmetric(
                insertion: .opacity,
                removal: .scale(scale: 0.94, anchor: .leading).combined(with: .opacity)
            )
        case .badge:
            return .scale(scale: 0.7).combined(with: .opacity)
        }
    }
}

private struct RoostTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let role: RoostTransition

    func body(content: Content) -> some View {
        content.transition(role.transition(reduceMotion: reduceMotion))
    }
}

private struct RoostAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let named: RoostMotion.Named
    let value: V

    func body(content: Content) -> some View {
        content.animation(RoostMotion.reduceMotionAware(named, reduceMotion: reduceMotion), value: value)
    }
}

public extension View {
    /// Applies the named transition, already Reduce Motion aware.
    ///
    ///     ForEach(rows) { RowView($0).roostTransition(.row) }
    func roostTransition(_ role: RoostTransition) -> some View {
        modifier(RoostTransitionModifier(role: role))
    }

    /// Applies one of the four springs to a specific piece of state, already Reduce Motion aware.
    /// Always scoped to `value` — there is deliberately no unscoped version.
    func roostAnimation(_ named: RoostMotion.Named, value: some Equatable) -> some View {
        modifier(RoostAnimationModifier(named: named, value: value))
    }
}
