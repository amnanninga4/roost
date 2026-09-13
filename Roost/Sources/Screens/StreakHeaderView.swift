// The head-to-head block from the mockup: two cards, VS between them, the leader tagged and its number in gold.
import SwiftUI
import RoostCore
import RoostDesign

struct StreakHeaderView: View {
    let model: StreakHeaderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(Array(model.sides.enumerated()), id: \.element.person) { index, side in
                    if index > 0 {
                        Text(Strings.Streak.versus)
                            .font(RoostFont.mono(size: RoostFont.Size.badge, weight: .bold))
                            .foregroundStyle(RoostColor.inkSoft)
                            .frame(width: 20)
                            .frame(maxHeight: .infinity)
                    }
                    sideCard(side)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(model.tallyLine)
                .font(RoostFont.mono(size: RoostFont.Size.caption, weight: .medium))
                .foregroundStyle(RoostColor.inkSoft)
                .accessibilityLabel("This week: \(model.tallyLine)")
        }
    }

    private func sideCard(_ side: StreakHeaderModel.Side) -> some View {
        let leading = model.isLeading(side.person)
        return VStack(alignment: .leading, spacing: 2) {
            Text(side.person.displayName)
                .font(RoostFont.display(size: RoostFont.Size.caption, weight: .semibold))
                .foregroundStyle(leading ? RoostColor.accent : RoostColor.inkSoft)
            Text("\(side.streak)")
                .font(RoostFont.mono(size: 25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(leading ? RoostColor.gold : RoostColor.ink)
            Text(Strings.Streak.dayStreak)
                .font(RoostFont.body(size: RoostFont.Size.badge))
                .foregroundStyle(RoostColor.inkSoft)
            if leading {
                Text(Strings.Streak.ahead)
                    .font(RoostFont.mono(size: 8.5, weight: .bold))
                    .kerning(0.4)
                    .foregroundStyle(RoostColor.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(RoostColor.surface, in: RoundedRectangle(cornerRadius: 5))
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(leading ? RoostColor.accentSoft : RoostColor.surface2, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(leading ? RoostColor.accent : RoostColor.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side.person.displayName), \(side.streak) \(Strings.Streak.dayStreak)\(leading ? ", currently ahead" : "")")
    }
}

#Preview("Anne ahead") {
    StreakHeaderView(model: StreakHeaderModel(streak: [.anne: 9, .wes: 6], doneThisWeek: [.anne: 14, .wes: 11]))
        .padding()
        .background(RoostColor.bg)
}

#Preview("Tied") {
    StreakHeaderView(model: StreakHeaderModel(streak: [.anne: 3, .wes: 3], doneThisWeek: [.anne: 5, .wes: 5]))
        .padding()
        .background(RoostColor.bg)
}
