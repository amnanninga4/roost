// Every user-facing string R-10 and R-11 added, in one place so Anne can edit the copy without touching a screen.
// Functions take a title or a count; edit the text inside the quotes and keep the \(...) where the value goes.
import Foundation

enum Strings {
    enum Tabs {
        static let tasks = "Tasks"
        static let shopping = "Shopping"
        static let meals = "Meals"
        static let projects = "Projects"
    }

    /// Shared by the three list tabs.
    enum Lists {
        static let delete = "Delete"
        /// Joins the parts of a meta line: "Weeknight · last made Jul 20"
        static let metaSeparator = " · "
    }

    enum Shopping {
        /// "10 items · 2 already bought"
        static func header(items: Int, bought: Int) -> String {
            "\(items) \(items == 1 ? "item" : "items")\(Lists.metaSeparator)\(bought) already bought"
        }
        static let add = "Add an item…"
        static let empty = "Nothing on the list."
    }

    enum Meals {
        /// "8 saved ideas"
        static func header(count: Int) -> String { "\(count) saved \(count == 1 ? "idea" : "ideas")" }
        static let add = "Add an idea…"
        static let tag = "Tag, like Weeknight"
        static let empty = "No ideas saved yet."
        /// The badge on the meal that is next up.
        static let nextUpBadge = "NEXT UP"
        /// Swipe action / context menu.
        static let nextUp = "Next up"
        static let clearNextUp = "Clear next up"
        static let madeToday = "Made it today"
        /// "last made Jul 20"; the date is formatted by the screen.
        static func lastMade(_ when: String) -> String { "last made \(when)" }
    }

    enum Projects {
        /// "3 active projects"
        static func header(count: Int) -> String { "\(count) active \(count == 1 ? "project" : "projects")" }
        static let add = "Start a project…"
        static let steps = "First steps, one per line"
        static let start = "Start"
        static let addStep = "Add a step…"
        static let empty = "No projects yet."
        static let deleteProject = "Delete project"
        /// "1/5"
        static func progress(done: Int, total: Int) -> String { "\(done)/\(total)" }
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

    /// Kitchen mode (Gear → Kitchen mode): the phone propped on the counter, both people at once.
    enum Kitchen {
        static let menuEntry = "Kitchen mode"
        static let close = "Close"
        /// Heading over the shared red banner that lists every alert-stage chore from either person.
        static let alertHeading = "VISIBLE TO BOTH OF YOU"
        /// Under each name, beneath the big number: everything the person owes today, overdue included.
        static let dueTodayLabel = "DUE TODAY"
        /// The same as one line, for accessibility: "4 DUE TODAY"
        static func dueToday(_ count: Int) -> String { "\(count) \(dueTodayLabel)" }
        /// "1 DAY LATE" / "3 DAYS LATE", the stage label on an overdue card.
        static func daysLate(_ days: Int) -> String { days == 1 ? "1 DAY LATE" : "\(days) DAYS LATE" }
        /// Under a name when this person has nothing overdue but the other one does.
        static let columnClear = "Nothing overdue."
        /// The one calm line when nobody has anything overdue.
        static let caughtUp = "All caught up."
        /// Bottom line, from the coordinator's last successful sync.
        static func synced(_ relative: String) -> String { "Synced \(relative)" }
        static let syncedJustNow = "Synced just now"
        static let neverSynced = "Not synced yet"
    }
}

extension String {
    /// "Scoop litter" -> "scoop litter", but an acronym keeps its case: "PM wet cat food" stays as it is.
    var lowercasedFirst: String {
        guard let first, first.isUppercase else { return self }
        if let second = dropFirst().first, second.isUppercase { return self }
        return first.lowercased() + dropFirst()
    }

    var uppercasedFirst: String { prefix(1).uppercased() + dropFirst() }
}
