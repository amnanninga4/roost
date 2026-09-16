# Home list grouping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home and each board column group this person's existing due rows into Overdue / Today / If you have time, with later rows quieter. Assignment, streak, digest, widget, and any numeric cap stay untouched.

**Architecture:** A pure `HomeRowBuckets.group` splits `[TodayRow]` using fields already on `DueItem` (`daysOverdue`, `dueLastDay`). Views render the three buckets. `ChoreRowView` gains a `.quiet` style and stops painting every late title red. No `DailyCap.swift`, no `Tallies` edits, no `rules.js`.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, iOS 26. Packages `RoostCore` and `RoostDesign`. XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-16-daily-cap-design.md` — read it before Task 1. Wes: UI, not scheduler.

## Global Constraints

- User-facing strings live **only** in `Roost/Sources/Strings.swift`. Never inline a literal in a view.
- Plain wording. Do not say `Bonus`, `Optional chores`, `Stretch goals`, or greet.
- Never hand-edit `Roost/Roost.xcodeproj/project.pbxproj`. Edit `Roost/project.yml` only if a new file is outside `Sources/` / `Tests/` (these two are folder refs; new files under them are picked up).
- Every `@State` is `private`. `.animation(_:value:)` always has `value`. `ForEach` uses stable identity, never `.indices`.
- Minimum tap target 44 pt. Headings that fold are `Button`s.
- Pin destinations: `platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1`.
- **Never run two `xcodebuild` test runs at once on this Mac.**
- Do not change who owes a chore. Do not touch `Packages/RoostCore` except reading `DueItem`. Do not touch `server/`. Do not touch the widget.

---

## File Structure

| File | Responsibility |
|---|---|
| `Roost/Sources/Home/HomeRowBuckets.swift` | **New.** Pure split of `[TodayRow]` into overdue / today / later. No SwiftUI. |
| `Roost/Tests/HomeRowBucketsTests.swift` | **New.** The split, including empty buckets and done-today under Today. |
| `Roost/Sources/Home/HomeRowsView.swift` | Replace the mixed fold with three buckets. |
| `Roost/Sources/Tasks/ChoreRowView.swift` | `.quiet` style; overdue titles not danger unless `alert`; Home skips escalation subtitle. |
| `Roost/Sources/Tasks/PersonColumnView.swift` | Same buckets inside the column card. |
| `Roost/Sources/Screens/HomeScreen.swift` | Pass `calendar` + `now` into `HomeRowsView`. |
| `Roost/Sources/Screens/TodayScreen.swift` | Pass `calendar` + date into `PersonColumnView`. |
| `Roost/Sources/Strings.swift` | The three headings. |
| `Roost/Sources/Debug/UITestSeed.swift` | Remembered keys for the new folds. |
| `Roost/Tests/HomeRowsCollapseTests.swift` | Keep the per-bucket fold arithmetic; drop "this is waiting for the cap" comments. |
| `Roost/UITests/HomeScreenUITests.swift` | Identifiers `home.overdue`, `home.today`, `home.later`. |

How "later" is decided, without a scheduler change: a due row with `daysOverdue == 0` whose `dueLastDay` is **after** today still has days left in its window (Friday of a Fri–Sat garbage window). Dailies have `dueLastDay == today`, so they stay in Today. Overdue is `daysOverdue > 0`. Done rows always sit under Today. Empty buckets do not render.

---

### Task 1: Strings

**Files:**
- Modify: `Roost/Sources/Strings.swift` (`enum Home`, after `showLess`)

**Interfaces:**
- Produces: `Strings.Home.overdue`, `.today`, `.ifYouHaveTime`

- [ ] **Step 1: Add the three headings**

Inside `enum Home`, after `static let showLess = "Show less"`:

```swift
        static let overdue = "Overdue"
        static let today = "Today"
        static let ifYouHaveTime = "If you have time"
```

Keep `more` / `moreHint` / `showLess` — buckets reuse the fold.

- [ ] **Step 2: Lint**

Run: `swiftformat --lint Roost/Sources/Strings.swift && swiftlint lint --quiet Roost/Sources/Strings.swift`

Expected: silent.

- [ ] **Step 3: Commit**

```bash
git add Roost/Sources/Strings.swift
git commit -m "strings: Overdue, Today, If you have time"
```

---

### Task 2: HomeRowBuckets — the split, as arithmetic

**Files:**
- Create: `Roost/Sources/Home/HomeRowBuckets.swift`
- Test: `Roost/Tests/HomeRowBucketsTests.swift`

**Interfaces:**
- Consumes: `TodayRow`, `DueItem` (`daysOverdue`, `dueLastDay`), `HouseholdCalendar.dayIndex`
- Produces:
  - `enum HomeRowBucket { case overdue, today, later }`
  - `struct HomeRowGroups { let overdue, today, later: [TodayRow] }`
  - `static func group(_ rows: [TodayRow], calendar: HouseholdCalendar, on date: Date) -> HomeRowGroups`
  - `static func bucket(for row: TodayRow, calendar: HouseholdCalendar, on date: Date) -> HomeRowBucket`

- [ ] **Step 1: Write the failing test**

Create `Roost/Tests/HomeRowBucketsTests.swift`:

```swift
@testable import Roost
import RoostCore
import XCTest

final class HomeRowBucketsTests: XCTestCase {
    let cal = HouseholdCalendar()
    // Wednesday 16 Sep 2026.
    lazy var today: Date = cal.date(year: 2026, month: 9, day: 16)
    lazy var tomorrow: Date = cal.date(year: 2026, month: 9, day: 17)

    func testOverdueIsDaysOverduePositive() {
        let row = due(id: "late", daysOverdue: 2, last: today)
        XCTAssertEqual(HomeRowBuckets.bucket(for: row, calendar: cal, on: today), .overdue)
    }

    func testDailyWindowEndingTodayIsToday() {
        let row = due(id: "daily", daysOverdue: 0, last: today)
        XCTAssertEqual(HomeRowBuckets.bucket(for: row, calendar: cal, on: today), .today)
    }

    func testWindowThatStillHasDaysLeftIsLater() {
        let row = due(id: "garbage", daysOverdue: 0, last: tomorrow)
        XCTAssertEqual(HomeRowBuckets.bucket(for: row, calendar: cal, on: today), .later)
    }

    func testDoneRowsSitUnderToday() {
        let chore = Chore(id: "x", title: "X", cadence: .daily, category: .chore)
        let done = TodayRow(chore: chore, person: .anne, kind: .done(completionId: "c1"))
        let groups = HomeRowBuckets.group([done], calendar: cal, on: today)
        XCTAssertEqual(groups.today.map(\.id), [done.id])
        XCTAssertTrue(groups.overdue.isEmpty)
        XCTAssertTrue(groups.later.isEmpty)
    }

    func testEmptyBucketsAreEmptyArraysNotNil() {
        let groups = HomeRowBuckets.group([], calendar: cal, on: today)
        XCTAssertTrue(groups.overdue.isEmpty && groups.today.isEmpty && groups.later.isEmpty)
    }

    func testGroupPreservesPlannerOrderInsideABucket() {
        let a = due(id: "a", daysOverdue: 5, last: today)
        let b = due(id: "b", daysOverdue: 3, last: today)
        let groups = HomeRowBuckets.group([a, b], calendar: cal, on: today)
        XCTAssertEqual(groups.overdue.map(\.chore.id), ["a", "b"])
    }

    private func due(id: String, daysOverdue: Int, last: Date) -> TodayRow {
        let chore = Chore(id: id, title: id, cadence: .daily, category: .chore)
        let item = DueItem(
            chore: chore,
            person: .anne,
            periodIndex: 0,
            periodStart: today,
            periodLastDay: last,
            dueFirstDay: today,
            dueLastDay: last,
            daysOverdue: daysOverdue
        )
        return TodayRow(chore: chore, person: .anne, kind: .due(item))
    }
}
```

- [ ] **Step 2: Run it — it must fail**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeRowBucketsTests test`

Expected: compile error, `HomeRowBuckets` not found.

- [ ] **Step 3: Implement**

Create `Roost/Sources/Home/HomeRowBuckets.swift`:

```swift
import Foundation
import RoostCore

enum HomeRowBucket: Equatable {
    case overdue, today, later
}

struct HomeRowGroups: Equatable {
    var overdue: [TodayRow] = []
    var today: [TodayRow] = []
    var later: [TodayRow] = []
}

enum HomeRowBuckets {
    static func bucket(for row: TodayRow, calendar: HouseholdCalendar, on date: Date) -> HomeRowBucket {
        if row.isDone { return .today }
        if row.daysOverdue > 0 { return .overdue }
        if case let .due(item) = row.kind, calendar.dayIndex(item.dueLastDay) > calendar.dayIndex(date) {
            return .later
        }
        return .today
    }

    static func group(_ rows: [TodayRow], calendar: HouseholdCalendar, on date: Date) -> HomeRowGroups {
        var groups = HomeRowGroups()
        for row in rows {
            switch bucket(for: row, calendar: calendar, on: date) {
            case .overdue: groups.overdue.append(row)
            case .today: groups.today.append(row)
            case .later: groups.later.append(row)
            }
        }
        return groups
    }
}
```

- [ ] **Step 4: Run the tests — they must pass**

Same `xcodebuild` as Step 2. Expected: `** TEST SUCCEEDED **` and all six methods pass.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Home/HomeRowBuckets.swift Roost/Tests/HomeRowBucketsTests.swift
git commit -m "home: overdue / today / later is arithmetic, not a view"
```

---

### Task 3: ChoreRowView — quieter late, quiet later

**Files:**
- Modify: `Roost/Sources/Tasks/ChoreRowView.swift`
- Test: `Roost/Tests/ChoreRowMetaTests.swift` only if a test already asserts title colour (it does not). Add `Roost/Tests/ChoreRowViewStyleTests.swift` for the subtitle skip, as pure logic extracted next to the view.

**Interfaces:**
- Produces: `ChoreRowView.Style { standard, quiet }`; `showsEscalationSubtitle: Bool = true`; `titleRole` is `textPrimary` unless done, quiet, or `alert`.

- [ ] **Step 1: Add a tiny helper the view can share with a test**

At the bottom of `ChoreRowView.swift` (or a new `ChoreRowPresentation.swift` next to it if the file is already long):

```swift
enum ChoreRowPresentation {
    static func titleRole(isDone: Bool, stage: EscalationStage, style: ChoreRowView.Style) -> RoostColor.Role {
        if isDone || style == .quiet { return .textSecondary }
        if stage == .alert { return .danger }
        return .textPrimary
    }

    /// Home drops the escalation subtitle; it repeats the title as "X emergency".
    static func showsSubtitle(_ subtitle: String, title: String, allowed: Bool) -> Bool {
        guard allowed else { return false }
        return !subtitle.lowercased().hasPrefix(title.lowercased())
    }
}
```

Put `enum Style { case standard, quiet }` inside `ChoreRowView`.

- [ ] **Step 2: Tests for the helper**

`Roost/Tests/ChoreRowViewStyleTests.swift`:

```swift
@testable import Roost
import RoostCore
import XCTest

final class ChoreRowViewStyleTests: XCTestCase {
    func testOverdueTitleIsNotDangerUntilAlert() {
        XCTAssertEqual(
            ChoreRowPresentation.titleRole(isDone: false, stage: .nudge, style: .standard),
            .textPrimary
        )
        XCTAssertEqual(
            ChoreRowPresentation.titleRole(isDone: false, stage: .alert, style: .standard),
            .danger
        )
    }

    func testQuietIsAlwaysSecondary() {
        XCTAssertEqual(
            ChoreRowPresentation.titleRole(isDone: false, stage: .alert, style: .quiet),
            .textSecondary
        )
    }

    func testHomeDropsTheEmergencySubtitle() {
        XCTAssertFalse(
            ChoreRowPresentation.showsSubtitle(
                "Scoop litter emergency", title: "Scoop litter", allowed: false
            )
        )
        XCTAssertFalse(
            ChoreRowPresentation.showsSubtitle(
                "Scoop litter emergency", title: "Scoop litter", allowed: true
            )
        )
        XCTAssertTrue(
            ChoreRowPresentation.showsSubtitle("Getting overdue.", title: "Vacuum", allowed: true)
        )
    }
}
```

Run: `xcodebuild … -only-testing:RoostTests/ChoreRowViewStyleTests test` — fail, then implement helper, pass.

- [ ] **Step 3: Wire the view**

On `ChoreRowView`:

```swift
    var style: Style = .standard
    var showsEscalationSubtitle: Bool = true
    enum Style { case standard, quiet }
```

Replace `titleRole` with `ChoreRowPresentation.titleRole(isDone:row.isDone, stage:row.stage, style:style)`.

Subtitle block:

```swift
                    if let subtitle = EscalationCopy.subtitle(for: row),
                       ChoreRowPresentation.showsSubtitle(
                           subtitle, title: row.chore.title, allowed: showsEscalationSubtitle
                       )
                    {
                        Text(subtitle)
                        // existing modifiers
                    }
```

Edge bar overlay: draw only when `style == .standard` (keep the existing `!row.isDone, row.stage.fillRole != nil` guard).

Quiet rows: no change to check-off. They stay buttons.

- [ ] **Step 4: Run `ChoreRowViewStyleTests` and `EscalationCopyTests`**

Expected: both pass. Escalation copy itself is unchanged.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Tasks/ChoreRowView.swift Roost/Tests/ChoreRowViewStyleTests.swift
git commit -m "rows: late titles stay readable; later rows go quiet"
```

---

### Task 4: HomeRowsView draws buckets

**Files:**
- Modify: `Roost/Sources/Home/HomeRowsView.swift`
- Modify: `Roost/Sources/Screens/HomeScreen.swift` (pass calendar + date)
- Modify: `Roost/Tests/HomeRowsCollapseTests.swift` (comment only: fold is per-bucket now)
- Modify: `Roost/Sources/Debug/UITestSeed.swift` (`rememberedKeys`)

**Interfaces:**
- Consumes: `HomeRowBuckets.group`, `ChoreRowView.style`, `Strings.Home.overdue/today/ifYouHaveTime`
- `HomeRowsView` gains `calendar: HouseholdCalendar`, `now: Date`

- [ ] **Step 1: Replace the mixed stack**

`HomeRowsView` becomes:

```swift
struct HomeRowsView: View {
    let rows: [TodayRow]
    let calendar: HouseholdCalendar
    let now: Date
    let onToggle: (TodayRow) -> Void

    @AppStorage("roost.home.overdueExpanded") private var overdueExpanded = false
    @AppStorage("roost.home.todayExpanded") private var todayExpanded = false
    @AppStorage("roost.home.laterExpanded") private var laterExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: HomeRowGroups {
        HomeRowBuckets.group(rows, calendar: calendar, on: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: RoostSpacing.sectionGap) {
            bucket(
                groups.overdue,
                title: Strings.Home.overdue,
                expanded: $overdueExpanded,
                style: .standard,
                identifier: "home.overdue"
            )
            bucket(
                groups.today,
                title: Strings.Home.today,
                expanded: $todayExpanded,
                style: .standard,
                identifier: "home.today"
            )
            bucket(
                groups.later,
                title: Strings.Home.ifYouHaveTime,
                expanded: $laterExpanded,
                style: .quiet,
                identifier: "home.later"
            )
        }
        .roostAnimation(.standard, value: rows.map(\.id))
    }

    @ViewBuilder
    private func bucket(
        _ rows: [TodayRow],
        title: String,
        expanded: Binding<Bool>,
        style: ChoreRowView.Style,
        identifier: String
    ) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(title)
                    .roostType(.monoLabel)
                    .foregroundStyle(RoostColor.Role.textSecondary.color)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier)
                let hidden = HomeRowsCollapse.hiddenCount(rows.count)
                ForEach(rows.prefix(HomeRowsCollapse.visible(rows.count, expanded: expanded.wrappedValue))) { row in
                    ChoreRowView(row: row, style: style, showsEscalationSubtitle: false) { onToggle(row) }
                        .roostTransition(.checkOff)
                }
                if hidden > 0 {
                    Button {
                        expanded.wrappedValue.toggle()
                    } label: {
                        Text(expanded.wrappedValue ? Strings.Home.showLess : Strings.Home.more(hidden))
                            .roostType(.rowTitle)
                            .foregroundStyle(RoostColor.Role.accent.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.roostPressQuiet)
                    .accessibilityHint(Strings.Home.moreHint(hidden))
                    .accessibilityIdentifier("\(identifier).more")
                }
            }
            .animation(RoostMotion.reduceMotionAware(.quick, reduceMotion: reduceMotion), value: expanded.wrappedValue)
        }
    }
}
```

In `HomeScreen.swift` `content(asOf:)`:

```swift
                HomeRowsView(rows: summary.myRows, calendar: calendar, now: now) { row in
                    toggle(row, among: summary.myRows)
                }
```

`UITestSeed.rememberedKeys`: replace `"roost.home.rowsExpanded"` with the three new keys.

`HomeRowsCollapse.threshold` stays 6. Update the comment: it is now per-bucket, not waiting on a cap.

- [ ] **Step 2: Compile the app tests that touch Home**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' -only-testing:RoostTests/HomeRowsCollapseTests -only-testing:RoostTests/HomeSummaryTests -only-testing:RoostTests/HomeRowBucketsTests test`

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Roost/Sources/Home/HomeRowsView.swift Roost/Sources/Screens/HomeScreen.swift Roost/Sources/Debug/UITestSeed.swift Roost/Tests/HomeRowsCollapseTests.swift
git commit -m "home: three buckets instead of one fold"
```

---

### Task 5: Board columns use the same buckets

**Files:**
- Modify: `Roost/Sources/Tasks/PersonColumnView.swift`
- Modify: `Roost/Sources/Screens/TodayScreen.swift` (pass calendar + date)

**Interfaces:**
- Consumes: `HomeRowBuckets.group` (same function as Home)
- Board rows keep `showsEscalationSubtitle: true` except later rows use `.quiet` (subtitle still skipped when it prefixes the title)

- [ ] **Step 1: Bucket the ForEach**

Add to `PersonColumnView`:

```swift
    let calendar: HouseholdCalendar
    let now: Date
```

Replace the `ForEach(Array(rows.enumerated())…)` body with three bucket stacks, same headings, identifiers `board.\(person.rawValue).overdue` etc. Later rows: `style: .quiet`. Standard rows keep handoff closures. Preserve the entrance stagger by enumerating the concatenated visible rows, or drop stagger on headings (stagger the rows only). Offers stay above everything.

Empty column: if `rows.isEmpty`, keep `clearLine(Strings.Tasks.nothingDue)`. If every due row is checked off, keep `nothingLeft` above done rows in Today.

`TodayScreen` constructs `HouseholdCalendar()` already via the planner — pass the same `calendar` and the `TimelineView` date into both columns.

- [ ] **Step 2: Compile `TodayBoardTests` + `RootTabsTests`**

Run: `xcodebuild … -only-testing:RoostTests/TodayBoardTests -only-testing:RoostTests/RootTabsTests test`

Expected: pass. Board logic is unchanged; this is layout.

- [ ] **Step 3: Commit**

```bash
git add Roost/Sources/Tasks/PersonColumnView.swift Roost/Sources/Screens/TodayScreen.swift
git commit -m "board: the same three buckets in each column"
```

---

### Task 6: UI tests see the headings

**Files:**
- Modify: `Roost/UITests/HomeScreenUITests.swift`
- Modify: `Roost/UITests/AccessibilityAuditTests.swift` if it lists Home identifiers

- [ ] **Step 1: Add a test that Home has the today heading**

The `paired` fixture has due rows. After launch:

```swift
    func testHomeSplitsTheListIntoBuckets() {
        let app = launch(.paired)
        XCTAssertTrue(app.staticTexts["home.sentence"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["home.today"].exists, "Today bucket missing")
        // Overdue / later are fixture-dependent; only assert they are headings if present,
        // and that the old mixed fold is gone.
        XCTAssertFalse(app.buttons["home.more"].exists)
    }
```

If the fixture's pinned dailies last done 6 days ago produce overdue, also `XCTAssertTrue(app.staticTexts["home.overdue"].exists)`.

- [ ] **Step 2: Run UI tests for Home**

Run: `xcodebuild … -only-testing:RoostUITests/HomeScreenUITests test`

Expected: `** TEST SUCCEEDED **`. If a heading is missing, look at the fixture's completions in `UITestSeed` rather than inventing a cap.

- [ ] **Step 3: Commit**

```bash
git add Roost/UITests/HomeScreenUITests.swift
git commit -m "test: Home's list is overdue / today / later"
```

---

### Task 7: Full app test, once

- [ ] **Step 1:** Confirm no other `xcodebuild` is running (`pgrep xcodebuild` empty).

- [ ] **Step 2:**

```bash
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3:** Open the simulator, `paired` fixture or the installed phone build, and look at Home: three headings at most, no red-title wall, later rows quieter. Screenshot is not required for CI.

Do not open a second PR. This work lands on `specs/daily-cap` (or rebase onto current `main` first if that branch has only the spec).

---

## Dispatch (Cursor, this Mac)

Local CLI is `agent` at `~/.local/bin/agent`. `--trust` is required. Cheap models only: `composer-2.5` or `cursor-grok-4.6-high`. Use `agent persist` if the parent session might die.

```bash
cd ~/hines/projects/anne-app
agent -p --trust --model composer-2.5 "$(cat docs/superpowers/plans/2026-09-16-home-list-grouping.md)"
```

One agent, this plan, this checkout. Do not start a Cloud Agent; those are Linux VMs without Xcode.
