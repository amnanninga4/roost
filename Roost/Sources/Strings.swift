// Every user-facing string in the app, in one place so Anne can edit the copy without touching a screen.
// Functions take a title or a count; edit the text inside the quotes and keep the \(...) where the value goes.
import Foundation

// swiftlint:disable:next type_body_length - one enum per screen is the point of this file; it grows with the app.
enum Strings {
    /// The bar title on every tab.
    static let appTitle = "Roost"

    /// "1 DAY LATE" / "3 DAYS LATE". Shared with the widget via `RoostCopy` in Shared/.
    static func daysLate(_ days: Int) -> String {
        RoostCopy.daysLate(days)
    }

    enum Tabs {
        static let tasks = "Tasks"
        static let lists = "Lists"
        static let more = "More"
        /// The four pages under Lists; each page's header prints its own name.
        static let shopping = "Shopping"
        static let meals = "Meals"
        static let projects = "Projects"
        static let wishlist = "Wishlist"
    }

    /// The Home tab's own words. The app does not greet: every line here names a thing.
    /// Anne edits this file directly, so nothing in it may be assembled from fragments
    /// elsewhere — a sentence that only exists at runtime is a sentence she cannot change.
    enum Home {
        /// The tab's title in the bar.
        static let title = "Home"

        /// The two segments inside the Home tab.
        static let segmentHome = "Home"
        static let segmentBoard = "Anne & Wes"
        /// What the segments show at accessibility text sizes, where the words no longer fit.
        static let segmentHomeSymbol = "house"
        static let segmentBoardSymbol = "person.2"

        /// The orientation sentence, in place of the word "Today". Four states, in the order
        /// the screen checks them.
        /// Both people still owe something: "5 for you, 4 for Anne."
        static func split(_ mine: Int, _ theirs: Int, other: String) -> String {
            "\(mine) for you, \(theirs) for \(other)."
        }

        /// This phone is clear, the other person is not: "Nothing left for you. Anne still has 4."
        static func clearForYou(_ theirs: Int, other: String) -> String {
            "Nothing left for you. \(other) still has \(theirs)."
        }

        /// Both clear, and something was checked off today.
        static let allCaught = "All caught up."

        /// Nothing is owed by anybody — a fresh household, or a day with no window open.
        /// Deliberately the same words the empty column already uses.
        static let nothingDue = "Nothing due today"

        /// The other person as one line, tapping through to the board.
        static func otherStillHas(_ count: Int, other: String) -> String {
            "\(other) still has \(count)"
        }

        /// The collapse control under a long list of rows: "3 more".
        static func more(_ count: Int) -> String {
            "\(count) more"
        }

        /// Collapses an expanded list again.
        static let showLess = "Show less"

        static let overdue = "Overdue"
        static let today = "Today"
        static let ifYouHaveTime = "If you have time"

        static func left(_ count: Int) -> String {
            "\(count) left"
        }

        static func daysLate(_ days: Int) -> String {
            "\(days)d late"
        }

        /// VoiceOver on a matchup header: opens that person's own page.
        static let openPerson = "Opens their day"

        /// VoiceOver for the collapse control, which must say what it does, not just how many.
        static func moreHint(_ count: Int) -> String {
            count == 1 ? "Shows 1 more chore" : "Shows \(count) more chores"
        }
    }

    /// The More tab: what the gear menu held, as a page.
    enum More {
        /// Section headers, in the mono eyebrow like Settings', so written in caps here.
        static let household = "HOUSEHOLD"
        static let thisPhone = "THIS PHONE"
    }

    /// Shared by the four list pages.
    enum Lists {
        static let delete = "Delete"
        /// The swipe action on a row the server refused: it never reached the server, so nothing is deleted there.
        static let remove = "Remove"
        /// Joins the parts of a meta line: "Weeknight · last made Jul 20"
        static let metaSeparator = " · "
        /// VoiceOver, on the small avatar: "Added by Anne"
        static func addedBy(_ name: String) -> String {
            "Added by \(name)"
        }

        /// The marker on a row the server refused. Plain: it is not an error the reader can fix by retrying.
        static let didNotSync = "Didn't sync"
        /// VoiceOver, appended to such a row's value.
        static let didNotSyncValue = "Didn't sync"

        /// The floating bar after a swipe-delete, for the five seconds it can be taken back.
        static let undo = "Undo"
        /// "Bread removed"
        static func removed(_ title: String) -> String {
            "\(title) removed"
        }

        /// "3 items removed", after Clear bought.
        static func removedCount(_ count: Int) -> String {
            "\(count) \(count == 1 ? "item" : "items") removed"
        }

        /// VoiceOver, on the undo bar.
        static let undoHint = "Puts it back"
        /// VoiceOver, on the composer's text field.
        static let composerHint = "Return adds it and keeps the keyboard up"
        /// The row menu's first item: retitle (and reprice, on the wishlist) in a small sheet.
        static let edit = "Edit"
        /// The edit sheet's confirming button.
        static let save = "Save"
    }

    enum Shopping {
        /// "10 items · 2 already bought"
        static func header(items: Int, bought: Int) -> String {
            "\(items) \(items == 1 ? "item" : "items")\(Lists.metaSeparator)\(bought) already bought"
        }

        static let add = "Add an item…"
        static let empty = "Nothing on the list."
        /// Under the empty line: what to do about it.
        static let emptyHint = "Type what you need above."
        /// The section the ticked rows sink into.
        static let boughtSection = "Bought"
        /// Clears that section: the rows are removed, with five seconds to take it back.
        static let clearBought = "Clear bought"
        /// VoiceOver: a row's state, and what a tap does to it.
        static let bought = "Bought"
        static let stillNeeded = "Still needed"
        static let markBought = "Marks it bought"
        static let markStillNeeded = "Marks it still needed"
        /// The edit sheet's title.
        static let editItem = "Edit item"
    }

    enum Wishlist {
        /// "4 items · $1,850 total"; with nothing priced, just "4 items".
        static func header(items: Int, total: String?) -> String {
            let count = "\(items) \(items == 1 ? "item" : "items")"
            guard let total else { return count }
            return "\(count)\(Lists.metaSeparator)\(total) total"
        }

        static let add = "Add something you'd like…"
        /// The second field under the title: dollars, cents optional.
        static let price = "Price, like 599"
        static let empty = "Nothing on the wishlist."
        /// Under the empty line: what to do about it.
        static let emptyHint = "Add the things you'd buy some day."
        static let boughtSection = "Bought"
        static let clearBought = "Clear bought"
        /// VoiceOver: a row's state, and what a tap does to it.
        static let bought = "Bought"
        static let stillWanted = "Still wanted"
        static let markBought = "Marks it bought"
        static let markStillWanted = "Marks it still wanted"
        /// The edit sheet's title.
        static let editItem = "Edit item"
        /// VoiceOver, after the state: "priced $599".
        static func priced(_ price: String) -> String {
            "priced \(price)"
        }
    }

    enum Meals {
        /// "8 saved ideas"
        static func header(count: Int) -> String {
            "\(count) saved \(count == 1 ? "idea" : "ideas")"
        }

        static let add = "Add an idea…"
        static let tag = "Tag, like Weeknight"
        static let empty = "No ideas saved yet."
        /// Under the empty line: what to do about it.
        static let emptyHint = "Save something you both like."
        /// The badge on the meal that is next up.
        static let nextUpBadge = "NEXT UP"
        /// Swipe action / context menu.
        static let nextUp = "Next up"
        static let clearNextUp = "Clear next up"
        /// The action that stamps today's date on a meal. Shorter than the sentence it used to be.
        static let madeIt = "Made it"
        /// "last made Jul 20" / "last made Tuesday"; `MealDates` picks the wording of the date part.
        static func lastMade(_ when: String) -> String {
            "last made \(when)"
        }

        /// The two recent days get a word instead of a date.
        static let today = "today"
        static let yesterday = "yesterday"
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
        /// Under the empty line: what to do about it.
        static let emptyHint = "Name one and list its first steps."
        static let deleteProject = "Delete project"
        /// The chip on a card whose every step is done.
        static let doneChip = "DONE"
        /// What to do with a finished project: it leaves the list without losing anything.
        static let archive = "Archive"
        /// VoiceOver, on a finished card, before the step count.
        static let finished = "Finished"
        /// VoiceOver actions on a step, because the drag handle is a gesture it cannot make.
        static let moveUp = "Move up"
        static let moveDown = "Move down"
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

        /// On a card with a due day: "Due Sep 20".
        static func due(_ day: String) -> String {
            "Due \(day)"
        }

        /// The card's menu.
        static let setDueDay = "Set a due day"
        static let changeDueDay = "Change the due day"
        static let clearDueDay = "Clear the due day"
        /// The picker sheet's title and its confirming button.
        static let dueDayPicker = "Due day"
        static let dueDayDone = "Done"
        /// VoiceOver, on a card whose day has passed.
        static let pastDue = "Past due"

        /// The owner picker on a step and in the step composer.
        static let owner = "Owner"
        static let nobody = "Nobody"
        /// VoiceOver, on an owned step: "For Wes".
        static func ownedBy(_ name: String) -> String {
            "For \(name)"
        }

        /// The morning-of reminder's body.
        static func dueToday(_ title: String) -> String {
            "\(title) is due today"
        }
    }

    /// The two people. Reached through `Person.displayName`, never spelled out in a screen.
    enum People {
        static let anne = "Anne"
        static let wes = "Wes"
    }

    /// The Tasks tab: the header, each person's section, and the states.
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
        /// The More page's rows. Settings is `Strings.Settings.title`, which the screen itself owns.
        static let allChores = "All chores"
        static let syncNow = "Sync now"

        /// Not paired: one line under the header pointing at the More tab's Settings row, where
        /// "Paired as" lives. A phone with a token but no person yet sees this.
        static let notPaired = "Not paired yet · More → Settings"
        /// The last sync failed, or the server could not be reached. Never a modal: offline is normal
        /// here. `synced` is `SyncStatusCopy`'s own phrase — "Synced just now", "Synced 5 min. ago" —
        /// so this screen never words "when" differently from the rest of the app.
        static func offline(_ synced: String) -> String {
            "\(synced) · offline, will retry"
        }

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

        /// The chip on a together chore, where a pinned chore wears its person's name.
        static let together = "TOGETHER"
        /// VoiceOver value for a together row, after the state.
        static let togetherValue = "Both of you"
        /// The long-press menu's last item: opens More → All chores.
        static let showInAllChores = "Show in All chores"
        /// The preview card's first fact: "For Anne".
        static func forPerson(_ name: String) -> String {
            "For \(name)"
        }
    }

    /// Handing a turn over: the ask, the wait, the answer. One period at a time, never a rule change.
    /// The period phrases (today / this week / this month / these two months / this quarter) match
    /// `PERIOD_PHRASES` in `server/src/push.js`, so the phone and the notification say the same thing.
    enum Handoffs {
        /// The context-menu item on your own row: "Ask Wes to take this".
        static func ask(_ name: String) -> String {
            "Ask \(name) to take this"
        }

        /// The one confirmation, before anything is sent. "Ask Wes to take Laundry this week?"
        static func confirmTitle(_ name: String, chore: String, period: String) -> String {
            "Ask \(name) to take \(chore) \(period)?"
        }

        /// The confirming button: "Ask Wes".
        static func confirmAction(_ name: String) -> String {
            "Ask \(name)"
        }

        /// On your row while nobody has answered: "Asked Wes · waiting".
        static func waiting(_ name: String) -> String {
            "Asked \(name)\(Lists.metaSeparator)waiting"
        }

        /// Taking the ask back, offered only while it is still on this phone.
        static let withdraw = "Don't ask after all"

        /// The card in the other person's column: "Anne asked you to take Laundry this week".
        static func incoming(_ name: String, chore: String, period: String) -> String {
            "\(name) asked you to take \(chore) \(period)"
        }

        static let accept = "Accept"
        static let decline = "Decline"

        /// The chip on a row you took from the other person.
        static func from(_ name: String) -> String {
            "from \(name)"
        }

        /// They turned it down. Clears on your next check-off, or when the period ends.
        static func saidNo(_ name: String) -> String {
            "\(name) said no"
        }

        /// The server would not take the offer, and never will: the row is yours after all.
        static let refused = "Couldn't hand that off"

        /// Which period an offer covers, worded as the server's push words it (biweekly included).
        static let periodToday = "today"
        static let periodWeek = "this week"
        static let periodMonth = "this month"
        static let periodTwoMonths = "these two months"
        static let periodQuarter = "this quarter"
    }

    /// More → All chores: the whole seeded list, grouped by cadence.
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
        static let bimonthly = "Every two months"
        static let quarterly = "Every three months"
        /// Under a seasonal chore in All chores: "April to October".
        static func season(from: String, to: String) -> String {
            "\(from) to \(to)"
        }

        /// Under a weekly chore with a window in All chores: "Fri–Sat". A one-day window is the day alone.
        static func window(from: String, to: String) -> String {
            "\(from)–\(to)"
        }

        /// Under a monthly, bimonthly or quarterly chore in All chores: "by the 25th".
        static func windowBy(_ ordinal: String) -> String {
            "by the \(ordinal)"
        }
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
        /// The collapsed line's word for this phone's person.
        static let lineYou = "You"
        /// Between the two scores on the collapsed line.
        static let scoreSeparator = " — "
        /// The collapsed line's trailing clause: "12-day streak".
        static func lineStreak(_ days: Int) -> String {
            "\(days)-day streak"
        }

        /// VoiceOver hints on the collapsed line.
        static let expandHint = "Shows the full streak card"
        static let collapseHint = "Hides the streak card"
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

    /// Kitchen mode (More → Kitchen mode): the phone propped on the counter, both people at once.
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
        /// On the banner line of a together chore, where a person's name goes otherwise.
        static let together = "TOGETHER"
    }

    /// The one-line sync status under every tab header. `SyncStatusCopy` picks which of the
    /// "Synced …" forms to use; the wording lives here.
    enum Sync {
        static let syncing = "Syncing…"
        static let neverSynced = "Not synced yet"
        static let notPaired = "Not paired · More → Settings"
        /// The reason comes from the failure itself, so it is the server's or the system's words.
        static func offline(_ reason: String) -> String {
            "Offline · will retry (\(reason))"
        }

        /// Synced, but the phone did not keep when.
        static let synced = "Synced"
        /// A pass that has only just landed: a moment, not a measurement.
        static let syncedJustNow = "Synced just now"
        static func syncedSecondsAgo(_ seconds: Int) -> String {
            "Synced \(seconds) sec. ago"
        }

        static func syncedMinutesAgo(_ minutes: Int) -> String {
            "Synced \(minutes) min. ago"
        }

        /// An hour or more later a count stops helping and the clock time takes over.
        static func syncedAt(_ time: String) -> String {
            "Synced at \(time)"
        }
    }

    /// More → Settings. What this phone is paired to, and how to undo it.
    enum Settings {
        static let title = "Settings"

        /// Section headers are set in the mono eyebrow rung, the same as the onboarding screens, so they are
        /// written in caps here rather than uppercased at the view.
        static let phoneHeader = "THIS PHONE"
        static let pairedAs = "Paired as"
        static let device = "Device"
        static let notPaired = "Not paired"
        /// The date this phone traded a code for its token, from `GET /me`.
        static let pairedSince = "Paired since"
        /// A device from the tokens file has no pairing date, because nothing paired it.
        static let pairedHandMinted = "Set up by hand"

        static let appearanceHeader = "APPEARANCE"
        /// The picker's own label. It is the row's leading text at the accessibility sizes, where the
        /// segmented control gives way to a menu, and it is what VoiceOver reads either way.
        static let appearanceLabel = "Appearance"
        static let appearanceSystem = "System"
        static let appearanceLight = "Light"
        static let appearanceDark = "Dark"
        /// Two facts, both of which come up the first time somebody picks Dark: what System means, and why
        /// the Home Screen did not change with everything else.
        static let appearanceFooter = "System follows the phone's setting. The Home Screen widget always follows the phone."

        static let serverHeader = "SERVER"
        static let serverField = "Address"
        /// Debug builds only: the field is editable and the launch argument overrides everything.
        static let serverFooter = "Debug builds only. Launch with -roostServer http://127.0.0.1:8790, or change it here and pair again."

        static let syncHeader = "SYNC"
        static let lastSync = "Last sync"
        static let status = "Status"
        static let neverSynced = "Not synced yet"
        /// The state of the last pass, as one phrase. The time it happened is the row above.
        static let statusUpToDate = "Up to date"
        static let statusSyncing = "Syncing…"
        static let statusOffline = "Offline · will retry"

        static let cancel = "Cancel"
        static let unpair = "Unpair this phone"
        static let unpairFooter = "Roost forgets the token on this phone. You'll need a new code to pair again."
        static let unpairConfirmTitle = "Unpair this phone?"
        static let unpairConfirm = "Unpair"
        /// 403 from DELETE /pair/self: the token came from the tokens file, so only that file can revoke it.
        static let unpairHandMinted = "This phone was set up by hand, so the server keeps its token. Roost forgot it here; ask Wes to remove it from the tokens file."
        /// The server could not be reached, so its copy of the token may still work.
        static let unpairOffline = "Couldn't reach the server, so its copy of the token may still work. Roost forgot it on this phone."
        /// The heading over the note, after the fact.
        static let unpairNoticeTitle = "Unpaired"
        static let unpairNoticeAction = "Got it"

        /// "Roost 0.1.0 (1)"
        static func version(_ short: String, build: String) -> String {
            "Roost \(short) (\(build))"
        }
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
