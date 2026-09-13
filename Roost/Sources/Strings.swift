// Every user-facing string R-10 added, in one place so Anne can edit the copy without touching a screen.
// Functions take the chore title; edit the text inside the quotes and keep the \(...) where the title goes.
import Foundation

enum Strings {
    enum Tabs {
        static let tasks = "Tasks"
        static let shopping = "Shopping"
        static let meals = "Meals"
        static let projects = "Projects"
    }

    enum Placeholder {
        static let shopping = "Nothing here yet."
        static let meals = "Nothing here yet."
        static let projects = "Nothing here yet."
    }

    enum Streak {
        static let dayStreak = "day streak"
        static let ahead = "CURRENTLY AHEAD"
        static let versus = "VS"
        /// "Anne · 14   Wes · 11"
        static let tallySeparator = " · "
        static let tallyGap = "   "
    }

    /// Subtitle under an overdue row. Stage and category come from RoostCore; dueToday shows nothing.
    enum Escalation {
        /// 1–2 days late. The title is lowercased to read mid-sentence: "Still no scoop litter…"
        static func nudge(title: String) -> String { "Still no \(title.lowercasedFirst)…" }
        /// 3–4 days late, cat-care rows.
        static let pointedCat = "The cat has feelings about this."
        /// 3–4 days late, home rows.
        static let pointedHome = "Getting overdue."
        /// 5+ days late. The title is capitalized: "Scoop litter emergency"
        static func alert(title: String) -> String { "\(title.uppercasedFirst) emergency" }
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
    var uppercasedFirst: String { prefix(1).uppercased() + dropFirst() }
}
