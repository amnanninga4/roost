// This phone's chores on the front door, checkable where they are. Long lists fold to a "N more"
// line whose open/shut state persists, following the pattern the streak block already set with
// `roost.today.streakExpanded` — the household decided once that a tally is the glance and the
// detail is the reveal, and that decision holds here.
//
// The rows are `ChoreRowView`, the same control as the board's, with its handoff affordances left
// off: offering a turn is a two-column conversation, and Home draws one column.
import RoostDesign
import SwiftUI

/// The fold, as arithmetic. Separate from the view so it can be tested without a simulator.
enum HomeRowsCollapse {
    /// Spec ruling 2026-09-15: six. It sits under the "around 5" daily cap Anne asked for, so a
    /// normal day is under the threshold and the fold is the exception, not the greeting. When the
    /// cap lane lands, the cap wins and this follows it.
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
    /// The screen owns what a tap feels like; this view only says which row was tapped.
    let onToggle: (TodayRow) -> Void

    @AppStorage("roost.home.rowsExpanded") private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hidden: Int {
        HomeRowsCollapse.hiddenCount(rows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
            ForEach(rows.prefix(HomeRowsCollapse.visible(rows.count, expanded: expanded))) { row in
                ChoreRowView(row: row) { onToggle(row) }
                    .roostTransition(.checkOff)
            }
            if hidden > 0 {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? Strings.Home.showLess : Strings.Home.more(hidden))
                        .roostType(.rowTitle)
                        .foregroundStyle(RoostColor.Role.accent.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityHint(Strings.Home.moreHint(hidden))
                .accessibilityIdentifier("home.more")
            }
        }
        .animation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion), value: expanded)
        // A check-off swaps a due row for a done one, so the list's identities change under the
        // finger. The board animates the same change the same way.
        .roostAnimation(.standard, value: rows.map(\.id))
    }
}
