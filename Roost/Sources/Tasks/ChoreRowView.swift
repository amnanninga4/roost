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
            .contentShape(Rectangle())
        }
        .buttonStyle(ChoreRowButtonStyle(fill: fill))
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

    /// The line under the words: how late it is, who it is pinned to, who handed it over, and — once the
    /// other phone is in on it — that it is not a private problem any more. Empty for a row that is
    /// simply due today and nobody's business but this person's.
    @ViewBuilder
    private var meta: some View {
        let late = row.daysOverdue > 0
        let pinned = row.chore.fixedAssignee
        if late || pinned != nil || row.chore.together || row.handoff != nil {
            // One line normally. At accessibility sizes a 40-pt chip leaves the note beside it a column
            // two characters wide, so the meta line becomes a stack instead.
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.xs))
                : AnyLayout(HStackLayout(spacing: RoostSpacing.sm))
            layout {
                if late {
                    // On a tinted row the chip sits on the card's own surface, so it reads as a chip
                    // rather than a second wash of the same colour.
                    RowBadge(text: Strings.daysLate(row.daysOverdue), tint: row.stage.role, fill: .surface)
                }
                if row.chore.together {
                    RowBadge(text: Strings.Tasks.together, tint: .assigned, fill: .assignedSoft)
                } else if let pinned {
                    RowBadge(text: pinned.displayName.uppercased(), tint: .assigned, fill: .assignedSoft)
                }
                if case let .takenFrom(giver) = row.handoff {
                    // A settled fact, so it gets a chip; the states still in motion below get a line of
                    // words instead, because a chip for a thing that is about to change reads as a label.
                    RowBadge(text: Strings.Handoffs.from(giver.displayName), tint: .accent, fill: .accentSoft)
                }
                if let note = handoffNote {
                    Text(note)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !row.isDone, row.stage.isSharedWithTheOther {
                    Text(Strings.Tasks.onTheOtherPhone)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, RoostSpacing.xxs)
        }
    }

    /// The one line a handoff in motion puts under the row. An expired offer has none: nobody answered,
    /// and being told so days later helps no one.
    private var handoffNote: String? {
        switch row.handoff {
        case let .waiting(asked, _, _): Strings.Handoffs.waiting(asked.displayName)
        case let .declined(by): Strings.Handoffs.saidNo(by.displayName)
        case .refused: Strings.Handoffs.refused
        case .takenFrom, .none: nil
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
        if let note = handoffNote {
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

/// The press state: the fill steps up and the row gives a little, on the quick spring, which under
/// Reduce Motion becomes no animation at all rather than a shortened one.
private struct ChoreRowButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The row's resting fill: the stage's soft colour, or clear for a row that is only due today.
    let fill: Color

    /// A press is felt, not watched: two percent is enough to register under a finger.
    private let pressedScale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed ? RoostColor.Role.surfaceElevated.color : fill,
                in: RoostRadius.rowShape
            )
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(
                RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
