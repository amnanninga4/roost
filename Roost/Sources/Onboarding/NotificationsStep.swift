// Screen four: say what the reminders are before iOS asks whether to allow them.
//
// The system prompt appears once per install and there is no second chance at it, so it goes behind a screen
// that names the two things Roost will actually send: the morning list and the evening nudge. "Not now"
// leaves without asking, which keeps that one chance unspent.
import RoostDesign
import SwiftUI

struct NotificationsStep: View {
    let onFinished: () -> Void

    @Environment(SyncCoordinator.self) private var sync
    @State private var asking = false

    var body: some View {
        OnboardingPage(
            eyebrow: Strings.Onboarding.notificationsEyebrow,
            title: Strings.Onboarding.notificationsTitle,
            line: Strings.Onboarding.notificationsLine
        ) {
            Label {
                Text(Strings.Onboarding.notificationsFootnote)
                    .roostType(.footnote)
            } icon: {
                Image(systemName: "bell.badge")
            }
            .foregroundStyle(RoostColor.Role.textSecondary.color)
            .padding(.top, RoostSpacing.sm)
        } footer: {
            VStack(spacing: RoostSpacing.sm) {
                OnboardingActionButton(Strings.Onboarding.notificationsAction, isWorking: asking) {
                    Task { await ask() }
                }
                Button(Strings.Onboarding.notificationsSkip, action: onFinished)
                    .roostType(.callout)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .buttonStyle(RoostTextActionStyle(alignment: .center))
                    .disabled(asking)
            }
        }
    }

    private func ask() async {
        asking = true
        await sync.askForNotifications()
        asking = false
        onFinished()
    }
}
