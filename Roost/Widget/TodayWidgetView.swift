// The four families. One root that picks between them, so every family shares the same two empty states
// and the same tokens.
//
// Rules this follows, from `ios-interaction-primitives-design`: the data is the widget (no logo, no "open
// app" button, no gear); the hero number is big enough to read at arm's length; the lock-screen families
// are iconography rather than data (SF Symbols and one line, no fills that flatten in tint mode); and
// nothing animates, because a widget that looks like a screensaver is noise.
import RoostDesign
import SwiftUI
import WidgetKit

struct TodayWidgetView: View {
    let entry: TodayEntry
    /// Normally nil: the family comes from the environment, which only a widget host sets. Passed
    /// explicitly when the views are rendered outside one — `WidgetRenderTests`, which also writes
    /// `docs/widget-small.png` and `docs/widget-medium.png`.
    private let requestedFamily: WidgetFamily?

    @Environment(\.widgetFamily) private var hostFamily

    init(entry: TodayEntry, family: WidgetFamily? = nil) {
        self.entry = entry
        requestedFamily = family
    }

    private var family: WidgetFamily {
        requestedFamily ?? hostFamily
    }

    var body: some View {
        content
            .modifier(WidgetBackground(family: family))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            LockCircularView(mine: mine)
        case .accessoryRectangular:
            LockRectangularView(mine: mine, snapshot: entry.snapshot)
        case .systemMedium:
            if let snapshot = entry.snapshot, snapshot.isPaired {
                MediumView(snapshot: snapshot)
            } else {
                EmptyStateView(snapshot: entry.snapshot)
            }
        default:
            if let mine {
                SmallView(person: mine)
            } else {
                EmptyStateView(snapshot: entry.snapshot)
            }
        }
    }

    /// The paired person's own row. The small and lock-screen families are about *you*, so without a
    /// pairing they have nothing to show and fall through to the empty state.
    private var mine: RoostSnapshot.Person? {
        entry.snapshot?.mine
    }
}

// MARK: - background

/// `containerBackground` is what makes a widget adopt the system's material per context — Home Screen,
/// Lock Screen tint, StandBy's night mode. The accessory families get nothing behind them on purpose: a
/// fill there is flattened to one colour in tint mode and reads as a smudge.
private struct WidgetBackground: ViewModifier {
    let family: WidgetFamily

    func body(content: Content) -> some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            content.containerBackground(.clear, for: .widget)
        default:
            content.containerBackground(RoostColor.Role.background.color, for: .widget)
        }
    }
}

// MARK: - systemSmall

/// Your count and your streak. One number, one label, one line.
private struct SmallView: View {
    let person: RoostSnapshot.Person

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            Text(person.name.uppercased())
                .roostType(.monoLabel)
                .foregroundStyle(person.design.role.color)

            Spacer(minLength: 0)

            if person.due == 0 {
                Text(WidgetStrings.allDone)
                    .roostType(.display)
                    .foregroundStyle(RoostColor.Role.success.color)
                    .minimumScaleFactor(0.7)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.sm) {
                    Text("\(person.due)")
                        .roostType(.displayLarge)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text(WidgetStrings.dueLabel)
                        .roostType(.monoLabel)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
                if person.overdue > 0 {
                    LateChip(count: person.overdue)
                }
            }

            Spacer(minLength: 0)

            StreakLine(days: person.streak)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetStrings.summary(
            name: person.name, due: person.due, overdue: person.overdue, streak: person.streak
        ))
    }
}

// MARK: - systemMedium

/// Both people, side by side, in the order the app always uses: Anne then Wes. A comparison needs a
/// stable side per person more than it needs the reader first.
private struct MediumView: View {
    let snapshot: RoostSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            Text(WidgetStrings.today)
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)

            HStack(alignment: .top, spacing: RoostSpacing.md) {
                ForEach(Array(snapshot.people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 {
                        Divider().overlay(RoostColor.Role.separator.color)
                    }
                    PersonColumn(person: person, isMe: person.id == snapshot.me)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PersonColumn: View {
    let person: RoostSnapshot.Person
    let isMe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
            Text(person.name.uppercased())
                .roostType(.monoLabel)
                .foregroundStyle(person.design.role.color)

            HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.xs) {
                Text("\(person.due)")
                    .roostType(.display)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .minimumScaleFactor(0.7)
                Text(WidgetStrings.dueLabel)
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }

            if let item = person.top.first {
                TopLine(item: item)
                    .padding(.top, RoostSpacing.xxs)
            } else {
                Text(WidgetStrings.allDone)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.success.color)
                    .padding(.top, RoostSpacing.xxs)
            }

            Spacer(minLength: 0)

            StreakLine(days: person.streak)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetStrings.summary(
            name: person.name, due: person.due, overdue: person.overdue, streak: person.streak
        ))
    }
}

/// The loudest row on a person's list: a dot in its stage's colour, then the title. One line, truncated —
/// a widget that wraps a chore title has stopped being glanceable.
private struct TopLine: View {
    let item: RoostSnapshot.Item

    var body: some View {
        HStack(spacing: RoostSpacing.xs) {
            if item.stage.carriesColour {
                Circle()
                    .fill(item.stage.role.color)
                    .frame(width: RoostSpacing.xs + 2, height: RoostSpacing.xs + 2)
            }
            Text(item.title)
                .roostType(.caption)
                .foregroundStyle(item.stage.role.color)
                .lineLimit(1)
        }
    }
}

// MARK: - shared pieces

/// "9 day streak", with the flame the app's streak header uses.
private struct StreakLine: View {
    let days: Int

    var body: some View {
        Label {
            Text(WidgetStrings.streak(days))
                .roostType(.monoTally)
        } icon: {
            Image(systemName: "flame.fill")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(RoostColor.Role.bonus.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// "2 late" in the danger role, so the one thing worth acting on is the one thing carrying red.
private struct LateChip: View {
    let count: Int

    var body: some View {
        Text(WidgetStrings.late(count))
            .roostType(.monoLabel)
            .foregroundStyle(RoostColor.Role.danger.color)
            .padding(.horizontal, RoostSpacing.sm)
            .padding(.vertical, RoostSpacing.xxs)
            .background(RoostColor.Role.dangerSoft.color, in: RoostRadius.pillShape)
    }
}

// MARK: - accessory (lock screen)

/// The due count in a ring, with the late share filling it: at a glance, how much of what you owe today
/// is already behind. A capacity gauge rather than a number alone, because the lock screen is monochrome
/// and a shape carries more at 76 pt than a digit does.
private struct LockCircularView: View {
    let mine: RoostSnapshot.Person?

    var body: some View {
        if let mine, mine.due > 0 {
            Gauge(value: Double(mine.overdue), in: 0 ... Double(mine.due)) {
                Image(systemName: "checklist")
            } currentValueLabel: {
                Text("\(mine.due)")
                    .minimumScaleFactor(0.6)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(WidgetStrings.due(mine.due))
        } else {
            Image(systemName: mine == nil ? "questionmark" : "checkmark")
                .font(.title2)
                .accessibilityLabel(mine == nil ? WidgetStrings.noData : WidgetStrings.allDone)
        }
    }
}

/// One line of supporting info under a title, which is all this family is for.
private struct LockRectangularView: View {
    let mine: RoostSnapshot.Person?
    let snapshot: RoostSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let mine {
                Text(mine.due == 0 ? WidgetStrings.allDone : WidgetStrings.due(mine.due))
                    .font(.headline)
                    .widgetAccentable()
                if let item = mine.top.first {
                    Text(item.title)
                        .font(.caption)
                        .lineLimit(1)
                }
                if mine.overdue > 0 {
                    Text(WidgetStrings.late(mine.overdue))
                        .font(.caption2)
                }
            } else {
                Text(snapshot == nil ? WidgetStrings.noData : WidgetStrings.notPaired)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - empty states

/// Two states, one line each, both read plainly: nothing to show yet, or this phone is not paired. Neither
/// is an error and neither says "error" — there is nothing the reader can do from the Home Screen but open
/// the app, and tapping already does that.
private struct EmptyStateView: View {
    let snapshot: RoostSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            Image(systemName: "checklist")
                .foregroundStyle(RoostColor.Role.accent.color)
            Text(snapshot == nil ? WidgetStrings.noData : WidgetStrings.notPaired)
                .roostType(.title)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WidgetStrings.noDataSummary)
    }
}

// MARK: - previews

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
    TodayEntry(date: .now, snapshot: nil)
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
    TodayEntry(date: .now, snapshot: nil)
}

#Preview("Lock rectangular", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}

#Preview("Lock circular", as: .accessoryCircular) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .placeholder)
}
