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

    var body: some View {
        HStack(spacing: RoostSpacing.sm) {
            Text(person.initial)
                .roostType(.headline)
                .foregroundStyle(person.design.color)
                .frame(minWidth: RoostSpacing.xl, minHeight: RoostSpacing.xl)
                .background(person.design.softColor, in: Circle())
            Text(person.displayName)
                .roostType(.rowTitle)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .lineLimit(1)
        }
        .padding(.vertical, RoostSpacing.sm)
        .padding(.horizontal, RoostSpacing.md)
        .background(RoostColor.Role.surface.color, in: RoostRadius.pillShape)
        .roostElevation(.card, cornerRadius: RoostRadius.pill)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(person.displayName)
    }
}
