// One chore row on the Tasks tab, and the app's most-pressed control.
//
// The whole row is the button (so there is no small target to miss), the check control holds 44 pt on
// its own, and the row reads as one element to VoiceOver: the chore's title, then its state, then what
// the tap will do. Everything that carries colour comes from the escalation stage, so a row that is
// running late is obvious without reading it.
import RoostCore
import RoostDesign
import SwiftUI

struct ChoreRowView: View {
    let row: TodayRow
    /// Offers this turn to the other person. Nil when `row.canOffer` is false, or on a column that is
    /// not this phone's — you cannot give away work that was never yours.
    var onOffer: (() -> Void)?
    /// Takes an offer back. Nil unless the offer is still queued on this phone: there is no withdraw
    /// endpoint on the server (`POST /handoffs` and the two answer routes are all of it), so once an
    /// offer has synced the only honest answer is to wait for one.
    var onWithdraw: (() -> Void)?
    let onToggle: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var category: RoostCategory {
        row.chore.category == .catCare ? .catCare : .home
    }

    /// Done rows step back to secondary; the rest wear their stage.
    private var titleRole: RoostColor.Role {
        row.isDone ? .textSecondary : row.stage.role
    }

    private var fill: Color {
        guard !row.isDone, let fillRole = row.stage.fillRole else { return .clear }
        return fillRole.color
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: RoostSpacing.xs) {
                check
                VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                    titleLine
                    if let subtitle = EscalationCopy.subtitle(for: row) {
                        Text(subtitle)
                            .roostType(.subheadline)
                            .foregroundStyle(row.stage.role.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The badges sit under the words rather than beside them, at every text size: a chip
                    // in the trailing slot takes a third of the width off a chore called "Wipe down
                    // kitchen counters, bathroom counters/mirror", and the title is what you read.
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, RoostSpacing.md)
            .padding(.vertical, RoostSpacing.xs)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .background(fill, in: RoostRadius.rowShape)
            .contentShape(Rectangle())
        }
        // Quiet: the toggle already fires .checkOff / .undo on the same touch — the kit's press
        // haptic on top of that would be two haptics for one finger.
        .buttonStyle(.roostPressQuiet)
        .contextMenu { handoffMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.chore.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(row.isDone ? Strings.Tasks.hintUncheck : Strings.Tasks.hintCheck)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions { handoffMenu }
    }

    /// The handoff actions, in the long-press menu and in VoiceOver's actions rotor. Empty for almost
    /// every row: a chore is only ever offered from the column of the person who owes it this period.
    @ViewBuilder
    private var handoffMenu: some View {
        if let onOffer {
            Button(Strings.Handoffs.ask(other.displayName), systemImage: "arrow.left.arrow.right", action: onOffer)
        }
        if let onWithdraw {
            Button(Strings.Handoffs.withdraw, systemImage: "arrow.uturn.backward", action: onWithdraw)
        }
    }

    /// The other half of the household, from the row's own person.
    private var other: Person {
        row.person == .anne ? .wes : .anne
    }

    // MARK: - Pieces

    private var check: some View {
        Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
            .font(RoostType.title)
            .foregroundStyle(row.isDone ? RoostColor.Role.success.color : checkRing.color)
            .contentTransition(.symbolEffect(.replace))
            .frame(minWidth: RoostSpacing.minTapTarget, minHeight: RoostSpacing.minTapTarget)
            .accessibilityHidden(true)
    }

    /// An empty circle is the separator colour until the row is late, when it picks up the stage.
    private var checkRing: RoostColor.Role {
        row.stage == .dueToday ? .separator : row.stage.role
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.sm) {
            // The cat/house badge is a tint, not information — at accessibility sizes it would cost the
            // title a third of its column and break "Vacuum basement" across two lines mid-word.
            if !typeSize.isAccessibilitySize {
                Image(systemName: category.symbol)
                    .roostType(.caption)
                    .foregroundStyle(category.color)
                    .padding(RoostSpacing.xs)
                    .background(category.softColor, in: RoostRadius.shape(RoostRadius.sm))
                    .accessibilityHidden(true)
            }
            Text(row.chore.title)
                .roostType(.rowTitle)
                .foregroundStyle(titleRole.color)
                .strikethrough(row.isDone, color: RoostColor.Role.textSecondary.color)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The line under the words: at most two elements, picked by `ChoreRowMeta` — how late it is,
    /// then a handoff in motion, then whose it is. Everything else the row knows is one long-press
    /// away, on the context menu's preview card.
    @ViewBuilder
    private var meta: some View {
        let elements = ChoreRowMeta.elements(for: row)
        if !elements.isEmpty {
            // One line normally. At accessibility sizes a 40-pt chip leaves the note beside it a column
            // two characters wide, so the meta line becomes a stack instead.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.xs))
                : AnyLayout(HStackLayout(spacing: RoostSpacing.sm))
            layout {
                ForEach(elements, id: \.self) { element in
                    switch element {
                    case let .daysLate(days):
                        // The stage's strong on its soft: the one chip that keeps a tinted fill.
                        RowBadge(text: Strings.daysLate(days), tint: row.stage.role, fill: row.stage.fillRole ?? .surface)
                    case let .handoffNote(note):
                        Text(note)
                            .roostType(.caption)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                            .fixedSize(horizontal: false, vertical: true)
                    case .together:
                        RowBadge(text: Strings.Tasks.together, tint: .assigned, fill: .assignedSoft)
                    case let .pinned(person):
                        RowBadge(text: person.displayName.uppercased(), tint: .assigned, fill: .assignedSoft)
                    case let .taken(giver):
                        RowBadge(text: giver.displayName.uppercased(), tint: giver.design.role, fill: giver.design.softRole)
                    }
                }
            }
            .padding(.top, RoostSpacing.xxs)
        }
    }

    /// "Due today", "3 days late", or "Done", plus the pinned note, read after the title.
    private var accessibilityValue: String {
        var parts: [String] = []
        if row.isDone {
            parts.append(Strings.Tasks.stateDone)
        } else if row.daysOverdue > 0 {
            parts.append(Strings.Tasks.stateLate(row.daysOverdue))
        } else {
            parts.append(Strings.Tasks.stateDueToday)
        }
        if row.chore.together {
            parts.append(Strings.Tasks.togetherValue)
        } else if let pinned = row.chore.fixedAssignee {
            parts.append(Strings.Tasks.always(pinned.displayName))
        }
        if case let .takenFrom(giver) = row.handoff {
            parts.append(Strings.Handoffs.from(giver.displayName))
        }
        if let note = ChoreRowMeta.handoffNote(for: row) {
            parts.append(note)
        }
        return parts.joined(separator: ", ")
    }
}

/// A mono chip: the days-late count, or the name a chore is pinned to.
private struct RowBadge: View {
    let text: String
    let tint: RoostColor.Role
    let fill: RoostColor.Role

    var body: some View {
        Text(text)
            .roostType(.monoLabel)
            .foregroundStyle(tint.color)
            .padding(.horizontal, RoostSpacing.sm)
            .padding(.vertical, RoostSpacing.xxs)
            .background(fill.color, in: RoostRadius.shape(RoostRadius.sm))
            .overlay(RoostRadius.shape(RoostRadius.sm).stroke(tint.color.opacity(strokeOpacity), lineWidth: 1))
            .fixedSize()
    }

    /// A hairline in the chip's own colour, so the chip survives on a fill of the same family.
    private var strokeOpacity: Double {
        fill == .surface ? 0.35 : 0
    }
}
