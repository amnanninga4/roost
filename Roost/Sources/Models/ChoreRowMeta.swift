// What a chore row's meta line shows, decided out of the view so the rule is testable: at most two
// inline elements, chosen by urgency — how late it is, then a handoff still in motion, then whose
// the chore is. The row shows the day-to-day minimum; the long-press preview (the context menu)
// shows the rest.
//
// Two things the old five-element line carried are gone by design: "from X" as text (the giver's
// chip wears the giver's own colour, which already says it) and "On the other phone too" (the
// row's not-synced marker carries that meaning).
import Foundation
import RoostCore

enum ChoreRowMeta {
    /// One thing on the meta line, in urgency order.
    enum Element: Hashable {
        /// The mono "N DAYS LATE" chip in the stage's colours.
        case daysLate(Int)
        /// The one line a handoff in motion puts under the row ("Asked Wes · waiting").
        case handoffNote(String)
        /// A together chore's chip.
        case together
        /// A pinned chore's name chip, in the assign colours.
        case pinned(Person)
        /// A taken-over turn's chip: the giver's name in the giver's own colours.
        case taken(Person)
    }

    /// At most two, most urgent first: the days-late chip, then an active handoff note, then the
    /// together/giver/name chip. A settled handoff (`.takenFrom`) is a chip, not a note; an expired
    /// or refused offer has no chip, matching the old line.
    static func elements(for row: TodayRow) -> [Element] {
        var candidates: [Element] = []
        if row.daysOverdue > 0 {
            candidates.append(.daysLate(row.daysOverdue))
        }
        if let note = handoffNote(for: row) {
            candidates.append(.handoffNote(note))
        }
        if row.chore.together {
            candidates.append(.together)
        } else if case let .takenFrom(giver) = row.handoff {
            candidates.append(.taken(giver))
        } else if let pinned = row.chore.fixedAssignee {
            candidates.append(.pinned(pinned))
        }
        return Array(candidates.prefix(2))
    }

    /// The one line a handoff in motion puts under the row. An expired offer has none: nobody
    /// answered, and being told so days later helps no one. A settled one is a chip instead.
    static func handoffNote(for row: TodayRow) -> String? {
        switch row.handoff {
        case let .waiting(asked, _, _): Strings.Handoffs.waiting(asked.displayName)
        case let .declined(by): Strings.Handoffs.saidNo(by.displayName)
        case .refused: Strings.Handoffs.refused
        case .takenFrom, .none: nil
        }
    }
}
