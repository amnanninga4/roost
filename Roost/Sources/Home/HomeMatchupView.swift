import RoostCore
import RoostDesign
import SwiftUI

/// A compact people summary. Each profile and the household comparison have distinct buttons.
struct HomeMatchupView: View {
    let columns: [HomeSummary.Column]
    let onOpenPerson: (Person) -> Void
    let onOpenMatchup: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.md))
                : AnyLayout(HStackLayout(spacing: RoostSpacing.md))
            layout {
                ForEach(columns) { column in
                    Button { onOpenPerson(column.person) } label: {
                        HStack(spacing: RoostSpacing.md) {
                            HouseholdAvatar(person: column.person)
                            VStack(alignment: .leading, spacing: RoostSpacing.xs) {
                                HStack {
                                    Text(column.person.displayName).roostType(.headline)
                                    Image(systemName: "chevron.right").font(.caption)
                                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                                        .accessibilityHidden(true)
                                }
                                Text(Strings.Home.left(column.dueCount))
                                    .roostType(.subheadline)
                                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.roostPressQuiet)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .accessibilityHint(Strings.Home.openPerson)
                    .accessibilityIdentifier("home.open.\(column.person.rawValue)")
                }
            }
            Divider()
            let footer = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.sm))
                : AnyLayout(HStackLayout(spacing: RoostSpacing.md))
            footer {
                Text(Strings.Home.weeklySummary(
                    anne: columns.first { $0.person == .anne }?.doneThisWeek ?? 0,
                    wes: columns.first { $0.person == .wes }?.doneThisWeek ?? 0
                ))
                .roostType(.caption)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onOpenMatchup) {
                    HStack(spacing: RoostSpacing.xs) {
                        Text(Strings.Matchup.view)
                        Image(systemName: "chevron.right")
                    }
                    .roostType(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: RoostSpacing.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.roostPressQuiet)
                .foregroundStyle(RoostColor.Role.accent.color)
                .accessibilityIdentifier("home.open.matchup")
            }
        }
        .padding(RoostSpacing.cardPadding)
        .roostCard()
    }
}

/// Decorative initial; the surrounding profile button carries the complete accessible name.
struct HouseholdAvatar: View {
    let person: Person
    @ScaledMetric(relativeTo: .title2) private var diameter = RoostSpacing.xxxl
    var body: some View {
        Text(String(person.displayName.prefix(1)))
            .font(.system(.title2, weight: .bold))
            .foregroundStyle(RoostColor.Role.onAccent.color)
            .frame(width: diameter, height: diameter)
            .background(person.design.color, in: Circle())
            .accessibilityHidden(true)
    }
}

struct HomeChoreRow: View {
    let row: TodayRow
    let date: Date
    let onToggle: () -> Void

    private var timing: String {
        if row.daysOverdue > 0 {
            return Strings.Home.daysLate(row.daysOverdue)
        }
        if HomeRowBuckets.bucket(for: row, calendar: HouseholdCalendar(), on: date) == .later {
            return WindowCopy.line(row.chore) ?? Strings.Home.ifYouHaveTime
        }
        return Strings.Home.today
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: RoostSpacing.md) {
                if row.chore.together {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .frame(width: RoostSpacing.xxl, height: RoostSpacing.xxl)
                        .accessibilityLabel(Strings.Tasks.togetherValue)
                } else {
                    RoostAvatar(person: row.person.design, label: Strings.Tasks.forPerson(row.person.displayName))
                }
                VStack(alignment: .leading, spacing: RoostSpacing.xs) {
                    Text(row.chore.title)
                        .roostType(.headline)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(timing)
                        .roostType(.caption)
                        .foregroundStyle(row.daysOverdue > 0
                            ? RoostColor.Role.warning.color : RoostColor.Role.textSecondary.color)
                }
                Spacer(minLength: RoostSpacing.sm)
                Image(systemName: "circle")
                    .font(.title2)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, RoostSpacing.md)
            .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.roostPressQuiet)
        .accessibilityHint(Strings.Tasks.hintCheck)
        .accessibilityIdentifier("home.chore.\(row.chore.id)")
    }
}
