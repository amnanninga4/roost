// The component rung on the swatchbook: the press style, the card, and the avatar — the pieces the
// screens build out of the tokens above. If something is in the kit and not on this page, that is a bug.
import SwiftUI

struct ComponentsSection: View {
    var body: some View {
        SwatchSection(
            "Components",
            note: "The rung above tokens: one press vocabulary, one card, one avatar."
        ) {
            VStack(alignment: .leading, spacing: RoostSpacing.md) {
                HStack(spacing: RoostSpacing.md) {
                    pressDemo("Press me", quiet: false)
                    pressDemo("Quiet press", quiet: true)
                }
                HStack(spacing: RoostSpacing.lg) {
                    ForEach(RoostPerson.allCases) { person in
                        HStack(spacing: RoostSpacing.sm) {
                            RoostAvatar(person: person)
                            Text(person.shortName)
                                .roostType(.subheadline)
                                .foregroundStyle(RoostColor.Role.textPrimary.color)
                        }
                    }
                }
                .padding(RoostSpacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .roostCard()
            }
        }
    }

    /// One pill button; the style is the demo. The pill's styling lives in the label so the press
    /// scales background and all — a background set on the Button itself would not.
    private func pressDemo(_ title: String, quiet: Bool) -> some View {
        Button {} label: {
            Text(title)
                .roostType(.headline)
                .foregroundStyle(RoostColor.Role.onAccent.color)
                .padding(.horizontal, RoostSpacing.lg)
                .frame(minHeight: RoostSpacing.minTapTarget)
                .background(RoostColor.Role.accent.color, in: RoostRadius.pillShape)
                .contentShape(RoostRadius.pillShape)
        }
        .buttonStyle(quiet ? .roostPressQuiet : .roostPress)
    }
}
