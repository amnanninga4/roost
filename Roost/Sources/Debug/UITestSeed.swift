// The store a UI test launches into. DEBUG only — the whole file is compiled out of a release build.
//
// `xcrun simctl launch booted xyz.hinescreative.roost -roostUITestState paired`, or from XCUITest:
//
//     app.launchArguments += ["-roostUITestState", "paired"]
//
// A leading-dash launch argument lands in UserDefaults, so there is nothing to parse. What the argument
// buys is a phone that needs no server: an in-memory store seeded with a fixed set of records, a fake
// identity in place of the Keychain's token, and `SyncState.baseURL` left nil — which is what "points
// sync at nothing" means here. `SyncClient.runOnce()` returns `.unpaired` on that nil before it builds a
// request, so a UI test never waits on a network call and never reaches the real server. That is a
// guarantee, not a timeout: there is no URL to reach.
//
// Every date is an offset from the start of today, so the same launch produces the same screen on any
// day. Daily chores pinned to a person make the ladder deterministic too: a chore last done N days ago
// is N-1 days overdue, so 6 days ago is the 5-day alert, 4 is the 3-day nudge-past-nudge, 2 is one day
// late, 1 is due today, and today is a row that is already checked off.
#if DEBUG
    import Foundation
    import RoostCore
    import SwiftData

    /// Which fixture `-roostUITestState <name>` asked for.
    enum UITestSeed: String, CaseIterable {
        /// No token: `RootGate` shows the first-run flow.
        case onboarding
        /// Paired as Anne, with the escalation ladder and a few rows on each list tab.
        case paired
        /// `paired`, plus 200 shopping items — the scroll-performance fixture.
        case shoppingLarge = "shopping-large"
        /// `paired`, plus one quarterly chore with a dueDay so All chores can show a window line.
        case pairedWindows = "paired-windows"

        /// `-roostUITestState <name>`.
        static let launchArgumentName = "roostUITestState"

        /// The fixture this process was launched with, if any.
        static var current: UITestSeed? {
            UserDefaults.standard.string(forKey: launchArgumentName)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap(UITestSeed.init(rawValue:))
        }

        /// The token `SyncCoordinator` reads to decide whether onboarding is still owed. In memory, so a
        /// test never touches — or leaves anything in — the simulator's Keychain.
        var tokenStore: TokenStore {
            InMemoryTokenStore(self == .onboarding ? nil : "roost-uitest-token")
        }

        /// A fresh in-memory store with this fixture in it. On the main actor, because seeding goes through
        /// the container's `mainContext` — the same context the app's views write through.
        @MainActor
        func makeContainer() -> ModelContainer {
            // Launch reset: every fixture starts with the streak card collapsed.
            UserDefaults.standard.removeObject(forKey: "roost.today.streakExpanded")
            let container: ModelContainer
            do {
                container = try ModelContainer(
                    for: RoostSchema.schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("Roost: could not open the UI-test store: \(error)")
            }
            do {
                try seed(into: container.mainContext)
            } catch {
                fatalError("Roost: could not seed the UI-test store: \(error)")
            }
            return container
        }

        // MARK: - the fixture

        @MainActor
        private func seed(into context: ModelContext) throws {
            let calendar = HouseholdCalendar()
            let today = calendar.startOfDay(Date())
            /// Noon, so a completion sits inside its day whatever the device's time zone does.
            func day(_ offset: Int) -> Date {
                calendar.adding(days: offset, to: today).addingTimeInterval(12 * 60 * 60)
            }

            var choreList = Self.chores
            var seededCompletions = Self.completions
            if self == .pairedWindows {
                choreList = ChoreList(version: choreList.version, chores: choreList.chores + [
                    Chore(id: "uitest-deep-clean", title: "Deep-clean the fridge", cadence: .quarterly,
                          category: .chore, dueDay: 28),
                ])
                // Anne completed it today so Today never shows it, whatever the real date.
                seededCompletions.append(SeededCompletion(choreId: "uitest-deep-clean", person: .anne, daysAgo: 0))
            }
            try ChoreSeeder.seed(choreList, into: context)

            let state = try ChoreSeeder.syncState(in: context)
            // `person` without `baseURL` is the whole trick: the app knows who it is, and the sync pass has
            // nowhere to go.
            state.person = self == .onboarding ? nil : Person.anne.rawValue
            state.baseURL = nil
            state.activeFrom = calendar.adding(days: -Self.historyDays, to: today)
            state.cursor = 0

            guard self != .onboarding else {
                try context.save()
                return
            }

            for (index, seeded) in seededCompletions.enumerated() {
                let record = CompletionRecord(
                    id: "uitest-completion-\(index)",
                    choreId: seeded.choreId,
                    person: seeded.person.rawValue,
                    completedAt: day(seeded.daysAgo * -1),
                    syncedAt: day(seeded.daysAgo * -1)
                )
                context.insert(record)
            }

            seedHandoffs(into: context, day: day, calendar: calendar)
            seedShopping(into: context, day: day)
            seedWishlist(into: context, day: day)
            seedMeals(into: context, day: day)
            seedProjects(into: context, day: day)
            try context.save()
        }

        /// The three handoff states a row can be in, so the Tasks tab's audit sees all of them: the offer
        /// card waiting for Anne's answer, the "FROM WES" chip on a turn she took, and the one-line note
        /// after a no.
        ///
        /// The period a handoff names has to be the chore's oldest incomplete one, because that is the
        /// period the row on screen is about. A pending offer also has to be for the *current* period —
        /// `Handoff.hasExpired` retires a pending offer the moment its period ends — while accepted and
        /// declined stand for good, which is why those two sit on chores that are already overdue.
        @MainActor
        private func seedHandoffs(into context: ModelContext, day: (Int) -> Date, calendar: HouseholdCalendar) {
            for (index, offer) in Self.handoffs.enumerated() {
                let record = HandoffRecord(
                    id: "uitest-handoff-\(index)",
                    choreId: offer.choreId,
                    fromPerson: offer.from.rawValue,
                    toPerson: offer.to.rawValue,
                    periodIndex: calendar.periodIndex(.daily, containing: day(offer.periodDaysAgo * -1)),
                    cadence: Cadence.daily.rawValue,
                    state: offer.state.rawValue,
                    createdAt: day(offer.periodDaysAgo * -1),
                    // Unsynced for the one offer still on this phone, so the row can offer Withdraw;
                    // synced for the rest, so nothing is queued that the fixture cannot honour.
                    syncedAt: offer.synced ? day(offer.periodDaysAgo * -1) : nil
                )
                context.insert(record)
            }
        }

        @MainActor
        private func seedShopping(into context: ModelContext, day: (Int) -> Date) {
            for (index, item) in Self.shopping.enumerated() {
                let record = ShoppingItemRecord(
                    id: "uitest-shopping-\(index)",
                    title: item.title,
                    addedBy: item.addedBy.rawValue,
                    bought: item.bought,
                    boughtBy: item.bought ? item.addedBy.rawValue : nil,
                    boughtAt: item.bought ? day(-1) : nil,
                    // Reversed, because the screen sorts newest first and the fixture reads top to bottom.
                    createdAt: day(-1).addingTimeInterval(Double(Self.shopping.count - index)),
                    syncedAt: day(-1)
                )
                record.rejected = item.rejected
                context.insert(record)
            }
            guard self == .shoppingLarge else { return }
            for index in 0 ..< Self.longListLength {
                let record = ShoppingItemRecord(
                    id: "uitest-bulk-\(index)",
                    title: Self.bulkTitle(index),
                    addedBy: (index.isMultiple(of: 2) ? Person.anne : Person.wes).rawValue,
                    createdAt: day(-2).addingTimeInterval(Double(Self.longListLength - index)),
                    syncedAt: day(-2)
                )
                context.insert(record)
            }
        }

        @MainActor
        private func seedWishlist(into context: ModelContext, day: (Int) -> Date) {
            for (index, item) in Self.wishlist.enumerated() {
                let record = WishlistItemRecord(
                    id: "uitest-wishlist-\(index)",
                    title: item.title,
                    priceCents: item.priceCents,
                    addedBy: item.addedBy.rawValue,
                    createdAt: day(-1).addingTimeInterval(Double(Self.wishlist.count - index)),
                    syncedAt: day(-1)
                )
                context.insert(record)
            }
        }

        @MainActor
        private func seedMeals(into context: ModelContext, day: (Int) -> Date) {
            for (index, meal) in Self.meals.enumerated() {
                let record = MealRecord(
                    id: "uitest-meal-\(index)",
                    title: meal.title,
                    tag: meal.tag,
                    lastMadeAt: meal.lastMadeDaysAgo.map { day($0 * -1) },
                    nextUp: meal.nextUp,
                    createdAt: day(-1).addingTimeInterval(Double(Self.meals.count - index)),
                    syncedAt: day(-1)
                )
                record.rejected = meal.rejected
                context.insert(record)
            }
        }

        @MainActor
        private func seedProjects(into context: ModelContext, day: (Int) -> Date) {
            for (index, project) in Self.projects.enumerated() {
                let id = "uitest-project-\(index)"
                let record = ProjectRecord(
                    id: id,
                    title: project.title,
                    dueOn: project.dueInDays.map { ProjectDates.dayString(day($0)) },
                    createdAt: day(-1).addingTimeInterval(Double(Self.projects.count - index)),
                    syncedAt: day(-1)
                )
                context.insert(record)
                for (stepIndex, step) in project.steps.enumerated() {
                    let subtask = SubtaskRecord(
                        id: "\(id)-step-\(stepIndex)",
                        projectId: id,
                        title: step.title,
                        sortOrder: stepIndex,
                        assignee: step.assignee?.rawValue,
                        done: step.done,
                        doneBy: step.done ? Person.anne.rawValue : nil,
                        doneAt: step.done ? day(-1) : nil,
                        createdAt: day(-1),
                        syncedAt: day(-1)
                    )
                    context.insert(subtask)
                }
            }
        }
    }

    // MARK: - the rows themselves

    extension UITestSeed {
        /// How far back the household has been running. Eight days is one day older than the oldest
        /// completion, so no chore is due for a period before the household existed.
        static let historyDays = 8
        /// The scroll fixture's length. Two hundred rows is more than either of them will ever have on the
        /// list and enough that a non-lazy stack would show up as a hitch.
        static let longListLength = 200

        /// Ten daily chores. Nine are pinned, so which column a row lands in never depends on the date;
        /// the tenth is unpinned, which is the row style that carries no name chip.
        static var chores: ChoreList {
            ChoreList(version: 1, chores: [
                Chore(id: "uitest-litter", title: "Scoop the litter box", cadence: .daily,
                      fixedAssignee: .anne, category: .catCare),
                Chore(id: "uitest-cat-water", title: "Refill the cat water", cadence: .daily,
                      fixedAssignee: .anne, category: .catCare),
                Chore(id: "uitest-feed-cat", title: "Feed the cat", cadence: .daily,
                      fixedAssignee: .anne, category: .catCare),
                Chore(id: "uitest-dishwasher", title: "Run the dishwasher", cadence: .daily,
                      fixedAssignee: .anne, category: .chore),
                Chore(id: "uitest-counters", title: "Wipe down the kitchen counters and the bathroom mirror",
                      cadence: .daily, fixedAssignee: .anne, category: .chore),
                Chore(id: "uitest-plants", title: "Water the plants", cadence: .daily,
                      fixedAssignee: .anne, category: .chore),
                Chore(id: "uitest-trash", title: "Take the trash out", cadence: .daily,
                      fixedAssignee: .wes, category: .chore),
                Chore(id: "uitest-brush-cat", title: "Brush the cat", cadence: .daily,
                      fixedAssignee: .wes, category: .catCare),
                Chore(id: "uitest-laundry", title: "Start a load of laundry", cadence: .daily,
                      fixedAssignee: .wes, category: .chore),
                Chore(id: "uitest-sweep", title: "Sweep the floors", cadence: .daily,
                      fixedAssignee: .wes, category: .chore),
                Chore(id: "uitest-mail", title: "Bring the mail in", cadence: .daily, category: .chore),
            ])
        }

        struct SeededCompletion {
            let choreId: String
            let person: Person
            /// Whole days before today. A chore last done N days ago is N-1 days overdue, so this is the
            /// dial that puts a row on a particular rung of the escalation ladder.
            let daysAgo: Int
        }

        /// One row per rung, for each of them: 5 days late, 3 days late, 1 day late, due today, and done.
        static var completions: [SeededCompletion] {
            [
                SeededCompletion(choreId: "uitest-litter", person: .anne, daysAgo: 6),
                SeededCompletion(choreId: "uitest-cat-water", person: .anne, daysAgo: 4),
                // Done yesterday, so today's period is open and nobody has offered it: the one row on
                // Anne's card the menu and the trailing swipe can hand off.
                SeededCompletion(choreId: "uitest-feed-cat", person: .anne, daysAgo: 1),
                SeededCompletion(choreId: "uitest-dishwasher", person: .anne, daysAgo: 2),
                SeededCompletion(choreId: "uitest-counters", person: .anne, daysAgo: 1),
                SeededCompletion(choreId: "uitest-plants", person: .anne, daysAgo: 0),
                SeededCompletion(choreId: "uitest-trash", person: .wes, daysAgo: 6),
                SeededCompletion(choreId: "uitest-brush-cat", person: .wes, daysAgo: 2),
                SeededCompletion(choreId: "uitest-laundry", person: .wes, daysAgo: 1),
                SeededCompletion(choreId: "uitest-sweep", person: .wes, daysAgo: 0),
                SeededCompletion(choreId: "uitest-mail", person: .wes, daysAgo: 2),
            ]
        }

        struct SeededHandoff {
            let choreId: String
            let from: Person
            let to: Person
            /// The period, as whole days before today. It must be the chore's oldest incomplete period:
            /// that is the period the row on screen is about.
            let periodDaysAgo: Int
            let state: Handoff.State
            var synced = true
        }

        /// One of each live state, all on daily chores so a period is a day, plus one unsynced pending
        /// offer so the row menu can show Withdraw:
        ///
        ///  - `uitest-laundry` is Wes's and due today, so a pending offer to Anne is still inside its
        ///    period: Anne gets the card, and Wes's row reads "Asked Anne".
        ///  - `uitest-trash` is Wes's and five days late; an accepted turn never expires, so the row moves
        ///    into Anne's column wearing the "FROM WES" chip.
        ///  - `uitest-cat-water` is Anne's and three days late; a declined offer never expires either, so
        ///    her row carries the "Wes said no" line.
        ///  - `uitest-counters` is Anne's, due today, offered to Wes a moment ago and not yet synced: the
        ///    one state that can still be taken back.
        static var handoffs: [SeededHandoff] {
            [
                SeededHandoff(choreId: "uitest-laundry", from: .wes, to: .anne, periodDaysAgo: 0, state: .pending),
                SeededHandoff(choreId: "uitest-trash", from: .wes, to: .anne, periodDaysAgo: 5, state: .accepted),
                SeededHandoff(choreId: "uitest-cat-water", from: .anne, to: .wes, periodDaysAgo: 3, state: .declined),
                // Anne's, due today, offered to Wes a moment ago and not yet synced: the one state
                // that can still be taken back, so the row menu gets to show Withdraw.
                SeededHandoff(choreId: "uitest-counters", from: .anne, to: .wes, periodDaysAgo: 0,
                              state: .pending, synced: false),
            ]
        }

        struct SeededShoppingItem {
            let title: String
            let addedBy: Person
            var bought = false
            var rejected = false
        }

        /// Four rows: three still to buy — one of them refused by the server, so the "Didn't sync" marker
        /// is on screen — over a Bought section, which is what brings "Clear bought" with it.
        static var shopping: [SeededShoppingItem] {
            [
                SeededShoppingItem(title: "Cat litter", addedBy: .anne),
                SeededShoppingItem(title: "Oat milk", addedBy: .wes),
                SeededShoppingItem(title: "Dish soap", addedBy: .anne, rejected: true),
                SeededShoppingItem(title: "Coffee beans", addedBy: .wes, bought: true),
            ]
        }

        /// Every fifth row is long enough to wrap, so the scroll fixture has uneven row heights rather than
        /// two hundred identical ones.
        static func bulkTitle(_ index: Int) -> String {
            let number = String(format: "%03d", index + 1)
            return index.isMultiple(of: 5)
                ? "Item \(number) — the long one, so the row wraps onto a second line"
                : "Item \(number)"
        }

        struct SeededWishlistItem {
            let title: String
            let addedBy: Person
            var priceCents: Int?
        }

        /// Two rows: one with a price, so the chip and the header total are on screen, and one without.
        static var wishlist: [SeededWishlistItem] {
            [
                SeededWishlistItem(title: "Bigger TV", addedBy: .anne, priceCents: 59900),
                SeededWishlistItem(title: "A weekend away", addedBy: .wes),
            ]
        }

        struct SeededMeal {
            let title: String
            var tag = ""
            var lastMadeDaysAgo: Int?
            var nextUp = false
            var rejected = false
        }

        /// One marked NEXT UP, two with a "last made" line (a weekday and a date), one the server refused.
        static var meals: [SeededMeal] {
            [
                SeededMeal(title: "Sheet pan chicken", tag: "Weeknight", nextUp: true),
                SeededMeal(title: "Black bean tacos", tag: "Fast", lastMadeDaysAgo: 3),
                SeededMeal(title: "Roast and potatoes", tag: "Sunday", lastMadeDaysAgo: 9),
                SeededMeal(title: "Soup and bread", rejected: true),
            ]
        }

        struct SeededStep {
            let title: String
            var done = false
            var assignee: Person?
        }

        struct SeededProject {
            let title: String
            let steps: [SeededStep]
            var dueInDays: Int?
        }

        /// The finished card is newest, so the screen's "open the first one" rule puts the DONE chip, the
        /// full bar, and the Archive row on screen without a tap; the other card is one tap away at 2 of 4,
        /// due in three days, with one step that is Wes's.
        static var projects: [SeededProject] {
            [
                SeededProject(title: "Hang the shelves", steps: [
                    SeededStep(title: "Find the studs", done: true),
                    SeededStep(title: "Drill and mount", done: true),
                ]),
                SeededProject(title: "Clear out the garage", steps: [
                    SeededStep(title: "Sort the boxes", done: true),
                    SeededStep(title: "Book the dump run", done: true),
                    SeededStep(title: "Shelve what stays", assignee: .wes),
                    SeededStep(title: "Sweep it out"),
                ], dueInDays: 3),
            ]
        }
    }
#endif
