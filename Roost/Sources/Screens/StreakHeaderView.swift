// The head-to-head block at the top of the Tasks tab: two streak cards with VS between them, the leader
// tagged, and the week's completions as one two-colour bar under the numbers.
//
// Three details worth knowing. The AHEAD pill is always laid out and only faded in, so taking the lead
// never nudges the layout. Every digit rolls with `.numericText()` and the whole block moves on one
// animation, so the bar, the numbers, and the tag read as one thing changing rather than three widgets.
// At accessibility text sizes the two cards stack, because side by side they would be two narrow columns
// of wrapped words.
import RoostCore
import RoostDesign
import SwiftUI

struct StreakHeaderView: View {
    let model: StreakHeaderModel

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .footnote) private var barHeight = RoostSpacing.sm

    private var stacked: Bool {
        typeSize.isAccessibilitySize
    }

    /// Anne's half of the week's completions; nil until one of them has done something.
    private var anneShare: Double? {
        TodayBoard.anneShare(doneThisWeek: Dictionary(
            uniqueKeysWithValues: model.sides.map { ($0.person, $0.doneThisWeek) }
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            sides
            week
        }
        .roostAnimation(.standard, value: model)
    }

    // MARK: - The two cards

    private var sides: some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: RoostSpacing.sm))
        return layout {
            ForEach(model.sides.enumerated(), id: \.element.person) { index, side in
                if index > 0 {
                    Text(Strings.Streak.versus)
                        .roostType(.monoLabel)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .accessibilityHidden(true)
                }
                sideCard(side)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func sideCard(_ side: StreakHeaderModel.Side) -> some View {
        let leading = model.isLeading(side.person)
        return VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
            Text(side.person.displayName)
                .roostType(.rowTitle)
                .foregroundStyle(leading ? RoostColor.Role.accent.color : RoostColor.Role.textSecondary.color)
            Text("\(side.streak)")
                .roostType(.display)
                .monospacedDigit()
                .foregroundStyle(leading ? RoostColor.Role.bonus.color : RoostColor.Role.textPrimary.color)
                .contentTransition(.numericText(value: Double(side.streak)))
            Text(Strings.Streak.dayStreak)
                .roostType(.caption)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            // Side by side the pill is always laid out and only faded in, so taking the lead does not
            // shove the two cards around. Stacked, at accessibility sizes, an invisible pill would be a
            // whole empty line of 40-pt type, so the loser's card simply does without it.
            if leading || !stacked {
                Text(Strings.Streak.ahead)
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.accent.color)
                    .padding(.horizontal, RoostSpacing.sm)
                    .padding(.vertical, RoostSpacing.xxs)
                    .background(RoostColor.Role.surface.color, in: RoostRadius.shape(RoostRadius.sm))
                    .padding(.top, RoostSpacing.xs)
                    .opacity(leading ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(RoostSpacing.md)
        .background(
            leading ? RoostColor.Role.accentSoft.color : RoostColor.Role.surfaceElevated.color,
            in: RoostRadius.shape(RoostRadius.xl)
        )
        .overlay(
            RoostRadius.shape(RoostRadius.xl)
                .stroke(leading ? RoostColor.Role.accent.color : RoostColor.Role.separator.color, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(side.person.displayName)
        .accessibilityValue(streakValue(side, leading: leading))
    }

    private func streakValue(_ side: StreakHeaderModel.Side, leading: Bool) -> String {
        let streak = "\(side.streak) \(Strings.Streak.dayStreak)"
        return leading ? "\(streak), \(Strings.Streak.ahead.lowercased())" : streak
    }

    // MARK: - The week

    private var week: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            Text(Strings.Streak.weekLabel)
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            bar
            tally
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Strings.Streak.weekLabel.capitalized)
        .accessibilityValue(model.tallyLine)
    }

    private var bar: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if let anneShare {
                    RoostColor.Role.anne.color
                        .frame(width: geometry.size.width * anneShare)
                    RoostColor.Role.wes.color
                } else {
                    // Nothing done yet: an empty track rather than a 50/50 split of nothing.
                    RoostColor.Role.separator.color
                }
            }
        }
        .frame(height: barHeight)
        .clipShape(RoostRadius.pillShape)
    }

    /// One count at each end of the bar, under its own half of it — or one per line at accessibility
    /// sizes, where two mono counts side by side would wrap "Anne ·" onto two lines.
    private var tally: some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.xs))
            : AnyLayout(HStackLayout(spacing: RoostSpacing.sm))
        return layout {
            ForEach(model.sides.enumerated(), id: \.element.person) { index, side in
                HStack(spacing: 0) {
                    Text(side.person.displayName + Strings.Streak.tallySeparator)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                    Text("\(side.doneThisWeek)")
                        .foregroundStyle(side.person.design.color)
                        .contentTransition(.numericText(value: Double(side.doneThisWeek)))
                }
                .roostType(.monoTally)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: stacked || index == 0 ? .leading : .trailing)
            }
        }
    }
}

#Preview("Anne ahead") {
    StreakHeaderView(model: StreakHeaderModel(streak: [.anne: 9, .wes: 6], doneThisWeek: [.anne: 14, .wes: 11]))
        .padding(RoostSpacing.screenMargin)
        .background(RoostColor.Role.background.color)
}

#Preview("Tied, nothing done") {
    StreakHeaderView(model: StreakHeaderModel(streak: [.anne: 0, .wes: 0], doneThisWeek: [:]))
        .padding(RoostSpacing.screenMargin)
        .background(RoostColor.Role.background.color)
}

#Preview("Dark") {
    StreakHeaderView(model: StreakHeaderModel(streak: [.anne: 3, .wes: 7], doneThisWeek: [.anne: 5, .wes: 9]))
        .padding(RoostSpacing.screenMargin)
        .background(RoostColor.Role.background.color)
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    StreakHeaderView(model: StreakHeaderModel(streak: [.anne: 9, .wes: 6], doneThisWeek: [.anne: 14, .wes: 11]))
        .padding(RoostSpacing.screenMargin)
        .background(RoostColor.Role.background.color)
        .environment(\.dynamicTypeSize, .accessibility5)
}
