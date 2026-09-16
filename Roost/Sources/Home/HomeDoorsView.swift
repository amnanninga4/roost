// The four rooms as four words. A door is always drawn; its count only when the room holds
// something. An empty household therefore sees four quiet labels rather than four empty cards
// telling it to go and fill them in.
import RoostDesign
import SwiftUI

struct HomeDoorsView: View {
    let doors: [HomeSummary.Door]
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: RoostSpacing.xs) {
            ForEach(doors) { door in
                Button {
                    open(door.id)
                } label: {
                    VStack(spacing: RoostSpacing.xxs) {
                        Text(door.title)
                            .roostType(.rowTitle)
                            .foregroundStyle(RoostColor.Role.textPrimary.color)
                        Text(door.count.map(String.init) ?? "—")
                            .roostType(.monoTally)
                            .foregroundStyle(
                                door.count == nil
                                    ? RoostColor.Role.textSecondary.color
                                    : RoostColor.Role.accent.color
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, RoostSpacing.xs)
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityLabel(accessibilityLabel(door))
                .accessibilityIdentifier("home.door.\(door.id)")
            }
        }
    }

    /// VoiceOver reads a door as a sentence, not as "Shopping, 3" — the count means items.
    private func accessibilityLabel(_ door: HomeSummary.Door) -> String {
        guard let count = door.count else { return door.title }
        return "\(door.title), \(count)"
    }
}
