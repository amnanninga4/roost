// One chore row on the Tasks tab, and the app's most-pressed control.
//
// The whole row is the button (so there is no small target to miss), the check control holds 44 pt on
// its own, and the row reads as one element to VoiceOver: the chore's title, then its state, then what
// the tap will do. The stage reads through the title colour, the days-late chip, and a 3-pt bar along
// the row's leading edge, so a row that is running late is obvious without reading it — and without
// painting the card.
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
    /// Opens More → All chores from the long-press menu. Nil when the parent has not wired the route.
    var onShowInAllChores: (() -> Void)?
    let onToggle: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// How far the row has slid left, 0 closed to `-revealWidth` open.
    @State private var swipeOffset: CGFloat = 0

    private var category: RoostCategory {
        row.chore.category == .catCare ? .catCare : .home
    }

    /// Done rows step back to secondary; the rest wear their stage.
    private var titleRole: RoostColor.Role {
        row.isDone ? .textSecondary : row.stage.role
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let onOffer {
                Button {
                    closeSwipe()
                    onOffer()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .roostType(.headline)
                        .foregroundStyle(RoostColor.Role.onAccent.color)
                        .frame(width: handoffRevealWidth)
                        .frame(maxHeight: .infinity)
                        .background(RoostColor.Role.assigned.color, in: RoostRadius.rowShape)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityLabel(Strings.Handoffs.ask(other.displayName))
                // The strip is only real once the row has moved; a due-today row has a clear
                // background, so without this the button would peek through it at rest.
                .opacity(swipeOffset < 0 ? 1 : 0)
            }
            swipeableRow
        }
    }

    @ViewBuilder
    private var swipeableRow: some View {
        if onOffer != nil {
            rowButton
                .offset(x: swipeOffset)
                .gesture(swipe)
                .onChange(of: row.id) { _, _ in swipeOffset = 0 } // a reused row snaps shut
        } else {
            rowButton
        }
    }

    /// A horizontal-dominant drag slides the row; the ScrollView keeps the vertical ones. Open past
    /// half the strip, or on a flick, closed otherwise.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: RoostSpacing.lg)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                swipeOffset = min(0, max(-handoffRevealWidth, value.translation.width))
            }
            .onEnded { value in
                let open = value.translation.width < -handoffRevealWidth / 2
                    || value.predictedEndTranslation.width < -handoffRevealWidth
                withAnimation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion)) {
                    swipeOffset = open ? -handoffRevealWidth : 0
                }
            }
    }

    private func closeSwipe() {
        withAnimation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion)) {
            swipeOffset = 0
        }
    }

    private var rowButton: some View {
        Button {
            if swipeOffset != 0 {
                closeSwipe()
            } else {
                onToggle()
            }
        } label: {
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
            .contentShape(Rectangle())
            .overlay(alignment: .leading) {
                if !row.isDone, row.stage.fillRole != nil {
                    Capsule()
                        .fill(row.stage.role.color)
                        .frame(width: EdgeBar.width)
                        .padding(.vertical, RoostSpacing.xxs)
                        .accessibilityHidden(true)
                }
            }
        }
        // Quiet: the toggle already fires .checkOff / .undo on the same touch — the kit's press
        // haptic on top of that would be two haptics for one finger.
        .buttonStyle(.roostPressQuiet)
        .contextMenu {
            handoffMenu
            if let onShowInAllChores {
                Button(Strings.Tasks.showInAllChores, systemImage: "list.bullet", action: onShowInAllChores)
            }
        } preview: {
            ChoreRowPreview(row: row)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.chore.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(row.isDone ? Strings.Tasks.hintUncheck : Strings.Tasks.hintCheck)
        .accessibilityAddTraits(.isButton)
        .accessibilityActions {
            handoffMenu
            if let onShowInAllChores {
                Button(Strings.Tasks.showInAllChores, action: onShowInAllChores)
            }
        }
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
                        RowBadge(
                            text: Strings.daysLate(days),
                            tint: row.stage.role,
                            fill: row.stage.fillRole ?? .surface
                        )
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
                        RowBadge(
                            text: giver.displayName.uppercased(),
                            tint: giver.design.role,
                            fill: giver.design.softRole
                        )
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

// MARK: - The trailing swipe

//
// The Today board is a ScrollView of cards, not a List, so the system's `.swipeActions` is not
// available here — this reveal is the one gesture in the app built by hand. It exists for exactly
// one action, Hand off, and only on rows where the context menu would offer it (`onOffer != nil`).
// No leading swipe: tap already toggles done, and a second done gesture adds nothing.

/// The strip the row uncovers. Two `xxxl` steps (96 pt): a comfortable thumb landing.
private let handoffRevealWidth = RoostSpacing.xxxl * 2

/// The escalation stage, as an edge rather than a wash: a rounded bar along the row's leading edge
/// in the stage's colour. A bad day still reads at a glance, but the card is no longer painted
/// wall to wall. Decorative — the days-late chip and the subtitle carry the meaning.
private enum EdgeBar {
    /// 3 pt, per the spec. Stroke geometry is the one thing RoostDesign has no scale for (the
    /// precedent is `ComposerBorder` in ListParts), so the number lives here, named once.
    static let width: CGFloat = 3
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

/// The card a long-press lifts the row into: everything the two-slot meta line had to leave out —
/// who the chore is for, its cadence, how late it is, and what a handoff is doing to it.
private struct ChoreRowPreview: View {
    let row: TodayRow

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.xs) {
            Text(row.chore.title)
                .roostType(.rowTitle)
                .foregroundStyle(RoostColor.Role.textPrimary.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .roostType(.subheadline)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            if let note = ChoreRowMeta.handoffNote(for: row) {
                Text(note)
                    .roostType(.caption)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
            }
        }
        .padding(RoostSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .roostCard()
    }

    /// "For Anne · Daily · 3 days late" — the whole story, since the row only ever tells two slots of it.
    private var detail: String {
        var parts: [String] = [
            row.chore.together ? Strings.Tasks.togetherValue : Strings.Tasks.forPerson(row.person.displayName),
            row.chore.cadence.label,
        ]
        if row.isDone {
            parts.append(Strings.Tasks.stateDone)
        } else if row.daysOverdue > 0 {
            parts.append(Strings.Tasks.stateLate(row.daysOverdue))
        } else {
            parts.append(Strings.Tasks.stateDueToday)
        }
        if case let .takenFrom(giver) = row.handoff {
            parts.append(Strings.Handoffs.from(giver.displayName))
        }
        return parts.joined(separator: Strings.Lists.metaSeparator)
    }
}
