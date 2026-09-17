// Both people on one card, Sleeper-matchup style: names and leftover counts in the header,
// then two compact columns. Full ChoreRowView stays on the board.
import RoostCore
import RoostDesign
import SwiftUI

struct HomeMatchupView: View {
    let columns: [HomeSummary.Column]
    let onToggle: (TodayRow) -> Void
    /// Opens that person's own page. The header and the leftover count are the way in.
    var onOpenPerson: (Person) -> Void = { _ in }

    /// How many chores the matchup shows before "more" sends you to their page.
    private static let previewLimit = 5

    @Environment(\.dynamicTypeSize) private var typeSize

    private var stacked: Bool {
        typeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(RoostColor.Role.separator.color)
                .frame(height: 1)
                .padding(.top, RoostSpacing.sm)
            lists
                .padding(.top, RoostSpacing.sm)
        }
        .padding(RoostSpacing.md)
        .roostCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.matchup")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: RoostSpacing.sm) {
            if let left = columns.first {
                headerSide(left, trailing: false)
            }
            if columns.count > 1, let right = columns.last {
                headerSide(right, trailing: true)
            }
        }
    }

    private func headerSide(_ column: HomeSummary.Column, trailing: Bool) -> some View {
        Button {
            onOpenPerson(column.person)
        } label: {
            HStack(spacing: RoostSpacing.sm) {
                if !trailing {
                    RoostAvatar(person: column.person.design, label: column.person.displayName)
                        .accessibilityHidden(true)
                }
                VStack(alignment: trailing ? .trailing : .leading, spacing: 0) {
                    HStack(spacing: RoostSpacing.xs) {
                        Text(column.person.displayName)
                            .roostType(.monoLabel)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                        if column.isMine {
                            Text(Strings.Tasks.you)
                                .roostType(.monoLabel)
                                .foregroundStyle(RoostColor.Role.onAccent.color)
                                .padding(.horizontal, RoostSpacing.xs)
                                .padding(.vertical, 2)
                                .background(column.person.design.color, in: RoostRadius.pillShape)
                                .accessibilityHidden(true)
                        }
                    }
                    Text("\(column.dueCount)")
                        .roostType(.title)
                        .monospacedDigit()
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .contentTransition(.numericText(value: Double(column.dueCount)))
                        .roostAnimation(.standard, value: column.dueCount)
                }
                .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
                if trailing {
                    RoostAvatar(person: column.person.design, label: column.person.displayName)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.roostPressQuiet)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Strings.Home.openPerson)
        .accessibilityIdentifier("home.open.\(column.person.rawValue)")
        .accessibilityLabel(column.person.displayName)
        .accessibilityValue(Strings.Tasks.due(column.dueCount))
    }

    @ViewBuilder
    private var lists: some View {
        if stacked {
            VStack(alignment: .leading, spacing: RoostSpacing.md) {
                ForEach(columns) { column in
                    columnList(column)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    if index > 0 {
                        Rectangle()
                            .fill(RoostColor.Role.separator.color)
                            .frame(width: 1)
                            .padding(.horizontal, RoostSpacing.sm)
                    }
                    columnList(column)
                }
            }
        }
    }

    private func columnList(_ column: HomeSummary.Column) -> some View {
        let due = column.rows.filter { !$0.isDone }
        return VStack(alignment: .leading, spacing: 0) {
            if due.isEmpty {
                Text(Strings.Home.allCaught)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget, alignment: .leading)
            } else {
                ForEach(Array(due.prefix(Self.previewLimit))) { row in
                    HomeMatchupRow(row: row) { onToggle(row) }
                }
                if due.count > Self.previewLimit {
                    Button {
                        onOpenPerson(column.person)
                    } label: {
                        Text(Strings.Home.more(due.count - Self.previewLimit))
                            .roostType(.caption)
                            .foregroundStyle(RoostColor.Role.accent.color)
                            .frame(maxWidth: .infinity, minHeight: RoostSpacing.minTapTarget, alignment: .leading)
                    }
                    .buttonStyle(.roostPressQuiet)
                    .accessibilityIdentifier("home.more.\(column.person.rawValue)")
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

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: RoostSpacing.sm) {
                Image(systemName: "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(
                        row.stage == .dueToday
                            ? RoostColor.Role.separator.color
                            : row.stage.role.color
                    )
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                Text(row.chore.title)
                    .roostType(.subheadline)
                    .foregroundStyle(
                        row.stage == .alert
                            ? RoostColor.Role.danger.color
                            : RoostColor.Role.textPrimary.color
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.chore.title)
        .accessibilityValue(row.daysOverdue > 0 ? Strings.daysLate(row.daysOverdue) : "")
        .accessibilityHint(Strings.Tasks.hintCheck)
        .accessibilityAddTraits(.isButton)
    }
}
