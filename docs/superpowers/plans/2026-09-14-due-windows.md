# Due Windows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chore can carry a due window inside its period — `weekdays` on weekly chores, a `dueDay` on every monthly, bimonthly and quarterly chore — so garbages are Friday–Saturday, the can is Sunday, and monthlies spread across the month instead of bunching on the 1st.

**Architecture:** Two optional keys in `data/chores.json` (version 4) travel the same chain as `season`: validator → RoostCore `Chore` → `HouseholdCalendar.dueWindow` → `Scheduler.dueItem` (window bounds on `DueItem`, `daysOverdue` from the window's last day, "not yet" and "never owed" rules) → server columns, seed, shape and the `rules.js` mirror → app `ChoreRecord`, converters, seeder, sync DTO → All chores copy. Periods, rotation, pins, handoffs, streaks and the escalation ladder are untouched.

**Tech Stack:** Swift 6 packages (XCTest), SwiftUI/SwiftData app (XCTest + XCUITest), Node 22 server with `node:sqlite` (`node --test`), Python 3 validator.

**Spec:** `docs/superpowers/specs/2026-09-14-due-windows-design.md` (binding). Inventory: `~/claude-reports/roost-design-round-dig-kimi-2026-09-14.md`.

## Global Constraints

- `data/chores.json` `version` becomes **4**; 41 chores, counts and the ten pins unchanged.
- `weekdays`: non-empty ascending unique ISO weekday numbers (Monday = 1 … Sunday = 7); **only** on `weekly`. Window = earliest listed day through latest listed day of the period week.
- `dueDay`: integer 1–28; **only** on `monthly`, `bimonthly`, `quarterly`, and **required** on all three. Window = the seven days ending on `dueDay` of the period's **last** month.
- `daily` and `biweekly` chores carry neither key. `season`/`together` combine freely with a window.
- **Never owed:** if the floor period (the one containing `activeFrom`) has a window whose last day is before `activeFrom`'s day, the floor is the next period.
- **Not yet:** when the oldest incomplete period is the current one and the date is before the window's first day, the chore is not due (nil).
- **Early windows:** for a chore with a `dueDay`, the period a date or a completion belongs to is its calendar period, or the next one once the next period's window has opened (`effectivePeriod`). Used for the current period, the `activeFrom` floor and every completion, on both sides.
- `daysOverdue = max(0, dayIndex(date) − dayIndex(window.lastDay))`. Escalation ladder unchanged. One nag, not a backlog (completing now clears older periods).
- The spec's "Dates that must hold" table is the test fixture set on both sides; Swift and Node tests use the same dates and values.
- User-facing strings only in `Roost/Sources/Strings.swift`; plain wording.
- No secrets. Never hand-edit the pbxproj: after adding a Swift file run `xcodegen generate` from `Roost/`. swiftformat/swiftlint clean on every changed Swift file.
- Branch `feat/due-windows` off `main` (≥ 4a55547); one commit per task; rebase before the PR.
- Test commands: `python3 scripts/validate-chores.py` · `cd server && npm test` · `swift test --package-path Packages/RoostCore` · `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (`id=<udid>` for a dedicated simulator). Baseline before this plan: RoostCore 56, RoostDesign 47, RoostTests 324, RoostUITests 22, server 147.

## File structure

| Area | Files | Responsibility |
|---|---|---|
| Data | `data/chores.json`, `scripts/validate-chores.py`, `data/README.md` | the keys, their rules, the pinned window map |
| RoostCore | `Sources/RoostCore/Models.swift` (`Chore.weekdays`, `Chore.dueDay`, `hasWindow`), `HouseholdCalendar.swift` (`dueWindow`), `Scheduler.swift` (`DueItem.dueFirstDay/dueLastDay`, window rules), `README.md` | the one place window arithmetic lives |
| RoostCore tests | `ChoreListTests.swift` (v4 + window map), `CalendarAndRotationTests.swift` (`dueWindow`), `SchedulerAndTalliesTests.swift` (the dates table) | pin the Swift side |
| Server | `src/db.js` (columns, v4 migration, seed, shape), `src/rules.js` (`dueWindow`, `hasWindow`, `dueItemFor`), `README.md` | mirror |
| Server tests | `test/rules.test.js` (dates table), `test/api.test.js`, `test/lists.test.js`, `test/pairing.test.js` (version 4), `test/migrate.test.js` (v4), `test/push.test.js` (recomputed fixtures) | pin the Node side |
| App | `Models/Records.swift`, `Models/Converters.swift`, `Sync/SyncAPI.swift`, `Sync/SyncClient.swift`, `Models/WindowCopy.swift` (new), `Screens/ChoreListScreen.swift`, `Strings.swift`, `Debug/UITestSeed.swift`, `README.md` | carry the fields, show the window in All chores |
| App tests | `Tests/SeedTests.swift`, `Tests/SyncTests.swift`, `Tests/TodayPlannerTests.swift`, `Tests/WindowCopyTests.swift` (new), `UITests/ChoreListWindowTests.swift` (new) | |
| Notes | `NOTES.md` | the decision line |

Interfaces every later task relies on (from Task 2–4):

```swift
// RoostCore
public struct Chore { …; public let weekdays: [Int]?; public let dueDay: Int?; public var hasWindow: Bool }
public init(id:title:cadence:fixedAssignee:category:season:together:weekdays:dueDay:) // weekdays/dueDay default nil
extension HouseholdCalendar { public func dueWindow(for chore: Chore, periodIndex: Int) -> (firstDay: Date, lastDay: Date) }
public struct DueItem { …; public let dueFirstDay: Date; public let dueLastDay: Date } // == period bounds when unwindowed
extension Scheduler { public func effectivePeriod(for chore: Chore, containing date: Date) -> Int }
```
```js
// server/src/rules.js
export function hasWindow(chore)            // boolean
export function dueWindow(chore, index)      // { firstDay, lastDay } — Chicago day starts
export function effectivePeriod(chore, date) // calendar period, or the next one once its window has opened
// dueItemFor(...) result gains dueFirstDay, dueLastDay
```

---

### Task 1: chores.json v4, validator, data README

**Files:**
- Modify: `data/chores.json`
- Modify: `scripts/validate-chores.py`
- Modify: `data/README.md`

- [ ] **Step 1: Make the validator demand v4 and the windows (it fails first)**

In `scripts/validate-chores.py`:

```python
OPTIONAL_CHORE_KEYS = ("season", "together", "weekdays", "dueDay")
WINDOW_MONTH_CADENCES = frozenset({"monthly", "bimonthly", "quarterly"})

EXPECTED_VERSION = 4
# EXPECTED_COUNTS / EXPECTED_COUNT / EXPECTED_PINNED unchanged (41, ten pins)
EXPECTED_WEEKDAYS = {
    "take-out-garbage-basement": [5, 6],
    "take-out-garbage-bathroom": [5, 6],
    "take-out-garbage-kitchen": [5, 6],
    "garbage-can-to-street-sunday": [7],
}
EXPECTED_DUE_DAYS = {
    "clean-under-cushions": 5,
    "wash-all-rugs": 8,
    "trim-wes-hair": 10,
    "clean-inside-ovens": 12,
    "clean-garbage-cans": 14,
    "wipe-dust-bar-cart": 15,
    "clean-under-couches": 19,
    "wipe-down-doors": 21,
    "clean-medicine-cabinet": 22,
    "change-litter": 25,
    "clean-out-fridge-pantry": 28,
}


def check_weekdays(loc: str, days: object, chore: dict) -> None:
    if not isinstance(days, list) or not days:
        fail(f"{loc}.weekdays must be a non-empty list")
    for d in days:
        if not isinstance(d, int) or isinstance(d, bool) or not 1 <= d <= 7:
            fail(f"{loc}.weekdays has a value outside 1..7 (Monday = 1 … Sunday = 7): {d!r}")
    if days != sorted(set(days)):
        fail(f"{loc}.weekdays must be ascending and unique")
    if chore["cadence"] != "weekly":
        fail(f"{loc}: weekdays only belong on a weekly chore, got {chore['cadence']!r}")


def check_due_day(loc: str, day: object, chore: dict) -> None:
    if not isinstance(day, int) or isinstance(day, bool) or not 1 <= day <= 28:
        fail(f"{loc}.dueDay must be an integer 1..28, got {day!r}")
    if chore["cadence"] not in WINDOW_MONTH_CADENCES:
        fail(f"{loc}: dueDay only belongs on a monthly, bimonthly or quarterly chore, got {chore['cadence']!r}")
```

In `main()`, next to `pinned`, add `weekdays: dict[str, list[int]] = {}` and `due_days: dict[str, int] = {}`; inside the loop after the season check:

```python
        if "weekdays" in chore:
            check_weekdays(loc, chore["weekdays"], chore)
            weekdays[cid] = chore["weekdays"]
        if "dueDay" in chore:
            check_due_day(loc, chore["dueDay"], chore)
            due_days[cid] = chore["dueDay"]
        elif cadence in WINDOW_MONTH_CADENCES:
            fail(f"{loc} ({cid}): every {cadence} chore needs a dueDay (1..28) so nothing bunches on the 1st")
```

After the pinned comparison:

```python
    if weekdays != EXPECTED_WEEKDAYS:
        fail(f"weekday windows {weekdays} do not match {EXPECTED_WEEKDAYS}")
    if due_days != EXPECTED_DUE_DAYS:
        fail(f"due days {due_days} do not match {EXPECTED_DUE_DAYS}")
```

And two print lines after `together`: `print("  weekdays: " + ", ".join(f"{cid}→{d}" for cid, d in weekdays.items()))` and `print("  dueDay: " + ", ".join(f"{cid}→{d}" for cid, d in due_days.items()))`. Update the docstring schema block (optional `weekdays`, `dueDay`, version 4).

- [ ] **Step 2: Run it, expect the version failure**

Run: `python3 scripts/validate-chores.py`
Expected: `FAIL: version must be 4, got 3`, exit 1.

- [ ] **Step 3: Edit the data**

`data/chores.json`: `"version": 4`; `"locked": "2026-09-14"`; notes → `"Version 4, 2026-09-14: due windows from Anne's feedback on issue #1. weekdays (Mon=1…Sun=7) on the three take-out-garbage rows [5, 6] and garbage-can-to-street-sunday [7]; a dueDay on every monthly, bimonthly and quarterly chore (window = the 7 days ending on it), change-litter on the 25th. 41 tasks (13 daily + 12 weekly + 5 biweekly + 7 monthly + 1 bimonthly + 3 quarterly). Grouped by cadence; the order is sortOrder. Mockup sample rows are illustrative and must not be merged in."`. Add `"weekdays": [5, 6]` after `category` on the three garbage rows, `"weekdays": [7]` on the can, and `"dueDay": N` after `category` on the eleven month-based rows per `EXPECTED_DUE_DAYS`.

- [ ] **Step 4: Run the validator, expect OK**

Run: `python3 scripts/validate-chores.py`
Expected: `OK`, `version: 4`, `chores: 41`, the weekdays line with four ids, the dueDay line with eleven.

- [ ] **Step 5: data/README.md**

Field table gains `weekdays` (`[int]`, optional, weekly only, Mon = 1 … Sun = 7, window = earliest…latest day) and `dueDay` (int 1–28, required on monthly/bimonthly/quarterly, window = the 7 days ending on it in the period's last month). Add the spec's window table. Count line → `version 4 since 2026-09-14`. Validate section: also checks the window rules and the window map.

- [ ] **Step 6: Commit**

```bash
git add data/chores.json scripts/validate-chores.py data/README.md
git commit -m "chores.json v4: weekday windows on garbage, a due day on every monthly chore"
```

---

### Task 2: RoostCore `Chore` gains `weekdays` and `dueDay`

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/Models.swift`
- Modify: `Packages/RoostCore/Tests/RoostCoreTests/ChoreListTests.swift`

**Interfaces — Produces:** `Chore.weekdays: [Int]?`, `Chore.dueDay: Int?`, `Chore.hasWindow: Bool`, the widened `init`.

- [ ] **Step 1: Failing tests**

In `ChoreListTests`, rename `testRealSeedHas41ChoresAndTenPinned` → `testRealSeedHas41ChoresTenPinsAndFifteenWindows`; change `XCTAssertEqual(list.version, 3)` → `4`; append:

```swift
        let weekdays = Dictionary(uniqueKeysWithValues: list.chores.compactMap { c in c.weekdays.map { (c.id, $0) } })
        XCTAssertEqual(weekdays, [
            "take-out-garbage-basement": [5, 6], "take-out-garbage-bathroom": [5, 6],
            "take-out-garbage-kitchen": [5, 6], "garbage-can-to-street-sunday": [7],
        ])
        let dueDays = Dictionary(uniqueKeysWithValues: list.chores.compactMap { c in c.dueDay.map { (c.id, $0) } })
        XCTAssertEqual(dueDays, [
            "clean-under-cushions": 5, "wash-all-rugs": 8, "trim-wes-hair": 10, "clean-inside-ovens": 12,
            "clean-garbage-cans": 14, "wipe-dust-bar-cart": 15, "clean-under-couches": 19, "wipe-down-doors": 21,
            "clean-medicine-cabinet": 22, "change-litter": 25, "clean-out-fridge-pantry": 28,
        ])
        XCTAssertTrue(list.chores.filter { $0.cadence.monthsPerPeriod != nil }.allSatisfy { $0.dueDay != nil })
        XCTAssertEqual(list.chores.filter(\.hasWindow).count, 15)
```

Add a decoder test beside `testSeasonAndTogetherDecodeAndDefault`:

```swift
    func testWindowKeysDecodeAndDefault() throws {
        let v3 = #"{"id":"x","title":"X","cadence":"weekly","fixedAssignee":null,"category":"chore"}"#
        let plain = try JSONDecoder().decode(Chore.self, from: Data(v3.utf8))
        XCTAssertNil(plain.weekdays); XCTAssertNil(plain.dueDay); XCTAssertFalse(plain.hasWindow)

        let v4 = #"{"id":"g","title":"G","cadence":"weekly","fixedAssignee":null,"category":"chore","weekdays":[5,6]}"#
        let garbage = try JSONDecoder().decode(Chore.self, from: Data(v4.utf8))
        XCTAssertEqual(garbage.weekdays, [5, 6]); XCTAssertTrue(garbage.hasWindow)

        let litter = Chore(id: "l", title: "L", cadence: .monthly, category: .catCare, dueDay: 25)
        let round = try JSONDecoder().decode(Chore.self, from: JSONEncoder().encode(litter))
        XCTAssertEqual(round.dueDay, 25); XCTAssertEqual(round, litter)
    }
```

Run: `swift test --package-path Packages/RoostCore` — Expected: compile errors (`weekdays`, `dueDay`, `hasWindow` unknown).

- [ ] **Step 2: Implement**

In `Chore`: two stored properties after `together` —

```swift
    /// Weekly only: ISO weekdays (Monday = 1 … Sunday = 7) the chore is due on; the window runs from the
    /// earliest to the latest. Nil for a whole-week chore.
    public let weekdays: [Int]?
    /// Monthly, bimonthly and quarterly: the day of the period's last month the chore is due by (1...28);
    /// the window is the seven days ending on it. Nil for a whole-period chore.
    public let dueDay: Int?

    public var hasWindow: Bool { !(weekdays ?? []).isEmpty || dueDay != nil }
```

Widen `init` with `weekdays: [Int]? = nil, dueDay: Int? = nil` (assign both), add `weekdays, dueDay` to `CodingKeys`, and in `init(from:)`: `weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays)`, `dueDay = try c.decodeIfPresent(Int.self, forKey: .dueDay)`. Synthesized `encode(to:)` already emits them (nil → omitted? No — synthesized Codable encodes nil optionals as absent only with `encodeIfPresent`; add an explicit `encode(to:)` that uses `encodeIfPresent` for `fixedAssignee`, `season`, `weekdays`, `dueDay` and `encode` for the rest, so fixtures and the round-trip stay tidy). Check whether the file already has a custom `encode(to:)`; extend it if so.

- [ ] **Step 3: Run, expect green**

Run: `swift test --package-path Packages/RoostCore` — Expected: 57 tests, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Packages/RoostCore
git commit -m "RoostCore: Chore carries weekdays and dueDay (v4 keys, decoder defaults)"
```

---

### Task 3: `HouseholdCalendar.dueWindow`

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/HouseholdCalendar.swift`
- Modify: `Packages/RoostCore/Tests/RoostCoreTests/CalendarAndRotationTests.swift`

**Interfaces — Consumes:** `Chore.weekdays`, `Chore.dueDay`. **Produces:** `dueWindow(for:periodIndex:)`.

- [ ] **Step 1: Failing test** (in `CalendarTests`)

```swift
    func testDueWindowInsideThePeriod() {
        // Week of Mon 2026-09-14 is weekly period 36 (dayIndex 252 / 7).
        XCTAssertEqual(cal.periodIndex(.weekly, containing: cal.date(year: 2026, month: 9, day: 14)), 36)
        let garbage = Chore(id: "g", title: "G", cadence: .weekly, category: .chore, weekdays: [5, 6])
        let g = cal.dueWindow(for: garbage, periodIndex: 36)
        XCTAssertEqual(g.firstDay, cal.date(year: 2026, month: 9, day: 18, hour: 0))
        XCTAssertEqual(g.lastDay, cal.date(year: 2026, month: 9, day: 19, hour: 0))

        let can = Chore(id: "c", title: "C", cadence: .weekly, fixedAssignee: .wes, category: .chore, weekdays: [7])
        let s = cal.dueWindow(for: can, periodIndex: 36)
        XCTAssertEqual(s.firstDay, cal.date(year: 2026, month: 9, day: 20, hour: 0))
        XCTAssertEqual(s.lastDay, s.firstDay)

        // September 2026 is monthly period 8, bimonthly 4 (Sep–Oct), quarterly 2 (Jul–Sep).
        let litter = Chore(id: "l", title: "L", cadence: .monthly, category: .catCare, dueDay: 25)
        let m = cal.dueWindow(for: litter, periodIndex: 8)
        XCTAssertEqual(m.firstDay, cal.date(year: 2026, month: 9, day: 19, hour: 0))
        XCTAssertEqual(m.lastDay, cal.date(year: 2026, month: 9, day: 25, hour: 0))

        let hair = Chore(id: "h", title: "H", cadence: .bimonthly, fixedAssignee: .anne, category: .chore, dueDay: 10)
        let b = cal.dueWindow(for: hair, periodIndex: 4)
        XCTAssertEqual(b.firstDay, cal.date(year: 2026, month: 10, day: 4, hour: 0))
        XCTAssertEqual(b.lastDay, cal.date(year: 2026, month: 10, day: 10, hour: 0))

        let pantry = Chore(id: "p", title: "P", cadence: .quarterly, category: .chore, together: true, dueDay: 28)
        let q = cal.dueWindow(for: pantry, periodIndex: 2)
        XCTAssertEqual(q.firstDay, cal.date(year: 2026, month: 9, day: 22, hour: 0))
        XCTAssertEqual(q.lastDay, cal.date(year: 2026, month: 9, day: 28, hour: 0))

        // No window: the period itself. A dueDay early in a month reaches back into the month before.
        let laundry = Chore(id: "w", title: "W", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        let w = cal.dueWindow(for: laundry, periodIndex: 36)
        XCTAssertEqual(w.firstDay, cal.date(year: 2026, month: 9, day: 14, hour: 0))
        XCTAssertEqual(w.lastDay, cal.date(year: 2026, month: 9, day: 20, hour: 0))
        let cushions = Chore(id: "u", title: "U", cadence: .monthly, category: .chore, dueDay: 5)
        XCTAssertEqual(cal.dueWindow(for: cushions, periodIndex: 9).firstDay, cal.date(year: 2026, month: 9, day: 29, hour: 0))
    }
```

- [ ] **Step 2: Implement** (after `periodBounds`)

```swift
    /// The days inside period `index` on which `chore` is due: the period itself for a chore without a
    /// window; the earliest through the latest listed weekday for a weekly chore with `weekdays`; the seven
    /// days ending on `dueDay` of the period's last month for a month-based chore with `dueDay`.
    public func dueWindow(for chore: Chore, periodIndex index: Int) -> (firstDay: Date, lastDay: Date) {
        let bounds = periodBounds(chore.cadence, index: index)
        if chore.cadence == .weekly, let days = chore.weekdays, let first = days.min(), let last = days.max() {
            return (adding(days: first - 1, to: bounds.firstDay), adding(days: last - 1, to: bounds.firstDay))
        }
        if let months = chore.cadence.monthsPerPeriod, let dueDay = chore.dueDay {
            let lastMonth = calendar.date(byAdding: .month, value: months - 1, to: bounds.firstDay)!
            let due = adding(days: dueDay - 1, to: lastMonth)
            return (adding(days: -6, to: due), due)
        }
        return bounds
    }
```

- [ ] **Step 3: Run** — Expected: 58 tests, 0 failures.

- [ ] **Step 4: Commit** — `git commit -am "RoostCore: HouseholdCalendar.dueWindow — weekday and due-day windows inside a period"`

---

### Task 4: `DueItem` window bounds and the two window rules in `Scheduler.dueItem`

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/Scheduler.swift`
- Create: `Packages/RoostCore/Tests/RoostCoreTests/DueWindowTests.swift`
- Modify: `Packages/RoostCore/README.md`

**Interfaces — Consumes:** `HouseholdCalendar.dueWindow(for:periodIndex:)`, `Chore.hasWindow`. **Produces:** `DueItem.dueFirstDay`, `DueItem.dueLastDay`; `daysOverdue` now counts from `dueLastDay`.

- [ ] **Step 1: Failing tests** — new file, same helper style as `SchedulerTests`:

```swift
@testable import RoostCore
import XCTest

/// The spec's "Dates that must hold": household starts Monday 2026-09-14.
final class DueWindowTests: XCTestCase {
    let cal = HouseholdCalendar()
    let garbage = Chore(id: "take-out-garbage-kitchen", title: "Take out garbage: kitchen", cadence: .weekly,
                        category: .chore, weekdays: [5, 6])
    let can = Chore(id: "garbage-can-to-street-sunday", title: "Garbage can to street, Sunday", cadence: .weekly,
                    fixedAssignee: .wes, category: .chore, weekdays: [7])
    let litter = Chore(id: "change-litter", title: "Change litter", cadence: .monthly, category: .catCare, dueDay: 25)
    let hair = Chore(id: "trim-wes-hair", title: "Trim Wes's hair", cadence: .bimonthly, fixedAssignee: .anne,
                     category: .chore, dueDay: 10)
    let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry", cadence: .quarterly,
                       category: .chore, together: true, dueDay: 28)
    let cushions = Chore(id: "clean-under-cushions", title: "Clean/vacuum under cushions", cadence: .monthly,
                         category: .chore, dueDay: 5)
    let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)

    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 14, hour: 0)
    lazy var scheduler = Scheduler(chores: [garbage, can, litter, hair, pantry, cushions, laundry],
                                   activeFrom: activeFrom, calendar: cal)

    func day(_ month: Int, _ day: Int, year: Int = 2026) -> Date { cal.date(year: year, month: month, day: day, hour: 9) }
    func overdue(_ chore: Chore, _ date: Date, _ completions: [Completion] = []) -> Int? {
        scheduler.dueItem(for: chore, on: date, completions: completions)?.daysOverdue
    }
    func done(_ chore: Chore, _ person: Person, _ date: Date) -> Completion {
        Completion(id: "\(chore.id)-\(date.timeIntervalSince1970)", choreId: chore.id, person: person, completedAt: date)
    }

    func testGarbageIsFridaySaturdayThenLate() {
        for d in 14 ... 17 { XCTAssertNil(overdue(garbage, day(9, d)), "Sep \(d) is before the window") }
        XCTAssertEqual(overdue(garbage, day(9, 18)), 0)
        XCTAssertEqual(overdue(garbage, day(9, 19)), 0)
        XCTAssertEqual(overdue(garbage, day(9, 20)), 1)
        // Monday: the oldest incomplete period is still the week of the 14th; late counts from Sat 19.
        let monday = scheduler.dueItem(for: garbage, on: day(9, 21), completions: [])
        XCTAssertEqual(monday?.daysOverdue, 2)
        XCTAssertEqual(monday?.periodIndex, 36)
        XCTAssertEqual(monday?.dueFirstDay, cal.date(year: 2026, month: 9, day: 18, hour: 0))
        XCTAssertEqual(monday?.dueLastDay, cal.date(year: 2026, month: 9, day: 19, hour: 0))
        XCTAssertEqual(monday?.periodLastDay, cal.date(year: 2026, month: 9, day: 20, hour: 0))
        // Done on Sunday: clear, and the next window opens Fri 25.
        let sunday = [done(garbage, .anne, day(9, 20))]
        for d in 21 ... 24 { XCTAssertNil(overdue(garbage, day(9, d), sunday)) }
        XCTAssertEqual(overdue(garbage, day(9, 25), sunday), 0)
    }

    func testCanIsSundayOnly() {
        for d in 14 ... 19 { XCTAssertNil(overdue(can, day(9, d))) }
        XCTAssertEqual(overdue(can, day(9, 20)), 0)
        XCTAssertEqual(overdue(can, day(9, 21)), 1)
        XCTAssertEqual(scheduler.dueItem(for: can, on: day(9, 20), completions: [])?.person, .wes)
    }

    func testLitterChangeIsTheWeekEndingOnThe25th() {
        for d in 14 ... 18 { XCTAssertNil(overdue(litter, day(9, d))) }
        XCTAssertEqual(overdue(litter, day(9, 19)), 0)
        XCTAssertEqual(overdue(litter, day(9, 25)), 0)
        XCTAssertEqual(overdue(litter, day(9, 26)), 1)
        let doneEarly = [done(litter, .wes, day(9, 20))]
        XCTAssertNil(overdue(litter, day(9, 26), doneEarly))
        for d in 1 ... 18 { XCTAssertNil(overdue(litter, day(10, d), doneEarly)) }
        XCTAssertEqual(overdue(litter, day(10, 19), doneEarly), 0)
    }

    func testBimonthlyAndQuarterlyUseThePeriodsLastMonth() {
        XCTAssertNil(overdue(hair, day(9, 30)))
        XCTAssertNil(overdue(hair, day(10, 3)))
        XCTAssertEqual(overdue(hair, day(10, 4)), 0)
        XCTAssertEqual(overdue(hair, day(10, 10)), 0)
        XCTAssertEqual(overdue(hair, day(10, 11)), 1)

        XCTAssertNil(overdue(pantry, day(9, 21)))
        let both = scheduler.dueItems(for: pantry, on: day(9, 22), completions: [])
        XCTAssertEqual(both.map(\.person), [.anne, .wes])
        XCTAssertEqual(both.map(\.daysOverdue), [0, 0])
        XCTAssertEqual(overdue(pantry, day(9, 29)), 1)
        XCTAssertTrue(scheduler.dueItems(for: pantry, on: day(9, 29), completions: [done(pantry, .anne, day(9, 23))]).isEmpty)
    }

    func testWindowClosedBeforeTheHouseholdStartedWasNeverOwed() {
        // Cushions are due by the 5th; the household starts the 14th. Nothing in September, then Sep 29 – Oct 5.
        for d in 14 ... 28 { XCTAssertNil(overdue(cushions, day(9, d)), "Sep \(d)") }
        XCTAssertEqual(overdue(cushions, day(9, 29)), 0)
        XCTAssertEqual(overdue(cushions, day(10, 5)), 0)
        XCTAssertEqual(overdue(cushions, day(10, 6)), 1)
        // Same rule for a weekly window: start on Sunday Sep 13 and the Fri–Sat garbage was never owed that week.
        let sundayStart = Scheduler(chores: [garbage], activeFrom: cal.date(year: 2026, month: 9, day: 13, hour: 0), calendar: cal)
        XCTAssertNil(sundayStart.dueItem(for: garbage, on: day(9, 13), completions: []))
        XCTAssertNil(sundayStart.dueItem(for: garbage, on: day(9, 17), completions: []))
        XCTAssertEqual(sundayStart.dueItem(for: garbage, on: day(9, 18), completions: [])?.daysOverdue, 0)
    }

    func testAnEarlyWindowBelongsToItsPeriodForDatesAndCompletions() {
        // Cushions' October window opens Sep 29 and reports October's period. A completion on Sep 30 is
        // October's, so nothing is due Oct 1–29 and the November window (Oct 30 – Nov 5) opens on time.
        XCTAssertEqual(scheduler.dueItem(for: cushions, on: day(9, 29), completions: [])?.periodIndex, 9)
        let early = [done(cushions, .wes, day(9, 30))]
        for d in 1 ... 29 { XCTAssertNil(overdue(cushions, day(10, d), early), "Oct \(d)") }
        XCTAssertEqual(overdue(cushions, day(10, 30), early), 0)
        XCTAssertEqual(overdue(cushions, day(11, 5), early), 0)
        XCTAssertEqual(overdue(cushions, day(11, 6), early), 1)
        // A late completion still clears the late period: litter changed Sep 27 clears September; October opens Oct 19.
        let late = [done(litter, .anne, day(9, 27))]
        XCTAssertNil(overdue(litter, day(9, 28), late))
        XCTAssertNil(overdue(litter, day(10, 18), late))
        XCTAssertEqual(overdue(litter, day(10, 19), late), 0)
    }

    func testUnwindowedChoreIsUnchanged() {
        for d in 14 ... 20 { XCTAssertEqual(overdue(laundry, day(9, d)), 0) }
        XCTAssertEqual(overdue(laundry, day(9, 21)), 1)
        let item = scheduler.dueItem(for: laundry, on: day(9, 16), completions: [])
        XCTAssertEqual(item?.dueFirstDay, item?.periodStart)
        XCTAssertEqual(item?.dueLastDay, item?.periodLastDay)
    }
}
```

Run: `swift test --package-path Packages/RoostCore` — Expected: compile errors (`dueFirstDay`, `dueLastDay`), then failures once the fields exist.

- [ ] **Step 2: Implement**

`DueItem`: add after `periodLastDay`

```swift
    /// The first and last day the chore is actually due inside that period — the period itself unless the
    /// chore has a window (`weekdays` or `dueDay`). Overdue counting begins the day after `dueLastDay`.
    public let dueFirstDay: Date
    public let dueLastDay: Date
```

and carry both in `with(person:)`. In `dueItem(for:on:completions:handoffs:)` replace the body from `var floor` through the return with:

```swift
        let current = effectivePeriod(for: chore, containing: date)
        var floor = effectivePeriod(for: chore, containing: activeFrom)
        // A window that closed before the household started was never owed: start at the next period.
        if chore.hasWindow,
           calendar.dueWindow(for: chore, periodIndex: floor).lastDay < calendar.startOfDay(activeFrom) {
            floor += 1
        }
        if let season = chore.season {
            guard let start = firstPeriod(inSeason: season, endingAt: current, notBefore: floor, cadence: chore.cadence)
            else { return nil }
            floor = max(floor, start)
        }
        let lastDone = completions
            .filter { $0.choreId == chore.id }
            .map { effectivePeriod(for: chore, containing: $0.completedAt) }
            .max()
        let oldestIncomplete = max((lastDone.map { $0 + 1 }) ?? floor, floor)
        guard oldestIncomplete <= current else { return nil }

        let bounds = calendar.periodBounds(chore.cadence, index: oldestIncomplete)
        let window = calendar.dueWindow(for: chore, periodIndex: oldestIncomplete)
        // Not yet: this period's window has not opened. A missed window from an older period still shows.
        if oldestIncomplete == current, calendar.startOfDay(date) < window.firstDay { return nil }
        let daysOverdue = max(0, calendar.dayIndex(date) - calendar.dayIndex(window.lastDay))
        return DueItem(
            chore: chore,
            person: chore.together
                ? .anne // both of them owe it; `dueItems` hands out the second row
                : assignee(for: chore, periodIndex: oldestIncomplete, on: date, handoffs: handoffs),
            periodIndex: oldestIncomplete,
            periodStart: bounds.firstDay,
            periodLastDay: bounds.lastDay,
            dueFirstDay: window.firstDay,
            dueLastDay: window.lastDay,
            daysOverdue: daysOverdue
        )
```

Add the helper next to `firstPeriod`:

```swift
    /// The period `date` belongs to for `chore`: its calendar period, or the next one once the next period's
    /// window has opened. A due day early in the month reaches back into the month before, and a day or a
    /// completion inside that early window counts for the period the window belongs to. Only a `dueDay`
    /// window can start before its period; a weekday window never leaves its week.
    public func effectivePeriod(for chore: Chore, containing date: Date) -> Int {
        let index = calendar.periodIndex(chore.cadence, containing: date)
        guard chore.dueDay != nil else { return index }
        let next = calendar.dueWindow(for: chore, periodIndex: index + 1)
        return calendar.startOfDay(date) >= next.firstDay ? index + 1 : index
    }
```

Update the type's doc comment (the "Model:" paragraph) with the three rules. Every other `DueItem(` construction in the package (grep: `FairnessBalancer`, tests) must pass the two new fields — pass the period bounds where no window is involved.

- [ ] **Step 3: Run** — Expected: 65 tests (56 + 1 + 1 + 7), 0 failures. Existing tests are untouched because their fixture chores have no window.

- [ ] **Step 4: README** — `Packages/RoostCore/README.md`: a "Due windows" paragraph under the scheduler section: the two keys, the window arithmetic (weekday min…max; seven days ending on `dueDay` of the last month), the never-owed and not-yet rules, `daysOverdue` from `dueLastDay`; the test count line if it states one.

- [ ] **Step 5: Commit** — `git add Packages/RoostCore && git commit -m "RoostCore: DueItem carries its window; dueItem applies never-owed and not-yet; overdue counts from the window's last day"`

---

### Task 5: Server columns, schema v4, seed and shape

**Files:**
- Modify: `server/src/db.js`
- Modify: `server/test/migrate.test.js`, `server/test/api.test.js`, `server/test/lists.test.js`, `server/test/pairing.test.js`

- [ ] **Step 1: Failing tests**

`migrate.test.js`, modelled on the v3 test at line 135: build a database with the v3 `chores` shape and `schemaVersion` 3 (copy that test's fixture SQL and add `season TEXT, together INTEGER NOT NULL DEFAULT 0` to the chores columns, one chore row), open it with `openDb`, assert `columns(db, "chores")` includes `weekdays` and `dueDay`, `getMeta(db, "schemaVersion") === "4"`, the old row survives with both nulls, and a second `openDb` is a no-op. Also extend the "fresh database" test's assertions to include the two columns.

`api.test.js`: `h.body.choresVersion` → 4; every `/sync?choresVersion=3` → `4` (also in `lists.test.js`); the retire test's trimmed file `version: 3` → `version: 5` and `chores.body.version` → 5; add to the seed test:

```js
  const can = app.db.prepare("SELECT weekdays, dueDay FROM chores WHERE id = 'garbage-can-to-street-sunday'").get();
  assert.deepEqual(JSON.parse(can.weekdays), [7]);
  assert.equal(can.dueDay, null);
  const litter = app.db.prepare("SELECT weekdays, dueDay FROM chores WHERE id = 'change-litter'").get();
  assert.equal(litter.weekdays, null);
  assert.equal(litter.dueDay, 25);
  const shaped = (await call("GET", "/chores", { token: ANNE })).body.chores;
  assert.deepEqual(shaped.find((c) => c.id === "garbage-can-to-street-sunday").weekdays, [7]);
  assert.equal(shaped.find((c) => c.id === "change-litter").dueDay, 25);
  assert.equal(shaped.find((c) => c.id === "laundry").weekdays, null);
  assert.equal(shaped.find((c) => c.id === "laundry").dueDay, null);
  assert.equal(shaped.filter((c) => c.dueDay != null).length, 11);
```

`pairing.test.js` keeps 41. Run `cd server && npm test` — Expected: the new assertions fail (no columns; version 3).

- [ ] **Step 2: Implement** in `db.js`

- `SCHEMA_VERSION = 4`.
- `CHORES_COLUMNS`: append `,\n  weekdays      TEXT,\n  dueDay        INTEGER CHECK (dueDay IS NULL OR dueDay BETWEEN 1 AND 28)`.
- `migrate`: `if (current < 4) migrateToV4(db);` and

```js
/**
 * v4 (due windows): weekdays (JSON array text) and dueDay on chores. Both nullable, so ADD COLUMN is enough;
 * guarded on the column list so a database built from the v4 schema string is left alone.
 */
function migrateToV4(db) {
  if (!columnNames(db, "chores").includes("weekdays")) {
    db.exec("ALTER TABLE chores ADD COLUMN weekdays TEXT");
  }
  if (!columnNames(db, "chores").includes("dueDay")) {
    db.exec("ALTER TABLE chores ADD COLUMN dueDay INTEGER CHECK (dueDay IS NULL OR dueDay BETWEEN 1 AND 28)");
  }
}
```

- `seedChores`: the upsert lists `weekdays, dueDay` (VALUES `?, ?`, `DO UPDATE SET weekdays = excluded.weekdays, dueDay = excluded.dueDay`), run with `c.weekdays ? JSON.stringify(c.weekdays) : null, c.dueDay ?? null`.
- `shapeChore`: `weekdays: row.weekdays ? JSON.parse(row.weekdays) : null, dueDay: row.dueDay ?? null`. `listChores` selects both columns. Check `migrateToV2`'s `INSERT INTO chores_v2 (…)` still lists only the columns it copies (it does; the new columns default to NULL).

- [ ] **Step 3: Run** — `cd server && npm test` — Expected: all green; count = 147 + the migrate test.

- [ ] **Step 4: Commit** — `git add server && git commit -m "server: chores carry weekdays and dueDay (schema v4, seed, shape); tests expect chores v4"`

---

### Task 6: `rules.js` mirror and the Node dates table

**Files:**
- Modify: `server/src/rules.js`
- Modify: `server/test/rules.test.js`, `server/test/push.test.js`
- Modify: `server/README.md`

- [ ] **Step 1: Failing tests** in `rules.test.js` (import `dueWindow`, `hasWindow`, `effectivePeriod`); dates via `chicagoLocal(y, m, d, 9, 0, 0)`, `activeFrom = chicagoLocal(2026, 9, 14, 0, 0, 0)`:

```js
const garbageK = { id: "take-out-garbage-kitchen", title: "Take out garbage: kitchen", cadence: "weekly", fixedAssignee: null, category: "chore", weekdays: [5, 6] };
const canW = { id: "garbage-can-to-street-sunday", title: "Garbage can to street, Sunday", cadence: "weekly", fixedAssignee: "wes", category: "chore", weekdays: [7] };
const litterW = { id: "change-litter", title: "Change litter", cadence: "monthly", fixedAssignee: null, category: "cat_care", dueDay: 25 };
const hairW = { id: "trim-wes-hair", title: "Trim Wes's hair", cadence: "bimonthly", fixedAssignee: "anne", category: "chore", dueDay: 10 };
const pantryW = { id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry", cadence: "quarterly", fixedAssignee: null, category: "chore", together: true, dueDay: 28 };
const cushionsW = { id: "clean-under-cushions", title: "Clean/vacuum under cushions", cadence: "monthly", fixedAssignee: null, category: "chore", dueDay: 5 };
const start14 = chicagoLocal(2026, 9, 14, 0, 0, 0);
const at = (m, d) => chicagoLocal(2026, m, d, 9, 0, 0);
const od = (chore, date, completions = [], activeFrom = start14) => dueItemFor(chore, { completions, asOf: date, activeFrom })?.daysOverdue ?? null;

test("dueWindow: weekday and due-day windows inside the period", () => {
  assert.deepEqual(dueWindow(garbageK, 36), { firstDay: dayAt(256), lastDay: dayAt(257) }); // Fri 18 – Sat 19 Sep (dayIndex 252 = Mon 14)
  assert.deepEqual(dueWindow(canW, 36), { firstDay: dayAt(258), lastDay: dayAt(258) });
  assert.deepEqual(dueWindow(litterW, 8), { firstDay: chicagoLocal(2026, 9, 19, 0, 0, 0), lastDay: chicagoLocal(2026, 9, 25, 0, 0, 0) });
  assert.deepEqual(dueWindow(hairW, 4), { firstDay: chicagoLocal(2026, 10, 4, 0, 0, 0), lastDay: chicagoLocal(2026, 10, 10, 0, 0, 0) });
  assert.deepEqual(dueWindow(pantryW, 2), { firstDay: chicagoLocal(2026, 9, 22, 0, 0, 0), lastDay: chicagoLocal(2026, 9, 28, 0, 0, 0) });
  assert.deepEqual(dueWindow(toilet, 36), periodBounds("weekly", 36));
  assert.equal(hasWindow(toilet), false); assert.equal(hasWindow(canW), true); assert.equal(hasWindow(litterW), true);
});

test("garbage is Friday–Saturday, late from Sunday, carried into Monday, cleared by a Sunday completion", () => {
  for (const d of [14, 15, 16, 17]) assert.equal(od(garbageK, at(9, d)), null, `Sep ${d}`);
  assert.equal(od(garbageK, at(9, 18)), 0);
  assert.equal(od(garbageK, at(9, 19)), 0);
  assert.equal(od(garbageK, at(9, 20)), 1);
  const mon = dueItemFor(garbageK, { completions: [], asOf: at(9, 21), activeFrom: start14 });
  assert.equal(mon.daysOverdue, 2); assert.equal(mon.periodIndex, 36);
  assert.deepEqual([mon.dueFirstDay, mon.dueLastDay], [dayAt(256), dayAt(257)]);
  const sunday = [{ choreId: garbageK.id, person: "anne", completedAt: at(9, 20).toISOString() }];
  for (const d of [21, 22, 23, 24]) assert.equal(od(garbageK, at(9, d), sunday), null);
  assert.equal(od(garbageK, at(9, 25), sunday), 0);
});

test("can is Sunday only; litter is the week ending on the 25th; bimonthly and quarterly use the last month", () => {
  for (const d of [14, 15, 16, 17, 18, 19]) assert.equal(od(canW, at(9, d)), null);
  assert.equal(od(canW, at(9, 20)), 0); assert.equal(od(canW, at(9, 21)), 1);
  for (const d of [14, 18]) assert.equal(od(litterW, at(9, d)), null);
  assert.equal(od(litterW, at(9, 19)), 0); assert.equal(od(litterW, at(9, 25)), 0); assert.equal(od(litterW, at(9, 26)), 1);
  const early = [{ choreId: litterW.id, person: "wes", completedAt: at(9, 20).toISOString() }];
  assert.equal(od(litterW, at(9, 26), early), null); assert.equal(od(litterW, at(10, 18), early), null); assert.equal(od(litterW, at(10, 19), early), 0);
  assert.equal(od(hairW, at(10, 3)), null); assert.equal(od(hairW, at(10, 4)), 0); assert.equal(od(hairW, at(10, 11)), 1);
  assert.equal(od(pantryW, at(9, 21)), null);
  const both = dueItems({ chores: [pantryW], completions: [], asOf: at(9, 22), activeFrom: start14 });
  assert.equal(both.anne.length, 1); assert.equal(both.wes.length, 1);
  assert.equal(od(pantryW, at(9, 29)), 1);
});

test("a window that closed before activeFrom was never owed", () => {
  for (let d = 14; d <= 28; d += 1) assert.equal(od(cushionsW, at(9, d)), null, `Sep ${d}`);
  assert.equal(od(cushionsW, at(9, 29)), 0); assert.equal(od(cushionsW, at(10, 5)), 0); assert.equal(od(cushionsW, at(10, 6)), 1);
  const start13 = chicagoLocal(2026, 9, 13, 0, 0, 0);
  assert.equal(od(garbageK, at(9, 13), [], start13), null);
  assert.equal(od(garbageK, at(9, 17), [], start13), null);
  assert.equal(od(garbageK, at(9, 18), [], start13), 0);
});

test("an early window belongs to its period for dates and completions", () => {
  assert.equal(dueItemFor(cushionsW, { completions: [], asOf: at(9, 29), activeFrom: start14 }).periodIndex, 9);
  assert.equal(effectivePeriod(cushionsW, at(9, 29)), 9); assert.equal(effectivePeriod(cushionsW, at(9, 28)), 8);
  const early = [{ choreId: cushionsW.id, person: "wes", completedAt: at(9, 30).toISOString() }];
  for (let d = 1; d <= 29; d += 1) assert.equal(od(cushionsW, at(10, d), early), null, `Oct ${d}`);
  assert.equal(od(cushionsW, at(10, 30), early), 0); assert.equal(od(cushionsW, at(11, 5), early), 0); assert.equal(od(cushionsW, at(11, 6), early), 1);
  const late = [{ choreId: litterW.id, person: "anne", completedAt: at(9, 27).toISOString() }];
  assert.equal(od(litterW, at(9, 28), late), null); assert.equal(od(litterW, at(10, 18), late), null); assert.equal(od(litterW, at(10, 19), late), 0);
});

test("an unwindowed chore is unchanged and reports its period as its window", () => {
  const item = dueItemFor(toilet, { completions: [], asOf: at(9, 16), activeFrom: start14 });
  assert.equal(item.daysOverdue, 0);
  assert.deepEqual([item.dueFirstDay, item.dueLastDay], [item.periodStart, item.periodLastDay]);
  assert.equal(od(toilet, at(9, 21)), 1);
});
```

(`dayAt(252)` is Monday 2026-09-14: 252 days after 2026-01-05. Fri 18 = 256, Sat 19 = 257, Sun 20 = 258.)

- [ ] **Step 2: Implement** in `rules.js`, after `periodBounds`:

```js
/** Whether the chore narrows its due days inside the period. Mirrors Chore.hasWindow. */
export function hasWindow(chore) {
  return (Array.isArray(chore.weekdays) && chore.weekdays.length > 0) || chore.dueDay != null;
}

/**
 * The days inside period `index` on which `chore` is due: the period itself without a window; the
 * earliest through the latest listed ISO weekday (Mon = 1 … Sun = 7) for a weekly chore with `weekdays`;
 * the seven days ending on `dueDay` of the period's last month for a month-based chore with `dueDay`.
 * Mirrors HouseholdCalendar.dueWindow(for:periodIndex:).
 */
export function dueWindow(chore, index) {
  const bounds = periodBounds(chore.cadence, index);
  if (chore.cadence === "weekly" && Array.isArray(chore.weekdays) && chore.weekdays.length > 0) {
    const first = Math.min(...chore.weekdays);
    const last = Math.max(...chore.weekdays);
    const start = dayIndex(bounds.firstDay);
    return { firstDay: dayAt(start + first - 1), lastDay: dayAt(start + last - 1) };
  }
  const months = MONTHS_PER_PERIOD[chore.cadence];
  if (months && chore.dueDay != null) {
    const lastMonth = index * months + months - 1; // month index of the period's last month
    const due = chicagoLocal(2026 + floorDiv(lastMonth, 12), mod(lastMonth, 12) + 1, chore.dueDay, 0, 0, 0);
    return { firstDay: dayAt(dayIndex(due) - 6), lastDay: due };
  }
  return bounds;
}
```

Also, after `dueWindow`:

```js
/**
 * The period `date` belongs to for `chore`: its calendar period, or the next one once the next period's
 * window has opened (a dueDay early in the month reaches back into the month before). Mirrors
 * Scheduler.effectivePeriod(for:containing:).
 */
export function effectivePeriod(chore, date) {
  const d = asDate(date);
  const index = periodIndex(chore.cadence, d);
  if (chore.dueDay == null) return index;
  const next = dueWindow(chore, index + 1);
  return dayIndex(d) >= dayIndex(next.firstDay) ? index + 1 : index;
}
```

In `dueItemFor`: `const current = effectivePeriod(chore, asOfD); let floor = effectivePeriod(chore, active);` replace the two `periodIndex(chore.cadence, …)` calls, and the completion loop uses `effectivePeriod(chore, asDate(c.completedAt))`. After `let floor = …`:

```js
  // A window that closed before the household started was never owed: start at the next period.
  if (hasWindow(chore) && dayIndex(dueWindow(chore, floor).lastDay) < dayIndex(active)) floor += 1;
```

and replace the `bounds`/`daysOverdue` lines with:

```js
  const bounds = periodBounds(chore.cadence, oldestIncomplete);
  const window = dueWindow(chore, oldestIncomplete);
  // Not yet: this period's window has not opened. A missed window from an older period still shows.
  if (oldestIncomplete === current && dayIndex(asOfD) < dayIndex(window.firstDay)) return null;
  const daysOverdue = Math.max(0, dayIndex(asOfD) - dayIndex(window.lastDay));
```

and add `dueFirstDay: window.firstDay, dueLastDay: window.lastDay` to the returned object. Anything in `rules.js` that spreads or rebuilds due items (`balance`, `boardStats`) keeps the two fields (check with `grep -n "periodLastDay" server/src`).

- [ ] **Step 3: Run** — `cd server && npm test`. Expected: the six new tests pass. `push.test.js` runs against the real v4 file with `activeFrom` Sep 7 and `asOf` Sep 20: the red-alert sweep now also sees the month-based chores whose windows have closed (rugs 8, ovens 12, garbage cans 14, bar cart 15 are alert-stage on Sep 20; couches 19 is nudge; cushions 5 is never owed). If any push assertion changes, recompute it from these rules and assert the new explicit set — do not loosen an assertion to make it pass. Report which assertions moved.

- [ ] **Step 4: README** — `server/README.md`: the two columns in the chores table, `dueWindow`/`hasWindow` in the rules list, and one sentence that the digest and red-alert sweep follow the window.

- [ ] **Step 5: Commit** — `git add server && git commit -m "server: rules mirror due windows (never-owed, not-yet, overdue from the window end); tests on the spec dates"`

---

### Task 7: App record, converters, seeder, sync DTO; the planner and sync tests

**Files:**
- Modify: `Roost/Sources/Models/Records.swift`, `Roost/Sources/Models/Converters.swift`, `Roost/Sources/Sync/SyncAPI.swift`, `Roost/Sources/Sync/SyncClient.swift`
- Modify: `Roost/Tests/SeedTests.swift`, `Roost/Tests/SyncTests.swift`, `Roost/Tests/TodayPlannerTests.swift`

**Interfaces — Consumes:** `Chore.weekdays/dueDay`. **Produces:** `ChoreRecord.weekdays: String?` (JSON array text), `ChoreRecord.dueDay: Int?`, `ChoreDTO.weekdays: [Int]?`, `ChoreDTO.dueDay: Int?`.

- [ ] **Step 1: Failing tests**

`SeedTests`: `testSeedLoads41RowsAnd10Pinned` → `choresVersion` 4; `testChoreRemovedFromFileIsRetiredAndReaddedIsRestored` trimmed `version: 4` → `5` and its assertion `4` → `5`; new test:

```swift
    func testWindowsRoundTripThroughTheRecord() throws {
        let can = Chore(id: "garbage-can-to-street-sunday", title: "Garbage can to street, Sunday", cadence: .weekly,
                        fixedAssignee: .wes, category: .chore, weekdays: [7])
        let litter = Chore(id: "change-litter", title: "Change litter", cadence: .monthly, category: .catCare, dueDay: 25)
        let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 4, chores: [can, litter, laundry]), into: context)
        let rows = try activeChores()
        XCTAssertEqual(try rows.map { try $0.toChore() }, [can, litter, laundry])
        XCTAssertEqual(rows[0].weekdays, "[7]")
        XCTAssertNil(rows[0].dueDay)
        XCTAssertNil(rows[1].weekdays)
        XCTAssertEqual(rows[1].dueDay, 25)
        XCTAssertNil(rows[2].weekdays)
        XCTAssertNil(rows[2].dueDay)

        // Re-seeding without the window clears it; broken weekday text is a conversion error, not a crash.
        let plainCan = Chore(id: can.id, title: can.title, cadence: .weekly, fixedAssignee: .wes, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 5, chores: [plainCan, litter, laundry]), into: context)
        XCTAssertNil(try activeChores()[0].weekdays)
        rows[0].weekdays = "[not json"
        XCTAssertThrowsError(try rows[0].toChore())
    }
```

`SyncTests.testDeltaWithChoresReseedsAndBumpsVersion`: the `trimmed` dictionary gains `"weekdays": $0.weekdays as Any, "dueDay": $0.dueDay as Any`; stub `choresVersion: 4` → `5`, assertion `4` → `5`; `active.count` stays 40. `testServerSentChoresCarrySeasonAndTogether` (or a sibling `testServerSentChoresCarryWindows`): the stub payload includes `"weekdays": [7]` on one chore and `"dueDay": 25` on another; after `syncNow`, the records' `weekdays == "[7]"` and `dueDay == 25`, and a chore sent without the keys has both nil.

`TodayPlannerTests.testPinnedChoresLandOnTheRightPerson` on Sunday 2026-09-13 with `activeFrom` that Sunday: of the 15 windowed chores only four are due that day — the can (Sunday), bar cart (window 9–15), couches (13–19), garbage cans (quarterly, 8–14); the three garbage rows (window 11–12 closed before the start), cushions (5), rugs (8), ovens (12) are never owed; medicine (22), litter (25), hair (Oct 4–10), doors (21) and pantry (22–28, two rows) are not yet. Twelve rows fewer:

```swift
        // every active chore is due for exactly one person on day one — except the together chore, due for both,
        // and the eleven windowed chores whose window is not open on Sep 13 (pantry counts twice): 42 - 12.
        XCTAssertEqual(Set(anne).intersection(wes), [], "the together chore's window (Sep 22–28) is not open")
        XCTAssertEqual(anne.count + wes.count, 30, "41 chores, 12 rows outside their window on Sep 13")
        XCTAssertEqual(plan.dueCount(for: .anne) + plan.dueCount(for: .wes), 30)
        XCTAssertTrue(wes.contains("garbage-can-to-street-sunday"), "Sunday is the can's day")
        XCTAssertFalse((anne + wes).contains("take-out-garbage-kitchen"), "Fri–Sat window closed before the household started")
        XCTAssertFalse((anne + wes).contains("change-litter"), "due the 19th–25th")

        // Two Sundays on: the together chore is inside its window and lands on both.
        let sep27 = cal.date(year: 2026, month: 9, day: 27)
        let later = try TodayPlanner.plan(chores: chores(), completions: [], asOf: sep27,
                                          activeFrom: cal.startOfDay(sunday), calendar: cal)
        XCTAssertEqual(Set(later.rows(for: .anne).map(\.chore.id)).intersection(later.rows(for: .wes).map(\.chore.id)),
                       ["clean-out-fridge-pantry"])
```

(Keep the existing laundry/can/mow-lawn assertions.) Run `xcodebuild … -only-testing:RoostTests test` — Expected: compile errors, then failures.

- [ ] **Step 2: Implement**

`Records.swift` `ChoreRecord`: after `together`,

```swift
    /// JSON text of the weekday list (`[5,6]`), the `season` pattern; nil for a whole-week chore.
    var weekdays: String?
    /// 1...28, the day of the period's last month the chore is due by; nil for a whole-period chore.
    var dueDay: Int?
```

with `weekdays: String? = nil, dueDay: Int? = nil` on `init`. (Two optional attributes: SwiftData lightweight migration handles them; nothing to declare.)

`Converters.swift`: `init(_ chore:sortOrder:)` and `apply` set `weekdays: Self.weekdaysText(chore.weekdays)` and `dueDay: chore.dueDay`; `toChore()` decodes `[Int]` from the text (`ConversionError.badWeekdays(text, id:)` with its description line) and passes `weekdays:`/`dueDay:` to `Chore(...)`; add

```swift
    /// The stored form of the weekday list: its JSON (`[5,6]`), or nil.
    static func weekdaysText(_ weekdays: [Int]?) -> String? {
        guard let weekdays, !weekdays.isEmpty, let data = try? JSONEncoder().encode(weekdays) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
```

`SyncAPI.ChoreDTO`: `let weekdays: [Int]?` and `let dueDay: Int?` (both optional, older servers omit them). `SyncClient.apply`: pass `weekdays: dto.weekdays, dueDay: dto.dueDay` into `Chore(...)`. Grep `Roost/Sources` and `Roost/Widget` for other `Chore(` constructions (UI seed, previews) — they compile unchanged because the new parameters default to nil.

- [ ] **Step 3: Run** — `xcodebuild … -only-testing:RoostTests test` — Expected: `** TEST SUCCEEDED **`, 324 + 1 (+1 if the sync test is a new method) tests.

- [ ] **Step 4: Commit** — `git add Roost && git commit -m "app: ChoreRecord, converters, seeder and sync carry weekdays and dueDay; planner test on the v4 windows"`

---

### Task 8: All chores shows the window

**Files:**
- Create: `Roost/Sources/Models/WindowCopy.swift`
- Modify: `Roost/Sources/Strings.swift`, `Roost/Sources/Screens/ChoreListScreen.swift`
- Create: `Roost/Tests/WindowCopyTests.swift`
- Run `xcodegen generate` from `Roost/` (two new files) and commit the pbxproj with them.

- [ ] **Step 1: Failing test**

```swift
@testable import Roost
import RoostCore
import XCTest

final class WindowCopyTests: XCTestCase {
    // Sunday-first, the way Calendar.shortWeekdaySymbols is laid out.
    let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    func testWeekdayWindows() {
        let garbage = Chore(id: "g", title: "G", cadence: .weekly, category: .chore, weekdays: [5, 6])
        XCTAssertEqual(WindowCopy.line(garbage, shortWeekdaySymbols: symbols), "Fri–Sat")
        let can = Chore(id: "c", title: "C", cadence: .weekly, category: .chore, weekdays: [7])
        XCTAssertEqual(WindowCopy.line(can, shortWeekdaySymbols: symbols), "Sun")
        let span = Chore(id: "s", title: "S", cadence: .weekly, category: .chore, weekdays: [1, 3])
        XCTAssertEqual(WindowCopy.line(span, shortWeekdaySymbols: symbols), "Mon–Wed")
    }

    func testDueDayWindows() {
        XCTAssertEqual(WindowCopy.line(Chore(id: "l", title: "L", cadence: .monthly, category: .catCare, dueDay: 25)), "by the 25th")
        XCTAssertEqual(WindowCopy.line(Chore(id: "u", title: "U", cadence: .monthly, category: .chore, dueDay: 1)), "by the 1st")
        XCTAssertEqual(WindowCopy.line(Chore(id: "d", title: "D", cadence: .quarterly, category: .chore, dueDay: 22)), "by the 22nd")
        XCTAssertEqual(WindowCopy.line(Chore(id: "t", title: "T", cadence: .bimonthly, category: .chore, dueDay: 3)), "by the 3rd")
    }

    func testNoWindowNoLine() {
        XCTAssertNil(WindowCopy.line(Chore(id: "w", title: "W", cadence: .weekly, category: .chore)))
        XCTAssertNil(WindowCopy.line(Chore(id: "x", title: "X", cadence: .weekly, category: .chore, weekdays: [9]), shortWeekdaySymbols: symbols))
    }
}
```

- [ ] **Step 2: Implement**

`Strings.swift`, beside `season(from:to:)` in `Strings.Chores`:

```swift
        /// Under a weekly chore with a window in All chores: "Fri–Sat". A one-day window is the day alone.
        static func window(from: String, to: String) -> String { "\(from)–\(to)" }
        /// Under a monthly, bimonthly or quarterly chore in All chores: "by the 25th".
        static func windowBy(_ ordinal: String) -> String { "by the \(ordinal)" }
```

`WindowCopy.swift`:

```swift
// How a chore's due window reads on the All chores screen. Pure, so the wording is tested without a screen.
import Foundation
import RoostCore

enum WindowCopy {
    /// "Fri–Sat" for weekdays [5, 6], "Sun" for [7], "by the 25th" for a due day; nil without a window or
    /// with a weekday outside 1...7. `shortWeekdaySymbols` is Sunday-first, as `Calendar` lays it out; the
    /// default follows the reader's locale and the tests pass English.
    static func line(
        _ chore: Chore,
        shortWeekdaySymbols: [String] = Calendar.autoupdatingCurrent.shortWeekdaySymbols
    ) -> String? {
        if let days = chore.weekdays, let first = days.min(), let last = days.max() {
            guard (1 ... 7).contains(first), (1 ... 7).contains(last), shortWeekdaySymbols.count == 7 else { return nil }
            let from = shortWeekdaySymbols[first % 7] // ISO Monday = 1 → index 1; Sunday = 7 → index 0
            let to = shortWeekdaySymbols[last % 7]
            return first == last ? from : Strings.Chores.window(from: from, to: to)
        }
        if let dueDay = chore.dueDay {
            let formatter = NumberFormatter()
            formatter.numberStyle = .ordinal
            guard let ordinal = formatter.string(from: NSNumber(value: dueDay)) else { return nil }
            return Strings.Chores.windowBy(ordinal)
        }
        return nil
    }
}
```

(If `NumberFormatter` ordinals come out locale-odd in the test host, pin `formatter.locale = Locale(identifier: "en_US")` in the test by passing a formatter through; otherwise leave it on the reader's locale.)

`ChoreListRow`: `private var windowLine: String? { chore.flatMap { WindowCopy.line($0) } }`; the `a11yValue` and the caption `Text` below the title show `windowLine` the same way `seasonLine` is shown (window first, then season, joined by `Strings.Lists.metaSeparator` when both exist — only `mow-lawn` has a season and it has no window, so in practice one line). The preview list at the bottom of the file gains a garbage row with `weekdays: [5, 6]` and a litter row with `dueDay: 25`.

- [ ] **Step 3: xcodegen + run** — `cd Roost && xcodegen generate && cd ..`; `xcodebuild … -only-testing:RoostTests test` — Expected: green, 3 more tests. Open All chores in the simulator and look: garbage rows read "Fri–Sat", the can "Sun", monthlies "by the Nth".

- [ ] **Step 4: Commit** — `git add Roost && git commit -m "app: All chores shows a chore's due window (Fri–Sat, Sun, by the 25th)"`

---

### Task 9: UI test — the window line on an isolated fixture

**Files:**
- Modify: `Roost/Sources/Debug/UITestSeed.swift`
- Create: `Roost/UITests/ChoreListWindowTests.swift`
- Run `xcodegen generate` from `Roost/`.

- [ ] **Step 1: The fixture** — add `case pairedWindows = "paired-windows"` to `UITestSeed`: everything `paired` seeds, plus one chore

```swift
Chore(id: "uitest-deep-clean", title: "Deep-clean the fridge", cadence: .quarterly, category: .chore, dueDay: 28)
```

and one completion for it by Anne dated **today** (so Today never shows it, whatever the real date), placed in whatever hook `paired` uses to seed completions. Follow how `shoppingLarge` extends `paired` (the fixture switch), so no other fixture changes.

- [ ] **Step 2: Failing UI test**

```swift
import XCTest

final class ChoreListWindowTests: RoostUITestCase {
    func testAllChoresShowsTheWindowLine() {
        let app = launch(fixture: "paired-windows") // whatever RoostUITestCase's launch helper is called
        // More → All chores, the same path the existing More tests use.
        app.tabBars.buttons["More"].tap()
        app.buttons["All chores"].tap()
        let row = app.staticTexts["Deep-clean the fridge"]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["by the 28th"].exists, "the quarterly chore shows its due day")
    }
}
```

Adapt the launch and navigation calls to `RoostUITestCase` (read `Roost/UITests/RoostUITestCase.swift` and `TodayBehaviourTests.swift` first; the More screen reaches All chores through `MoreRoute.allChores`).

- [ ] **Step 3: Run** — `xcodebuild … -only-testing:RoostUITests/ChoreListWindowTests test` — Expected: passes; then the full `xcodebuild … test` for the whole app: RoostTests 328–329, RoostUITests 23, `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit** — `git add Roost && git commit -m "ui test: All chores shows the due window on the paired-windows fixture"`

---

### Task 10: Docs and the decision line

**Files:**
- Modify: `Roost/README.md`, `NOTES.md` (and `Packages/RoostCore/README.md`, `server/README.md`, `data/README.md` if anything from Tasks 1, 4, 6 is still missing)

- [ ] **Step 1:** `Roost/README.md`: All chores shows a chore's window; the two keys ride `/sync` like `season`. `NOTES.md`: `2026-09-14 — Due windows: weekdays on weekly chores, a dueDay on every month-based chore (window = 7 days ending on it, in the period's last month); never-owed and not-yet rules; overdue counts from the window end. Spec docs/superpowers/specs/2026-09-14-due-windows-design.md.`
- [ ] **Step 2:** Run all four suites one last time on the rebased branch and paste the tails in the PR: validator OK v4; server green; RoostCore 65; app `** TEST SUCCEEDED **` with the RoostTests/RoostUITests counts.
- [ ] **Step 3: Commit and PR** — `git commit -am "docs: due windows"`, rebase on main, push `feat/due-windows`, open the PR against main with the tails in the body. Do not merge.

## Self-Review

**Spec coverage:** data keys + validator + README (Task 1); `Chore` fields (2); `dueWindow` arithmetic incl. last-month rule (3); `DueItem` bounds, never-owed, not-yet, early windows (`effectivePeriod`), overdue from window end, one nag (4); server columns/migration/seed/shape (5); rules mirror on the same dates, digest/red-alert follow (6); app record/DTO/seeder/sync, old builds ignore the keys, planner test (7); All chores copy (8); UI test on an isolated fixture (9); docs and NOTES (10). Rotation, pins, handoffs, streaks, escalation ladder: untouched by design — no task edits them.

**Placeholder scan:** none; every step carries code, commands and expected results. Task 9's launch/navigation helper names are to be read from `RoostUITestCase`, stated as such.

**Type consistency:** `Chore.weekdays: [Int]?` / `dueDay: Int?` (Tasks 2, 3, 4, 7, 8); `HouseholdCalendar.dueWindow(for:periodIndex:) -> (firstDay: Date, lastDay: Date)` (3, 4); `DueItem.dueFirstDay/dueLastDay` (4, 7 tests); server `dueWindow(chore, index) -> { firstDay, lastDay }`, `hasWindow(chore)` (6); `ChoreRecord.weekdays: String?` / `dueDay: Int?` (7, 8); `ChoreDTO.weekdays: [Int]?` / `dueDay: Int?` (7); `WindowCopy.line(_:shortWeekdaySymbols:)` (8, 9).

**Arithmetic checked:** Mon 2026-09-14 is dayIndex 252 (26 + 28 + 31 + 30 + 31 + 30 + 31 + 31 + 14), weekly period 36; September is monthIndex 8 → monthly 8, bimonthly 4 (Sep–Oct), quarterly 2 (Jul–Sep); the TodayPlanner Sunday-13 fixture drops 12 rows (3 garbage + cushions + rugs + ovens never owed; medicine, litter, hair, doors not yet; pantry ×2 not yet) → 30.
