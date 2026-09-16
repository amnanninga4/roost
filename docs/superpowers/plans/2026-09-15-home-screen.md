# Home Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tab one stops being the chore board and becomes Home — a place you arrive, showing your own checkable rows, the other person as one line, and doors into the rest of the house. The two-column board moves to the second segment of the same tab.

**Architecture:** `RootTab.tasks` is renamed `.home` and its screen becomes a new `HomeTabScreen` that owns a two-segment `RoostSegmentedControl` — `Home` and `Anne & Wes`. The existing `TodayScreen` becomes the second segment, unchanged except that its streak block moves out of the header. The sentence and door counts come from a new pure struct `HomeSummary`, so every string on the screen is testable without a simulator.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 26 deployment target. Local packages `RoostCore` (scheduling) and `RoostDesign` (tokens). XcodeGen generates the project.

**Spec:** `docs/superpowers/specs/2026-09-15-home-screen-design.md` — read it before Task 1. It carries the measurement and the trade this plan implements.

## Global Constraints

- User-facing strings live **only** in `Roost/Sources/Strings.swift`. Never inline a literal in a view.
- Plain wording, no marketing copy. The app does not greet — it names the thing. `Good morning`, `Welcome back`, `at a glance`, `Let's` are all out of bounds.
- Never hand-edit `Roost/Roost.xcodeproj/project.pbxproj`. Edit `Roost/project.yml` and run `xcodegen generate` from `Roost/`.
- `main` takes pull requests only. Rebase onto current `main` before opening one.
- No secrets in the repo: no Team ID, certificates, provisioning profiles, APNs keys, device tokens, or device UDIDs.
- Prefer native SwiftUI APIs over dependencies. The only approved third-party UI dependency is ConfettiSwiftUI.
- Every `@State` property is `private`. `.animation(_:value:)` always carries its `value`. `ForEach` uses stable identity, never `.indices`.
- Minimum tap target is 44 pt. Every tappable element is a `Button`, not a tappable `HStack`.
- Before calling app work done: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test` prints `** TEST SUCCEEDED **`.
- **Never run two `xcodebuild` test runs concurrently on this Mac.** Another agent shares the simulator. Serialize.
- **Pin `OS=26.3.1` in every destination.** This Mac now has two iOS runtimes, 26.3 and 27.0. `OS:latest` resolves to 27.0, which has no `iPhone 17 Pro`, so an unpinned destination fails with "Unable to find a device matching the provided destination specifier" — a red run that has nothing to do with the diff. Found by Apple-Dev-3 on 2026-09-15. Note that `CLAUDE.md`'s own verification command is still unpinned and will fail here; that is a separate change, and CI (Xcode 26.6) is unaffected.

---

## File Structure

| File | Responsibility |
|---|---|
| `Roost/Sources/Models/HomeSummary.swift` | **New.** Pure struct: the orientation sentence, this phone's rows, the other person's count, the four door counts. No SwiftUI. |
| `Roost/Sources/Screens/HomeTabScreen.swift` | **New.** Owns the segmented control and switches between `HomeScreen` and `TodayScreen`. |
| `Roost/Sources/Screens/HomeScreen.swift` | **New.** The arrival screen: eyebrow, sentence, your rows, the other person's line, the doors. |
| `Roost/Sources/Home/HomeDoorsView.swift` | **New.** The four doors as one extracted subview. |
| `Roost/Sources/Home/HomeRowsView.swift` | **New.** This phone's rows plus the collapse behaviour. |
| `Roost/Sources/Root/RootTabView.swift` | Modify: `tasks` → `home`, and the segment selection on `RootNavigation`. |
| `Roost/Sources/Screens/TodayScreen.swift` | Modify: becomes the board segment; loses the streak block from its header. |
| `Roost/Sources/Tasks/TodayHeaderView.swift` | Modify: streak block moves out; the date eyebrow stays. |
| `Roost/Sources/Strings.swift` | Modify: the sentence, the doors, the collapse line, the segment titles. |
| `Roost/Tests/HomeSummaryTests.swift` | **New.** Every sentence state, every count. |
| `Roost/UITests/HomeScreenUITests.swift` | **New.** Arrival, segment switch, collapse. |

---

## Task 1: Strings for Home

**Files:**
- Modify: `Roost/Sources/Strings.swift`
- Test: none (strings are exercised by Task 2's tests)

**Interfaces:**
- Produces: `Strings.Home.*` — every literal the Home screen needs.

- [ ] **Step 1: Add the `Home` enum to `Strings.swift`**

Add this immediately after the existing `enum Tabs { ... }` block:

```swift
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

        /// VoiceOver for the collapse control, which must say what it does, not just how many.
        static func moreHint(_ count: Int) -> String {
            count == 1 ? "Shows 1 more chore" : "Shows \(count) more chores"
        }
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `cd Packages/RoostCore && swift build 2>&1 | tail -3 && cd ../.. && swiftformat --lint Roost/Sources/Strings.swift && swiftlint lint --quiet Roost/Sources/Strings.swift`

Expected: no output from swiftformat or swiftlint (both silent on success).

- [ ] **Step 3: Commit**

```bash
git add Roost/Sources/Strings.swift
git commit -m "strings: the Home tab's words"
```

---

## Task 2: HomeSummary — the sentence and the counts, as pure logic

**Files:**
- Create: `Roost/Sources/Models/HomeSummary.swift`
- Test: `Roost/Tests/HomeSummaryTests.swift`

**Interfaces:**
- Consumes: `TodayPlan` (from `Roost/Sources/Models/TodayPlanner.swift`) — `plan.rows(for:)`, `plan.dueCount(for:)`. `Person` from RoostCore, with `.displayName`. `Strings.Home` from Task 1.
- Produces:
  - `struct HomeSummary` with `init(plan: TodayPlan, me: Person?, doorCounts: HomeSummary.DoorCounts)`
  - `var sentence: String`
  - `var myRows: [TodayRow]`
  - `var otherCount: Int`
  - `var otherName: String`
  - `var showsOtherLine: Bool`
  - `struct DoorCounts { let shopping, meals, projects, wishlist: Int }`
  - `var doors: [HomeSummary.Door]` where `Door` has `title: String`, `count: Int?`, `id: String`

- [ ] **Step 1: Write the failing test**

Create `Roost/Tests/HomeSummaryTests.swift`:

```swift
// The Home screen's words, tested without a simulator. Every sentence state the screen can
// reach has a case here, because the sentence replaces the word "Today" as the only thing
// orienting the reader — a wrong one is worse than a blank one.
@testable import Roost
import RoostCore
import XCTest

final class HomeSummaryTests: XCTestCase {
    private let noDoors = HomeSummary.DoorCounts(shopping: 0, meals: 0, projects: 0, wishlist: 0)

    private func plan(anne: Int, wes: Int) -> TodayPlan {
        TodayPlanTestBuilder.plan(anne: anne, wes: wes)
    }

    func testBothOweShowsTheSplit() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 5), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "5 for you, 4 for Anne.")
    }

    func testSplitReadsFromTheOtherPhoneToo() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 5), me: .anne, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "4 for you, 5 for Wes.")
    }

    func testClearForYouNamesTheOtherPersonsRemainder() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 0), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "Nothing left for you. Anne still has 4.")
    }

    func testBothClearIsAllCaughtUp() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "All caught up.")
    }

    func testUnpairedPhoneFallsBackToNothingDue() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: nil, doorCounts: noDoors)
        XCTAssertEqual(summary.sentence, "Nothing due today")
    }

    func testOtherLineHidesWhenTheOtherPersonIsClear() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 3), me: .wes, doorCounts: noDoors)
        XCTAssertFalse(summary.showsOtherLine)
    }

    func testOtherLineShowsWhenTheOtherPersonOwesSomething() {
        let summary = HomeSummary(plan: plan(anne: 4, wes: 3), me: .wes, doorCounts: noDoors)
        XCTAssertTrue(summary.showsOtherLine)
        XCTAssertEqual(summary.otherCount, 4)
        XCTAssertEqual(summary.otherName, "Anne")
    }

    // A door is always shown. Its count is shown only when the room holds something — the
    // spec's hide rule applies to the number, not to the door.
    func testEmptyRoomsShowNoCount() {
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: .wes, doorCounts: noDoors)
        XCTAssertEqual(summary.doors.count, 4)
        XCTAssertTrue(summary.doors.allSatisfy { $0.count == nil })
    }

    func testDoorsCarryTheirCountsWhenTheRoomsHaveContent() {
        let counts = HomeSummary.DoorCounts(shopping: 3, meals: 0, projects: 1, wishlist: 0)
        let summary = HomeSummary(plan: plan(anne: 0, wes: 0), me: .wes, doorCounts: counts)
        XCTAssertEqual(summary.doors.map(\.count), [3, nil, 1, nil])
        XCTAssertEqual(summary.doors.map(\.title), ["Shopping", "Meals", "Projects", "Wishlist"])
    }
}
```

- [ ] **Step 2: Add the test builder the tests lean on**

Append to the same file, below `HomeSummaryTests`:

```swift
/// Builds a `TodayPlan` with a chosen number of due rows per person. The rows' content does not
/// matter to these tests — only how many each person owes — so the chores are minimal and
/// distinct only by id.
enum TodayPlanTestBuilder {
    static func plan(anne: Int, wes: Int) -> TodayPlan {
        let chores = (0 ..< (anne + wes)).map { index in
            Chore(
                id: "c\(index)",
                title: "Chore \(index)",
                cadence: .daily,
                fixedAssignee: index < anne ? .anne : .wes,
                category: .chore
            )
        }
        return TodayPlanner.plan(
            chores: chores,
            completions: [],
            handoffs: [],
            asOf: Date(timeIntervalSince1970: 1_789_000_000),
            activeFrom: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: HouseholdCalendar()
        )
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeSummaryTests test 2>&1 | tail -15`

Expected: FAIL — `cannot find 'HomeSummary' in scope`.

- [ ] **Step 4: Write the implementation**

Create `Roost/Sources/Models/HomeSummary.swift`:

```swift
// What the Home screen says, decided here rather than in the view. The screen's whole job is to
// orient someone in one glance, so the sentence is the screen — and a sentence assembled inside a
// SwiftUI body is a sentence no test can reach. Everything user-visible on Home comes through
// this struct.
import RoostCore

struct HomeSummary {
    /// How many items each list holds. Passed in rather than queried here so this stays free of
    /// SwiftData and testable with plain integers.
    struct DoorCounts {
        let shopping: Int
        let meals: Int
        let projects: Int
        let wishlist: Int
    }

    /// One room, as the strip draws it. `count` is nil when the room is empty: the door is always
    /// shown, the number is not.
    struct Door: Identifiable {
        let id: String
        let title: String
        let count: Int?
    }

    let sentence: String
    let myRows: [TodayRow]
    let otherCount: Int
    let otherName: String
    let doors: [Door]

    /// The other person's line is not drawn when they owe nothing. Hiding it is the point: a line
    /// reading "Anne still has 0" is noise pretending to be information.
    var showsOtherLine: Bool {
        otherCount > 0
    }

    init(plan: TodayPlan, me: Person?, doorCounts: DoorCounts) {
        let other = me.map { $0 == .anne ? Person.wes : Person.anne }
        let mine = me.map { plan.dueCount(for: $0) } ?? 0
        let theirs = other.map { plan.dueCount(for: $0) } ?? 0

        myRows = me.map { TodayBoard.ordered(plan.rows(for: $0)) } ?? []
        otherCount = theirs
        otherName = other?.displayName ?? ""

        // Order matters: an unpaired phone has no "you", so it can never reach the first three.
        if me == nil {
            sentence = Strings.Home.nothingDue
        } else if mine > 0 {
            sentence = Strings.Home.split(mine, theirs, other: other?.displayName ?? "")
        } else if theirs > 0 {
            sentence = Strings.Home.clearForYou(theirs, other: other?.displayName ?? "")
        } else {
            sentence = Strings.Home.allCaught
        }

        doors = [
            Door(id: "shopping", title: Strings.Tabs.shopping, count: Self.shown(doorCounts.shopping)),
            Door(id: "meals", title: Strings.Tabs.meals, count: Self.shown(doorCounts.meals)),
            Door(id: "projects", title: Strings.Tabs.projects, count: Self.shown(doorCounts.projects)),
            Door(id: "wishlist", title: Strings.Tabs.wishlist, count: Self.shown(doorCounts.wishlist)),
        ]
    }

    private static func shown(_ count: Int) -> Int? {
        count > 0 ? count : nil
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeSummaryTests test 2>&1 | tail -15`

Expected: `** TEST SUCCEEDED **`, 9 tests.

- [ ] **Step 6: Commit**

```bash
git add Roost/Sources/Models/HomeSummary.swift Roost/Tests/HomeSummaryTests.swift
git commit -m "home: the sentence and the door counts, as testable logic"
```

**Note on `sentence` when `mine > 0` and `theirs == 0`:** the split form still applies and reads "5 for you, 0 for Anne." That is intentional and tested by `testOtherLineHidesWhenTheOtherPersonIsClear` only for the line, not the sentence. If a reviewer objects, the fix is a fifth `Strings.Home` case, not a change to the ordering above — raise it rather than inventing one.

---

## Task 3: Rename the tab and add segment state

**Files:**
- Modify: `Roost/Sources/Root/RootTabView.swift`
- Test: `Roost/Tests/RootNavigationTests.swift` (create)

**Interfaces:**
- Consumes: `Strings.Home.title` from Task 1.
- Produces:
  - `RootTab.home` (replaces `.tasks`; raw value stays `"tasks"` — see Step 1)
  - `HomeSegment` enum, `case home, board`, `Identifiable`, `id: String`
  - `RootNavigation.segment: HomeSegment`
  - `RootNavigation.showBoard()`

- [ ] **Step 1: Write the failing test**

Create `Roost/Tests/RootNavigationTests.swift`:

```swift
// The Home tab's two segments, and the cross-tab jumps that set them.
@testable import Roost
import XCTest

final class RootNavigationTests: XCTestCase {
    func testTheAppOpensOnHome() {
        let navigation = RootNavigation()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .home)
    }

    // The raw value is what AppStorage and any persisted selection wrote before the rename.
    // Changing it would silently reset every phone's tab on upgrade.
    func testTheHomeTabKeepsItsOldRawValue() {
        XCTAssertEqual(RootTab.home.rawValue, "tasks")
    }

    func testShowBoardSelectsTheTabAndTheSegment() {
        let navigation = RootNavigation()
        navigation.segment = .home
        navigation.showBoard()
        XCTAssertEqual(navigation.selected, .home)
        XCTAssertEqual(navigation.segment, .board)
    }

    func testShowAllChoresStillReachesTheMoreTab() {
        let navigation = RootNavigation()
        navigation.showAllChores()
        XCTAssertEqual(navigation.selected, .more)
        XCTAssertEqual(navigation.morePath, [.allChores])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/RootNavigationTests test 2>&1 | tail -15`

Expected: FAIL — `type 'RootTab' has no member 'home'`.

- [ ] **Step 3: Rename the case and add the segment**

In `Roost/Sources/Root/RootTabView.swift`, replace the `RootTab` enum with:

```swift
enum RootTab: String, CaseIterable, Identifiable {
    // The raw value stays "tasks" after the rename to .home. It is what any persisted selection
    // already holds, and changing it would reset the open tab on every phone that upgrades —
    // a silent, confusing one-off for a cosmetic gain.
    case home = "tasks"
    case lists
    case more

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: Strings.Home.title
        case .lists: Strings.Tabs.lists
        case .more: Strings.Tabs.more
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .lists: "list.bullet.rectangle"
        case .more: "ellipsis.circle"
        }
    }
}

/// The two halves of the Home tab. Home is arrival; the board is the two columns, which are the
/// same screen they have always been.
enum HomeSegment: String, CaseIterable, Identifiable {
    case home, board

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .home: Strings.Home.segmentHome
        case .board: Strings.Home.segmentBoard
        }
    }

    var symbol: String {
        switch self {
        case .home: Strings.Home.segmentHomeSymbol
        case .board: Strings.Home.segmentBoardSymbol
        }
    }
}
```

- [ ] **Step 4: Add the segment to `RootNavigation`**

In the same file, inside `final class RootNavigation`, change the `selected` default and add the segment:

```swift
    var selected: RootTab = .home
    /// Which half of the Home tab is showing. Lives here rather than in `@AppStorage` inside the
    /// screen so a cross-tab jump can set both at once, and so a minute tick in the board's
    /// TimelineView cannot invalidate it.
    var segment: HomeSegment = .home
    /// The More tab's navigation path. Empty is the More page itself.
    var morePath: [MoreRoute] = []

    func showAllChores() {
        morePath = [.allChores]
        selected = .more
    }

    /// From Home's "Anne still has 4" line: the board, in the tab the reader is already in.
    func showBoard() {
        segment = .board
        selected = .home
    }
```

- [ ] **Step 5: Point the tab at the new screen and fix the push route**

In the same file, change `screen(for:)` and the push `onChange`:

```swift
    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .home: HomeTabScreen()
        case .lists: ListsScreen()
        case .more: MoreScreen()
        }
    }
```

and

```swift
        // A tapped push lands on Home: everything the server pushes is about a chore, and Home
        // carries this phone's chores. A counter rather than a flag, so a second tap works even if
        // the reader has moved to another tab since the first.
        .onChange(of: sync.push.openTasksRequests) {
            navigation.selected = .home
            navigation.segment = .home
        }
```

- [ ] **Step 6: Run the test — it will still fail to build**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/RootNavigationTests test 2>&1 | tail -15`

Expected: FAIL — `cannot find 'HomeTabScreen' in scope`. That is Task 4. Do not stub it; go to Task 4 and return here.

- [ ] **Step 7: Commit (after Task 4 builds)**

```bash
git add Roost/Sources/Root/RootTabView.swift Roost/Tests/RootNavigationTests.swift
git commit -m "root: tab one is Home, with two segments"
```

---

## Task 4: HomeTabScreen and HomeScreen

**Files:**
- Create: `Roost/Sources/Screens/HomeTabScreen.swift`
- Create: `Roost/Sources/Screens/HomeScreen.swift`
- Create: `Roost/Sources/Home/HomeDoorsView.swift`
- Modify: `Roost/project.yml` is **not** edited — `Roost/Sources` is globbed, so new files under it are picked up by `xcodegen generate`.

**Interfaces:**
- Consumes: `HomeSegment`, `RootNavigation` (Task 3); `HomeSummary` (Task 2); `Strings.Home` (Task 1); the existing `RoostSegmentedControl`, `ChoreRowView`, `TodayScreen`.
- Produces: `HomeTabScreen`, `HomeScreen`, `HomeDoorsView`.

- [ ] **Step 1: Create `HomeTabScreen`**

```swift
// The Home tab: two segments over one navigation stack. Home is arrival; "Anne & Wes" is the
// board that used to be this tab's whole content. The board is not gone and not demoted to More —
// it is one tap away, in the tab the reader is already in.
//
// The segment lives on RootNavigation rather than in @AppStorage here, so the "Anne still has 4"
// line on Home can switch it, and so the board's minute-by-minute TimelineView cannot invalidate
// the picker above it.
import RoostDesign
import SwiftUI

struct HomeTabScreen: View {
    @Environment(RootNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack {
            VStack(spacing: 0) {
                RoostSegmentedControl(
                    items: HomeSegment.allCases,
                    selection: $navigation.segment,
                    title: { $0.title },
                    symbol: { $0.symbol }
                )
                .padding(.horizontal, RoostSpacing.screenMargin)
                .padding(.vertical, RoostSpacing.sm)

                switch navigation.segment {
                case .home: HomeScreen()
                case .board: TodayScreen()
                }
            }
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.appTitle)
            .toolbarTitleDisplayMode(.inline)
        }
        .tint(RoostColor.Role.accent.color)
    }
}
```

- [ ] **Step 2: Create `HomeDoorsView`**

```swift
// The four rooms as four words. A door is always drawn; its count only when the room holds
// something. An empty household therefore sees four quiet labels rather than four empty cards
// telling it to go and fill them in.
import RoostDesign
import SwiftUI

struct HomeDoorsView: View {
    let doors: [HomeSummary.Door]
    let open: (String) -> Void

    var body: some View {
        HStack(spacing: RoostSpacing.xs) {
            ForEach(doors) { door in
                Button {
                    open(door.id)
                } label: {
                    VStack(spacing: RoostSpacing.xxs) {
                        Text(door.title)
                            .roostType(.rowTitle)
                            .foregroundStyle(RoostColor.Role.textPrimary.color)
                        Text(door.count.map(String.init) ?? "—")
                            .roostType(.monoTally)
                            .foregroundStyle(
                                door.count == nil
                                    ? RoostColor.Role.textSecondary.color
                                    : RoostColor.Role.accent.color
                            )
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, RoostSpacing.xs)
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityLabel(accessibilityLabel(door))
                .accessibilityIdentifier("home.door.\(door.id)")
            }
        }
    }

    /// VoiceOver reads a door as a sentence, not as "Shopping, 3" — the count means items.
    private func accessibilityLabel(_ door: HomeSummary.Door) -> String {
        guard let count = door.count else { return door.title }
        return "\(door.title), \(count)"
    }
}
```

- [ ] **Step 3: Create `HomeScreen`**

```swift
// The front door. The date, one sentence, this phone's chores — checkable right here, so the
// standing-in-the-kitchen tick still happens on the first screen — the other person as a single
// line, and four doors into the rest of the house.
//
// What is deliberately NOT here: the Anne-vs-Wes streak card and the week bar. They are a
// scoreboard, they cost ~200 pt at the top of the old screen, and the household already collapsed
// them by default. They live on the board segment now.
//
// Each section is its own extracted subview. This screen re-renders every 60 seconds under the
// same TimelineView the board uses, so a minute tick must not rebuild the whole body.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct HomeScreen: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(RootNavigation.self) private var navigation

    @Query(filter: #Predicate<ChoreRecord> { !$0.retired }, sort: \ChoreRecord.sortOrder)
    private var choreRecords: [ChoreRecord]
    @Query(filter: #Predicate<CompletionRecord> { !$0.removed })
    private var completionRecords: [CompletionRecord]
    @Query(filter: #Predicate<HandoffRecord> { !$0.removed }, sort: \HandoffRecord.createdAt)
    private var handoffRecords: [HandoffRecord]
    @Query private var syncStates: [SyncState]

    @Query(filter: #Predicate<ShoppingItemRecord> { !$0.removed })
    private var shoppingRecords: [ShoppingItemRecord]
    @Query(filter: #Predicate<MealRecord> { !$0.removed })
    private var mealRecords: [MealRecord]
    @Query(filter: #Predicate<ProjectRecord> { !$0.removed })
    private var projectRecords: [ProjectRecord]
    @Query(filter: #Predicate<WishlistItemRecord> { !$0.removed })
    private var wishlistRecords: [WishlistItemRecord]

    private let calendar = HouseholdCalendar()

    private var state: SyncState? {
        syncStates.first
    }

    private var me: Person? {
        state?.person.flatMap(Person.init(rawValue:))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(asOf: context.date)
        }
        .refreshable { await sync.syncNow() }
    }

    private func content(asOf now: Date) -> some View {
        let summary = summary(asOf: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
                VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                    Text(dateLine(now))
                        .roostType(.monoLabel)
                        .foregroundStyle(RoostColor.Role.accent.color)
                        .accessibilityIdentifier("dateEyebrow")
                    Text(summary.sentence)
                        .roostType(.displayLarge)
                        .foregroundStyle(RoostColor.Role.textPrimary.color)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("home.sentence")
                }

                HomeRowsView(rows: summary.myRows)

                if summary.showsOtherLine {
                    Button {
                        navigation.showBoard()
                    } label: {
                        HStack {
                            Text(Strings.Home.otherStillHas(summary.otherCount, other: summary.otherName))
                                .roostType(.rowTitle)
                                .foregroundStyle(RoostColor.Role.textPrimary.color)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(RoostColor.Role.textSecondary.color)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.roostPressQuiet)
                    .accessibilityIdentifier("home.otherLine")
                }

                HomeDoorsView(doors: summary.doors) { id in
                    navigation.selected = .lists
                    UserDefaults.standard.set(id, forKey: ListPage.storageKey)
                }
            }
            .padding(.horizontal, RoostSpacing.screenMargin)
            .padding(.top, RoostSpacing.sm)
            .padding(.bottom, RoostSpacing.xxl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func dateLine(_ date: Date) -> String {
        date
            .formatted(.dateTime.weekday(.wide).month(.wide).day().locale(.autoupdatingCurrent))
            .uppercased()
    }

    private func summary(asOf now: Date) -> HomeSummary {
        let chores = choreRecords.compactMap { try? $0.toChore() }
        let completions = completionRecords.compactMap { try? $0.toCompletion() }
        let activeFrom = state?.activeFrom ?? calendar.startOfDay(now)
        let plan = TodayPlanner.plan(
            chores: chores,
            completions: completions,
            handoffs: handoffRecords.compactMap { try? $0.toSnapshot() },
            asOf: now,
            activeFrom: activeFrom,
            calendar: calendar
        )
        return HomeSummary(
            plan: plan,
            me: me,
            doorCounts: .init(
                shopping: shoppingRecords.count,
                meals: mealRecords.count,
                projects: projectRecords.count,
                wishlist: wishlistRecords.count
            )
        )
    }
}
```

- [ ] **Step 4: Regenerate the project and build**

Run: `cd Roost && xcodegen generate && cd .. && git diff --stat Roost/Roost.xcodeproj/project.pbxproj`

Expected: the pbxproj shows the three new files added.

- [ ] **Step 5: Run Tasks 2 and 3's tests**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeSummaryTests -only-testing:RoostTests/RootNavigationTests test 2>&1 | tail -15`

Expected: `** TEST SUCCEEDED **`. This is also where Task 3's Step 7 commit happens.

- [ ] **Step 6: Commit**

```bash
git add Roost/Sources/Screens/HomeTabScreen.swift Roost/Sources/Screens/HomeScreen.swift \
        Roost/Sources/Home/HomeDoorsView.swift Roost/Roost.xcodeproj/project.pbxproj \
        Roost/Sources/Root/RootTabView.swift Roost/Tests/RootNavigationTests.swift
git commit -m "home: the arrival screen"
```

---

## Task 5: HomeRowsView and the collapse rule

**Files:**
- Create: `Roost/Sources/Home/HomeRowsView.swift`
- Test: `Roost/Tests/HomeRowsCollapseTests.swift`

**Interfaces:**
- Consumes: `TodayRow`, `ChoreRowView`, `Strings.Home.more(_:)`, `Strings.Home.showLess`.
- Produces: `HomeRowsView(rows:)`, and `HomeRowsCollapse.visible(_:expanded:)` / `HomeRowsCollapse.hiddenCount(_:)`.

**Ruling from the spec:** the threshold is **6**. Six or fewer rows render in full; more than six render the first six plus a "N more" line. Six sits under the "around 5" daily cap Anne asked for, so collapse is the exception rather than the greeting. When the cap lane lands, the cap wins and this follows it.

- [ ] **Step 1: Write the failing test**

Create `Roost/Tests/HomeRowsCollapseTests.swift`:

```swift
// The collapse threshold, as arithmetic rather than as a view. Six is a spec ruling, not a taste
// call, so it gets a test that will fail loudly if someone "tidies" it.
@testable import Roost
import XCTest

final class HomeRowsCollapseTests: XCTestCase {
    func testSixOrFewerAreAllVisible() {
        XCTAssertEqual(HomeRowsCollapse.visible(6, expanded: false), 6)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(6), 0)
    }

    func testSevenCollapsesToSix() {
        XCTAssertEqual(HomeRowsCollapse.visible(7, expanded: false), 6)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(7), 1)
    }

    func testNineCollapsesToSixWithThreeMore() {
        XCTAssertEqual(HomeRowsCollapse.visible(9, expanded: false), 6)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(9), 3)
    }

    func testExpandedShowsEverything() {
        XCTAssertEqual(HomeRowsCollapse.visible(9, expanded: true), 9)
    }

    func testZeroRowsIsNotACollapse() {
        XCTAssertEqual(HomeRowsCollapse.visible(0, expanded: false), 0)
        XCTAssertEqual(HomeRowsCollapse.hiddenCount(0), 0)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeRowsCollapseTests test 2>&1 | tail -15`

Expected: FAIL — `cannot find 'HomeRowsCollapse' in scope`.

- [ ] **Step 3: Write `HomeRowsView`**

Create `Roost/Sources/Home/HomeRowsView.swift`:

```swift
// This phone's chores on the front door, checkable where they are. Long lists fold to a "N more"
// line whose open/shut state persists, following the pattern the streak block already set with
// `roost.today.streakExpanded` — the household decided once that a tally is the glance and the
// detail is the reveal, and that decision holds here.
import RoostDesign
import SwiftUI

/// The fold, as arithmetic. Separate from the view so it can be tested without a simulator.
enum HomeRowsCollapse {
    /// Spec ruling 2026-09-15: six. It sits under the "around 5" daily cap Anne asked for, so a
    /// normal day is under the threshold and the fold is the exception, not the greeting. When the
    /// cap lane lands, the cap wins and this follows it.
    static let threshold = 6

    static func visible(_ total: Int, expanded: Bool) -> Int {
        expanded ? total : min(total, threshold)
    }

    static func hiddenCount(_ total: Int) -> Int {
        max(0, total - threshold)
    }
}

struct HomeRowsView: View {
    let rows: [TodayRow]

    @AppStorage("roost.home.rowsExpanded") private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hidden: Int {
        HomeRowsCollapse.hiddenCount(rows.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows.prefix(HomeRowsCollapse.visible(rows.count, expanded: expanded))) { row in
                ChoreRowView(row: row)
            }
            if hidden > 0 {
                Button {
                    expanded.toggle()
                } label: {
                    Text(expanded ? Strings.Home.showLess : Strings.Home.more(hidden))
                        .roostType(.rowTitle)
                        .foregroundStyle(RoostColor.Role.accent.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.roostPressQuiet)
                .accessibilityHint(Strings.Home.moreHint(hidden))
                .accessibilityIdentifier("home.more")
            }
        }
        .animation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion), value: expanded)
    }
}
```

**If `ChoreRowView(row:)` does not have that exact initializer**, read `Roost/Sources/Tasks/ChoreRowView.swift` and `PersonColumnView.swift` to see how the board constructs a row, and match it — including the toggle/offer closures. Do not invent a wrapper. If the row cannot be built without the board's action closures, stop and report it: threading those into Home is a design question, not an implementation detail.

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeRowsCollapseTests test 2>&1 | tail -15`

Expected: `** TEST SUCCEEDED **`, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd Roost && xcodegen generate && cd ..
git add Roost/Sources/Home/HomeRowsView.swift Roost/Tests/HomeRowsCollapseTests.swift Roost/Roost.xcodeproj/project.pbxproj
git commit -m "home: fold a long list at six, and remember it"
```

---

## Task 6: Move the streak block to the board

**Files:**
- Modify: `Roost/Sources/Tasks/TodayHeaderView.swift`
- Modify: `Roost/Sources/Screens/TodayScreen.swift`

**Interfaces:**
- Consumes: `StreakSummaryView(model:me:expanded:)` — unchanged.
- Produces: `TodayHeaderView` without the streak block.

- [ ] **Step 1: Remove the streak block from the header**

In `Roost/Sources/Tasks/TodayHeaderView.swift`, delete the `@AppStorage` line and the `StreakSummaryView` call from `body`, leaving the date, the title, and the sync line. Update the file's opening comment to say what it now is:

```swift
// The top of the board segment: the date, the word Today, and one status line. The head-to-head
// streak block moved down to sit above the columns — it is a scoreboard, and a scoreboard belongs
// on the board rather than on the front door. See docs/superpowers/specs/2026-09-15-home-screen-design.md.
```

Remove `let streaks: StreakHeaderModel` from the struct's properties, since the header no longer draws them.

- [ ] **Step 2: Draw the streaks above the columns instead**

In `Roost/Sources/Screens/TodayScreen.swift`, inside `content(asOf:)`, change the header call and add the streak block under it:

```swift
                TodayHeaderView(date: now, notice: notice(asOf: now), me: me)
                StreakSummaryView(model: StreakHeaderModel(plan: plan), me: me, expanded: $streaksExpanded)
```

and add the state it needs, next to the other `@State` properties:

```swift
    /// Ruling 2026-09-14, carried over from the header: expand state persists; default collapsed
    /// on a fresh install. The key is unchanged so a phone that had it open keeps it open.
    @AppStorage("roost.today.streakExpanded") private var streaksExpanded = false
```

- [ ] **Step 3: Build and run the full app suite**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test 2>&1 | tail -20`

Expected: `** TEST SUCCEEDED **`. Existing tests that referenced `TodayHeaderView(date:streaks:notice:me:)` will fail to compile — fix each by dropping the `streaks:` argument. Do not delete a test to make it build.

- [ ] **Step 4: Commit**

```bash
git add Roost/Sources/Tasks/TodayHeaderView.swift Roost/Sources/Screens/TodayScreen.swift Roost/Tests
git commit -m "board: the streak card moves off the front door"
```

---

## Task 7: UI tests and the accessibility audit

**Files:**
- Create: `Roost/UITests/HomeScreenUITests.swift`
- Modify: `Roost/UITests/AccessibilityAuditTests.swift`

**Interfaces:**
- Consumes: the accessibility identifiers set in Tasks 4 and 5 — `home.sentence`, `home.otherLine`, `home.door.<id>`, `home.more`, `dateEyebrow`.

- [ ] **Step 1: Write the UI test**

Create `Roost/UITests/HomeScreenUITests.swift`:

```swift
// Arrival, and the one tap from the front door to the board.
import XCTest

final class HomeScreenUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", "1"]
        app.launch()
    }

    func testTheAppOpensOnHomeNotTheBoard() {
        XCTAssertTrue(app.staticTexts["home.sentence"].waitForExistence(timeout: 10))
    }

    func testTheSegmentReachesTheBoard() {
        XCTAssertTrue(app.staticTexts["home.sentence"].waitForExistence(timeout: 10))
        app.buttons["listsPicker.board"].tap()
        // The board's own eyebrow is the proof we switched, not a Home identifier disappearing.
        XCTAssertTrue(app.staticTexts["dateEyebrow"].waitForExistence(timeout: 5))
    }

    func testEveryDoorIsPresentEvenWithEmptyRooms() {
        XCTAssertTrue(app.staticTexts["home.sentence"].waitForExistence(timeout: 10))
        for room in ["shopping", "meals", "projects", "wishlist"] {
            XCTAssertTrue(app.buttons["home.door.\(room)"].exists, "missing door: \(room)")
        }
    }
}
```

**Note:** `listsPicker.board` is the identifier `RoostSegmentedControl` generates — it hardcodes the `listsPicker.` prefix. If a reviewer objects to that name on the Home tab, the fix is to make the prefix a parameter of `RoostSegmentedControl` and update `ListsScreen` too. Raise it; do not rename only one side.

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostUITests/HomeScreenUITests test 2>&1 | tail -20`

Expected: FAIL, or PASS if Tasks 4–5 already satisfy it. A pass here is fine — this test describes behaviour those tasks built.

- [ ] **Step 3: Extend the accessibility audit to Home**

Read `Roost/UITests/AccessibilityAuditTests.swift` and add a case that audits the Home segment the same way the existing cases audit their screens. Match the file's existing structure exactly; do not invent a second audit style.

- [ ] **Step 4: Run the whole suite**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test 2>&1 | tail -20`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd Roost && xcodegen generate && cd ..
git add Roost/UITests Roost/Roost.xcodeproj/project.pbxproj
git commit -m "test: Home arrival, the segment, and the doors"
```

---

## Task 8: Look at it, then the docs

**Files:**
- Modify: `docs/superpowers/specs/2026-09-15-home-screen-design.md`
- Modify: `OPEN-ITEMS.md`

- [ ] **Step 1: Render it and look**

Build and run the app in the simulator, and look at the Home screen at default Dynamic Type. The product bar is "a polished app for a couple, not a template" — a screen nobody looked at has not been built.

Check specifically:
- How far down the first checkable row sits. The old screen spent ~190–210 pt before it. If Home is not meaningfully better than that, the lane has failed its own premise — say so rather than shipping it.
- The empty-household case: the doors should read as four quiet labels, not as four things demanding to be filled.
- The sentence at accessibility text sizes: it must not truncate.

- [ ] **Step 2: Record what the measurement actually came out at**

Append to the spec, under **What this gives up**:

```markdown
## What it measured

Built 2026-09-__. Distance from the nav bar to the first checkable chore row, default Dynamic
Type, fresh launch: __ pt on Home, against ~190–210 pt on the old Today screen.
```

Fill in the real number. If you did not measure it, do not write one.

- [ ] **Step 3: Sweep the open items**

In `OPEN-ITEMS.md`, move the home-screen lane out of "In flight" and record anything the build surfaced that outlives it.

- [ ] **Step 4: Commit and open the PR**

```bash
git add docs OPEN-ITEMS.md
git commit -m "docs: what the home screen measured"
git fetch origin && git rebase origin/main
cd Roost && xcodegen generate && cd ..   # the rebase may have moved project.yml
git push -u origin feat/home-screen
```

Then open a PR titled `Home screen` whose body states the measured pt figure from Step 2.

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| `RootTab.tasks` → `.home`, still first, still the push target | 3 |
| Two-segment control using the existing `RoostSegmentedControl` | 3, 4 |
| Segment selection persists, does not reset on foreground | 3 (on `RootNavigation`, not reset anywhere) |
| Date eyebrow keeps `accessibilityIdentifier("dateEyebrow")` | 4 (Home), 6 (board) |
| The sentence, in `displayLarge`, replacing "Today" | 1, 2, 4 |
| Your rows, checkable, planner order | 2 (`myRows` via `TodayBoard.ordered`), 5 |
| The other person as one tappable line | 2 (`showsOtherLine`), 4 |
| Doors: one word, count only when > 0, never an empty-state essay | 2, 4 |
| Sync notice last | **GAP — see below** |
| Streak block and week bar leave Home | 6 |
| Hide rule: a section with nothing to say does not render | 2, 4 |
| Collapse rule: threshold 6, state persists, `roost.home.<section>Expanded` | 5 |
| Animated with `.animation(_:value:)`, respects Reduce Motion | 5 |
| Each section its own extracted subview | 4, 5 |
| Segment state on `RootNavigation`, not the environment | 3 |
| Planner runs once per tick | **PARTIAL — see below** |
| Voice: no greeting, named lines only | 1 |
| Sentence has a value in every state | 2 (five states, all tested) |
| `.isHeader` moves to the sentence | 4 |
| Segmented control reachable and labelled; audit covers Home | 7 |
| Collapsed section announces count and state | 5 (`moreHint`) |
| Every door is a `Button` | 4 |
| 44 pt minimum | 4, 5 |

**Two gaps, both deliberate, both for the executor to resolve rather than ignore:**

1. **The sync notice is not placed on Home.** The spec lists it seventh. `SyncNoticeLine` currently lives inside `TodayHeaderView` and takes a `TodayBoard.Notice` built by `TodayScreen.notice(asOf:)`. Adding it to Home means either duplicating that construction or lifting it. **Ruling: lift `notice(asOf:)` into a shared place and use it from both, in Task 4.** If that turns out to drag the whole board's state with it, put the notice on the board only for this lane and record it in `OPEN-ITEMS.md` as owed.

2. **"The planner runs once per tick" is not achieved as written.** Home and the board each build their own `TodayPlan`, because they are separate views with their own `@Query` sets. Since only one segment is on screen at a time, only one plan is built per tick in practice — the spec's concern (paying twice) does not occur. **Ruling: accept as-is.** If both segments are ever rendered simultaneously (a future iPad layout), this becomes real and needs a shared planner in the environment.

**Placeholder scan:** no TBDs, no "add error handling", no "similar to Task N". Every code step carries its code. Task 5 Step 3 and Task 7 Step 1 name a specific uncertainty and tell the executor to stop and report rather than invent — that is a deliberate instruction, not a placeholder.

**Type consistency:** `HomeSummary.DoorCounts` and `HomeSummary.Door` are defined in Task 2 and used in Tasks 2 and 4. `HomeSegment` is defined in Task 3 and used in 3, 4, 7. `HomeRowsCollapse.visible(_:expanded:)` and `.hiddenCount(_:)` are defined in Task 5 and used only there and in its test. `RootNavigation.showBoard()` is defined in Task 3 and called in Task 4. `Strings.Home.*` is defined in Task 1 and used in 2, 4, 5.
