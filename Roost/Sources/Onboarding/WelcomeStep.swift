// Screen one: what this is, in one sentence, and the two people it is for.
//
// The two chips are the whole illustration. They are the mockup's avatar language (Anne green, Wes blue) and
// they say "this app has exactly two people in it" without a line of copy claiming anything.
import RoostCore
import RoostDesign
import SwiftUI

struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        OnboardingPage(
            eyebrow: Strings.Onboarding.welcomeEyebrow,
            title: Strings.Onboarding.welcomeTitle,
            line: Strings.Onboarding.welcomeLine
        ) {
            // Side by side while they fit; stacked at the text sizes where they would not, because a chip
            // that breaks "Wes" across two lines is worse than two chips on two lines.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: RoostSpacing.md) { chips }
                VStack(alignment: .leading, spacing: RoostSpacing.sm) { chips }
            }
            .padding(.top, RoostSpacing.sm)
        } footer: {
            OnboardingActionButton(Strings.Onboarding.welcomeAction, action: onContinue)
        }
    }

    private var chips: some View {
        ForEach(Person.allCases, id: \.self) { person in
            PersonChip(person: person)
        }
    }
}

private struct PersonChip: View {
    let person: Person

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: RoostSpacing.sm) {
            // The initial is the name again, in a circle — decoration, and the first thing to go, the same
            // rule the chore rows follow for their category badge. It goes at accessibility sizes because a
            // `Circle` background takes the smaller side of the text's box, so a letter that is taller than
            // it is wide grows out of its own circle.
            if !typeSize.isAccessibilitySize {
                Text(person.initial)
                    .roostType(.headline)
                    .foregroundStyle(person.design.color)
                    .frame(minWidth: RoostSpacing.xl, minHeight: RoostSpacing.xl)
                    .background(person.design.softColor, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(person.displayName)
                .roostType(.rowTitle)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                // No `lineLimit(1)`: it was here to stop "Wes" breaking in two, but a line limit is also
                // what stopped `ViewThatFits` above from ever choosing the stacked layout — a truncating
                // HStack always "fits" — so the chips squeezed instead of stacking, and the name was
                // clipped at the text sizes the stack exists for. Letting the word measure itself is what
                // makes the fallback fire.
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, RoostSpacing.sm)
        .padding(.horizontal, RoostSpacing.md)
        .background(RoostColor.Role.surface.color, in: RoostRadius.pillShape)
        .roostElevation(.card, cornerRadius: RoostRadius.pill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(person.displayName)
    }
}
