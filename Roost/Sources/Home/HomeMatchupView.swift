// Both people, side by side, the way a Sleeper matchup puts two teams on one screen.
// Compact rows (check + title) so two columns fit a phone. Full ChoreRowView stays on the board.
import RoostCore
import RoostDesign
import SwiftUI

struct HomeMatchupView: View {
    let columns: [HomeSummary.Column]
    let onToggle: (TodayRow) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool {
        typeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            header
            lists
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.matchup")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.sm) {
            ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                if index > 0 { Spacer(minLength: RoostSpacing.sm) }
                headerSide(column, trailing: index == columns.count - 1 && columns.count > 1)
            }
        }
    }

    private func headerSide(_ column: HomeSummary.Column, trailing: Bool) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: RoostSpacing.xxs) {
            HStack(spacing: RoostSpacing.xs) {
                if !trailing {
                    RoostAvatar(person: column.person.design, label: column.person.displayName)
                }
                Text(column.isMine ? Strings.Tasks.you : column.person.displayName)
                    .roostType(.rowTitle)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                if trailing {
                    RoostAvatar(person: column.person.design, label: column.person.displayName)
                }
            }
            Text("\(column.dueCount)")
                .roostType(.display)
                .monospacedDigit()
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .contentTransition(.numericText(value: Double(column.dueCount)))
                .roostAnimation(.standard, value: column.dueCount)
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityIdentifier("home.column.\(column.person.rawValue)")
    }

    @ViewBuilder
    private var lists: some View {
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.sectionGap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: RoostSpacing.sm))
        layout {
            ForEach(columns) { column in
                columnList(column)
            }
        }
    }

    private func columnList(_ column: HomeSummary.Column) -> some View {
        let due = column.rows.filter { !$0.isDone }
        return VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
            if due.isEmpty {
                Text(Strings.Home.nothingDue)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else {
                ForEach(due) { row in
                    HomeMatchupRow(row: row) { onToggle(row) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("home.list.\(column.person.rawValue)")
    }
}

struct HomeMatchupRow: View {
    let row: TodayRow
    let onToggle: () -> Void

    private var titleRole: RoostColor.Role {
        if row.stage == .alert { return .danger }
        return .textPrimary
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.xs) {
                Image(systemName: "circle")
                    .font(RoostType.headline)
                    .foregroundStyle(
                        row.stage == .dueToday
                            ? RoostColor.Role.separator.color
                            : row.stage.role.color
                    )
                    .frame(minWidth: RoostSpacing.minTapTarget / 2)
                    .accessibilityHidden(true)
                Text(row.chore.title)
                    .roostType(.rowTitle)
                    .foregroundStyle(titleRole.color)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.daysOverdue > 0 {
                    Text("\(row.daysOverdue)")
                        .roostType(.monoTally)
                        .foregroundStyle(row.stage.role.color)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.roostPressQuiet)
        .accessibilityLabel(row.chore.title)
        .accessibilityValue(row.daysOverdue > 0 ? Strings.daysLate(row.daysOverdue) : "")
        .accessibilityHint(Strings.Tasks.hintCheck)
        .accessibilityAddTraits(.isButton)
    }
}
