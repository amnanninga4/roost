// What the app shows first: the tabs, or the first-run flow.
//
// The question is "is there a token in the Keychain", answered once at launch by `SyncCoordinator` — a token
// is what the server accepts, so a phone that has one has nothing left to ask. Unpairing puts the flow back.
import RoostDesign
import SwiftUI

struct RootGate: View {
    @Environment(SyncCoordinator.self) private var sync

    var body: some View {
        ZStack {
            if sync.needsOnboarding {
                OnboardingFlow()
                    .transition(.opacity)
            } else {
                RootTabView()
                    .transition(.opacity)
            }
        }
        .roostAnimation(.gentle, value: sync.needsOnboarding)
    }
}
