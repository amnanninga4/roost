// First run, four screens: what this is, the code, who you are, reminders.
//
// The flow owns the whole sequence, including the part after pairing has already succeeded. That is the
// reason it exists as a container: the token lands on the second screen, but the tabs must not appear until
// the notification question has been asked, or the one shot at the system prompt is spent behind a tab bar.
import RoostCore
import RoostDesign
import SwiftUI

struct OnboardingFlow: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step: Step = .welcome
    @State private var person: Person?

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, code, confirm, notifications

        var id: Int {
            rawValue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(step: step.rawValue, total: Step.allCases.count)
                .padding(.top, RoostSpacing.md)
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RoostColor.Role.background.color)
        .roostAnimation(.gentle, value: step)
        .roostHaptic(.selection, trigger: step)
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            WelcomeStep { step = .code }
                .transition(pageTransition)
        case .code:
            CodeStep(service: sync) { paired in
                person = paired
                step = .confirm
            }
            .transition(pageTransition)
        case .confirm:
            // The person always exists here: `.confirm` is only reachable through `onPaired`. If it somehow
            // is not, the notification screen is a better place to land than a blank one.
            ConfirmStep(person: person ?? .anne) { step = .notifications }
                .transition(pageTransition)
        case .notifications:
            NotificationsStep { sync.finishOnboarding() }
                .transition(pageTransition)
        }
    }

    /// Forward through a sequence, so the screens slide the way the steps read. Reduce Motion gets the
    /// cross-fade that `RoostMotion` would give any of its springs.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}
