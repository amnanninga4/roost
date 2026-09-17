// The top of the board segment: the date, the word Today, and one status line. The head-to-head
// streak block moved down to sit above the columns — it is a scoreboard, and a scoreboard belongs
// on the board rather than on the front door. See docs/superpowers/specs/2026-09-15-home-screen-design.md.
import RoostCore
import RoostDesign
import SwiftUI

struct TodayHeaderView: View {
    let date: Date
    let notice: TodayBoard.Notice

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.md) {
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(dateLine)
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.accent.color)
                    // So the accessibility audit can name this line: its label is today's date, which is
                    // not something a test can match on. See Roost/UITests/AccessibilityAuditTests.swift.
                    .accessibilityIdentifier("dateEyebrow")
                Text(Strings.Tasks.today)
                    .roostType(.displayLarge)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("board.title")
            }
            SyncNoticeLine(notice: notice)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateLine: String {
        date
            .formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent))
            .uppercased()
    }
}

/// The sync state, as one line. Offline and unpaired are notices, not modals: two phones behind a home
/// tunnel lose touch often, the queue replays on its own, and the screen still works meanwhile.
struct SyncNoticeLine: View {
    let notice: TodayBoard.Notice

    var body: some View {
        HStack(spacing: RoostSpacing.xs) {
            if notice.tone == .notice {
                // Not colour alone: the icon says "read this" to anyone who cannot see the blue.
                Image(systemName: "exclamationmark.circle")
                    .accessibilityHidden(true)
            }
            Text(notice.text)
        }
        .roostType(.footnote)
        .foregroundStyle(tint)
    }

    private var tint: Color {
        switch notice.tone {
        case .quiet: RoostColor.Role.textSecondary.color
        case .notice: RoostColor.Role.notice.color
        }
    }
}

#Preview("Paired and synced") {
    TodayHeaderView(
        date: Date(),
        notice: TodayBoard.Notice(tone: .quiet, text: SyncStatusCopy.synced(at: Date()))
    )
    .padding(RoostSpacing.screenMargin)
    .background(RoostColor.Role.background.color)
}

#Preview("Not paired") {
    TodayHeaderView(
        date: Date(),
        notice: TodayBoard.Notice(tone: .notice, text: Strings.Tasks.notPaired)
    )
    .padding(RoostSpacing.screenMargin)
    .background(RoostColor.Role.background.color)
}
