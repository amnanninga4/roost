// The card at the top of your column when the other person has asked you to take a chore.
//
// It sits above the rows rather than inside them because it is not a chore yet — it is a question, and
// answering it is the only thing on it. Two plain buttons, no swipe and no long press: this is the one
// screen in the app where a wrong tap moves work onto somebody, so the targets are large and labelled.
//
// To VoiceOver it is one element with two actions, which is how a card with two buttons should read:
// the sentence, then "Accept" and "Decline" in the actions rotor, instead of three separate stops.
import RoostCore
import RoostDesign
import SwiftUI

struct HandoffOfferCard: View {
    let offer: IncomingOffer
    let accept: () -> Void
    let decline: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var sentence: String {
        Strings.Handoffs.incoming(
            offer.from.displayName, chore: offer.chore.title, period: offer.cadence.periodPhrase
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            HStack(alignment: .top, spacing: RoostSpacing.sm) {
                Image(systemName: "arrow.left.arrow.right")
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.accent.color)
                    .padding(RoostSpacing.xs)
                    .background(RoostColor.Role.accentSoft.color, in: RoostRadius.shape(RoostRadius.sm))
                    .accessibilityHidden(true)
                Text(sentence)
                    .roostType(.headline)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            buttons
        }
        .padding(RoostSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoostColor.Role.accentSoft.color, in: RoostRadius.rowShape)
        .overlay(RoostRadius.rowShape.stroke(RoostColor.Role.accent.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
        .accessibilityAction(named: Text(Strings.Handoffs.accept), accept)
        .accessibilityAction(named: Text(Strings.Handoffs.decline), decline)
    }

    /// Side by side normally; stacked at accessibility sizes, where two words on one line leave each
    /// button about four characters wide.
    @ViewBuilder
    private var buttons: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.sm))
            : AnyLayout(HStackLayout(spacing: RoostSpacing.sm))
        layout {
            Button(Strings.Handoffs.accept, action: accept)
                .buttonStyle(OfferButtonStyle(prominent: true))
            Button(Strings.Handoffs.decline, action: decline)
                .buttonStyle(OfferButtonStyle(prominent: false))
        }
        // The whole card is one VoiceOver element with these two as actions, so the buttons themselves
        // must not also be stops in the rotor.
        .accessibilityHidden(true)
    }
}

/// The two answers: accent for taking it on, a plain outline for saying no. Both hold 44 pt and give a
/// little under a finger on the quick spring, which Reduce Motion turns into no animation at all.
private struct OfferButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // `.headline`, the same rung the onboarding buttons use: one button voice in the app. The mono
            // label rung is for eyebrows and chips, and its caps tracking makes a two-word button read as a tag.
            .roostType(.headline)
            .foregroundStyle(prominent ? RoostColor.Role.onAccent.color : RoostColor.Role.textPrimary.color)
            .padding(.horizontal, RoostSpacing.lg)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .frame(minWidth: RoostSpacing.xxxl)
            .background(
                prominent ? RoostColor.Role.accent.color : RoostColor.Role.surface.color,
                in: RoostRadius.pillShape
            )
            .overlay(
                RoostRadius.pillShape
                    .stroke(RoostColor.Role.separator.color, lineWidth: prominent ? 0 : 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(
                RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
            .contentShape(RoostRadius.pillShape)
    }
}

#Preview {
    VStack(spacing: RoostSpacing.md) {
        HandoffOfferCard(
            offer: IncomingOffer(
                id: "1",
                chore: Chore(id: "laundry", title: "Laundry", cadence: .weekly, category: .chore),
                from: .anne,
                cadence: .weekly
            ),
            accept: {},
            decline: {}
        )
    }
    .padding()
    .background(RoostColor.Role.background.color)
}
