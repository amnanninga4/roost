// The day's one celebration: the moment you check off the last thing you owed today.
//
// Nothing else in the app uses confetti, and this fires at most once a day (see TodayBoard.Celebration),
// which is the whole reason it is allowed to be loud. It is deliberately short — the burst is over in
// under a second — and under Reduce Motion there is no confetti at all: a checkmark scales in instead.
// The haptic is the screen's, so the cannon's own is off.
import ConfettiSwiftUI
import RoostDesign
import SwiftUI

struct CelebrationView: View {
    /// Bumped once per celebration by the screen. A change is the trigger.
    @Binding var trigger: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markShown = false

    // Confetti physics, not design tokens. ConfettiSwiftUI derives its timing from these:
    // radius / 1300 for the explosion, (rainHeight + radius) / 200 for the fall, so 130 and 30 put the
    // whole thing at about 0.9 s. Twenty pieces is a flick of colour, not a parade.
    private let pieces = 20
    private let burstRadius: CGFloat = 130
    private let fallHeight: CGFloat = 30
    private let pieceSize: CGFloat = 8
    /// How long the Reduce Motion checkmark stays up.
    private let markSeconds: Double = 0.9

    var body: some View {
        Group {
            if reduceMotion {
                mark
            } else {
                Color.clear
                    .confettiCannon(
                        trigger: $trigger,
                        num: pieces,
                        colors: [
                            RoostColor.Role.accent.color,
                            RoostColor.Role.bonus.color,
                            RoostColor.Role.notice.color,
                            RoostColor.Role.warning.color,
                        ],
                        confettiSize: pieceSize,
                        rainHeight: fallHeight,
                        radius: burstRadius,
                        hapticFeedback: false
                    )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            guard reduceMotion else { return }
            showMark()
        }
    }

    private var mark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(RoostType.displayLarge)
            .foregroundStyle(RoostColor.Role.success.color)
            .padding(RoostSpacing.xl)
            .background(RoostColor.Role.surface.color, in: Circle())
            .roostElevation(.floating)
            .scaleEffect(markShown ? 1 : 0.7)
            .opacity(markShown ? 1 : 0)
            .roostAnimation(.bouncyCelebration, value: markShown)
    }

    private func showMark() {
        markShown = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(markSeconds))
            markShown = false
        }
    }
}
