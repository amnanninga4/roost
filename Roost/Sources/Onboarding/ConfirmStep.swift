// Screen three: the server said who this phone belongs to, so say it back.
//
// This screen exists because the person is not a choice — it comes from the code Wes minted — and a phone
// that quietly decides you are Wes is a phone that puts the laundry on the wrong person for a week. The
// name is in that person's colour, which is the same green or blue their rows carry everywhere else.
import RoostCore
import RoostDesign
import SwiftUI

struct ConfirmStep: View {
    let person: Person
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Flipped once, after the screen is on-screen, so the check has something to bounce about. Left alone
    /// under Reduce Motion, which is the same as not animating.
    @State private var arrived = false

    var body: some View {
        OnboardingPage(
            eyebrow: Strings.Onboarding.confirmEyebrow,
            title: Strings.Onboarding.youAre(person.displayName),
            line: Strings.Onboarding.confirmLine
        ) {
            HStack(spacing: RoostSpacing.md) {
                Text(person.initial)
                    .roostType(.display)
                    .foregroundStyle(person.design.color)
                    .frame(minWidth: RoostSpacing.xxl, minHeight: RoostSpacing.xxl)
                    .padding(RoostSpacing.md)
                    .background(person.design.softColor, in: Circle())
                Image(systemName: "checkmark.circle.fill")
                    .font(RoostType.title)
                    .foregroundStyle(RoostColor.Role.success.color)
                    .symbolEffect(.bounce, options: .nonRepeating, value: arrived)
            }
            .padding(.top, RoostSpacing.sm)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(person.displayName)
            .task {
                guard !reduceMotion else { return }
                arrived = true
            }
        } footer: {
            OnboardingActionButton(Strings.Onboarding.confirmAction, action: onContinue)
        }
    }
}
