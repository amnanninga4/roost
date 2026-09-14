// One person's column on the Tasks tab: their name, what they still owe today, and the rows.
//
// Both columns are always on screen, and the other person's says their name — Anne or Wes — never
// "Partner". One card per person, so the two lists can never be read as one.
import RoostCore
import RoostDesign
import SwiftUI

struct PersonColumnView: View {
    let person: Person
    /// Already in the card's order (see TodayBoard.ordered).
    let rows: [TodayRow]
    /// Everything still owed today, overdue included.
    let dueCount: Int
    /// True for the person this phone is paired as.
    let isMine: Bool
    /// Offers waiting for an answer, above the rows. Only ever this phone's own person's: an offer the
    /// other phone has to answer already reads on this one as "Asked Wes · waiting" on the row it came
    /// from, and a card with two buttons nobody here may press would be the same news twice.
    var offers: [IncomingOffer] = []
    let toggle: (TodayRow) -> Void
    /// Offers a row's turn to the other person. Nil on a column this phone cannot act in.
    var offer: ((TodayRow) -> Void)?
    /// Takes back an offer that has not synced yet.
    var withdraw: ((String) -> Void)?
    var answer: ((IncomingOffer, HandoffRules.Decision) -> Void)?
    var showInAllChores: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Set once, on the card's first appearance: the rows' entrance stagger never repeats.
    @State private var entered = false
    /// The dot that ties a column to its half of the week bar.
    @ScaledMetric(relativeTo: .title2) private var dot = RoostSpacing.sm

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sm) {
            header
            card
        }
    }

    // MARK: - Header

    /// Name, whose column it is, and what is left. One line normally; at accessibility sizes the three
    /// pieces stack, because a 60-pt name next to a pill and a count wraps the name mid-word.
    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: RoostSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: RoostSpacing.sm))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: RoostSpacing.sm) {
                Circle()
                    .fill(person.design.color)
                    .frame(width: dot, height: dot)
                    .accessibilityHidden(true)
                Text(person.displayName)
                    .roostType(.title)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isMine {
                Text(Strings.Tasks.you)
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.onAccent.color)
                    .padding(.horizontal, RoostSpacing.sm)
                    .padding(.vertical, RoostSpacing.xxs)
                    .background(RoostColor.Role.accent.color, in: RoostRadius.pillShape)
                    .fixedSize()
            }
            if !typeSize.isAccessibilitySize {
                Spacer(minLength: RoostSpacing.sm)
            }
            Text(Strings.Tasks.due(dueCount))
                .roostType(.monoTally)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
                .contentTransition(.numericText(value: Double(dueCount)))
                .roostAnimation(.standard, value: dueCount)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Card

    private var card: some View {
        // A hairline gap so two tinted rows next to each other still read as two rows.
        VStack(spacing: RoostSpacing.xxs) {
            // Above the rows, and above "Nothing due today": a question is not a chore yet, and the
            // answer decides whether the list below it is right.
            ForEach(offers) { offer in
                HandoffOfferCard(
                    offer: offer,
                    accept: { answer?(offer, .accept) },
                    decline: { answer?(offer, .decline) }
                )
                .roostTransition(.row)
                .padding(.bottom, RoostSpacing.xxs)
            }
            if rows.isEmpty {
                // Nothing due and nothing checked off: a day with none of this person's chores on it.
                clearLine(Strings.Tasks.nothingDue)
            } else {
                if dueCount == 0 {
                    // Everything they owed today is checked off; the done rows stay under it to un-check.
                    clearLine(Strings.Tasks.nothingLeft)
                        .roostTransition(.row)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ChoreRowView(
                        row: row,
                        onOffer: offerAction(for: row),
                        onWithdraw: withdrawAction(for: row),
                        onShowInAllChores: showInAllChores
                    ) { toggle(row) }
                        .roostTransition(.checkOff)
                        .opacity(entered ? 1 : 0)
                        .offset(y: entered ? 0 : RoostSpacing.xs)
                        .animation(
                            RoostMotion.reduceMotionAware(.standard, reduceMotion: reduceMotion)
                                .delay(RoostMotion.staggerDelay(index: index, reduceMotion: reduceMotion)),
                            value: entered
                        )
                }
            }
        }
        // Rows inset by sm inside a card-radius card land on the row radius: 22 - 8 = 14.
        .padding(RoostSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .roostCard()
        .roostAnimation(.standard, value: rows.map(\.id))
        .roostAnimation(.standard, value: offers.map(\.id))
        .onAppear {
            // First appearance per launch only: `entered` never goes back to false, so a tab switch,
            // a scroll, or a re-render never staggers the card again.
            entered = true
        }
    }

    /// Whether this row may be offered is `row.canOffer` — `RoostCore.HandoffRules.canOffer`, decided in
    /// the planner. The view only adds the one thing the planner cannot know: whose phone this is.
    private func offerAction(for row: TodayRow) -> (() -> Void)? {
        guard isMine, row.canOffer, let offer else { return nil }
        return { offer(row) }
    }

    /// Offered only while the offer is still on this phone. The server has no withdraw route, so an
    /// offer that has synced can only be waited out — see `HandoffActions.withdraw`.
    private func withdrawAction(for row: TodayRow) -> (() -> Void)? {
        guard isMine, let withdraw, case .waiting(_, let id, true) = row.handoff else { return nil }
        return { withdraw(id) }
    }

    private func clearLine(_ text: String) -> some View {
        HStack(spacing: RoostSpacing.sm) {
            Image(systemName: "checkmark.circle")
                .font(RoostType.title)
                .foregroundStyle(RoostColor.Role.success.color)
                .accessibilityHidden(true)
            Text(text)
                .roostType(.headline)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, RoostSpacing.sm)
        .padding(.vertical, RoostSpacing.md)
        .accessibilityElement(children: .combine)
    }
}
