// Compile bridge for Task 4. Task 5 owns the real fold + ChoreRowView wiring.
// ChoreRowView has no `init(row:)` — it requires onToggle (and optionally offer/withdraw).
// Do not invent board-action wiring here; Task 5 must match PersonColumnView or stop for design.
import RoostCore
import SwiftUI

struct HomeRowsView: View {
    let rows: [TodayRow]

    var body: some View {
        EmptyView()
    }
}
