// Every user-facing string in the app, in one place so Anne can edit the copy without touching a screen.
// Functions take a title or a count; edit the text inside the quotes and keep the \(...) where the value goes.
import Foundation

enum Strings {
    /// The bar title on every tab.
    static let appTitle = "Roost"

    /// "1 DAY LATE" / "3 DAYS LATE". The overdue badge, worded the same on the Tasks tab and in Kitchen mode.
    static func daysLate(_ days: Int) -> String {
        days == 1 ? "1 DAY LATE" : "\(days) DAYS LATE"
    }

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
        /// VoiceOver, on the small avatar: "Added by Anne"
        static func addedBy(_ name: String) -> String {
            "Added by \(name)"
        }
    }

    enum Shopping {
        /// "10 items · 2 already bought"
        static func header(items: Int, bought: Int) -> String {
            "\(items) \(items == 1 ? "item" : "items")\(Lists.metaSeparator)\(bought) already bought"
        }

        static let add = "Add an item…"
        static let empty = "Nothing on the list."
        /// VoiceOver: a row's state, and what a tap does to it.
        static let bought = "Bought"
        static let stillNeeded = "Still needed"
        static let markBought = "Marks it bought"
        static let markStillNeeded = "Marks it still needed"
    }

    enum Meals {
        /// "8 saved ideas"
        static func header(count: Int) -> String {
            "\(count) saved \(count == 1 ? "idea" : "ideas")"
        }

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
        static func lastMade(_ when: String) -> String {
            "last made \(when)"
        }
    }

    enum Projects {
        /// "3 active projects"
        static func header(count: Int) -> String {
            "\(count) active \(count == 1 ? "project" : "projects")"
        }

        static let add = "Start a project…"
        static let steps = "First steps, one per line"
        static let start = "Start"
        static let addStep = "Add a step…"
        static let empty = "No projects yet."
        static let deleteProject = "Delete project"
        /// "1/5"
        static func progress(done: Int, total: Int) -> String {
            "\(done)/\(total)"
        }

        /// VoiceOver, on a project card: "1 of 5 steps done", then what a tap does.
        static func stepsDone(done: Int, total: Int) -> String {
            "\(done) of \(total) \(total == 1 ? "step" : "steps") done"
        }

        static let showSteps = "Shows the steps"
        static let hideSteps = "Hides the steps"
        /// VoiceOver, on a step: its state, and what a tap does to it.
        static let stepDone = "Done"
        static let stepNotDone = "Not done"
        static let markDone = "Marks it done"
        static let markNotDone = "Marks it not done"
    }

    /// The two people. Reached through `Person.displayName`, never spelled out in a screen.
    enum People {
        static let anne = "Anne"
        static let wes = "Wes"
    }

    /// The Tasks tab: the header, each person's section, the states, and the gear menu.
    enum Tasks {
        /// The screen's own title, under the date.
        static let today = "Today"
        /// The count on a person's section header: "12 DUE".
        static func due(_ count: Int) -> String {
            "\(count) DUE"
        }

        /// Tag on the paired person's own section, so you can tell the two apart at a glance.
        static let you = "YOU"

        /// A person's section when nothing is due and nothing was checked off today.
        static let nothingDue = "Nothing due today"
        /// A person's section once everything they owed today is checked off.
        static let nothingLeft = "Nothing left"
        /// Under the escalation copy from three days late: the other phone shows it too, and from five
        /// days the server pushes it there.
        static let onTheOtherPhone = "On the other phone too"

        /// Gear menu, in order.
        static let allChores = "All chores"
        static let pairing = "Pairing…"
        static let syncNow = "Sync now"
        /// VoiceOver name for the gear button itself.
        static let settings = "Settings"

        /// Not paired: one line under the header pointing at the gear menu's Pairing item.
        static let notPaired = "Not paired yet · gear menu → Pairing"
        static let syncing = "Syncing…"
        /// The last sync failed, or the server could not be reached. Never a modal: offline is normal here.
        static func offline(_ lastSynced: String) -> String {
            "Offline · last synced \(lastSynced)"
        }

        static func synced(_ lastSynced: String) -> String {
            "Synced \(lastSynced)"
        }

        static let neverSynced = "Not synced yet"
        static let justNow = "just now"
        static let never = "never"

        /// VoiceOver value for a row: what state it is in.
        static let stateDone = "Done"
        static let stateDueToday = "Due today"
        /// VoiceOver value for an overdue row: "3 days late".
        static func stateLate(_ days: Int) -> String {
            days == 1 ? "1 day late" : "\(days) days late"
        }

        /// VoiceOver hints: what the tap does.
        static let hintCheck = "Marks it done"
        static let hintUncheck = "Puts it back on today's list"
        /// VoiceOver label for the pinned badge.
        static func always(_ name: String) -> String {
            "Always \(name)"
        }
    }

    /// Gear → All chores: the whole seeded list, grouped by cadence.
    enum Chores {
        static let eyebrow = "HOUSEHOLD LIST"
        static func seeded(_ count: Int) -> String {
            "\(count) chores"
        }

        static func version(_ version: Int) -> String {
            "List version \(version)"
        }

        /// The count beside a cadence heading: "11 TASKS".
        static func tasks(_ count: Int) -> String {
            "\(count) TASKS"
        }

        static let daily = "Daily"
        static let weekly = "Weekly"
        static let biweekly = "Biweekly"
        static let monthly = "Monthly"
    }

    enum Streak {
        static let dayStreak = "day streak"
        static let ahead = "CURRENTLY AHEAD"
        static let versus = "VS"
        /// Eyebrow over the two-colour week bar.
        static let weekLabel = "TASKS DONE THIS WEEK"
        /// "Anne · 14   Wes · 11"
        static let tallySeparator = " · "
        static let tallyGap = "   "
    }

    /// Subtitle under an overdue row. Stage and category come from RoostCore; dueToday shows nothing.
    enum Escalation {
        /// 1–2 days late. The title is lowercased to read mid-sentence: "Still no scoop litter…"
        static func nudge(title: String) -> String {
            "Still no \(title.lowercasedFirst)…"
        }

        /// 3–4 days late, cat-care rows.
        static let pointedCat = "The cat has feelings about this."
        /// 3–4 days late, home rows.
        static let pointedHome = "Getting overdue."
        /// 5+ days late. The title is capitalized: "Scoop litter emergency"
        static func alert(title: String) -> String {
            "\(title.uppercasedFirst) emergency"
        }
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
        static func dueToday(_ count: Int) -> String {
            "\(count) \(dueTodayLabel)"
        }

        /// The stage label on an overdue card. Shared with the Tasks tab's badge.
        static func daysLate(_ days: Int) -> String {
            Strings.daysLate(days)
        }

        /// Under a name when this person has nothing overdue but the other one does.
        static let columnClear = "Nothing overdue."
        /// The one calm line when nobody has anything overdue.
        static let caughtUp = "All caught up."
        /// Bottom line, from the coordinator's last successful sync.
        static func synced(_ relative: String) -> String {
            "Synced \(relative)"
        }

        static let syncedJustNow = "Synced just now"
        static let neverSynced = "Not synced yet"
    }
}

extension String {
    /// "Scoop litter" -> "scoop litter", but an acronym keeps its case: "PM wet cat food" stays as it is.
    var lowercasedFirst: String {
        guard let first, first.isUppercase else { return self }
        if let second = dropFirst().first, second.isUppercase {
            return self
        }
        return first.lowercased() + dropFirst()
    }

    var uppercasedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
