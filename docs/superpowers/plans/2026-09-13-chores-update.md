# Chores Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Anne's chore-list changes: two longer cadences (every two months, every three months), a seasonal pause, chores the two of them do together, and the 39-chore list itself, on RoostCore, the server, and the app, without breaking rotation, escalation, streaks, handoffs, the kitchen board, or the digest.

**Architecture:** The cadence set, the season rule, and the together rule are each written once in `Packages/RoostCore` and mirrored line for line in `server/src/rules.js`; both sides are pinned to the same numbers by tests that read the same fixtures. The app stores the two new chore fields on `ChoreRecord` and shows them; the server adds them to its `chores` table through a one-time, versioned table rebuild. The list itself changes last, after every reader of `data/chores.json` understands the new keys, so no test suite ever sees a cadence it cannot decode.

**Tech Stack:** Swift 6 package (`swift test`), SwiftUI + SwiftData app on iOS 26 (`xcodebuild test`), Node 22 with `node:sqlite` and `node:test` (`npm test`), Python 3 stdlib for the validator.

**Spec:** `docs/superpowers/specs/2026-09-13-chores-update-design.md` (read it first; this plan argues from it and does not restate the reasons).

## Global Constraints

- `main` takes pull requests only. Rebase onto current `main` before opening one. Never merge your own PR.
- User-facing strings live in `Roost/Sources/Strings.swift`. Plain wording, no marketing copy.
- No secrets in the repo: no Team ID, certificates, provisioning profiles, APNs keys, device tokens.
- The Xcode project is generated: a new Swift file under `Roost/Sources` or `Roost/Tests` needs `cd Roost && xcodegen generate` and the regenerated `Roost/Roost.xcodeproj/project.pbxproj` committed. Never hand-edit the pbxproj.
- Swift is formatted by swiftformat and linted by swiftlint through the committed hook in `.claude/hooks`; commit what the hook leaves.
- Server: Node 22, built-in sqlite, **no dependencies**. `cd server && npm test` must pass with no network.
- Before calling app work done: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` prints `** TEST SUCCEEDED **`, and any screen you changed has been rendered in the simulator and looked at.
- Period 0 of every cadence contains the anchor Monday 2026-01-05 (America/Chicago). Escalation stays cadence-independent. Streaks stay daily-only.
- `monthIndex = (year - 2026) * 12 + (month - 1)`; bimonthly period = `floorDiv(monthIndex, 2)`; quarterly period = `floorDiv(monthIndex, 3)`.
- Fairness weights: daily 1, weekly 3, biweekly 5, monthly 8, **bimonthly 10, quarterly 13**.
- Period phrases, identical on both sides: daily "today", weekly and biweekly "this week", monthly "this month", **bimonthly "these two months", quarterly "this quarter"**.
- All-chores section labels: **"Every two months"**, **"Every three months"**.
- Together item id: `"<choreId>#<periodIndex>#<person>"`; every other id stays `"<choreId>#<periodIndex>"`.
- The list after the change: 39 chores, daily 11, weekly 12, biweekly 5, monthly 7, bimonthly 1, quarterly 3; pinned `laundry`, `wash-all-rugs`, `mow-lawn`, `trim-wes-hair` → anne, `garbage-can-to-street-sunday` → wes; `data/chores.json` `version: 2`.
- Rollout: server first (with the version-2 list), then the app build on Wes's phone by cable.

---

## Lanes and order

The tasks fall into four lanes. A and B can run in parallel (different people, different files). C depends on A. D depends on A, B and C being merged, because it changes the file that every test suite reads.

| Lane | Tasks | Who | Test command |
|---|---|---|---|
| A — RoostCore | 1–5 | an app-side agent | `swift test --package-path Packages/RoostCore` |
| B — server (ticket R-29) | 6–11 | the server worker | `cd server && npm test` |
| C — app | 12–15 | an app-side agent, after A is merged | the `xcodebuild … test` line above |
| D — data, validator, docs, rollout | 16–17 | the orchestrator, after A, B, C are merged | all three, plus `python3 scripts/validate-chores.py` |

Each lane is its own branch and PR (`core/cadences-season-together`, `server/r29-cadences-season-together`, `app/cadences-season-together`, `data/chores-v2`). Inside a lane, commit after every task.

## File structure

**RoostCore (lane A)**
- Modify `Packages/RoostCore/Sources/RoostCore/Models.swift` — `Cadence` gains two cases and `monthsPerPeriod`; new `Season` struct; `Chore` gains `season`, `together`, a decoding init with defaults.
- Modify `Packages/RoostCore/Sources/RoostCore/HouseholdCalendar.swift` — `monthIndex`, `month(of:)`, the month-based arms of `periodIndex` / `periodBounds`.
- Modify `Packages/RoostCore/Sources/RoostCore/FairnessBalancer.swift` — two weight fields; together chores are neither moved nor weighed.
- Modify `Packages/RoostCore/Sources/RoostCore/Scheduler.swift` — `DueItem.id`, `dueItems(for:…)`, the season floor, the together rows.
- Modify `Packages/RoostCore/Sources/RoostCore/Tallies.swift` — together credit in the week tally and the streak walk.
- Modify `Packages/RoostCore/Sources/RoostCore/HandoffRules.swift` — `canOffer` false for together.
- Tests: `CalendarAndRotationTests.swift`, `ChoreListTests.swift`, `SchedulerAndTalliesTests.swift`, `HandoffTests.swift`, `FairnessBalancerTests.swift`, all under `Packages/RoostCore/Tests/RoostCoreTests/`.
- Docs: `Packages/RoostCore/README.md`.

**Server (lane B)**
- Modify `server/src/rules.js` — `CADENCES`, `MONTHS_PER_PERIOD`, `monthIndex`, the two cadence arms, weights, `seasonStart`, together in `dueItemFor` / `dueItems` / `dueItemId` / `doneThisWeek` / `isDayComplete` / `isReassignable` / `balance` / `loads`.
- Modify `server/src/db.js` — `CHORES_COLUMNS`, schema version + `migrate`, `seedChores`, `shapeChore`, `listChores`.
- Modify `server/src/handoffs.js` — `HANDOFFS_COLUMNS` / `HANDOFFS_INDEXES`, cadence validation from `CADENCES`, together refusal.
- Modify `server/src/push.js` — `PERIOD_PHRASES`, the together red alert, chores through `listChores`.
- Tests: `server/test/rules.test.js`, new `server/test/migrate.test.js`, `server/test/handoffs.test.js`, `server/test/push.test.js`.
- Docs: `server/README.md`.

**App (lane C)**
- Modify `Roost/Sources/Models/Records.swift` — `ChoreRecord.season`, `.together`.
- Modify `Roost/Sources/Models/Converters.swift` — the two fields both ways; `ConversionError.badSeason`.
- Modify `Roost/Sources/Sync/SyncAPI.swift` — `ChoreDTO.season`, `.together`.
- Modify `Roost/Sources/Sync/SyncClient.swift` — server-sent chores carry the two fields.
- Modify `Roost/Sources/Strings.swift` — the chip, the two period phrases, the two section labels, the season line, the kitchen banner label.
- Modify `Roost/Sources/Models/HandoffPresentation.swift` — `Cadence.periodPhrase` arms.
- Modify `Roost/Sources/Screens/ChoreListScreen.swift` — `Cadence.label` arms, the season line, the together chip.
- Create `Roost/Sources/Models/SeasonCopy.swift` — "April to October".
- Modify `Roost/Sources/Tasks/ChoreRowView.swift` — the Together chip and its VoiceOver value.
- Modify `Roost/Sources/Models/KitchenModel.swift` and `Roost/Sources/Screens/KitchenScreen.swift` — one banner line per together alert.
- Tests: `Roost/Tests/SeedTests.swift`, `Roost/Tests/SyncTests.swift`, `Roost/Tests/HandoffPlanningTests.swift`, `Roost/Tests/TodayPlannerTests.swift`, `Roost/Tests/KitchenModelTests.swift`, new `Roost/Tests/SeasonCopyTests.swift`.
- Docs: `Roost/README.md`, `NOTES.md`.

**Data (lane D)**
- Modify `data/chores.json`, `scripts/validate-chores.py`, `data/README.md`, and the count assertions in `ChoreListTests`, `SeedTests`, `TodayPlannerTests`, `SyncTests`, `server/test/api.test.js`, `server/test/pairing.test.js`, plus `Packages/RoostCore/README.md` ("31 chores").

---

## Lane A — RoostCore

### Task 1: Two cadences in the calendar and the weight table

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/Models.swift:9-14`
- Modify: `Packages/RoostCore/Sources/RoostCore/HouseholdCalendar.swift:51-82`
- Modify: `Packages/RoostCore/Sources/RoostCore/FairnessBalancer.swift:9-33`
- Test: `Packages/RoostCore/Tests/RoostCoreTests/CalendarAndRotationTests.swift`
- Test: `Packages/RoostCore/Tests/RoostCoreTests/FairnessBalancerTests.swift:283-288`
- Test: `Packages/RoostCore/Tests/RoostCoreTests/SchedulerAndTalliesTests.swift`

**Interfaces:**
- Produces: `Cadence.bimonthly`, `Cadence.quarterly`, `Cadence.monthsPerPeriod: Int?` (1, 2, 3 for the month-based cadences, nil otherwise); `HouseholdCalendar.monthIndex(_:) -> Int`; `HouseholdCalendar.month(of:) -> Int` (1...12); `FairnessWeights.init(daily:weekly:biweekly:monthly:bimonthly:quarterly:)`; `FairnessWeights.provisional` = 1/3/5/8/10/13.

- [ ] **Step 1: Write the failing calendar tests**

In `CalendarAndRotationTests.swift`, extend `testAnchorIsAMondayAndPeriodZero` and add one test to `CalendarTests`:

```swift
    func testAnchorIsAMondayAndPeriodZero() {
        let weekday = cal.calendar.component(.weekday, from: cal.anchor)
        XCTAssertEqual(weekday, 2, "anchor is Monday")
        for cadence in Cadence.allCases {
            XCTAssertEqual(cal.periodIndex(cadence, containing: cal.anchor), 0, "\(cadence) period 0 holds the anchor")
        }
    }

    func testBimonthlyAndQuarterlyPeriodsAcrossAYearBoundary() {
        // September 2026 is monthIndex 8: bimonthly 4 (Sep–Oct), quarterly 2 (Jul–Sep).
        let sep = cal.date(year: 2026, month: 9, day: 13)
        XCTAssertEqual(cal.monthIndex(sep), 8)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: sep), 4)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: sep), 2)
        let bi = cal.periodBounds(.bimonthly, index: 4)
        XCTAssertEqual(bi.firstDay, cal.date(year: 2026, month: 9, day: 1, hour: 0))
        XCTAssertEqual(bi.lastDay, cal.date(year: 2026, month: 10, day: 31, hour: 0))
        let quarter = cal.periodBounds(.quarterly, index: 2)
        XCTAssertEqual(quarter.firstDay, cal.date(year: 2026, month: 7, day: 1, hour: 0))
        XCTAssertEqual(quarter.lastDay, cal.date(year: 2026, month: 9, day: 30, hour: 0))

        // Across New Year: Nov–Dec 2026 is bimonthly 5, Jan–Feb 2027 is 6; Oct–Dec is quarterly 3, Jan–Mar 2027 is 4.
        let dec31 = cal.date(year: 2026, month: 12, day: 31)
        let jan1 = cal.date(year: 2027, month: 1, day: 1)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: dec31), 5)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: jan1), 6)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: dec31), 3)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: jan1), 4)
        let q4 = cal.periodBounds(.quarterly, index: 4)
        XCTAssertEqual(q4.firstDay, cal.date(year: 2027, month: 1, day: 1, hour: 0))
        XCTAssertEqual(q4.lastDay, cal.date(year: 2027, month: 3, day: 31, hour: 0))

        // Before the anchor the index goes negative and the bounds still land on month starts.
        let dec2025 = cal.date(year: 2025, month: 12, day: 15)
        XCTAssertEqual(cal.periodIndex(.bimonthly, containing: dec2025), -1)
        XCTAssertEqual(cal.periodIndex(.quarterly, containing: dec2025), -1)
        XCTAssertEqual(cal.periodBounds(.bimonthly, index: -1).firstDay, cal.date(year: 2025, month: 11, day: 1, hour: 0))
        XCTAssertEqual(cal.periodBounds(.quarterly, index: -1).firstDay, cal.date(year: 2025, month: 10, day: 1, hour: 0))
        XCTAssertEqual(cal.month(of: dec2025), 12)
    }
```

In `FairnessBalancerTests.swift`, inside `testProvisionalWeightsAndAWeeklyOutweighingTwoDailies`, after the `.monthly` line add:

```swift
        XCTAssertEqual(weights.weight(for: .bimonthly), 10)
        XCTAssertEqual(weights.weight(for: .quarterly), 13)
```

In `SchedulerAndTalliesTests.swift`, add to `SchedulerTests` (next to `testMonthlyPeriod`):

```swift
    let fridge = Chore(
        id: "clean-out-fridge-pantry",
        title: "Clean out fridge and pantry",
        cadence: .quarterly,
        category: .chore
    )

    func testQuarterlyChoreIsOneDayLateOnTheFirstDayOfTheNextQuarter() {
        // Household started Sep 7, so Jul–Sep 2026 (quarter 2) is the first period; due all quarter.
        let s = Scheduler(chores: [fridge], activeFrom: activeFrom, calendar: cal)
        XCTAssertEqual(s.dueItem(for: fridge, on: wed, completions: [])?.daysOverdue, 0)
        XCTAssertEqual(s.dueItem(for: fridge, on: wed, completions: [])?.periodIndex, 2)
        // Oct 1 with nothing done: the quarter ended Sep 30 → 1 day late, like a daily the morning after.
        let oct1 = cal.date(year: 2026, month: 10, day: 1, hour: 9)
        XCTAssertEqual(s.dueItem(for: fridge, on: oct1, completions: [])?.daysOverdue, 1)
        XCTAssertEqual(s.dueItem(for: fridge, on: oct1, completions: [])?.stage, .nudge)
    }
```

- [ ] **Step 2: Run the package tests to see them fail**

Run: `swift test --package-path Packages/RoostCore 2>&1 | tail -20`
Expected: compile errors — `Cadence` has no member `bimonthly`, `HouseholdCalendar` has no `monthIndex`.

- [ ] **Step 3: Add the cases and the month helpers**

`Models.swift`, replace the `Cadence` enum:

```swift
public enum Cadence: String, Codable, CaseIterable, Sendable, Hashable {
    case daily
    case weekly
    case biweekly
    case monthly
    case bimonthly
    case quarterly

    /// How many calendar months one period spans, for the month-based cadences; nil for the day-based ones.
    public var monthsPerPeriod: Int? {
        switch self {
        case .daily, .weekly, .biweekly: nil
        case .monthly: 1
        case .bimonthly: 2
        case .quarterly: 3
        }
    }
}
```

`HouseholdCalendar.swift`, replace `periodIndex` and `periodBounds` and add the two helpers above them:

```swift
    /// Whole calendar months from January 2026 to the month containing `date`. Negative before it.
    public func monthIndex(_ date: Date) -> Int {
        let c = calendar.dateComponents([.year, .month], from: date)
        return (c.year! - 2026) * 12 + (c.month! - 1)
    }

    /// The calendar month containing `date`, 1...12.
    public func month(of date: Date) -> Int {
        calendar.component(.month, from: date)
    }

    public func periodIndex(_ cadence: Cadence, containing date: Date) -> Int {
        switch cadence {
        case .daily:
            return dayIndex(date)
        case .weekly:
            return floorDiv(dayIndex(date), 7)
        case .biweekly:
            return floorDiv(dayIndex(date), 14)
        case .monthly, .bimonthly, .quarterly:
            return floorDiv(monthIndex(date), cadence.monthsPerPeriod!)
        }
    }

    /// Start of the first day and start of the last day of a period. The month-based cadences share one
    /// path: a period is `monthsPerPeriod` whole months starting at month index `index * monthsPerPeriod`.
    public func periodBounds(_ cadence: Cadence, index: Int) -> (firstDay: Date, lastDay: Date) {
        switch cadence {
        case .daily:
            let d = day(at: index)
            return (d, d)
        case .weekly:
            return (day(at: index * 7), day(at: index * 7 + 6))
        case .biweekly:
            return (day(at: index * 14), day(at: index * 14 + 13))
        case .monthly, .bimonthly, .quarterly:
            let months = cadence.monthsPerPeriod!
            let firstMonth = index * months
            let year = 2026 + floorDiv(firstMonth, 12)
            let month = mod(firstMonth, 12) + 1
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            let nextFirst = calendar.date(byAdding: .month, value: months, to: first)!
            return (first, calendar.date(byAdding: .day, value: -1, to: nextFirst)!)
        }
    }
```

Also update the doc comment at the top of the file: "All day / week / month arithmetic" stays; add a line: "Bimonthly and quarterly periods are two and three calendar months, counted from January 2026 (period 0 of each holds the anchor)."

`FairnessBalancer.swift`, replace `FairnessWeights`:

```swift
public struct FairnessWeights: Codable, Sendable, Hashable {
    public var daily: Int
    public var weekly: Int
    public var biweekly: Int
    public var monthly: Int
    public var bimonthly: Int
    public var quarterly: Int

    public init(daily: Int, weekly: Int, biweekly: Int, monthly: Int, bimonthly: Int, quarterly: Int) {
        self.daily = daily
        self.weekly = weekly
        self.biweekly = biweekly
        self.monthly = monthly
        self.bimonthly = bimonthly
        self.quarterly = quarterly
    }

    /// daily 1, weekly 3, biweekly 5, monthly 8, bimonthly 10, quarterly 13.
    public static let provisional = FairnessWeights(daily: 1, weekly: 3, biweekly: 5, monthly: 8, bimonthly: 10, quarterly: 13)

    public func weight(for cadence: Cadence) -> Int {
        switch cadence {
        case .daily: daily
        case .weekly: weekly
        case .biweekly: biweekly
        case .monthly: monthly
        case .bimonthly: bimonthly
        case .quarterly: quarterly
        }
    }
}
```

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/RoostCore 2>&1 | tail -5`
Expected: `Test Suite 'All tests' passed` (the existing 46 plus the new ones).

- [ ] **Step 5: Commit**

```bash
git add Packages/RoostCore
git commit -m "RoostCore: bimonthly and quarterly cadences, month-based periods, weights 10 and 13"
```

### Task 2: `Season` and `together` on `Chore`

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/Models.swift:21-40`
- Test: `Packages/RoostCore/Tests/RoostCoreTests/ChoreListTests.swift`

**Interfaces:**
- Produces: `public struct Season: Codable, Sendable, Hashable { public let months: Set<Int>; public init(months:); public func contains(month: Int) -> Bool }`; `Chore.season: Season?`, `Chore.together: Bool`; `Chore.init(id:title:cadence:fixedAssignee:category:season:together:)` with `season = nil`, `together = false` defaults; JSON without the keys decodes to those defaults.

- [ ] **Step 1: Write the failing decoding test**

Add to `ChoreListTests`:

```swift
    func testSeasonAndTogetherDecodeAndDefault() throws {
        let json = """
        {
          "version": 2,
          "chores": [
            { "id": "mow-lawn", "title": "Mow lawn", "cadence": "weekly", "fixedAssignee": "anne",
              "category": "chore", "season": { "months": [4, 5, 6, 7, 8, 9, 10] } },
            { "id": "clean-out-fridge-pantry", "title": "Clean out fridge and pantry", "cadence": "quarterly",
              "fixedAssignee": null, "category": "chore", "together": true },
            { "id": "scoop-litter", "title": "Scoop litter", "cadence": "daily", "fixedAssignee": null,
              "category": "cat_care" }
          ]
        }
        """
        let list = try ChoreList.load(json: Data(json.utf8))
        XCTAssertEqual(list["mow-lawn"]?.season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(list["mow-lawn"]?.together, false)
        XCTAssertTrue(list["mow-lawn"]?.season?.contains(month: 10) ?? false)
        XCTAssertFalse(list["mow-lawn"]?.season?.contains(month: 11) ?? true)
        XCTAssertEqual(list["clean-out-fridge-pantry"]?.together, true)
        XCTAssertNil(list["clean-out-fridge-pantry"]?.season)
        XCTAssertFalse(list["clean-out-fridge-pantry"]?.isPinned ?? true, "together is not a pin")
        XCTAssertNil(list["scoop-litter"]?.season, "absent keys are the defaults")
        XCTAssertEqual(list["scoop-litter"]?.together, false)
        XCTAssertEqual(
            list["scoop-litter"],
            Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare),
            "the memberwise init and the decoder agree on the defaults"
        )
        // Round trip: what we encode, we decode.
        let data = try JSONEncoder().encode(list.chores)
        XCTAssertEqual(try JSONDecoder().decode([Chore].self, from: data), list.chores)
    }
```

- [ ] **Step 2: Run to see it fail**

Run: `swift test --package-path Packages/RoostCore --filter ChoreListTests 2>&1 | tail -10`
Expected: compile error — cannot find `Season` in scope.

- [ ] **Step 3: Add `Season` and the two fields**

In `Models.swift`, before `Chore`:

```swift
/// The months a chore is in season: `"season": { "months": [4, 5, 6, 7, 8, 9, 10] }` in data/chores.json.
/// A chore with a season is due only in periods whose first day falls in one of these months.
public struct Season: Codable, Sendable, Hashable {
    public let months: Set<Int>

    public init(months: Set<Int>) {
        self.months = months
    }

    /// Whether a period whose first day falls in `month` (1...12) is in season.
    public func contains(month: Int) -> Bool {
        months.contains(month)
    }
}
```

Replace `Chore`:

```swift
/// One row of data/chores.json.
public struct Chore: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let cadence: Cadence
    public let fixedAssignee: Person?
    public let category: ChoreCategory
    /// Absent for almost every chore. Present: due only in periods that start in one of these months.
    public let season: Season?
    /// Owed by both people at once: a row in each column, one check-off clears both, credit for both,
    /// no handoffs and no balancing. Never pinned (`fixedAssignee` is nil).
    public let together: Bool

    public init(
        id: String,
        title: String,
        cadence: Cadence,
        fixedAssignee: Person? = nil,
        category: ChoreCategory,
        season: Season? = nil,
        together: Bool = false
    ) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
        self.season = season
        self.together = together
    }

    enum CodingKeys: String, CodingKey {
        case id, title, cadence, fixedAssignee, category, season, together
    }

    /// The two optional keys default when absent, so a version-1 file and every fixture keep decoding.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        cadence = try c.decode(Cadence.self, forKey: .cadence)
        fixedAssignee = try c.decodeIfPresent(Person.self, forKey: .fixedAssignee)
        category = try c.decode(ChoreCategory.self, forKey: .category)
        season = try c.decodeIfPresent(Season.self, forKey: .season)
        together = try c.decodeIfPresent(Bool.self, forKey: .together) ?? false
    }

    public var isPinned: Bool {
        fixedAssignee != nil
    }
}
```

(`encode(to:)` stays synthesized from `CodingKeys`.)

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/RoostCore 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/RoostCore
git commit -m "RoostCore: Season and together on Chore, decoding with defaults"
```

### Task 3: The seasonal pause in the scheduler

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/Scheduler.swift:137-163`
- Test: `Packages/RoostCore/Tests/RoostCoreTests/SchedulerAndTalliesTests.swift`

**Interfaces:**
- Consumes: `Season.contains(month:)`, `HouseholdCalendar.month(of:)`, `HouseholdCalendar.periodBounds`.
- Produces: `Scheduler.firstPeriod(inSeason:endingAt:notBefore:cadence:) -> Int?` (internal); `dueItem(for:…)` returns nil when the current period is out of season and never reaches back past the season's first period.

- [ ] **Step 1: Write the failing tests**

Add to `SchedulerTests`:

```swift
    let mowing = Chore(
        id: "mow-lawn",
        title: "Mow lawn",
        cadence: .weekly,
        fixedAssignee: .anne,
        category: .chore,
        season: Season(months: [4, 5, 6, 7, 8, 9, 10])
    )

    func testSeasonalChoreIsNotDueInMarchAndStartsFreshInApril() {
        let s = Scheduler(chores: [mowing], activeFrom: activeFrom, calendar: cal)
        // Week of Mar 15 2027: out of season, and not overdue either.
        XCTAssertNil(s.dueItem(for: mowing, on: cal.date(year: 2027, month: 3, day: 17, hour: 9), completions: []))
        // Apr 1 2027 is a Thursday in the week of Mar 29, which starts in March: still out.
        XCTAssertNil(s.dueItem(for: mowing, on: cal.date(year: 2027, month: 4, day: 1, hour: 9), completions: []))
        // Week of Apr 5: in season, and last autumn's missed weeks do not carry over.
        let item = s.dueItem(for: mowing, on: cal.date(year: 2027, month: 4, day: 7, hour: 9), completions: [])
        XCTAssertEqual(item?.periodStart, cal.date(year: 2027, month: 4, day: 5, hour: 0))
        XCTAssertEqual(item?.daysOverdue, 0)
        XCTAssertEqual(item?.person, .anne)
    }

    func testSeasonalChoreStaysDueWhileItsLastPeriodRunsIntoNovember() {
        let s = Scheduler(chores: [mowing], activeFrom: activeFrom, calendar: cal)
        let mowed = done(mowing, .anne, cal.date(year: 2026, month: 10, day: 22, hour: 17)) // week of Oct 19
        // The week of Oct 26 starts in October, so it is due through Sunday Nov 1.
        let oct30 = s.dueItem(for: mowing, on: cal.date(year: 2026, month: 10, day: 30, hour: 9), completions: [mowed])
        XCTAssertEqual(oct30?.periodStart, cal.date(year: 2026, month: 10, day: 26, hour: 0))
        XCTAssertEqual(oct30?.daysOverdue, 0)
        XCTAssertNotNil(s.dueItem(for: mowing, on: cal.date(year: 2026, month: 11, day: 1, hour: 9), completions: [mowed]))
        // The week of Nov 2 starts out of season: not due, and the missed Oct 26 week is not overdue.
        XCTAssertNil(s.dueItem(for: mowing, on: cal.date(year: 2026, month: 11, day: 3, hour: 9), completions: [mowed]))
    }

    func testSeasonalChoreInsideTheSeasonCarriesLikeAnyOther() {
        let s = Scheduler(chores: [mowing], activeFrom: activeFrom, calendar: cal)
        // Household started Sep 7 (in season). Nothing done by Wed Sep 16 → the week of Sep 7 is 3 days late.
        let item = s.dueItem(for: mowing, on: wed, completions: [])
        XCTAssertEqual(item?.periodStart, activeFrom)
        XCTAssertEqual(item?.daysOverdue, 3)
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RoostCore --filter SchedulerTests 2>&1 | tail -15`
Expected: the March and November assertions fail (an item comes back), the April one has a September `periodStart`.

- [ ] **Step 3: Add the season floor**

In `Scheduler.swift`, replace `dueItem(for:on:completions:handoffs:)` with:

```swift
    /// The oldest incomplete period for `chore` as of `date`, or nil if it is done for the current period —
    /// or, for a chore with a season, if the current period started out of season. Inside a season the
    /// floor is the season's first period, so last year's missed weeks never carry into this spring.
    public func dueItem(
        for chore: Chore,
        on date: Date,
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> DueItem? {
        let current = calendar.periodIndex(chore.cadence, containing: date)
        var floor = calendar.periodIndex(chore.cadence, containing: activeFrom)
        if let season = chore.season {
            guard let start = firstPeriod(inSeason: season, endingAt: current, notBefore: floor, cadence: chore.cadence)
            else { return nil }
            floor = max(floor, start)
        }
        let lastDone = completions
            .filter { $0.choreId == chore.id }
            .map { calendar.periodIndex(chore.cadence, containing: $0.completedAt) }
            .max()
        let oldestIncomplete = max((lastDone.map { $0 + 1 }) ?? floor, floor)
        guard oldestIncomplete <= current else { return nil }

        let bounds = calendar.periodBounds(chore.cadence, index: oldestIncomplete)
        let daysOverdue = max(0, calendar.dayIndex(date) - calendar.dayIndex(bounds.lastDay))
        return DueItem(
            chore: chore,
            person: assignee(for: chore, periodIndex: oldestIncomplete, on: date, handoffs: handoffs),
            periodIndex: oldestIncomplete,
            periodStart: bounds.firstDay,
            periodLastDay: bounds.lastDay,
            daysOverdue: daysOverdue
        )
    }

    /// The first period of the run of in-season periods that ends at `current`: `current` itself when the
    /// period before it started out of season, earlier when the season has been running. Nil when `current`
    /// started out of season. The walk stops at `floor`, so a season that never ends still starts where the
    /// household did.
    func firstPeriod(inSeason season: Season, endingAt current: Int, notBefore floor: Int, cadence: Cadence) -> Int? {
        func inSeason(_ index: Int) -> Bool {
            season.contains(month: calendar.month(of: calendar.periodBounds(cadence, index: index).firstDay))
        }
        guard inSeason(current) else { return nil }
        var start = current
        while start - 1 >= floor, inSeason(start - 1) {
            start -= 1
        }
        return start
    }
```

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/RoostCore 2>&1 | tail -5`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/RoostCore
git commit -m "RoostCore: a chore with a season is due only in periods that start in season"
```

### Task 4: Together chores: two rows, one completion, credit for both, no handoffs, no balancing

**Files:**
- Modify: `Packages/RoostCore/Sources/RoostCore/Scheduler.swift:4-22, 95-135`
- Modify: `Packages/RoostCore/Sources/RoostCore/Tallies.swift:14-22, 63-87`
- Modify: `Packages/RoostCore/Sources/RoostCore/HandoffRules.swift:40-46`
- Modify: `Packages/RoostCore/Sources/RoostCore/FairnessBalancer.swift:81-139, 172-201`
- Test: `SchedulerAndTalliesTests.swift`, `HandoffTests.swift`, `FairnessBalancerTests.swift`

**Interfaces:**
- Produces: `DueItem.id` = `"<choreId>#<periodIndex>#<person>"` for together chores; `Scheduler.dueItems(for:on:completions:handoffs:) -> [DueItem]` (empty, one, or Anne-then-Wes); `dueItem(for:…)` for a together chore returns Anne's row; `Tallies.doneThisWeek` credits both people for a together completion; `HandoffRules.canOffer` is false for a together chore; `FairnessBalancer.isReassignable` is false for one, and `balance` / `windowLoads` ignore together chores entirely.

- [ ] **Step 1: Write the failing tests**

`SchedulerAndTalliesTests.swift`, add to `SchedulerTests`:

```swift
    let pantry = Chore(
        id: "clean-out-fridge-pantry",
        title: "Clean out fridge and pantry",
        cadence: .quarterly,
        category: .chore,
        together: true
    )

    func testTogetherChoreIsARowForBothAndOneCheckOffClearsBoth() {
        let s = Scheduler(chores: [litter, pantry], activeFrom: activeFrom, calendar: cal)
        let plan = s.plan(on: wed, completions: [])
        let anne = plan[.anne]?.first { $0.chore.id == pantry.id }
        let wes = plan[.wes]?.first { $0.chore.id == pantry.id }
        XCTAssertEqual(anne?.id, "clean-out-fridge-pantry#2#anne")
        XCTAssertEqual(wes?.id, "clean-out-fridge-pantry#2#wes")
        XCTAssertEqual(anne?.periodIndex, wes?.periodIndex)
        XCTAssertEqual(anne?.daysOverdue, wes?.daysOverdue)
        XCTAssertEqual(s.dueItems(for: pantry, on: wed, completions: []).map(\.person), [.anne, .wes])
        XCTAssertEqual(s.dueItem(for: pantry, on: wed, completions: [])?.person, .anne, "the single-row call answers Anne's row")

        // Wes does it: gone from both columns.
        let cleared = s.plan(on: wed, completions: [done(pantry, .wes, wed)])
        XCTAssertFalse(cleared[.anne]!.contains { $0.chore.id == pantry.id })
        XCTAssertFalse(cleared[.wes]!.contains { $0.chore.id == pantry.id })
        XCTAssertEqual(s.dueItems(for: pantry, on: wed, completions: [done(pantry, .wes, wed)]), [])

        // An ordinary chore's id is what it always was.
        let day = cal.periodIndex(.daily, containing: wed)
        XCTAssertEqual(s.dueItem(for: litter, on: wed, completions: [])?.id, "scoop-litter#\(day)")
        XCTAssertEqual(s.dueItems(for: litter, on: wed, completions: []).count, 1)
    }
```

Add to `TalliesTests`:

```swift
    func testTogetherCompletionCountsForBothInTheWeekTallyAndTheStreak() {
        let bothDaily = Chore(id: "feed-together", title: "Feed the cat together", cadence: .daily,
                              category: .catCare, together: true)
        let both = Tallies(scheduler: Scheduler(
            chores: [anneDaily, wesDaily, bothDaily],
            activeFrom: activeFrom,
            calendar: cal
        ))
        let wed = cal.date(year: 2026, month: 9, day: 16, hour: 18)
        let completions = [
            c(anneDaily, .anne, month: 9, day: 15),
            c(bothDaily, .wes, month: 9, day: 15), // one row, credited to both
        ]
        XCTAssertEqual(both.doneThisWeek(asOf: wed, completions: completions), [.anne: 2, .wes: 1])

        // Sep 15 is complete for Anne (her daily + the shared one) and incomplete for Wes (his daily is missing).
        XCTAssertEqual(both.streak(for: .anne, asOf: wed, completions: completions), 1)
        XCTAssertEqual(both.streak(for: .wes, asOf: wed, completions: completions), 0)
        // Without the shared completion Anne's day is incomplete too: a together daily is owed by both.
        XCTAssertEqual(both.streak(for: .anne, asOf: wed, completions: [c(anneDaily, .anne, month: 9, day: 15)]), 0)
    }
```

`HandoffTests.swift`, add:

```swift
    func testATogetherChoreCannotBeOffered() {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        let rules = HandoffRules(scheduler: Scheduler(
            chores: [pantry], activeFrom: activeFrom, rotation: FixedRotation(person: .anne), calendar: cal
        ))
        XCTAssertFalse(rules.canOffer(pantry, from: .anne, on: wed))
        XCTAssertFalse(rules.canOffer(pantry, from: .wes, on: wed))
        XCTAssertNil(rules.offer(pantry, from: .anne, to: .wes, on: wed, id: "h1"))
    }
```

`FairnessBalancerTests.swift`, add (the fixture already has `toilet`, `dailies`, `litter`, `tables`, `wed`, `cal`, `done(_:_:day:)`):

```swift
    func testTogetherChoresAreNeitherMovedNorWeighed() {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        let chores = [toilet, pantry] + dailies
        let scheduler = Scheduler(chores: chores, activeFrom: cal.date(year: 2026, month: 9, day: 7, hour: 0),
                                  calendar: cal, balancer: FairnessBalancer())
        let plan = scheduler.plan(on: wed, completions: [])
        XCTAssertEqual(plan[.anne]?.filter { $0.chore.id == pantry.id }.count, 1)
        XCTAssertEqual(plan[.wes]?.filter { $0.chore.id == pantry.id }.count, 1)
        let item = plan[.anne]!.first { $0.chore.id == pantry.id }!
        XCTAssertFalse(FairnessBalancer().isReassignable(item, on: wed, calendar: cal))
        // A together completion is not a weight on anybody's side of the scale.
        let loads = FairnessBalancer().windowLoads(chores: chores, completions: [done(pantry, .wes, day: 14)],
                                                   asOf: wed, calendar: cal)
        XCTAssertEqual(loads, [.anne: 0, .wes: 0])
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RoostCore 2>&1 | grep -E "error|failed" | head`
Expected: compile error — `Scheduler` has no member `dueItems`; after that, the id and credit assertions fail.

- [ ] **Step 3: Implement**

`Scheduler.swift`, replace the `id` on `DueItem`:

```swift
    /// `"<choreId>#<periodIndex>"`, and for a together chore `"<choreId>#<periodIndex>#<person>"`, so its two
    /// rows are two ids and every other id is unchanged.
    public var id: String {
        chore.together ? "\(chore.id)#\(periodIndex)#\(person.rawValue)" : "\(chore.id)#\(periodIndex)"
    }
```

Replace the loop in `plan(on:completions:handoffs:)`:

```swift
        for chore in chores {
            let forChore = byChore[chore.id] ?? []
            items += dueItems(for: chore, on: date, completions: forChore, handoffs: handoffs)
        }
```

Add above `dueItem(for:…)`:

```swift
    /// Every row `chore` puts on the day: none when it is done for the period or out of season, one for an
    /// ordinary chore, and one per person — Anne's then Wes's, same period, same days overdue — for a
    /// together chore. `plan` reads this; `dueItem` is the one-row view of the same answer.
    public func dueItems(
        for chore: Chore,
        on date: Date,
        completions: [Completion],
        handoffs: [Handoff] = []
    ) -> [DueItem] {
        guard let item = dueItem(for: chore, on: date, completions: completions, handoffs: handoffs) else { return [] }
        guard chore.together else { return [item] }
        return Person.allCases.map { item.with(person: $0) }
    }
```

In `dueItem(for:…)`, change the `person:` argument of the returned `DueItem` to:

```swift
            person: chore.together
                ? .anne // both of them owe it; `dueItems` hands out the second row
                : assignee(for: chore, periodIndex: oldestIncomplete, on: date, handoffs: handoffs),
```

and extend its doc comment: "For a together chore the row comes back as Anne's; `dueItems` is the call that knows there are two."

`Tallies.swift`, replace `doneThisWeek` and the `mine` line of `isDayComplete`:

```swift
    /// Completions per person in the Monday-to-Sunday (Chicago) week containing `date`. A together chore's
    /// completion is one row credited to both of them: it was both their turn.
    public func doneThisWeek(asOf date: Date, completions: [Completion]) -> [Person: Int] {
        let week = calendar.weekBounds(containing: date)
        let together = Set(scheduler.chores.filter(\.together).map(\.id))
        var counts: [Person: Int] = [.anne: 0, .wes: 0]
        for c in completions where c.completedAt >= week.start && c.completedAt < week.end {
            if together.contains(c.choreId) {
                for person in Person.allCases {
                    counts[person, default: 0] += 1
                }
            } else {
                counts[c.person, default: 0] += 1
            }
        }
        return counts
    }
```

```swift
        // A together daily is everybody's; the completion check below is already credit-blind.
        let mine = dailies.filter {
            $0.together || scheduler.assignee(for: $0, periodIndex: dayIndex, on: start, handoffs: handoffs) == person
        }
```

`HandoffRules.swift`, first line of `canOffer`:

```swift
    public func canOffer(_ chore: Chore, from person: Person, on date: Date) -> Bool {
        guard !chore.together else { return false } // nothing to hand over: it is already both of theirs
        let period = currentPeriod(for: chore, on: date)
```

and add to the doc comment above it: "A together chore is never offerable."

`FairnessBalancer.swift`:

- `isReassignable`: `guard !item.chore.isPinned, !item.chore.together, item.daysOverdue == 0 else { return false }`
- In `balance`, first line inside `for chore in chores {`: `if chore.together { continue } // owed by both, moved by nobody, weighed by nobody`
- In `loads`, after `let cadenceByChore = …` add `let together = Set(chores.filter(\.together).map(\.id))`, and in the loop after the window check: `guard !together.contains(completion.choreId) else { continue }`.
- Doc comment on `FairnessBalancer` (the "reassignable only when all three hold" list): add a fourth bullet "it is not a together chore (those are not weighed either: nobody's side of the scale is the right one)".

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/RoostCore 2>&1 | tail -5`
Expected: all pass. Existing `TodayPlannerTests`-style invariants live in the app, not here.

- [ ] **Step 5: Commit**

```bash
git add Packages/RoostCore
git commit -m "RoostCore: together chores are two rows, one completion, credit for both, no handoff, no balancing"
```

### Task 5: RoostCore README

**Files:**
- Modify: `Packages/RoostCore/README.md`

- [ ] **Step 1: Update the text**

- "What's in it" → Models bullet: add `Season` and the two `Chore` fields; Scheduler bullet: mention `dueItems(for:…)` and that a together chore is one row per person.
- "Rules (provisional)" → Periods: "Bimonthly = two calendar months, quarterly = three, both counted from January 2026 (Jan–Feb, Mar–Apr, …; Jan–Mar, Apr–Jun, …)." Add a **Season** bullet: "A chore with a `season` is due only in periods whose first day falls in one of its months; outside the season it is neither due nor overdue, and the season's first period is the floor, so last year's misses do not carry into spring." Add a **Together** bullet with the five rules from the spec (two rows, one completion clears both, credit for both, no handoffs, not balanced or weighed).
- Weights table: add `bimonthly | 10` and `quarterly | 13`.
- Leave the "31 chores, 2 pinned" sentence for lane D (it is true until the file changes).

- [ ] **Step 2: Commit and open the lane A PR**

```bash
git add Packages/RoostCore/README.md
git commit -m "RoostCore README: the two cadences, the season rule, the together rule"
git fetch origin && git rebase origin/main
swift test --package-path Packages/RoostCore 2>&1 | tail -3
gh api -X POST repos/amnanninga4/roost/pulls -f title="RoostCore: bimonthly/quarterly cadences, seasons, together chores" -f head=core/cadences-season-together -f base=main -F body=@/dev/stdin <<'EOF'
Lane A of docs/superpowers/plans/2026-09-13-chores-update.md (tasks 1–5). RoostCore only; the app and the server follow in their own PRs. data/chores.json is unchanged here.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

---

## Lane B — server (ticket R-29)

Everything in this lane is `server/`. Run `cd server && npm test` after every step that says so. Nothing here touches `data/chores.json`.

### Task 6: `rules.js` — the two cadences and the weights

**Files:**
- Modify: `server/src/rules.js:115-190, 421-431`
- Test: `server/test/rules.test.js:66-76, 369-376`

**Interfaces:**
- Produces: `export const CADENCES = ["daily","weekly","biweekly","monthly","bimonthly","quarterly"]`; `export const MONTHS_PER_PERIOD = { monthly: 1, bimonthly: 2, quarterly: 3 }`; `export function monthIndex(date)`; `periodIndex` / `periodBounds` accept the two new cadences; `FAIRNESS_WEIGHTS` gains `bimonthly: 10, quarterly: 13`.

- [ ] **Step 1: Write the failing tests**

In `rules.test.js`, add `CADENCES` and `monthIndex` to the import list, extend the anchor test, and add two tests after "monthly bounds for September 2026":

```js
test("anchor is Monday period zero", () => {
  for (const cadence of CADENCES) assert.equal(periodIndex(cadence, ANCHOR), 0, cadence);
  const p = new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", weekday: "short" }).format(ANCHOR);
  assert.equal(p, "Mon");
});
```

```js
test("bimonthly and quarterly periods across a year boundary", () => {
  assert.deepEqual(CADENCES, ["daily", "weekly", "biweekly", "monthly", "bimonthly", "quarterly"]);
  const sep13 = chicagoLocal(2026, 9, 13, 12);
  assert.equal(monthIndex(sep13), 8);
  assert.equal(periodIndex("bimonthly", sep13), 4);
  assert.equal(periodIndex("quarterly", sep13), 2);
  assert.equal(periodBounds("bimonthly", 4).firstDay.getTime(), chicagoLocal(2026, 9, 1).getTime());
  assert.equal(periodBounds("bimonthly", 4).lastDay.getTime(), chicagoLocal(2026, 10, 31).getTime());
  assert.equal(periodBounds("quarterly", 2).firstDay.getTime(), chicagoLocal(2026, 7, 1).getTime());
  assert.equal(periodBounds("quarterly", 2).lastDay.getTime(), chicagoLocal(2026, 9, 30).getTime());
  assert.equal(periodIndex("bimonthly", chicagoLocal(2026, 12, 31, 12)), 5);
  assert.equal(periodIndex("bimonthly", chicagoLocal(2027, 1, 1, 12)), 6);
  assert.equal(periodIndex("quarterly", chicagoLocal(2026, 12, 31, 12)), 3);
  assert.equal(periodIndex("quarterly", chicagoLocal(2027, 1, 1, 12)), 4);
  assert.equal(periodBounds("quarterly", 4).firstDay.getTime(), chicagoLocal(2027, 1, 1).getTime());
  assert.equal(periodBounds("quarterly", 4).lastDay.getTime(), chicagoLocal(2027, 3, 31).getTime());
  assert.equal(periodIndex("bimonthly", chicagoLocal(2025, 12, 15, 12)), -1);
  assert.equal(periodBounds("bimonthly", -1).firstDay.getTime(), chicagoLocal(2025, 11, 1).getTime());
  assert.equal(periodBounds("quarterly", -1).firstDay.getTime(), chicagoLocal(2025, 10, 1).getTime());
  assert.throws(() => periodIndex("fortnightly", sep13), /unknown cadence/);
});

test("quarterly chore is one day late on the first day of the next quarter", () => {
  const pantry = { id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry", cadence: "quarterly", fixedAssignee: null, category: "chore" };
  assert.equal(dueItemFor(pantry, { completions: [], asOf: wed, activeFrom })?.daysOverdue, 0);
  assert.equal(dueItemFor(pantry, { completions: [], asOf: wed, activeFrom })?.periodIndex, 2);
  const oct1 = chicagoLocal(2026, 10, 1, 9);
  const late = dueItemFor(pantry, { completions: [], asOf: oct1, activeFrom });
  assert.equal(late?.daysOverdue, 1);
  assert.equal(late?.stage, "nudge");
});
```

Change the weights test to:

```js
test("fairness provisional weights and window days", () => {
  assert.deepEqual(FAIRNESS_WEIGHTS, { daily: 1, weekly: 3, biweekly: 5, monthly: 8, bimonthly: 10, quarterly: 13 });
  assert.equal(FAIRNESS_WINDOW_DAYS, 14);
  assert.equal(weightFor("daily"), 1);
  assert.equal(weightFor("weekly"), 3);
  assert.equal(weightFor("biweekly"), 5);
  assert.equal(weightFor("monthly"), 8);
  assert.equal(weightFor("bimonthly"), 10);
  assert.equal(weightFor("quarterly"), 13);
});
```

(`wed` and `activeFrom` already exist in the file's scheduler section; if the new test sits above their declaration, move it below.)

- [ ] **Step 2: Run to see them fail**

Run: `cd server && node --test test/rules.test.js 2>&1 | tail -20`
Expected: `CADENCES` is not exported; `unknown cadence: bimonthly`.

- [ ] **Step 3: Implement**

In `rules.js`, after `export const PEOPLE`:

```js
/** Every cadence data/chores.json may use, in the order the file groups them. Mirrors RoostCore.Cadence. */
export const CADENCES = Object.freeze(["daily", "weekly", "biweekly", "monthly", "bimonthly", "quarterly"]);

/** Calendar months per period for the month-based cadences. Mirrors Cadence.monthsPerPeriod. */
export const MONTHS_PER_PERIOD = Object.freeze({ monthly: 1, bimonthly: 2, quarterly: 3 });
```

After `dayAt`:

```js
/** Whole calendar months from January 2026 to the month containing `date`. Negative before it. */
export function monthIndex(date) {
  const { year, month } = ymd(date);
  return (year - 2026) * 12 + (month - 1);
}
```

Replace the `monthly` arms:

```js
export function periodIndex(cadence, date) {
  switch (cadence) {
    case "daily":
      return dayIndex(date);
    case "weekly":
      return floorDiv(dayIndex(date), 7);
    case "biweekly":
      return floorDiv(dayIndex(date), 14);
    case "monthly":
    case "bimonthly":
    case "quarterly":
      return floorDiv(monthIndex(date), MONTHS_PER_PERIOD[cadence]);
    default:
      throw new Error(`unknown cadence: ${cadence}`);
  }
}

/** Start of first day and start of last day of a period. Month-based periods are `MONTHS_PER_PERIOD[cadence]` whole months from month index `index * months`. */
export function periodBounds(cadence, index) {
  switch (cadence) {
    case "daily": {
      const d = dayAt(index);
      return { firstDay: d, lastDay: d };
    }
    case "weekly":
      return { firstDay: dayAt(index * 7), lastDay: dayAt(index * 7 + 6) };
    case "biweekly":
      return { firstDay: dayAt(index * 14), lastDay: dayAt(index * 14 + 13) };
    case "monthly":
    case "bimonthly":
    case "quarterly": {
      const months = MONTHS_PER_PERIOD[cadence];
      const firstMonth = index * months;
      const first = chicagoLocal(2026 + floorDiv(firstMonth, 12), mod(firstMonth, 12) + 1, 1, 0, 0, 0);
      const endMonth = firstMonth + months; // the month after the period, as a month index
      const last = fromJulianDay(julianDay(2026 + floorDiv(endMonth, 12), mod(endMonth, 12) + 1, 1) - 1);
      return { firstDay: first, lastDay: last };
    }
    default:
      throw new Error(`unknown cadence: ${cadence}`);
  }
}
```

Weights: `export const FAIRNESS_WEIGHTS = Object.freeze({ daily: 1, weekly: 3, biweekly: 5, monthly: 8, bimonthly: 10, quarterly: 13 });`

- [ ] **Step 4: Run the whole server suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass (134 + the new ones), no network.

- [ ] **Step 5: Commit**

```bash
git add server/src/rules.js server/test/rules.test.js
git commit -m "server: bimonthly and quarterly cadences, month-based period math, weights 10 and 13"
```

### Task 7: `db.js` — schema version 2, the migration, and the two chore columns

**Files:**
- Modify: `server/src/db.js:20-33, 99-108, 123-159, 185-193`
- Modify: `server/src/handoffs.js:13-29`
- Create: `server/test/migrate.test.js`

**Interfaces:**
- Consumes: `CADENCES` from `rules.js`.
- Produces: `export const SCHEMA_VERSION = 2`; `export const CHORES_COLUMNS`; `openDb(path)` runs `migrate(db)` after the schema strings and before returning; `meta.schemaVersion` = `"2"` on every opened database; `chores` has `season TEXT` (JSON text or NULL) and `together INTEGER NOT NULL DEFAULT 0`; `seedChores` writes both from the file; `export function shapeChore(row)` returns `{ id, title, cadence, fixedAssignee, category, season: object|null, together: boolean }`; `listChores(db)` returns shaped rows. `handoffs.js` exports `HANDOFFS_COLUMNS`, `HANDOFFS_INDEXES`, and `HANDOFFS_SCHEMA` built from them; both cadence `CHECK`s come from `CADENCES`.

- [ ] **Step 1: Write the failing migration test**

Create `server/test/migrate.test.js`:

```js
// R-29: a database built by the version-1 schema string is rebuilt on open — wider cadence CHECKs, the two
// new chores columns — with every row, seq, and foreign key intact; a fresh database records the version.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { openDb, getMeta, listChores, SCHEMA_VERSION } from "../src/db.js";

// The chores and handoffs tables exactly as db.js / handoffs.js created them before R-29.
const V1 = `
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS chores (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  cadence       TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  fixedAssignee TEXT CHECK (fixedAssignee IN ('anne','wes')),
  category      TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
  sortOrder     INTEGER NOT NULL,
  retired       INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS completions (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  person      TEXT NOT NULL CHECK (person IN ('anne','wes')),
  completedAt TEXT NOT NULL,
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS completions_seq ON completions(seq);
CREATE TABLE IF NOT EXISTS handoffs (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  fromPerson  TEXT NOT NULL,
  toPerson    TEXT NOT NULL,
  periodIndex INTEGER NOT NULL,
  cadence     TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  state       TEXT NOT NULL CHECK (state IN ('pending','accepted','declined','expired')),
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS handoffs_seq ON handoffs(seq);
CREATE INDEX IF NOT EXISTS handoffs_chore_period ON handoffs(choreId, periodIndex);
INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', '2');
`;

function v1Database(dir) {
  const path = join(dir, "v1.db");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  db.exec(V1);
  db.prepare("INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .run("laundry", "Laundry", "weekly", "anne", "chore", 15, 0);
  db.prepare("INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .run("old-one", "Retired chore", "monthly", null, "chore", 30, 1);
  db.prepare("INSERT INTO completions (id, choreId, person, completedAt, createdAt, updatedAt, deletedAt, seq) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)")
    .run("c1", "laundry", "anne", "2026-09-10T18:00:00.000Z", "2026-09-10T18:00:00.000Z", "2026-09-10T18:00:00.000Z", 1);
  db.prepare("INSERT INTO handoffs (id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)")
    .run("h1", "laundry", "anne", "wes", 36, "weekly", "accepted", "2026-09-14T12:00:00.000Z", "2026-09-14T12:00:00.000Z", 2);
  db.close();
  return path;
}

const columns = (db, table) => db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
const sqlOf = (db, table) => db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?").get(table).sql;

test("a version-1 database is rebuilt to version 2 with rows, seqs and foreign keys intact", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-"));
  try {
    const path = v1Database(dir);
    const db = openDb(path);
    assert.equal(getMeta(db, "schemaVersion"), String(SCHEMA_VERSION));
    assert.ok(columns(db, "chores").includes("season"));
    assert.ok(columns(db, "chores").includes("together"));
    assert.match(sqlOf(db, "chores"), /'quarterly'/);
    assert.match(sqlOf(db, "handoffs"), /'bimonthly'/);

    // Every row survived with its values.
    const laundry = db.prepare("SELECT * FROM chores WHERE id = 'laundry'").get();
    assert.equal(laundry.fixedAssignee, "anne");
    assert.equal(laundry.sortOrder, 15);
    assert.equal(laundry.season, null);
    assert.equal(laundry.together, 0);
    assert.equal(db.prepare("SELECT retired FROM chores WHERE id = 'old-one'").get().retired, 1);
    assert.equal(db.prepare("SELECT seq FROM completions WHERE id = 'c1'").get().seq, 1);
    const h = db.prepare("SELECT * FROM handoffs WHERE id = 'h1'").get();
    assert.equal(h.seq, 2);
    assert.equal(h.state, "accepted");
    assert.equal(getMeta(db, "seq"), "2", "the shared counter is untouched");
    assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
    assert.equal(db.prepare("PRAGMA foreign_keys").get().foreign_keys, 1, "foreign keys are back on");
    assert.deepEqual(
      db.prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'handoffs' ORDER BY name").all().map((r) => r.name),
      ["handoffs_chore_period", "handoffs_seq"]
    );

    // The widened CHECK takes the new cadences, and the FK still points at chores.
    db.prepare("INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired, season, together) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)")
      .run("pantry", "Clean out fridge and pantry", "quarterly", null, "chore", 38, null, 1);
    assert.throws(
      () => db.prepare("INSERT INTO completions (id, choreId, person, completedAt, createdAt, updatedAt, deletedAt, seq) VALUES ('c2', 'nope', 'anne', 'x', 'x', 'x', NULL, 9)").run(),
      /FOREIGN KEY/
    );
    assert.deepEqual(listChores(db).map((c) => [c.id, c.season, c.together]), [["laundry", null, false], ["pantry", null, true]]);

    // Opening again is a no-op.
    db.close();
    const again = openDb(path);
    assert.equal(again.prepare("SELECT COUNT(*) AS n FROM chores").get().n, 3);
    assert.equal(getMeta(again, "schemaVersion"), "2");
    again.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a fresh database gets the version-2 shape directly and records the version", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-fresh-"));
  try {
    const db = openDb(join(dir, "fresh.db"));
    assert.equal(getMeta(db, "schemaVersion"), "2");
    assert.ok(columns(db, "chores").includes("together"));
    assert.match(sqlOf(db, "chores"), /'bimonthly'/);
    db.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd server && node --test test/migrate.test.js 2>&1 | tail -15`
Expected: `SCHEMA_VERSION` is not exported.

- [ ] **Step 3: Implement**

`handoffs.js`: import `CADENCES` from `./rules.js` (the import line becomes `import { periodIndex as calendarPeriodIndex, assigneeFor, CADENCES } from "./rules.js";`) and replace the schema block:

```js
const CADENCES_SQL = CADENCES.map((c) => `'${c}'`).join(",");

/** The handoffs columns, shared by the schema and db.js's v2 rebuild so the two cannot drift. */
export const HANDOFFS_COLUMNS = `
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  fromPerson  TEXT NOT NULL,
  toPerson    TEXT NOT NULL,
  periodIndex INTEGER NOT NULL,
  cadence     TEXT NOT NULL CHECK (cadence IN (${CADENCES_SQL})),
  state       TEXT NOT NULL CHECK (state IN ('pending','accepted','declined','expired')),
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE`;

export const HANDOFFS_INDEXES = `
CREATE INDEX IF NOT EXISTS handoffs_seq ON handoffs(seq);
CREATE INDEX IF NOT EXISTS handoffs_chore_period ON handoffs(choreId, periodIndex);
`;

export const HANDOFFS_SCHEMA = `
CREATE TABLE IF NOT EXISTS handoffs (${HANDOFFS_COLUMNS}
);
${HANDOFFS_INDEXES}`;
```

`db.js`: change the imports to `import { HANDOFFS_SCHEMA, HANDOFFS_COLUMNS, HANDOFFS_INDEXES } from "./handoffs.js";` and `import { chicagoDateString, CADENCES } from "./rules.js";`. After `PEOPLE_SQL`:

```js
const CADENCES_SQL = CADENCES.map((c) => `'${c}'`).join(",");

/**
 * Bumped when a table's shape changes in a way CREATE TABLE IF NOT EXISTS cannot apply to an existing
 * database (a CHECK, a new column). `migrate` brings an older database up to it, step by step.
 */
export const SCHEMA_VERSION = 2;

/** The chores columns, shared by the schema and the v2 rebuild so the two can never drift. */
export const CHORES_COLUMNS = `
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  cadence       TEXT NOT NULL CHECK (cadence IN (${CADENCES_SQL})),
  fixedAssignee TEXT CHECK (fixedAssignee IN (${PEOPLE_SQL})),
  category      TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
  sortOrder     INTEGER NOT NULL,
  retired       INTEGER NOT NULL DEFAULT 0,
  season        TEXT,
  together      INTEGER NOT NULL DEFAULT 0 CHECK (together IN (0,1))`;
```

In `SCHEMA`, replace the `chores` statement with `CREATE TABLE IF NOT EXISTS chores (${CHORES_COLUMNS}\n);`. Replace `openDb`:

```js
export function openDb(path) {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);
  db.exec(BONUS_SCHEMA);
  db.exec(PAIRING_SCHEMA);
  db.exec(PUSH_SCHEMA);
  db.exec(HANDOFFS_SCHEMA);
  migrate(db);
  return db;
}

/**
 * One-time upgrades for a database created by an older schema string. Runs before seeding, once per
 * open, and each step is idempotent: a fresh database already has the current shape and only records
 * the version. Keyed on meta.schemaVersion (absent = 1).
 */
function migrate(db) {
  const current = Number(getMeta(db, "schemaVersion") ?? 1);
  if (current >= SCHEMA_VERSION) return;
  if (current < 2) migrateToV2(db);
  setMeta(db, "schemaVersion", String(SCHEMA_VERSION));
}

function columnNames(db, table) {
  return db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
}

/**
 * v2 (R-29): chores gains season + together and both cadence CHECKs widen. SQLite cannot alter a CHECK,
 * so chores and handoffs are rebuilt the documented way — new table, copy, drop, rename — with foreign
 * keys off for the drop (a pragma, so it has to sit outside the transaction) and checked before commit.
 * The other tables' REFERENCES chores(id) are text and bind to the renamed table.
 */
function migrateToV2(db) {
  if (columnNames(db, "chores").includes("season")) return; // built from the v2 schema string already
  db.exec("PRAGMA foreign_keys = OFF");
  db.exec("BEGIN");
  try {
    db.exec(`
      CREATE TABLE chores_v2 (${CHORES_COLUMNS}
      );
      INSERT INTO chores_v2 (id, title, cadence, fixedAssignee, category, sortOrder, retired)
        SELECT id, title, cadence, fixedAssignee, category, sortOrder, retired FROM chores;
      DROP TABLE chores;
      ALTER TABLE chores_v2 RENAME TO chores;
      CREATE TABLE handoffs_v2 (${HANDOFFS_COLUMNS}
      );
      INSERT INTO handoffs_v2 (id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq)
        SELECT id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq FROM handoffs;
      DROP TABLE handoffs;
      ALTER TABLE handoffs_v2 RENAME TO handoffs;
      ${HANDOFFS_INDEXES}
    `);
    const broken = db.prepare("PRAGMA foreign_key_check").all();
    if (broken.length) throw new Error(`v2 migration broke foreign keys: ${JSON.stringify(broken)}`);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  } finally {
    db.exec("PRAGMA foreign_keys = ON");
  }
}
```

(`getMeta` / `setMeta` are function declarations further down the file; hoisting makes them reachable.)

Replace the upsert in `seedChores`:

```js
  const upsert = db.prepare(`
    INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired, season, together)
    VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      cadence = excluded.cadence,
      fixedAssignee = excluded.fixedAssignee,
      category = excluded.category,
      sortOrder = excluded.sortOrder,
      retired = 0,
      season = excluded.season,
      together = excluded.together
  `);
```

and the `forEach` body:

```js
      upsert.run(
        c.id, c.title, c.cadence, c.fixedAssignee ?? null, c.category, i,
        c.season ? JSON.stringify(c.season) : null,
        c.together ? 1 : 0
      );
```

Replace `listChores`:

```js
/** A chores row as clients and the rules see it: `season` parsed back to an object (or null), `together` a boolean. */
export function shapeChore(row) {
  return {
    id: row.id,
    title: row.title,
    cadence: row.cadence,
    fixedAssignee: row.fixedAssignee,
    category: row.category,
    season: row.season ? JSON.parse(row.season) : null,
    together: !!row.together,
  };
}

export function listChores(db) {
  return db
    .prepare("SELECT id, title, cadence, fixedAssignee, category, season, together FROM chores WHERE retired = 0 ORDER BY sortOrder")
    .all()
    .map(shapeChore);
}
```

- [ ] **Step 4: Run the whole suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass. `api.test.js` still sees 31 chores (the file is unchanged in this lane) and `/chores` rows now carry `season: null, together: false`.

- [ ] **Step 5: Commit**

```bash
git add server/src/db.js server/src/handoffs.js server/test/migrate.test.js
git commit -m "server: schema version 2 — chores season/together, wider cadence CHECKs, one-time table rebuild"
```

### Task 8: `rules.js` — the season rule and the together rows

**Files:**
- Modify: `server/src/rules.js:258-334, 336-347, 349-364, 433-435, 456-481, 520-571`
- Test: `server/test/rules.test.js`

**Interfaces:**
- Produces: `export function seasonStart(chore, current, floor)`; `dueItemFor` returns null out of season and uses the season floor; `person: "anne"` and `viaHandoff: false` for a together chore; `dueItems` emits one item per person for a together chore; `export function dueItemId(item)` (`"<id>#<period>"`, with `#<person>` for together); `doneThisWeek({ completions, asOf, chores = [] })` credits both for a together completion; `isDayComplete` treats a together daily as everyone's; `isReassignable` false for together; `balance` / `loads` skip together chores.

- [ ] **Step 1: Write the failing tests**

Add `seasonStart` and `dueItemId` to the import list. Add after the quarterly test:

```js
const mowing = {
  id: "mow-lawn", title: "Mow lawn", cadence: "weekly", fixedAssignee: "anne", category: "chore",
  season: { months: [4, 5, 6, 7, 8, 9, 10] },
};
const pantry = {
  id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry", cadence: "quarterly",
  fixedAssignee: null, category: "chore", together: true,
};

test("seasonal chore: not due in March, fresh in April, carries inside the season", () => {
  assert.equal(dueItemFor(mowing, { completions: [], asOf: chicagoLocal(2027, 3, 17, 9), activeFrom }), null);
  assert.equal(dueItemFor(mowing, { completions: [], asOf: chicagoLocal(2027, 4, 1, 9), activeFrom }), null, "week of Mar 29 starts in March");
  const april = dueItemFor(mowing, { completions: [], asOf: chicagoLocal(2027, 4, 7, 9), activeFrom });
  assert.equal(april.periodStart.getTime(), chicagoLocal(2027, 4, 5).getTime());
  assert.equal(april.daysOverdue, 0);
  assert.equal(april.person, "anne");
  // Inside the season a miss carries like any other chore: week of Sep 7 is 3 days late on Wed Sep 16.
  assert.equal(dueItemFor(mowing, { completions: [], asOf: wed, activeFrom }).daysOverdue, 3);
  // The week of Oct 26 starts in October: due through Nov 1, gone (not overdue) from Nov 2.
  const mowed = [{ id: "m1", choreId: "mow-lawn", person: "anne", completedAt: chicagoLocal(2026, 10, 22, 17) }];
  assert.equal(dueItemFor(mowing, { completions: mowed, asOf: chicagoLocal(2026, 10, 30, 9), activeFrom }).periodStart.getTime(), chicagoLocal(2026, 10, 26).getTime());
  assert.ok(dueItemFor(mowing, { completions: mowed, asOf: chicagoLocal(2026, 11, 1, 9), activeFrom }));
  assert.equal(dueItemFor(mowing, { completions: mowed, asOf: chicagoLocal(2026, 11, 3, 9), activeFrom }), null);
  // seasonStart on its own: the run of in-season weeks ending at the current one, never before the floor.
  const floor = periodIndex("weekly", activeFrom);
  const current = periodIndex("weekly", wed);
  assert.equal(seasonStart(mowing, current, floor), floor);
  assert.equal(seasonStart(mowing, periodIndex("weekly", chicagoLocal(2027, 3, 17)), floor), null);
});

test("together chore: one row per person, one completion clears both, credit for both, never handed off or balanced", () => {
  const chores = [litter, pantry];
  const due = dueItems({ chores, completions: [], asOf: wed, activeFrom });
  const anne = due.anne.find((i) => i.chore.id === pantry.id);
  const wes = due.wes.find((i) => i.chore.id === pantry.id);
  assert.equal(dueItemId(anne), "clean-out-fridge-pantry#2#anne");
  assert.equal(dueItemId(wes), "clean-out-fridge-pantry#2#wes");
  assert.equal(anne.periodIndex, wes.periodIndex);
  assert.equal(anne.viaHandoff, false);
  assert.equal(dueItemId(due.anne.find((i) => i.chore.id === litter.id) ?? due.wes.find((i) => i.chore.id === litter.id)), `scoop-litter#${periodIndex("daily", wed)}`);

  const doneByWes = [{ id: "p1", choreId: pantry.id, person: "wes", completedAt: wed }];
  const cleared = dueItems({ chores, completions: doneByWes, asOf: wed, activeFrom });
  assert.ok(!cleared.anne.some((i) => i.chore.id === pantry.id));
  assert.ok(!cleared.wes.some((i) => i.chore.id === pantry.id));

  assert.deepEqual(doneThisWeek({ completions: doneByWes, asOf: wed, chores }), { anne: 1, wes: 1 });
  assert.deepEqual(doneThisWeek({ completions: doneByWes, asOf: wed }), { anne: 0, wes: 1 }, "without the list there is nothing to know");
  assert.equal(boardStats({ chores, completions: doneByWes, asOf: wed, activeFrom }).anne.week, 1);

  assert.equal(isReassignable(anne, { asOf: wed }), false);
  const balanced = balance([anne, wes], { chores, completions: [], asOf: wed });
  assert.deepEqual(balanced.map((i) => i.person), ["anne", "wes"]);
  assert.deepEqual(windowLoads({ chores, completions: doneByWes, asOf: wed }), { anne: 0, wes: 0 }, "not weighed");

  // A together daily is owed by both in the streak walk.
  const bothDaily = { id: "feed-together", title: "Feed the cat together", cadence: "daily", fixedAssignee: null, category: "cat_care", together: true };
  const dailyChores = [anneDaily, wesDaily, bothDaily];
  const fed = [c(anneDaily, "anne", 9, 15), c(bothDaily, "wes", 9, 15)];
  const wedNight = chicagoLocal(2026, 9, 16, 18);
  assert.equal(streak({ person: "anne", chores: dailyChores, completions: fed, asOf: wedNight, activeFrom }), 1);
  assert.equal(streak({ person: "wes", chores: dailyChores, completions: fed, asOf: wedNight, activeFrom }), 0);
  assert.equal(streak({ person: "anne", chores: dailyChores, completions: [c(anneDaily, "anne", 9, 15)], asOf: wedNight, activeFrom }), 0);
});
```

(`litter`, `anneDaily`, `wesDaily`, `c`, `wed`, `activeFrom` already exist in the file; place the new tests after their declarations.)

- [ ] **Step 2: Run to see them fail**

Run: `cd server && node --test test/rules.test.js 2>&1 | tail -20`
Expected: `seasonStart` is not exported.

- [ ] **Step 3: Implement**

In `rules.js`, above `dueItemFor`:

```js
function inSeason(chore, index) {
  const months = chore.season?.months ?? [];
  return months.includes(ymd(periodBounds(chore.cadence, index).firstDay).month);
}

/**
 * First period of the run of in-season periods ending at `current`, never earlier than `floor`; null when
 * `current` itself started out of season. Mirrors Scheduler.firstPeriod(inSeason:endingAt:notBefore:).
 */
export function seasonStart(chore, current, floor) {
  if (!inSeason(chore, current)) return null;
  let start = current;
  while (start - 1 >= floor && inSeason(chore, start - 1)) start -= 1;
  return start;
}
```

In `dueItemFor`, replace the `floor` line and the two lines that set `person` / `viaHandoff`:

```js
  let floor = periodIndex(chore.cadence, active);
  if (chore.season) {
    const start = seasonStart(chore, current, floor);
    if (start === null) return null;
    floor = Math.max(floor, start);
  }
```

```js
  // Both of them owe a together chore; dueItems hands out the second row. Nothing was handed over.
  const person = chore.together ? "anne" : assigneeFor(chore, oldestIncomplete, handoffs, asOfD);
  const viaHandoff = !chore.together && person !== (chore.fixedAssignee || rotationAssignee(chore.id, oldestIncomplete));
```

In `dueItems`, replace `items.push(item);`:

```js
    if (chore.together) {
      for (const person of PEOPLE) items.push({ ...item, person });
    } else {
      items.push(item);
    }
```

Move `dueItemId` up next to `dueItems` and export it:

```js
/** `<choreId>#<periodIndex>`, plus `#<person>` for a together chore's two rows. Mirrors DueItem.id. */
export function dueItemId(item) {
  return item.chore.together
    ? `${item.chore.id}#${item.periodIndex}#${item.person}`
    : `${item.chore.id}#${item.periodIndex}`;
}
```

`doneThisWeek`:

```js
/** Completions per person in the Monday–Sunday Chicago week containing `asOf`. A together chore's completion counts for both. */
export function doneThisWeek({ completions, asOf, chores = [] }) {
  const week = weekBounds(asOf);
  const together = new Set(chores.filter((c) => c.together).map((c) => c.id));
  const counts = Object.fromEntries(PEOPLE.map((p) => [p, 0]));
  for (const c of completions) {
    const t = asDate(c.completedAt).getTime();
    if (t < week.start.getTime() || t >= week.end.getTime()) continue;
    if (together.has(c.choreId)) {
      for (const p of PEOPLE) counts[p] += 1;
    } else if (counts[c.person] !== undefined) {
      counts[c.person] += 1;
    }
  }
  return counts;
}
```

`isDayComplete`: `const mine = dailies.filter((ch) => ch.together || assigneeFor(ch, dayIdx, handoffs, start) === person);`

`boardStats`: `const week = doneThisWeek({ completions, asOf, chores });`

`loads`: after `cadenceByChore` add `const together = new Set(chores.filter((c) => c.together).map((c) => c.id));` and, after the window check, `if (together.has(completion.choreId)) continue;`

`isReassignable`: `if (item.chore.fixedAssignee || item.chore.together) return false;`

`balance`: first statement inside `for (const chore of chores) {`: `if (chore.together) continue; // owed by both, moved by nobody, weighed by nobody`

- [ ] **Step 4: Run the whole suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add server/src/rules.js server/test/rules.test.js
git commit -m "server rules: seasonal pause and together chores, mirroring RoostCore"
```

### Task 9: `handoffs.js` — no offers on a together chore

**Files:**
- Modify: `server/src/handoffs.js:142-172, 285-310`
- Test: `server/test/handoffs.test.js`

**Interfaces:**
- Produces: `insertHandoff` returns `{ error: "together" }` for a together chore; `POST /handoffs` answers `400 { error: "together chores cannot be handed off" }`; the cadence validation reads `CADENCES` and its message is `cadence must be one of daily|weekly|biweekly|monthly|bimonthly|quarterly`.

- [ ] **Step 1: Write the failing test**

Add to `handoffs.test.js` (imports: add `seedChores` from `../src/db.js` and `writeFileSync`/`readFileSync` are already imported from `node:fs`; add `readFileSync` if not):

```js
test("POST /handoffs on a together chore is refused; a bimonthly cadence is accepted by validation", async () => {
  const data = JSON.parse(readFileSync(CHORES, "utf8"));
  const withPantry = {
    ...data,
    version: 99,
    chores: [
      ...data.chores,
      { id: "pantry-t", title: "Clean out fridge and pantry", cadence: "quarterly", fixedAssignee: null, category: "chore", together: true },
      { id: "hair-b", title: "Trim Wes's hair", cadence: "bimonthly", fixedAssignee: "anne", category: "chore" },
    ],
  };
  const path = join(dir, "chores-together.json");
  writeFileSync(path, JSON.stringify(withPantry));
  seedChores(app.db, path);

  const refused = await offer(ANNE, { id: "h-together", choreId: "pantry-t", to: "wes" });
  assert.equal(refused.status, 400);
  assert.match(String(refused.body.error), /together/i);
  assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM handoffs WHERE id = 'h-together'").get().n, 0);

  const bad = await offer(ANNE, { id: "h-cad", choreId: "hair-b", to: "wes", cadence: "fortnightly" });
  assert.equal(bad.status, 400);
  assert.match(String(bad.body.error), /bimonthly\|quarterly/);
  const ok = await offer(ANNE, { id: "h-hair", choreId: "hair-b", to: "wes", cadence: "bimonthly" });
  assert.equal(ok.status, 201);
  assert.equal(ok.body.cadence, "bimonthly");

  seedChores(app.db, CHORES); // put the standard list back for the tests that follow
});
```

- [ ] **Step 2: Run to see it fail**

Run: `cd server && node --test test/handoffs.test.js 2>&1 | tail -15`
Expected: the together offer comes back `201` and the `fortnightly` message does not mention `bimonthly`.

- [ ] **Step 3: Implement**

In `insertHandoff`, change the chore query and add the refusal right after the `unknown_chore` check:

```js
  const chore = db.prepare("SELECT id, cadence, fixedAssignee, together FROM chores WHERE id = ? AND retired = 0").get(choreId);
  if (!chore) return { row: null, created: false, error: "unknown_chore" };
  if (chore.together) return { row: null, created: false, error: "together" };
```

Update the error list in the JSDoc above it (`… | cadence_mismatch | together`). In `handoffRoutes`, replace the cadence validation:

```js
    if (body.cadence !== undefined && !CADENCES.includes(body.cadence)) {
      send(res, 400, { error: `cadence must be one of ${CADENCES.join("|")}` });
      return true;
    }
```

and add to the error chain, before `not_owner`:

```js
    else if (error === "together") send(res, 400, { error: "together chores cannot be handed off" });
```

- [ ] **Step 4: Run the whole suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add server/src/handoffs.js server/test/handoffs.test.js
git commit -m "server handoffs: refuse offers on together chores, cadence list from rules"
```

### Task 10: `push.js` — period phrases, the together red alert, chores through `listChores`

**Files:**
- Modify: `server/src/push.js:13-15, 327-333, 372-403, 425-427`
- Test: `server/test/push.test.js`

**Interfaces:**
- Produces: `export const PERIOD_PHRASES = { daily: "today", weekly: "this week", biweekly: "this week", monthly: "this month", bimonthly: "these two months", quarterly: "this quarter" }`; a together item at stage alert sends one push to **each** person, title `Roost red alert`, body `"<title> is N days late"` (`1 day late` when N is 1), collapse id `red-<choreId>`, recorded once in `push_alerts`; both sweeps read chores with `listChores(db)`.

- [ ] **Step 1: Write the failing tests**

In `push.test.js`, import `PERIOD_PHRASES` from `../src/push.js` and `seedChores` from `../src/db.js` (add `readFileSync` to the `node:fs` import). Add:

```js
test("period phrases are the app's words for every cadence", () => {
  assert.deepEqual(PERIOD_PHRASES, {
    daily: "today",
    weekly: "this week",
    biweekly: "this week",
    monthly: "this month",
    bimonthly: "these two months",
    quarterly: "this quarter",
  });
});

test("red alert for a together chore reaches both phones once, naming nobody", async () => {
  const data = JSON.parse(readFileSync(CHORES, "utf8"));
  const path = join(dir, "chores-together.json");
  writeFileSync(path, JSON.stringify({
    ...data,
    version: 98,
    chores: [...data.chores, { id: "pantry-t", title: "Clean out fridge and pantry", cadence: "daily", fixedAssignee: null, category: "chore", together: true }],
  }));
  seedChores(app.db, path);
  app.db.prepare("DELETE FROM push_tokens").run();
  app.db.prepare("DELETE FROM push_alerts").run();
  app.db.prepare("DELETE FROM meta WHERE key = 'activeFrom'").run(); // the code default, Sep 7
  upsertPushToken(app.db, { token: ANNE_PUSH, person: "anne", platform: "ios" }, clock.toISOString());
  upsertPushToken(app.db, { token: WES_PUSH, person: "wes", platform: "ios" }, clock.toISOString());

  sent.length = 0;
  const asOf = new Date("2026-09-20T17:00:00.000Z"); // Sep 7 never done → 13 days late
  await app.push.runRedAlertSweep(asOf);
  const pantry = sent.filter((r) => r.headers["apns-collapse-id"] === "red-pantry-t");
  assert.equal(pantry.length, 2, "one push per person");
  assert.deepEqual(new Set(pantry.map((r) => r.deviceToken)), new Set([ANNE_PUSH, WES_PUSH]));
  for (const req of pantry) {
    assert.match(req.body.aps.alert.title, /red alert/i);
    assert.equal(req.body.aps.alert.body, "Clean out fridge and pantry is 13 days late");
  }
  assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM push_alerts WHERE choreId = 'pantry-t'").get().n, 1, "recorded once");

  sent.length = 0;
  await app.push.runRedAlertSweep(asOf);
  assert.equal(sent.filter((r) => r.headers["apns-collapse-id"] === "red-pantry-t").length, 0, "not re-sent");

  seedChores(app.db, CHORES);
  app.db.prepare("DELETE FROM push_alerts").run();
});
```

Place the together test **before** "red-alert sweep respects meta activeFrom" so the meta reset does not disturb that test's own setup, or after it with the same `DELETE FROM meta` line — either way it must leave `push_alerts` empty and the standard chores seeded.

- [ ] **Step 2: Run to see them fail**

Run: `cd server && node --test test/push.test.js 2>&1 | tail -15`
Expected: `PERIOD_PHRASES` is not exported.

- [ ] **Step 3: Implement**

Imports: `import { PEOPLE, getMeta, setMeta, listChores } from "./db.js";`. Replace `periodPhrase` with a module-level table and a lookup:

```js
/** Which period a handoff covers, in the words the app's `Cadence.periodPhrase` uses. One test on each side pins them. */
export const PERIOD_PHRASES = Object.freeze({
  daily: "today",
  weekly: "this week",
  biweekly: "this week",
  monthly: "this month",
  bimonthly: "these two months",
  quarterly: "this quarter",
});

function periodPhrase(cadence) {
  return PERIOD_PHRASES[cadence] ?? "this period";
}
```

(Delete the inner `periodPhrase` function from `createPush`; the closure keeps calling the module-level one.)

In `runRedAlertSweep`, replace the `chores` query with `const chores = listChores(db);` and the body of the inner loop with:

```js
        for (const item of due[person] ?? []) {
          if ((STAGE_RANK[item.stage] ?? -1) < 3) continue;
          if (hasPushAlert(db, item.chore.id, item.periodIndex)) continue;
          recordPushAlert(db, item.chore.id, item.periodIndex, sentAt);
          const headers = { "apns-collapse-id": `red-${item.chore.id}` };
          if (item.chore.together) {
            // Both of them owe it, so both hear about it, and nobody is named.
            const days = item.daysOverdue;
            const body = `${item.chore.title} is ${days} ${days === 1 ? "day" : "days"} late`;
            for (const each of PEOPLE) await deliver(each, { title: "Roost red alert", body, headers });
            continue;
          }
          const other = partnerOf(item.person);
          const who = NAME[item.person] ?? item.person;
          await deliver(other, { title: "Roost red alert", body: `${who}'s chore is overdue: ${item.chore.title}`, headers });
        }
```

In `runMorningDigestSweep`, replace its `chores` query with `const chores = listChores(db);` as well.

- [ ] **Step 4: Run the whole suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add server/src/push.js server/test/push.test.js
git commit -m "server push: the two new period phrases, red alert to both for a together chore"
```

### Task 11: `server/README.md` and the lane B PR

**Files:**
- Modify: `server/README.md`

- [ ] **Step 1: Update the text**

- Model → **chores** bullet: add "`season` (`{ months: [1..12] }` or null) and `together` (boolean) come from the file; the rules module applies them (a seasonal chore is due only in periods that start in season; a together chore is one row per person, one completion clears both, credit for both, no handoffs)."
- Add a **Schema versions** paragraph under the model: "`meta.schemaVersion` (2). `db.js` `migrate` runs on open, before seeding; v2 rebuilt `chores` and `handoffs` to widen the cadence CHECK and add the two chores columns. A fresh database gets the current shape and only records the version."
- Handoffs bullet / endpoints table: `POST /handoffs` gains "`400` on a together chore"; the cadence list in the validation paragraph becomes the six.
- Push section: the period phrase list becomes `today` / `this week` / `this month` / `these two months` / `this quarter`; add "A together chore's red alert goes to both phones with `<title> is N days late`."
- Any "four cadences" wording → six.

- [ ] **Step 2: Commit and open the lane B PR**

```bash
git add server/README.md
git commit -m "server README: cadences, seasons, together, schema version 2"
git fetch origin && git rebase origin/main
cd server && npm test 2>&1 | tail -3 && cd ..
gh api -X POST repos/amnanninga4/roost/pulls -f title="R-29: server cadences, seasons, together chores, schema v2" -f head=server/r29-cadences-season-together -f base=main -F body=@/dev/stdin <<'EOF'
Lane B of docs/superpowers/plans/2026-09-13-chores-update.md (tasks 6–11). Server only; data/chores.json is unchanged here (lane D flips it). Deploy after merge; the v2 migration runs on the first start.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

---

## Lane C — app (after lane A is merged)

### Task 12: The two fields on `ChoreRecord`, the converters, the DTO, and server-sent chores

**Files:**
- Modify: `Roost/Sources/Models/Records.swift:19-48`
- Modify: `Roost/Sources/Models/Converters.swift:5-54`
- Modify: `Roost/Sources/Sync/SyncAPI.swift:63-69`
- Modify: `Roost/Sources/Sync/SyncClient.swift:268-281`
- Test: `Roost/Tests/SeedTests.swift`, `Roost/Tests/SyncTests.swift`

**Interfaces:**
- Consumes: `RoostCore.Season`, `Chore.season`, `Chore.together`.
- Produces: `ChoreRecord.season: String?` (the JSON text of a `Season`), `ChoreRecord.together: Bool` (default false); `ChoreRecord.init(id:title:cadence:fixedAssignee:category:sortOrder:retired:season:together:)`; `ChoreRecord.seasonText(_:) -> String?`; `ConversionError.badSeason(String, id:)`; `SyncAPI.ChoreDTO.season: Season?`, `.together: Bool?`.

- [ ] **Step 1: Write the failing tests**

`SeedTests.swift`, add:

```swift
    func testSeasonAndTogetherRoundTripThroughTheRecord() throws {
        let mowing = Chore(id: "mow-lawn", title: "Mow lawn", cadence: .weekly, fixedAssignee: .anne,
                           category: .chore, season: Season(months: [4, 5, 6, 7, 8, 9, 10]))
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        try ChoreSeeder.seed(ChoreList(version: 2, chores: [mowing, pantry]), into: context)
        let rows = try activeChores()
        XCTAssertEqual(try rows.map { try $0.toChore() }, [mowing, pantry])
        XCTAssertEqual(rows[0].together, false)
        XCTAssertEqual(rows[1].together, true)
        XCTAssertEqual(rows[1].season, nil)
        XCTAssertNotNil(rows[0].season)

        // Re-seeding without the season clears it; a broken season text is a conversion error, not a crash.
        let plain = Chore(id: "mow-lawn", title: "Mow lawn", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        try ChoreSeeder.seed(ChoreList(version: 3, chores: [plain, pantry]), into: context)
        XCTAssertNil(try activeChores()[0].season)
        rows[0].season = "{not json"
        XCTAssertThrowsError(try rows[0].toChore())
    }
```

`SyncTests.swift`, add (next to `testDeltaWithChoresReseedsAndBumpsVersion`):

```swift
    func testServerSentChoresCarrySeasonAndTogether() async throws {
        try await pairAsAnne()
        let chores: [[String: Any]] = [
            ["id": "mow-lawn", "title": "Mow lawn", "cadence": "weekly", "fixedAssignee": "anne",
             "category": "chore", "season": ["months": [4, 5, 6, 7, 8, 9, 10]], "together": false],
            ["id": "clean-out-fridge-pantry", "title": "Clean out fridge and pantry", "cadence": "quarterly",
             "fixedAssignee": NSNull(), "category": "chore", "season": NSNull(), "together": true],
            ["id": "scoop-litter", "title": "Scoop litter", "cadence": "daily", "fixedAssignee": NSNull(),
             "category": "cat_care"], // an older server: no keys at all
        ]
        StubURLProtocol.reset { _ in (200, syncJSON(cursor: 7, choresVersion: 2, chores: chores)) }
        _ = await client.syncNow()
        let active = try fresh().fetch(FetchDescriptor<ChoreRecord>(
            predicate: #Predicate { !$0.retired }, sortBy: [SortDescriptor(\.sortOrder)]
        ))
        XCTAssertEqual(active.map(\.id), ["mow-lawn", "clean-out-fridge-pantry", "scoop-litter"])
        XCTAssertEqual(try active[0].toChore().season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(active[1].together, true)
        XCTAssertEqual(active[2].together, false)
        XCTAssertNil(active[2].season)
    }
```

- [ ] **Step 2: Run the two suites to see them fail**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RoostTests/SeedTests -only-testing:RoostTests/SyncTests test 2>&1 | grep -E "error:|Test Suite" | head`
Expected: compile errors — `ChoreRecord` has no member `together`.

- [ ] **Step 3: Implement**

`Records.swift`, replace `ChoreRecord`:

```swift
/// One row of data/chores.json, persisted. `cadence`, `category`, and `fixedAssignee` are stored as
/// their raw strings so a future value in the JSON does not crash the store; converters validate.
/// `season` is the JSON text of a `RoostCore.Season` (`{"months":[4,5,6,7,8,9,10]}`), nil for the rest.
@Model
final class ChoreRecord {
    @Attribute(.unique) var id: String
    var title: String
    var cadence: String
    var fixedAssignee: String?
    var category: String
    var sortOrder: Int
    var retired: Bool
    var season: String?
    var together: Bool = false

    init(
        id: String,
        title: String,
        cadence: String,
        fixedAssignee: String?,
        category: String,
        sortOrder: Int,
        retired: Bool = false,
        season: String? = nil,
        together: Bool = false
    ) {
        self.id = id
        self.title = title
        self.cadence = cadence
        self.fixedAssignee = fixedAssignee
        self.category = category
        self.sortOrder = sortOrder
        self.retired = retired
        self.season = season
        self.together = together
    }
}
```

(Both additions are lightweight SwiftData migrations: an optional and a defaulted property.)

`Converters.swift`: add `case badSeason(String, id: String)` to `ConversionError` with description `"chore \(id): unreadable season '\(v)'"`, and replace the `ChoreRecord` extension:

```swift
extension ChoreRecord {
    convenience init(_ chore: Chore, sortOrder: Int) {
        self.init(
            id: chore.id,
            title: chore.title,
            cadence: chore.cadence.rawValue,
            fixedAssignee: chore.fixedAssignee?.rawValue,
            category: chore.category.rawValue,
            sortOrder: sortOrder,
            season: Self.seasonText(chore.season),
            together: chore.together
        )
    }

    /// Copies every field from the value type except `sortOrder`, which the caller owns.
    func apply(_ chore: Chore, sortOrder: Int) {
        title = chore.title
        cadence = chore.cadence.rawValue
        fixedAssignee = chore.fixedAssignee?.rawValue
        category = chore.category.rawValue
        self.sortOrder = sortOrder
        retired = false
        season = Self.seasonText(chore.season)
        together = chore.together
    }

    func toChore() throws -> Chore {
        guard let cadence = Cadence(rawValue: cadence) else { throw ConversionError.badCadence(cadence, id: id) }
        guard let category = ChoreCategory(rawValue: category)
        else { throw ConversionError.badCategory(category, id: id) }
        var person: Person? = nil
        if let raw = fixedAssignee {
            guard let p = Person(rawValue: raw) else { throw ConversionError.badPerson(raw, id: id) }
            person = p
        }
        var season: Season? = nil
        if let text = self.season {
            guard let decoded = try? JSONDecoder().decode(Season.self, from: Data(text.utf8)) else {
                throw ConversionError.badSeason(text, id: id)
            }
            season = decoded
        }
        return Chore(
            id: id, title: title, cadence: cadence, fixedAssignee: person, category: category,
            season: season, together: together
        )
    }

    /// The stored form of a season: its JSON, or nil. Month order in the text is unspecified (it is a set).
    static func seasonText(_ season: Season?) -> String? {
        guard let season, let data = try? JSONEncoder().encode(season) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
```

`SyncAPI.swift`, replace `ChoreDTO`:

```swift
    struct ChoreDTO: Codable, Sendable {
        let id: String
        let title: String
        let cadence: String
        let fixedAssignee: String?
        let category: String
        /// Both optional so a server older than R-29, or a test stub, still decodes.
        let season: Season?
        let together: Bool?
    }
```

`SyncClient.swift`, the `Chore(` in `apply(_:to:)` gains two arguments:

```swift
                return Chore(
                    id: dto.id,
                    title: dto.title,
                    cadence: cadence,
                    fixedAssignee: dto.fixedAssignee.flatMap(Person.init(rawValue:)),
                    category: category,
                    season: dto.season,
                    together: dto.together ?? false
                )
```

- [ ] **Step 4: Run the full app suite**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "Test Suite 'All tests'|TEST (SUCCEEDED|FAILED)"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Models/Records.swift Roost/Sources/Models/Converters.swift Roost/Sources/Sync/SyncAPI.swift Roost/Sources/Sync/SyncClient.swift Roost/Tests/SeedTests.swift Roost/Tests/SyncTests.swift
git commit -m "app: season and together on ChoreRecord, the converters, the DTO, and server-sent chores"
```

### Task 13: Strings, the period phrases, the section labels, and the season line

**Files:**
- Modify: `Roost/Sources/Strings.swift:153-204, 206-258, 260-280, 310-339`
- Modify: `Roost/Sources/Models/HandoffPresentation.swift:55-65`
- Modify: `Roost/Sources/Screens/ChoreListScreen.swift:141-150`
- Create: `Roost/Sources/Models/SeasonCopy.swift`
- Create: `Roost/Tests/SeasonCopyTests.swift`
- Test: `Roost/Tests/HandoffPlanningTests.swift:259-263`

**Interfaces:**
- Produces: `Strings.Tasks.together` = "TOGETHER", `Strings.Tasks.togetherValue` = "Both of you"; `Strings.Handoffs.periodTwoMonths` = "these two months", `Strings.Handoffs.periodQuarter` = "this quarter"; `Strings.Chores.bimonthly` = "Every two months", `Strings.Chores.quarterly` = "Every three months", `Strings.Chores.season(from:to:)` = "\(from) to \(to)"; `Strings.Kitchen.together` = "TOGETHER"; `Cadence.periodPhrase` and `Cadence.label` cover six cases; `SeasonCopy.line(_:monthSymbols:) -> String?`.

- [ ] **Step 1: Write the failing tests**

`HandoffPlanningTests.swift`, extend `testThePeriodPhraseMatchesTheServers`:

```swift
        XCTAssertEqual(Cadence.bimonthly.periodPhrase, "these two months")
        XCTAssertEqual(Cadence.quarterly.periodPhrase, "this quarter")
        // The whole table, so the server's PERIOD_PHRASES test and this one pin the same six lines.
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: Cadence.allCases.map { ($0.rawValue, $0.periodPhrase) }),
            ["daily": "today", "weekly": "this week", "biweekly": "this week", "monthly": "this month",
             "bimonthly": "these two months", "quarterly": "this quarter"]
        )
```

Create `Roost/Tests/SeasonCopyTests.swift`:

```swift
@testable import Roost
import RoostCore
import XCTest

final class SeasonCopyTests: XCTestCase {
    private let english = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    ]

    func testSeasonReadsFirstMonthToLastMonth() {
        XCTAssertEqual(SeasonCopy.line(Season(months: [4, 5, 6, 7, 8, 9, 10]), monthSymbols: english), "April to October")
        XCTAssertEqual(SeasonCopy.line(Season(months: [11, 12, 1]), monthSymbols: english), "January to December",
                       "a set has no wrap-around; the line is the span the months cover")
        XCTAssertEqual(SeasonCopy.line(Season(months: [6]), monthSymbols: english), "June")
        XCTAssertNil(SeasonCopy.line(Season(months: []), monthSymbols: english))
        XCTAssertNil(SeasonCopy.line(Season(months: [0, 13]), monthSymbols: english), "out of range is not drawn")
    }

    func testCadenceLabelsCoverEveryCase() {
        XCTAssertEqual(Cadence.allCases.map(\.label), [
            "Daily", "Weekly", "Biweekly", "Monthly", "Every two months", "Every three months",
        ])
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd Roost && xcodegen generate && cd .. && xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RoostTests/SeasonCopyTests -only-testing:RoostTests/HandoffPlanningTests test 2>&1 | grep -E "error:|Test Suite" | head`
Expected: compile errors — `Cadence` switch must be exhaustive (`periodPhrase`, `label`), `SeasonCopy` not found.

- [ ] **Step 3: Implement**

`Strings.swift` additions, each inside the named enum:

```swift
    enum Tasks {
        // …existing…
        /// The chip on a together chore, where a pinned chore wears its person's name.
        static let together = "TOGETHER"
        /// VoiceOver value for a together row, after the state.
        static let togetherValue = "Both of you"
    }

    enum Handoffs {
        // …existing…
        static let periodTwoMonths = "these two months"
        static let periodQuarter = "this quarter"
    }

    enum Chores {
        // …existing…
        static let bimonthly = "Every two months"
        static let quarterly = "Every three months"
        /// Under a seasonal chore in All chores: "April to October".
        static func season(from: String, to: String) -> String {
            "\(from) to \(to)"
        }
    }

    enum Kitchen {
        // …existing…
        /// On the banner line of a together chore, where a person's name goes otherwise.
        static let together = "TOGETHER"
    }
```

Update the `Handoffs` enum's doc comment to mention the six phrases match `PERIOD_PHRASES` in `server/src/push.js`.

`HandoffPresentation.swift`, `Cadence.periodPhrase`:

```swift
    var periodPhrase: String {
        switch self {
        case .daily: Strings.Handoffs.periodToday
        case .weekly, .biweekly: Strings.Handoffs.periodWeek
        case .monthly: Strings.Handoffs.periodMonth
        case .bimonthly: Strings.Handoffs.periodTwoMonths
        case .quarterly: Strings.Handoffs.periodQuarter
        }
    }
```

`ChoreListScreen.swift`, `Cadence.label`:

```swift
extension Cadence {
    var label: String {
        switch self {
        case .daily: Strings.Chores.daily
        case .weekly: Strings.Chores.weekly
        case .biweekly: Strings.Chores.biweekly
        case .monthly: Strings.Chores.monthly
        case .bimonthly: Strings.Chores.bimonthly
        case .quarterly: Strings.Chores.quarterly
        }
    }
}
```

Create `Roost/Sources/Models/SeasonCopy.swift`:

```swift
// How a chore's season reads on the All chores screen. Pure, so the wording is tested without a screen.
import Foundation
import RoostCore

enum SeasonCopy {
    /// "April to October" for months 4...10; a single month is its name alone; nil when there is nothing
    /// sensible to say (an empty set, or a month outside 1...12). `monthSymbols` defaults to the reader's
    /// calendar so the names follow their locale; the tests pass English.
    static func line(_ season: Season, monthSymbols: [String] = Calendar.autoupdatingCurrent.monthSymbols) -> String? {
        guard let first = season.months.min(), let last = season.months.max(),
              (1 ... 12).contains(first), (1 ... 12).contains(last), monthSymbols.count == 12
        else { return nil }
        let from = monthSymbols[first - 1]
        let to = monthSymbols[last - 1]
        return first == last ? from : Strings.Chores.season(from: from, to: to)
    }
}
```

- [ ] **Step 4: Run the full app suite**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Strings.swift Roost/Sources/Models/HandoffPresentation.swift Roost/Sources/Screens/ChoreListScreen.swift Roost/Sources/Models/SeasonCopy.swift Roost/Tests/SeasonCopyTests.swift Roost/Tests/HandoffPlanningTests.swift Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: period phrases and section labels for the two cadences, the season line"
```

### Task 14: The Together chip, the All chores row, the kitchen banner, and the planner invariants

**Files:**
- Modify: `Roost/Sources/Tasks/ChoreRowView.swift:128-167, 180-200`
- Modify: `Roost/Sources/Screens/ChoreListScreen.swift:82-139`
- Modify: `Roost/Sources/Models/KitchenModel.swift:82-93`
- Modify: `Roost/Sources/Screens/KitchenScreen.swift:201-240`
- Test: `Roost/Tests/TodayPlannerTests.swift`, `Roost/Tests/KitchenModelTests.swift`, `Roost/Tests/HandoffPlanningTests.swift`

**Interfaces:**
- Consumes: `Strings.Tasks.together`, `.togetherValue`, `Strings.Kitchen.together`, `SeasonCopy.line`, `TodayRow.canOffer` (already false through `HandoffRules`).
- Produces: a together row shows the "TOGETHER" chip in place of a pinned name and reads "Both of you" to VoiceOver; the All chores row shows the chip and, under a seasonal chore, the season line; `KitchenModel.alerts` lists a together alert once (Anne's copy) while both columns keep it; the banner line of a together item reads `TOGETHER · N DAYS LATE`.

- [ ] **Step 1: Write the failing tests**

`TodayPlannerTests.swift`, add:

```swift
    func testTogetherChoreIsARowForBothAndOneCheckOffClearsBoth() throws {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .quarterly, category: .chore, together: true)
        let litter = Chore(id: "scoop-litter", title: "Scoop litter", cadence: .daily, fixedAssignee: .anne,
                           category: .catCare)
        let day = cal.date(year: 2026, month: 9, day: 14, hour: 10)
        let plan = TodayPlanner.plan(chores: [litter, pantry], completions: [], asOf: day,
                                     activeFrom: cal.startOfDay(day), calendar: cal)
        let anne = try XCTUnwrap(plan.rows(for: .anne).first { $0.chore.id == pantry.id })
        let wes = try XCTUnwrap(plan.rows(for: .wes).first { $0.chore.id == pantry.id })
        XCTAssertNotEqual(anne.id, wes.id, "two rows, two ids")
        XCTAssertFalse(anne.canOffer)
        XCTAssertFalse(wes.canOffer)
        XCTAssertEqual(plan.dueCount(for: .anne), 2)
        XCTAssertEqual(plan.dueCount(for: .wes), 1)

        let done = Completion(id: "p1", choreId: pantry.id, person: .wes, completedAt: day)
        let after = TodayPlanner.plan(chores: [litter, pantry], completions: [done], asOf: day,
                                      activeFrom: cal.startOfDay(day), calendar: cal)
        XCTAssertFalse(after.rows(for: .anne).contains { $0.chore.id == pantry.id && !$0.isDone })
        XCTAssertEqual(after.rows(for: .wes).first { $0.chore.id == pantry.id }?.isDone, true, "the done row sits in the tapper's column")
        XCTAssertEqual(after.doneThisWeek, [.anne: 1, .wes: 1], "credit for both")
    }
```

`KitchenModelTests.swift`, add:

```swift
    func testATogetherAlertIsInBothColumnsAndOnceInTheBanner() throws {
        let pantry = Chore(id: "clean-out-fridge-pantry", title: "Clean out fridge and pantry",
                           cadence: .daily, category: .chore, together: true)
        try seed(chores + [pantry], completions: [("c1", "scoop-litter", .anne, 4)])
        // Sep 1 never done → 5 days late on Sep 6 for both of them.
        let m = try model(asOf: sep6)
        XCTAssertTrue(m.column(for: .anne).overdue.contains { $0.chore.id == pantry.id })
        XCTAssertTrue(m.column(for: .wes).overdue.contains { $0.chore.id == pantry.id })
        XCTAssertEqual(m.alerts.filter { $0.chore.id == pantry.id }.count, 1, "the banner says it once")
        XCTAssertEqual(m.alerts.first { $0.chore.id == pantry.id }?.person, .anne)
        XCTAssertEqual(m.alerts.first { $0.chore.id == pantry.id }?.copy, "Clean out fridge and pantry emergency")
    }
```

`HandoffPlanningTests.swift`, add:

```swift
    func testATogetherRowIsNeverOfferable() {
        let pantry = Chore(id: "pantry", title: "Clean out fridge and pantry", cadence: .weekly,
                           category: .chore, together: true)
        let plan = TodayPlanner.plan(chores: [pantry], completions: [], asOf: monday,
                                     activeFrom: cal.startOfDay(monday), calendar: cal)
        XCTAssertEqual(plan.rows(for: .anne).first?.canOffer, false)
        XCTAssertEqual(plan.rows(for: .wes).first?.canOffer, false)
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `xcodebuild … -only-testing:RoostTests/TodayPlannerTests -only-testing:RoostTests/KitchenModelTests -only-testing:RoostTests/HandoffPlanningTests test 2>&1 | grep -E "error:|failed" | head`
Expected: the planner tests pass already (RoostCore did the work); the kitchen test fails on the banner count (2).

- [ ] **Step 3: Implement**

`KitchenModel.swift`, replace the `alerts =` assignment:

```swift
        // A together chore sits in both columns; the banner is one shout, so it is listed once (Anne's copy).
        var togetherSeen: Set<String> = []
        let loud = columns
            .flatMap { $0.overdue.filter { $0.stage == .alert } }
            .filter { item in !item.chore.together || togetherSeen.insert(item.chore.id).inserted }
        alerts = loud
            .enumerated()
            .sorted { a, b in
                if a.element.daysOverdue != b.element.daysOverdue {
                    return a.element.daysOverdue > b.element.daysOverdue
                }
                return a.offset < b.offset
            }
            .map(\.element)
```

`KitchenScreen.swift`, in `AlertBanner`, the person line:

```swift
                    Text("\(item.chore.together ? Strings.Kitchen.together : item.person.displayName.uppercased()) · \(Strings.Kitchen.daysLate(item.daysOverdue))")
```

`ChoreRowView.swift`, in `meta`: change the guard to `if late || pinned != nil || row.chore.together || row.handoff != nil {` and replace the pinned chip:

```swift
                if row.chore.together {
                    RowBadge(text: Strings.Tasks.together, tint: .assigned, fill: .assignedSoft)
                } else if let pinned {
                    RowBadge(text: pinned.displayName.uppercased(), tint: .assigned, fill: .assignedSoft)
                }
```

In `accessibilityValue`, replace the pinned line:

```swift
        if row.chore.together {
            parts.append(Strings.Tasks.togetherValue)
        } else if let pinned = row.chore.fixedAssignee {
            parts.append(Strings.Tasks.always(pinned.displayName))
        }
```

`ChoreListScreen.swift`, in `ChoreListRow`: add `private var chore: Chore? { try? record.toChore() }` and `private var seasonLine: String? { chore?.season.flatMap { SeasonCopy.line($0) } }`. Replace the `Text(record.title)` with a stack that adds the season line under it:

```swift
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(record.title)
                    .roostType(.rowTitle)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                    .fixedSize(horizontal: false, vertical: true)
                if let seasonLine {
                    Text(seasonLine)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
```

and replace the pinned chip with a `chip(_:)` helper used for both cases:

```swift
            if record.together {
                chip(Strings.Tasks.together)
            } else if let person = pinnedTo {
                chip(person.displayName.uppercased())
            }
```

```swift
    private func chip(_ text: String) -> some View {
        Text(text)
            .roostType(.monoLabel)
            .foregroundStyle(RoostColor.Role.assigned.color)
            .padding(.horizontal, RoostSpacing.sm)
            .padding(.vertical, RoostSpacing.xxs)
            .background(RoostColor.Role.assignedSoft.color, in: RoostRadius.shape(RoostRadius.sm))
            .fixedSize()
    }
```

Accessibility value of the row: `record.together ? Strings.Tasks.togetherValue : (pinnedTo.map { Strings.Tasks.always($0.displayName) } ?? "")`, and append the season line with `Strings.Lists.metaSeparator` when present.

Add to `PreviewStore` in the same file a seasonal chore and a together chore so the preview shows both:

```swift
            Chore(id: "mow-lawn", title: "Mow lawn", cadence: .weekly, fixedAssignee: .anne, category: .chore,
                  season: Season(months: [4, 5, 6, 7, 8, 9, 10])),
            Chore(id: "pantry", title: "Clean out fridge and pantry", cadence: .quarterly, category: .chore,
                  together: true),
```

- [ ] **Step 4: Run the full suite and look at the screens**

Run the `xcodebuild … test` line; expected `** TEST SUCCEEDED **`. Then run the app in the simulator with `-roostUITestState paired` (the fixture has no together chore; that is fine for the tab) and open More → All chores is not there yet (the gear menu is): open the gear menu → All chores, and confirm the preview canvas of `ChoreListScreen` shows "April to October" under Mow lawn and a TOGETHER chip on the pantry row. For the Tasks row, render `ChoreRowView` in a preview with a together `TodayRow` and confirm the chip sits where a pinned name would. Take one screenshot of each and attach both to the PR.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources Roost/Tests
git commit -m "app: Together chip on the Tasks and All chores rows, one banner line per together alert"
```

### Task 15: App README, NOTES, and the lane C PR

**Files:**
- Modify: `Roost/README.md`
- Modify: `NOTES.md`

- [ ] **Step 1: Update the text**

- `Roost/README.md` layout listing: add `Models/SeasonCopy.swift pure: a chore's season -> "April to October"`; `Models/Records.swift` line mentions `season` and `together`. In the Tasks section add one paragraph: "A together chore is a row in both columns with a TOGETHER chip where a pinned name goes; either check-off clears both rows, both tallies move, and it cannot be offered. A chore with a season (Mow lawn, April to October) is simply absent outside it." In the All chores paragraph add: "grouped by six cadences (Daily … Every three months); a seasonal chore carries its months under the title." Kitchen mode: "a together alert is in both columns and once in the banner, labelled TOGETHER."
- The unit-test count sentence: add the new tests in the same style (seed round trip of season/together; server-sent chores with the two fields; the period phrase table; season copy; the together planner invariants; the kitchen banner dedupe).
- `NOTES.md`: under "What's already locked in the chore list" add a dated line: "**2026-09-13, Anne + Wes:** six more chores, one replaced, one split; two new cadences (every two months, every three months, month-based like monthly); a seasonal pause (`season.months`); together chores (`together: true`, both boards, one check-off, credit for both, no handoffs). Spec: docs/superpowers/specs/2026-09-13-chores-update-design.md."

- [ ] **Step 2: Commit and open the lane C PR**

```bash
git add Roost/README.md NOTES.md
git commit -m "docs: app README and NOTES for cadences, seasons, together chores"
git fetch origin && git rebase origin/main
cd Roost && xcodegen generate && cd .. && git status --short   # must be clean: a regenerate is a no-op
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"
gh api -X POST repos/amnanninga4/roost/pulls -f title="App: seasons, together chores, the two new cadences" -f head=app/cadences-season-together -f base=main -F body=@/dev/stdin <<'EOF'
Lane C of docs/superpowers/plans/2026-09-13-chores-update.md (tasks 12–15). Needs the RoostCore PR merged first. data/chores.json is unchanged here.

Screenshots: (attach the two from task 14.)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

---

## Lane D — the list, the validator, the counts, the rollout (after A, B, C are merged)

### Task 16: `data/chores.json` version 2 and everything that counts it

**Files:**
- Modify: `data/chores.json`
- Modify: `scripts/validate-chores.py`
- Modify: `data/README.md`
- Modify: `Packages/RoostCore/Tests/RoostCoreTests/ChoreListTests.swift:15-33`
- Modify: `Packages/RoostCore/README.md` (the "31 chores, 2 pinned" sentence)
- Modify: `Roost/Tests/SeedTests.swift:32-74`, `Roost/Tests/TodayPlannerTests.swift:12-33`, `Roost/Tests/SyncTests.swift:297-314`
- Modify: `server/test/api.test.js:53-58, 87-88, 158, 162, 207`, `server/test/pairing.test.js:145`

**Interfaces:**
- Consumes: everything above. Produces the file the app bundles (`Roost/project.yml` already references `../data/chores.json`) and the server seeds.

- [ ] **Step 1: Rewrite the validator**

Replace `scripts/validate-chores.py` in full:

```python
#!/usr/bin/env python3
"""Validate data/chores.json against the Roost chore seed schema.

Schema (simple, Swift/SwiftData-friendly):
  Root object:
    version: int          # 2 since the 2026-09-13 update
    source: str           # e.g. "chore-master-list.html"
    locked: str           # ISO date the list was settled
    notes: str            # optional human note
    chores: list[Chore]

  Chore object:
    id: str                    # stable slug, unique
    title: str                 # display title
    cadence: str               # daily | weekly | biweekly | monthly | bimonthly | quarterly
    fixedAssignee: str|null    # anne | wes | null
    category: str              # chore | cat_care
    season: {"months": [int]}  # optional: 1..12, non-empty, unique; not on a together chore; not on a
                               # cadence longer than monthly
    together: bool             # optional: both people owe it; fixedAssignee must be null

The file is grouped by cadence in CADENCE_ORDER and the order is meaning: it becomes `sortOrder` on
both stores. Counts and pins below are the list Anne and Wes settled on 2026-09-13 (39 chores).

Exit codes:
  0  valid
  1  invalid JSON, schema, count, order, duplicate ids, bad enums, or a broken rule
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHORES_PATH = REPO_ROOT / "data" / "chores.json"

CADENCE_ORDER = ("daily", "weekly", "biweekly", "monthly", "bimonthly", "quarterly")
VALID_CADENCES = frozenset(CADENCE_ORDER)
SEASON_CADENCES = frozenset({"daily", "weekly", "biweekly", "monthly"})
VALID_ASSIGNEES = frozenset({"anne", "wes"})
VALID_CATEGORIES = frozenset({"chore", "cat_care"})
REQUIRED_CHORE_KEYS = ("id", "title", "cadence", "fixedAssignee", "category")
OPTIONAL_CHORE_KEYS = ("season", "together")

EXPECTED_VERSION = 2
EXPECTED_COUNTS = {"daily": 11, "weekly": 12, "biweekly": 5, "monthly": 7, "bimonthly": 1, "quarterly": 3}
EXPECTED_COUNT = sum(EXPECTED_COUNTS.values())  # 39
EXPECTED_PINNED = {
    "laundry": "anne",
    "wash-all-rugs": "anne",
    "mow-lawn": "anne",
    "trim-wes-hair": "anne",
    "garbage-can-to-street-sunday": "wes",
}


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def check_season(loc: str, season: object, chore: dict) -> None:
    if not isinstance(season, dict) or set(season) != {"months"}:
        fail(f"{loc}.season must be an object with exactly one key, months")
    months = season["months"]
    if not isinstance(months, list) or not months:
        fail(f"{loc}.season.months must be a non-empty list")
    for m in months:
        if not isinstance(m, int) or isinstance(m, bool) or not 1 <= m <= 12:
            fail(f"{loc}.season.months has a value outside 1..12: {m!r}")
    if len(set(months)) != len(months):
        fail(f"{loc}.season.months repeats a month")
    if chore["cadence"] not in SEASON_CADENCES:
        fail(f"{loc}: a season needs a cadence of at most monthly, got {chore['cadence']!r}")
    if chore.get("together"):
        fail(f"{loc}: a together chore cannot have a season")


def main() -> None:
    if not CHORES_PATH.is_file():
        fail(f"missing file: {CHORES_PATH}")

    try:
        data = json.loads(CHORES_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    if not isinstance(data, dict):
        fail("root must be an object")
    for key in ("version", "source", "locked", "chores"):
        if key not in data:
            fail(f"root missing required key: {key}")
    if data["version"] != EXPECTED_VERSION:
        fail(f"version must be {EXPECTED_VERSION}, got {data['version']!r}")
    if not isinstance(data["source"], str) or not data["source"].strip():
        fail("source must be a non-empty string")
    if not isinstance(data["locked"], str) or not data["locked"].strip():
        fail("locked must be a non-empty string")

    chores = data["chores"]
    if not isinstance(chores, list):
        fail("chores must be a list")
    if len(chores) != EXPECTED_COUNT:
        fail(f"expected {EXPECTED_COUNT} chores, got {len(chores)}")

    seen_ids: set[str] = set()
    by_cadence = {c: 0 for c in CADENCE_ORDER}
    pinned: dict[str, str] = {}
    last_rank = 0

    for i, chore in enumerate(chores):
        loc = f"chores[{i}]"
        if not isinstance(chore, dict):
            fail(f"{loc} must be an object")
        for key in REQUIRED_CHORE_KEYS:
            if key not in chore:
                fail(f"{loc} missing key: {key}")
        unknown = set(chore) - set(REQUIRED_CHORE_KEYS) - set(OPTIONAL_CHORE_KEYS)
        if unknown:
            fail(f"{loc} has unknown keys: {sorted(unknown)}")

        cid = chore["id"]
        if not isinstance(cid, str) or not cid.strip():
            fail(f"{loc}.id must be a non-empty string")
        if cid in seen_ids:
            fail(f"duplicate id: {cid}")
        seen_ids.add(cid)

        if not isinstance(chore["title"], str) or not chore["title"].strip():
            fail(f"{loc}.title must be a non-empty string")

        cadence = chore["cadence"]
        if cadence not in VALID_CADENCES:
            fail(f"{loc}.cadence invalid: {cadence!r} (want {list(CADENCE_ORDER)})")
        rank = CADENCE_ORDER.index(cadence)
        if rank < last_rank:
            fail(f"{loc} ({cid}) is out of order: the file is grouped {', '.join(CADENCE_ORDER)}")
        last_rank = rank
        by_cadence[cadence] += 1

        assignee = chore["fixedAssignee"]
        if assignee is not None and assignee not in VALID_ASSIGNEES:
            fail(f"{loc}.fixedAssignee invalid: {assignee!r} (want null|anne|wes)")
        if assignee is not None:
            pinned[cid] = assignee

        if chore["category"] not in VALID_CATEGORIES:
            fail(f"{loc}.category invalid: {chore['category']!r} (want {sorted(VALID_CATEGORIES)})")

        together = chore.get("together", False)
        if not isinstance(together, bool):
            fail(f"{loc}.together must be true or false")
        if together and assignee is not None:
            fail(f"{loc} ({cid}): a together chore has no fixedAssignee")

        if "season" in chore:
            check_season(loc, chore["season"], chore)

    if by_cadence != EXPECTED_COUNTS:
        fail(f"per-cadence counts {by_cadence} do not match {EXPECTED_COUNTS}")
    if pinned != EXPECTED_PINNED:
        fail(f"pinned chores {pinned} do not match {EXPECTED_PINNED}")

    print(f"OK: {CHORES_PATH.relative_to(REPO_ROOT)}")
    print(f"  version: {data['version']}")
    print(f"  chores: {len(chores)}")
    for cadence in CADENCE_ORDER:
        print(f"  {cadence}: {by_cadence[cadence]}")
    print("  pinned: " + ", ".join(f"{cid}→{who}" for cid, who in pinned.items()))
    print("  season: " + ", ".join(c["id"] for c in chores if "season" in c))
    print("  together: " + ", ".join(c["id"] for c in chores if c.get("together")))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it to see it fail against the version-1 file**

Run: `python3 scripts/validate-chores.py`
Expected: `FAIL: version must be 2, got 1`.

- [ ] **Step 3: Edit `data/chores.json`**

Set `"version": 2`, keep `"source"` and `"locked": "2026-09-13"`, and set `"notes"` to:

```
"Version 2, 2026-09-13: Anne's additions on issue #1. 39 tasks (11 daily + 12 weekly + 5 biweekly + 7 monthly + 1 bimonthly + 3 quarterly). Grouped by cadence; the order is sortOrder. take-out-garbages became three weekly chores; clean-out-fridge became clean-out-fridge-pantry (quarterly, together). Mockup sample rows are illustrative and must not be merged in."
```

Then apply these edits to the `chores` array, keeping every other entry exactly as it is:

1. Replace the entry with id `take-out-garbages` by these three, in this order:

```json
    {
      "id": "take-out-garbage-basement",
      "title": "Take out garbage: basement",
      "cadence": "weekly",
      "fixedAssignee": null,
      "category": "chore"
    },
    {
      "id": "take-out-garbage-bathroom",
      "title": "Take out garbage: bathroom",
      "cadence": "weekly",
      "fixedAssignee": null,
      "category": "chore"
    },
    {
      "id": "take-out-garbage-kitchen",
      "title": "Take out garbage: kitchen",
      "cadence": "weekly",
      "fixedAssignee": null,
      "category": "chore"
    },
```

2. After `wipe-appliance-exteriors` (the last weekly), add:

```json
    {
      "id": "mow-lawn",
      "title": "Mow lawn",
      "cadence": "weekly",
      "fixedAssignee": "anne",
      "category": "chore",
      "season": { "months": [4, 5, 6, 7, 8, 9, 10] }
    },
```

3. Delete the entry with id `clean-out-fridge`.

4. After `wipe-dust-bar-cart` (the last monthly), add, in this order:

```json
    {
      "id": "clean-medicine-cabinet",
      "title": "Clean inside medicine cabinet",
      "cadence": "monthly",
      "fixedAssignee": null,
      "category": "chore"
    },
    {
      "id": "wash-all-rugs",
      "title": "Wash all rugs (washer)",
      "cadence": "monthly",
      "fixedAssignee": "anne",
      "category": "chore"
    },
    {
      "id": "trim-wes-hair",
      "title": "Trim Wes's hair",
      "cadence": "bimonthly",
      "fixedAssignee": "anne",
      "category": "chore"
    },
    {
      "id": "clean-garbage-cans",
      "title": "Clean garbage cans",
      "cadence": "quarterly",
      "fixedAssignee": null,
      "category": "chore"
    },
    {
      "id": "wipe-down-doors",
      "title": "Wipe down doors",
      "cadence": "quarterly",
      "fixedAssignee": null,
      "category": "chore"
    },
    {
      "id": "clean-out-fridge-pantry",
      "title": "Clean out fridge and pantry",
      "cadence": "quarterly",
      "fixedAssignee": null,
      "category": "chore",
      "together": true
    }
```

The resulting id order must be exactly:

```
load-dishwasher, scoop-litter, wipe-counters-mirrors, wipe-tables, vacuum-first-floor, vacuum-basement,
am-wet-cat-food, pm-wet-cat-food, refill-cat-water, water-plants, general-tidy-reset,
clean-toilet-bowl, wipe-stove-top, take-out-garbage-basement, take-out-garbage-bathroom, take-out-garbage-kitchen,
garbage-can-to-street-sunday, laundry, wipe-cabinet-doors, change-bed-sheets, clean-microwave-inside,
wipe-appliance-exteriors, mow-lawn,
scrub-clean-shower, mop-first-floor, mop-basement, clean-rugs, wash-pillows-rotate-mattress,
change-litter, clean-inside-ovens, clean-under-cushions, clean-under-couches, wipe-dust-bar-cart,
clean-medicine-cabinet, wash-all-rugs,
trim-wes-hair,
clean-garbage-cans, wipe-down-doors, clean-out-fridge-pantry
```

- [ ] **Step 4: Run the validator**

Run: `python3 scripts/validate-chores.py`
Expected:

```
OK: data/chores.json
  version: 2
  chores: 39
  daily: 11
  weekly: 12
  biweekly: 5
  monthly: 7
  bimonthly: 1
  quarterly: 3
  pinned: garbage-can-to-street-sunday→wes, laundry→anne, mow-lawn→anne, wash-all-rugs→anne, trim-wes-hair→anne
  season: mow-lawn
  together: clean-out-fridge-pantry
```

Then, one at a time, prove the rules bite: temporarily set `"together": true` on `laundry` (expect `FAIL: … a together chore has no fixedAssignee`), give `clean-out-fridge-pantry` a season (expect `FAIL: … cannot have a season`), and put `13` in `mow-lawn`'s months (expect `FAIL: … outside 1..12`). Revert each.

- [ ] **Step 5: Update every count that reads the file**

`ChoreListTests.swift`, replace `testRealSeedHas31ChoresAndTwoPinned`:

```swift
    func testRealSeedHas39ChoresAndFivePinned() throws {
        let list = try ChoreList.load(from: repoChoresURL())
        XCTAssertEqual(list.version, 2)
        XCTAssertEqual(list.chores.count, 39)
        XCTAssertEqual(Set(list.chores.map(\.id)).count, 39, "ids unique")

        let pinned = Dictionary(uniqueKeysWithValues: list.pinned.map { ($0.id, $0.fixedAssignee!) })
        XCTAssertEqual(pinned, [
            "laundry": .anne, "wash-all-rugs": .anne, "mow-lawn": .anne, "trim-wes-hair": .anne,
            "garbage-can-to-street-sunday": .wes,
        ])

        let counts = Dictionary(grouping: list.chores, by: \.cadence).mapValues(\.count)
        XCTAssertEqual(counts, [.daily: 11, .weekly: 12, .biweekly: 5, .monthly: 7, .bimonthly: 1, .quarterly: 3])
        XCTAssertEqual(list.chores.filter { $0.category == .catCare }.count, 5)

        XCTAssertEqual(list["mow-lawn"]?.season, Season(months: [4, 5, 6, 7, 8, 9, 10]))
        XCTAssertEqual(list.chores.filter(\.together).map(\.id), ["clean-out-fridge-pantry"])
        XCTAssertNil(list["take-out-garbages"], "split into three")
        XCTAssertNil(list["clean-out-fridge"], "replaced")
        // Grouped by cadence in Cadence.allCases order: the order is sortOrder on both stores.
        let ranks = list.chores.map { Cadence.allCases.firstIndex(of: $0.cadence)! }
        XCTAssertEqual(ranks, ranks.sorted())
    }
```

`SeedTests.swift`: `testSeedLoads31RowsAnd2Pinned` → `testSeedLoads39RowsAnd5Pinned`, counts 39, `choresVersion` 2, pinned dictionary with the five; `testReseedIsIdempotent` 31 → 39 (both lines); `testChoreRemovedFromFileIsRetiredAndReaddedIsRestored`: 30 → 38, 31 → 39, `version: 2` → `version: 3`.

`TodayPlannerTests.swift`, `testPinnedChoresLandOnTheRightPerson`: the last three assertions become

```swift
        // every active chore is due for exactly one person on day one — except the together chore, due for both
        XCTAssertEqual(Set(anne).intersection(wes), ["clean-out-fridge-pantry"])
        XCTAssertEqual(anne.count + wes.count, 40, "39 chores, one of them twice")
        XCTAssertEqual(plan.dueCount(for: .anne) + plan.dueCount(for: .wes), 40)
        XCTAssertTrue(anne.contains("mow-lawn"), "September is in season")
```

`SyncTests.swift`, `testDeltaWithChoresReseedsAndBumpsVersion`: the dictionary literal must carry the two optional keys through (add `"season": $0.season.map { ["months": Array($0.months)] } as Any` and `"together": $0.together`), `choresVersion: 2` → `3`, `active.count` 30 → 38.

`server/test/api.test.js`: the seed test title and its three `31`s → `39`, "2 pinned" → 5 (add `assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM chores WHERE fixedAssignee IS NOT NULL AND retired = 0").get().n, 5)`); `/chores` length 31 → 39 and `version` 1 → 2; the `/sync` assertions 31 → 39 (two lines); in the retire test `version: 2` → `version: 3`, `30` → `38`, and the final `31` → `39`.

`server/test/pairing.test.js:145`: 31 → 39. Also grep every test file for `choresVersion=1` in a URL: a mismatched version just includes `chores` in the response, so those stay correct, but change them to `choresVersion=2` where the test asserts `chores` is **omitted** (lists.test.js "matching choresVersion → chores omitted").

`Packages/RoostCore/README.md`: "31 chores, 2 pinned" → "39 chores, 5 pinned".

`data/README.md`: the field table gains `season` (`{"months":[1..12]}`, optional) and `together` (bool, optional); the cadence list has six; "Pinned" lists the five; "Count: **39** items (11+12+5+7+1+3), version 2 since 2026-09-13; the previous list was 31 (11+9+5+6)"; the validate section says it also checks the grouping order, the season and together rules, and the pinned set.

- [ ] **Step 6: Run all three suites**

```bash
python3 scripts/validate-chores.py
swift test --package-path Packages/RoostCore 2>&1 | tail -3
(cd server && npm test 2>&1 | tail -5)
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"
```

Expected: OK, all pass, all pass, `** TEST SUCCEEDED **`. Then run the app with `-roostUITestState paired`, open the gear menu → All chores, and confirm six groups with "Every two months" and "Every three months" headings, the TOGETHER chip on the pantry row, and "April to October" under Mow lawn. Screenshot for the PR.

- [ ] **Step 7: Commit and open the lane D PR**

```bash
git add data/chores.json scripts/validate-chores.py data/README.md Packages/RoostCore Roost/Tests server/test
git commit -m "chores.json v2: Anne's list — 39 chores, mow-lawn seasonal, fridge-and-pantry together"
gh api -X POST repos/amnanninga4/roost/pulls -f title="chores.json version 2: the 39-chore list" -f head=data/chores-v2 -f base=main -F body=@/dev/stdin <<'EOF'
Lane D of docs/superpowers/plans/2026-09-13-chores-update.md (task 16). Flips the list every suite reads, so it merges after the RoostCore, server and app PRs. Deploy the server from this merge (task 17): /sync hands out the version-2 list once.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

### Task 17: Rollout — server first, then the phone

Orchestrator only. Nothing here is a code change.

- [ ] **Step 1: Deploy the server and verify the migration ran**

```bash
fssh theoldone 'cd ~/roost && [ "$(git rev-parse --abbrev-ref HEAD)" = main ] && git pull -q --ff-only && sudo server/install.sh'
MAIN=$(git rev-parse origin/main)
curl -s https://roost.hinescreative.xyz/health | python3 -c "import json,sys; h=json.load(sys.stdin); print('rev ok' if h['rev'].startswith('$MAIN'[:len(h['rev'])]) or '$MAIN'.startswith(h['rev']) else 'rev MISMATCH '+h['rev']); print('choresVersion', h['choresVersion'], 'seeded', h['choresSeeded'], 'push', h['push'])"
fssh theoldone "sudo -u roost sqlite3 /var/lib/roost/roost.db \"SELECT value FROM meta WHERE key='schemaVersion'; PRAGMA foreign_key_check; SELECT COUNT(*) FROM chores WHERE retired=0; SELECT id, cadence, together, season FROM chores WHERE id IN ('mow-lawn','clean-out-fridge-pantry','trim-wes-hair');\""
```

Expected: `rev ok`, `choresVersion 2 seeded 39 push no key` (or the APNs state of the day), `2`, no foreign-key rows, `39`, and the three rows with `weekly 0 {"months":[4,5,6,7,8,9,10]}`, `quarterly 1 NULL`, `bimonthly 0 NULL`. (If `sqlite3` is not installed on the host, read the same through `node --input-type=module -e` with `node:sqlite`.)

- [ ] **Step 2: Install the new build on Wes's phone by cable**

```bash
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -configuration Debug -destination "id=<Wes's UDID>" -allowProvisioningUpdates -derivedDataPath "$SCRATCH/dd" build 2>&1 | tail -3
xcrun devicectl device install app --device <CoreDevice id> "$SCRATCH/dd/Build/Products/Debug-iphoneos/Roost.app"
```

Then on the phone: pull to refresh on Tasks; All chores shows 39 in six groups; the pantry row carries TOGETHER in both columns; Mow lawn is in Anne's column (September). Ask Wes to confirm the screen.

---

## Self-review against the spec

- **The list after the change** — task 16 (ids, titles, cadences, pins, order, version 2, notes).
- **New cadences** — tasks 1 (core), 6 (server), 12–13 (app labels/phrases), 16 (validator); weights 10/13 in 1 and 6; period phrases in 10 and 13, pinned by one test on each side.
- **Seasonal pause** — tasks 2–3 (core), 7–8 (server column + rule), 12–14 (record, DTO, season line), 16 (validator rules: months 1–12, not together, cadence ≤ monthly).
- **Together chores** — rules 1–5 in task 4 (two rows, one completion, credit, no handoffs, not balanced), 8 (server mirror), 9 (400 on offer), 10 (red alert to both, nameless), 14 (chip, kitchen banner once, VoiceOver), 16 (validator: no assignee).
- **Garbage split** — task 16; rotation seeds are the ids, nothing else to do.
- **Server schema migration** — task 7, keyed on `meta.schemaVersion`, rebuild inside one transaction with foreign keys off, tested from the version-1 strings; backup verifier's table list unchanged.
- **Rollout order** — lanes and task 17.
- **Tests / Docs lists** — every file the spec names appears in a task above; `HandoffPlanningTests` period phrases in 13; `data/README.md`, validator header, RoostCore README, Roost README, server README, NOTES, the `notes` string in 5, 11, 15, 16.
- **Not in this change** — nothing here touches reminders, the calendar, the tab bar, Wishlist, project dates, or per-cadence escalation.
- **Open questions for Anne** — the third garbage location is `kitchen` (master list) until she answers; the months are April–October; the haircut is bimonthly, pinned to Anne. All three are one-line JSON edits later, and the validator's counts and pins move with them.
