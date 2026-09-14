// The top of the Tasks tab: the date, the word Today, the head-to-head block, and one status line.
import RoostCore
import RoostDesign
import SwiftUI

struct TodayHeaderView: View {
    let date: Date
    let streaks: StreakHeaderModel
    let notice: TodayBoard.Notice
    /// This phone's person, so the collapsed streak line can say "You".
    let me: Person?
    /// Ruling 2026-09-14: expand state persists; default collapsed on a fresh install.
    @AppStorage("roost.today.streakExpanded") private var expanded = false

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
            }
            StreakSummaryView(model: streaks, me: me, expanded: $expanded)
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
        streaks: StreakHeaderModel(streak: [.anne: 9, .wes: 6], doneThisWeek: [.anne: 14, .wes: 11]),
        notice: TodayBoard.Notice(tone: .quiet, text: SyncStatusCopy.synced(at: Date())),
        me: .anne
    )
    .padding(RoostSpacing.screenMargin)
    .background(RoostColor.Role.background.color)
}

#Preview("Not paired") {
    TodayHeaderView(
        date: Date(),
        streaks: StreakHeaderModel(streak: [:], doneThisWeek: [:]),
        notice: TodayBoard.Notice(tone: .notice, text: Strings.Tasks.notPaired),
        me: .anne
    )
    .padding(RoostSpacing.screenMargin)
    .background(RoostColor.Role.background.color)
}
