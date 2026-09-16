// This phone's chores on the front door, checkable where they are. Long buckets fold to a "N more"
// line whose open/shut state persists, following the pattern the streak block already set with
// `roost.today.streakExpanded`.
//
// The rows are `ChoreRowView`, the same control as the board's, with its handoff affordances left
// off: offering a turn is a two-column conversation, and Home draws one column.
import RoostCore
import RoostDesign
import SwiftUI

/// The fold, as arithmetic. Separate from the view so it can be tested without a simulator.
enum HomeRowsCollapse {
    /// Spec ruling 2026-09-15: six. Applied per bucket, not to the mixed list and not as a
    /// stand-in for a daily cap.
    static let threshold = 6

    static func visible(_ total: Int, expanded: Bool) -> Int {
        expanded ? total : min(total, threshold)
    }

    static func hiddenCount(_ total: Int) -> Int {
        max(0, total - threshold)
    }
}

struct HomeRowsView: View {
    let rows: [TodayRow]
    let calendar: HouseholdCalendar
    let now: Date
    let onToggle: (TodayRow) -> Void

    @AppStorage("roost.home.overdueExpanded") private var overdueExpanded = false
    @AppStorage("roost.home.todayExpanded") private var todayExpanded = false
    @AppStorage("roost.home.laterExpanded") private var laterExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: HomeRowGroups {
        HomeRowBuckets.group(rows, calendar: calendar, on: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
            bucket(
                groups.overdue,
                title: Strings.Home.overdue,
                expanded: $overdueExpanded,
                style: .standard,
                identifier: "home.overdue"
            )
            bucket(
                groups.today,
                title: Strings.Home.today,
                expanded: $todayExpanded,
                style: .standard,
                identifier: "home.today"
            )
            bucket(
                groups.later,
                title: Strings.Home.ifYouHaveTime,
                expanded: $laterExpanded,
                style: .quiet,
                identifier: "home.later"
            )
        }
        .roostAnimation(.standard, value: rows.map(\.id))
    }

    @ViewBuilder
    private func bucket(
        _ rows: [TodayRow],
        title: String,
        expanded: Binding<Bool>,
        style: ChoreRowView.Style,
        identifier: String
    ) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(title)
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier)
                let hidden = HomeRowsCollapse.hiddenCount(rows.count)
                ForEach(rows.prefix(HomeRowsCollapse.visible(rows.count, expanded: expanded.wrappedValue))) { row in
                    ChoreRowView(row: row, style: style, showsEscalationSubtitle: false) { onToggle(row) }
                        .roostTransition(.checkOff)
                }
                if hidden > 0 {
                    Button {
                        expanded.wrappedValue.toggle()
                    } label: {
                        Text(expanded.wrappedValue ? Strings.Home.showLess : Strings.Home.more(hidden))
                            .roostType(.rowTitle)
                            .foregroundStyle(RoostColor.Role.accent.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.roostPressQuiet)
                    .accessibilityHint(Strings.Home.moreHint(hidden))
                    .accessibilityIdentifier("\(identifier).more")
                }
            }
            .animation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion), value: expanded.wrappedValue)
        }
    }
}
