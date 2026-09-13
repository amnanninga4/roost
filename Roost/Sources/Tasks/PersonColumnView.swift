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
    let toggle: (TodayRow) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
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
            if rows.isEmpty {
                // Nothing due and nothing checked off: a day with none of this person's chores on it.
                clearLine(Strings.Tasks.nothingDue)
            } else {
                if dueCount == 0 {
                    // Everything they owed today is checked off; the done rows stay under it to un-check.
                    clearLine(Strings.Tasks.nothingLeft)
                        .roostTransition(.row)
                }
                ForEach(rows) { row in
                    ChoreRowView(row: row) { toggle(row) }
                        .roostTransition(.checkOff)
                }
            }
        }
        // Rows inset by sm inside a card-radius card land on the row radius: 22 - 8 = 14.
        .padding(RoostSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoostColor.Role.surface.color, in: RoostRadius.cardShape)
        .roostElevation(.card, cornerRadius: RoostRadius.card)
        .roostAnimation(.standard, value: rows.map(\.id))
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
