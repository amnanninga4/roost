// Everyday Shopping and Meals shortcuts; all four shared lists remain in Lists.
import RoostDesign
import SwiftUI

struct HomeDoorsView: View {
    let doors: [HomeSummary.Door]
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: RoostSpacing.xs) {
            ForEach(doors.prefix(2)) { door in
                Button {
                    open(door.id)
                } label: {
                    HStack(spacing: RoostSpacing.sm) {
                        Image(systemName: door.id == "shopping" ? "cart" : "fork.knife")
                            .roostType(.title)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                        VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
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
                    }
                    .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget, alignment: .leading)
                    .padding(.vertical, RoostSpacing.xs)
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityLabel(accessibilityLabel(door))
                .accessibilityIdentifier("home.door.\(door.id)")
            }
        }
        .padding(RoostSpacing.cardPadding)
        .roostCard()
    }

    /// VoiceOver reads a door as a sentence, not as "Shopping, 3" — the count means items.
    private func accessibilityLabel(_ door: HomeSummary.Door) -> String {
        guard let count = door.count else { return door.title }
        return "\(door.title), \(count)"
    }
}
