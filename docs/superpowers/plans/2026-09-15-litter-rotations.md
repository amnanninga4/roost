# Litter Rotations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A chore can state its own rotation (a repeating weekday table, or plain alternation from a named person) and can hand its period to whoever missed too many days of another chore — so scooping runs Anne 4 / Wes 3 and swaps weekly, the monthly litter change alternates from Wes, and more than two missed scoops in a month moves that month's change to the misser.

**Architecture:** Two optional keys in `data/chores.json` (version 5) travel the `season` / `weekdays` chain: validator → RoostCore `Chore` → two new `Rotation` implementations and a pure `MissCounter` → `Scheduler`'s assignment order → server columns, seed, shape and the `rules.js` mirror → app record, converters and sync DTO. Periods, due windows, handoffs, streaks and the escalation ladder are untouched; only the answer to "whose is it" changes, and only for chores that carry the new keys.

**Tech Stack:** Swift 6 packages (XCTest), SwiftUI/SwiftData app (XCTest), Node 22 server with `node:sqlite` (`node --test`), Python 3 validator.

**Spec:** `docs/superpowers/specs/2026-09-15-litter-rotations-design.md` (binding).

## Global Constraints

- `data/chores.json` `version` becomes **5**; 41 chores, per-cadence counts, the ten pins and every lane-1 window stay exactly as they are.
- `rotation` is `{"kind": "weekdayCycle", "weeks": [[7 people], …1–4 tables]}` (daily only) or `{"kind": "alternate", "start": "anne"|"wes"}` (any cadence). Never on a pinned chore.
- `weekdayCycle` lookup: for a daily chore the period index **is** the day index from the household anchor, and the anchor is a Monday, so `week = weeks[floorDiv(periodIndex, 7) mod weeks.count]` and the entry is `week[periodIndex mod 7]` with index 0 = Monday.
- `alternate`: `start` owns every **even** period index, the other person the odd ones. Never keyed off `activeFrom`.
- `missPenalty` is `{"watch": "<chore id>", "overMisses": <int 0–30>}`. Counted over the penalised chore's **calendar period** (`periodBounds`, not the due window). A missed day is a period of the watched chore that ended before today, started on or after `activeFrom`, was owed by that person (handoff, then pin, then rotation), and has no completion inside it by anyone. Over the threshold by **exactly one** person → that person; both over, or neither → the rotation stands (picking "further over" makes the owner flip daily, because the watched chore alternates daily).
- Assignment order everywhere: accepted handoff → `fixedAssignee` → `missPenalty` → `rotation` (chore's own, else the injected default round-robin).
- A chore with an explicit `rotation` is never moved by `FairnessBalancer`, even when the balancer is on.
- Both sides must agree: every Swift test date in this plan has a Node twin on the same date.
- User-facing strings only in `Roost/Sources/Strings.swift` (this lane adds none). No secrets. Never hand-edit the pbxproj: after adding a Swift file run `xcodegen generate` from `Roost/`. swiftformat/swiftlint clean on every changed Swift file.
- Branch `feat/litter-rotations` off `main` (≥ 7554dae); one commit per task; rebase before the PR; do not merge.
- Test commands: `python3 scripts/validate-chores.py` · `cd server && npm test` · `swift test --package-path Packages/RoostCore` · `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`. Baseline before this plan: RoostCore 65, server 154, RoostTests 329, RoostUITests 23.

## File structure

| Area | Files | Responsibility |
|---|---|---|
| Data | `data/chores.json`, `scripts/validate-chores.py`, `data/README.md` | the keys, their rules, the pinned rotation/penalty map |
| RoostCore models | `Sources/RoostCore/Models.swift` | `ChoreRotation`, `MissPenalty`, `Chore.rotation`, `Chore.missPenalty` |
| RoostCore rotation | `Sources/RoostCore/Rotation.swift` | `WeekdayCycleRotation`, `AlternateRotation`; `RoundRobinRotation` stays the default |
| RoostCore misses | `Sources/RoostCore/MissCounter.swift` (new) | pure: watched chore + bounds + completions + handoffs → misses per person |
| RoostCore wiring | `Sources/RoostCore/Scheduler.swift`, `FairnessBalancer.swift` | the assignment order; skip explicit rotations |
| RoostCore tests | `ChoreListTests`, `LitterRotationTests` (new) | the spec's dates |
| Server | `src/db.js`, `src/rules.js`, `README.md` | columns + schema v5 + seed/shape; the mirror |
| Server tests | `test/rules.test.js`, `test/api.test.js`, `test/migrate.test.js` | the same dates |
| App | `Sources/Models/Records.swift`, `Converters.swift`, `Sync/SyncAPI.swift`, `Sync/SyncClient.swift` | carry the two fields |
| App tests | `Tests/SeedTests.swift`, `Tests/SyncTests.swift` | round-trip |
| Docs | `Packages/RoostCore/README.md`, `server/README.md`, `NOTES.md` | |

Interfaces later tasks rely on:

```swift
public enum ChoreRotation: Codable, Sendable, Hashable {
    case weekdayCycle(weeks: [[Person]])
    case alternate(start: Person)
    func assignee(periodIndex: Int) -> Person          // pure, no calendar needed
}
public struct MissPenalty: Codable, Sendable, Hashable { public let watch: String; public let overMisses: Int }
public struct Chore { …; public let rotation: ChoreRotation?; public let missPenalty: MissPenalty? }
public enum MissCounter {
    public static func misses(
        watched: Chore, from: Date, through: Date, asOf: Date,
        activeFrom: Date, completions: [Completion], handoffs: [Handoff],
        calendar: HouseholdCalendar, fallback: Rotation
    ) -> [Person: Int]
    public static func penalised(_ counts: [Person: Int], overMisses: Int) -> Person?
}
```
```js
// server/src/rules.js
export function rotationFor(chore, periodIdx)        // chore.rotation or the hash round-robin
export function missesFor(watched, { from, through, asOf, activeFrom, completions, handoffs })
export function penalisedPerson(counts, overMisses)  // one person, or null
// assigneeFor(chore, periodIdx, handoffs, asOf, ctx) gains an optional ctx {chores, completions, activeFrom}
```

---

### Task 1: chores.json v5, validator, data README

**Files:** Modify `data/chores.json`, `scripts/validate-chores.py`, `data/README.md`.

- [ ] **Step 1: Make the validator demand v5 and the new keys (it fails first)**

```python
OPTIONAL_CHORE_KEYS = ("season", "together", "weekdays", "dueDay", "rotation", "missPenalty")
ROTATION_KINDS = frozenset({"weekdayCycle", "alternate"})

EXPECTED_VERSION = 5
EXPECTED_ROTATIONS = {
    "scoop-litter": {
        "kind": "weekdayCycle",
        "weeks": [
            ["anne", "wes", "anne", "wes", "anne", "wes", "anne"],
            ["wes", "anne", "wes", "anne", "wes", "anne", "wes"],
        ],
    },
    "change-litter": {"kind": "alternate", "start": "wes"},
}
EXPECTED_PENALTIES = {"change-litter": {"watch": "scoop-litter", "overMisses": 2}}


def check_rotation(loc: str, rotation: object, chore: dict) -> None:
    if not isinstance(rotation, dict) or "kind" not in rotation:
        fail(f"{loc}.rotation must be an object with a kind")
    kind = rotation["kind"]
    if kind not in ROTATION_KINDS:
        fail(f"{loc}.rotation.kind invalid: {kind!r} (want {sorted(ROTATION_KINDS)})")
    if chore["fixedAssignee"] is not None:
        fail(f"{loc}: a pinned chore cannot also carry a rotation")
    if kind == "weekdayCycle":
        if set(rotation) != {"kind", "weeks"}:
            fail(f"{loc}.rotation takes exactly kind and weeks")
        weeks = rotation["weeks"]
        if not isinstance(weeks, list) or not 1 <= len(weeks) <= 4:
            fail(f"{loc}.rotation.weeks must be a list of 1..4 week tables")
        for w, week in enumerate(weeks):
            if not isinstance(week, list) or len(week) != 7:
                fail(f"{loc}.rotation.weeks[{w}] must have exactly seven entries, Monday first")
            for d, who in enumerate(week):
                if who not in VALID_ASSIGNEES:
                    fail(f"{loc}.rotation.weeks[{w}][{d}] invalid: {who!r} (want anne|wes)")
        if chore["cadence"] != "daily":
            fail(f"{loc}: a weekdayCycle rotation needs a daily cadence, got {chore['cadence']!r}")
    else:
        if set(rotation) != {"kind", "start"}:
            fail(f"{loc}.rotation takes exactly kind and start")
        if rotation["start"] not in VALID_ASSIGNEES:
            fail(f"{loc}.rotation.start invalid: {rotation['start']!r} (want anne|wes)")


def check_penalty(loc: str, penalty: object, chore: dict, ids: set[str]) -> None:
    if not isinstance(penalty, dict) or set(penalty) != {"watch", "overMisses"}:
        fail(f"{loc}.missPenalty takes exactly watch and overMisses")
    if penalty["watch"] not in ids:
        fail(f"{loc}.missPenalty.watch names no chore in this file: {penalty['watch']!r}")
    if penalty["watch"] == chore["id"]:
        fail(f"{loc}.missPenalty.watch cannot be the chore itself")
    n = penalty["overMisses"]
    if not isinstance(n, int) or isinstance(n, bool) or not 0 <= n <= 30:
        fail(f"{loc}.missPenalty.overMisses must be an integer 0..30, got {n!r}")
```

The watch check needs every id, so collect `rotations`, `penalties` and the `(loc, penalty, chore)` triples inside the loop and run `check_penalty` after it, next to the other whole-file checks:

```python
        if "rotation" in chore:
            check_rotation(loc, chore["rotation"], chore)
            rotations[cid] = chore["rotation"]
        if "missPenalty" in chore:
            pending_penalties.append((loc, chore["missPenalty"], chore))
            penalties[cid] = chore["missPenalty"]
```

after the loop:

```python
    for loc, penalty, chore in pending_penalties:
        check_penalty(loc, penalty, chore, seen_ids)
    for cid, penalty in penalties.items():
        if penalty["watch"] in penalties:
            fail(f"{cid}: missPenalty.watch points at {penalty['watch']!r}, which is itself penalised; no chains")
    if rotations != EXPECTED_ROTATIONS:
        fail(f"rotations {rotations} do not match {EXPECTED_ROTATIONS}")
    if penalties != EXPECTED_PENALTIES:
        fail(f"miss penalties {penalties} do not match {EXPECTED_PENALTIES}")
```

plus two print lines after the dueDay line: `rotation: <ids>` and `missPenalty: <id>→watch/overMisses`. Update the module docstring (version 5, the two keys and their rules).

- [ ] **Step 2: Run it, expect the version failure**

Run: `python3 scripts/validate-chores.py` — Expected: `FAIL: version must be 5, got 4`, exit 1.

- [ ] **Step 3: Edit the data**

`data/chores.json`: `"version": 5`; `"locked": "2026-09-15"`; notes → `"Version 5, 2026-09-15: litter's two rotations from Anne's feedback on issue #1. scoop-litter takes a two-week weekdayCycle (week A Anne Mon/Wed/Fri/Sun, week B swapped); change-litter alternates from Wes and moves to whoever missed more than two scoop days that month. 41 tasks (13 daily + 12 weekly + 5 biweekly + 7 monthly + 1 bimonthly + 3 quarterly). Grouped by cadence; the order is sortOrder. Mockup sample rows are illustrative and must not be merged in."`. Add the `rotation` block to `scoop-litter` after `category`, and `rotation` + `missPenalty` to `change-litter` after its `dueDay`, exactly as `EXPECTED_ROTATIONS` / `EXPECTED_PENALTIES` spell them.

- [ ] **Step 4: Run the validator, expect OK**

Run: `python3 scripts/validate-chores.py` — Expected: `OK`, `version: 5`, `chores: 41`, the weekdays and dueDay lines unchanged from v4, a rotation line naming both litter chores, a missPenalty line naming `change-litter`.

- [ ] **Step 5: data/README.md** — the field table gains `rotation` (object, optional, never with a pin; `weekdayCycle` daily-only with 1–4 Monday-first tables; `alternate` with a starting person who owns even period indexes) and `missPenalty` (object, optional, `watch` + `overMisses`, counted over the chore's calendar period, beats the rotation and loses to a pin or an accepted handoff). Count line → `version 5 since 2026-09-15`. Add a short "Litter" paragraph stating the two rotations in Anne's words.

- [ ] **Step 6: Commit**

```bash
git add data/chores.json scripts/validate-chores.py data/README.md
git commit -m "chores.json v5: litter's two rotations and the missed-scoop consequence"
```

---

### Task 2: RoostCore — `ChoreRotation`, `MissPenalty`, and the two `Chore` fields

**Files:** Modify `Packages/RoostCore/Sources/RoostCore/Models.swift`, `Packages/RoostCore/Tests/RoostCoreTests/ChoreListTests.swift`.

**Produces:** `ChoreRotation`, `MissPenalty`, `Chore.rotation`, `Chore.missPenalty`, the widened `init`.

- [ ] **Step 1: Failing tests** — in `ChoreListTests`, bump `XCTAssertEqual(list.version, 4)` → `5` and append to the real-seed test:

```swift
        XCTAssertEqual(
            list["scoop-litter"]?.rotation,
            .weekdayCycle(weeks: [
                [.anne, .wes, .anne, .wes, .anne, .wes, .anne],
                [.wes, .anne, .wes, .anne, .wes, .anne, .wes],
            ])
        )
        XCTAssertEqual(list["change-litter"]?.rotation, .alternate(start: .wes))
        XCTAssertEqual(list["change-litter"]?.missPenalty, MissPenalty(watch: "scoop-litter", overMisses: 2))
        XCTAssertEqual(list.chores.filter { $0.rotation != nil }.count, 2)
        XCTAssertEqual(list.chores.filter { $0.missPenalty != nil }.count, 1)
        XCTAssertTrue(list.chores.allSatisfy { $0.rotation == nil || $0.fixedAssignee == nil })
```

and a decoder test beside `testWindowKeysDecodeAndDefault`:

```swift
    func testRotationAndPenaltyDecodeAndDefault() throws {
        let plain = #"{"id":"x","title":"X","cadence":"daily","fixedAssignee":null,"category":"chore"}"#
        let bare = try JSONDecoder().decode(Chore.self, from: Data(plain.utf8))
        XCTAssertNil(bare.rotation); XCTAssertNil(bare.missPenalty)

        let cycle = #"{"id":"s","title":"S","cadence":"daily","fixedAssignee":null,"category":"cat_care","rotation":{"kind":"weekdayCycle","weeks":[["anne","wes","anne","wes","anne","wes","anne"]]}}"#
        let scoop = try JSONDecoder().decode(Chore.self, from: Data(cycle.utf8))
        XCTAssertEqual(scoop.rotation, .weekdayCycle(weeks: [[.anne, .wes, .anne, .wes, .anne, .wes, .anne]]))

        let change = Chore(id: "c", title: "C", cadence: .monthly, category: .catCare,
                           rotation: .alternate(start: .wes),
                           missPenalty: MissPenalty(watch: "s", overMisses: 2))
        let round = try JSONDecoder().decode(Chore.self, from: JSONEncoder().encode(change))
        XCTAssertEqual(round, change)
    }
```

- [ ] **Step 2: Implement** — in `Models.swift`, above `Chore`:

```swift
/// How an unpinned chore picks its person, when the chore states it rather than taking the default
/// hash-and-alternate. Decoded from `"rotation"` in data/chores.json.
public enum ChoreRotation: Codable, Sendable, Hashable {
    /// One to four Monday-first week tables, used in turn. Daily chores only: a daily chore's period
    /// index is its day index from the anchor, and the anchor is a Monday.
    case weekdayCycle(weeks: [[Person]])
    /// `start` owns every even period index, the other person the odd ones. Not keyed off activeFrom:
    /// a rotation that moved when the household start date changed would reassign months already lived.
    case alternate(start: Person)

    public func assignee(periodIndex: Int) -> Person {
        switch self {
        case let .weekdayCycle(weeks):
            guard !weeks.isEmpty else { return .anne }
            let week = weeks[mod(floorDiv(periodIndex, 7), weeks.count)]
            guard week.count == 7 else { return .anne }
            return week[mod(periodIndex, 7)]
        case let .alternate(start):
            return mod(periodIndex, 2) == 0 ? start : start.other
        }
    }

    enum CodingKeys: String, CodingKey { case kind, weeks, start }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "weekdayCycle": self = .weekdayCycle(weeks: try c.decode([[Person]].self, forKey: .weeks))
        case "alternate": self = .alternate(start: try c.decode(Person.self, forKey: .start))
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown rotation kind '\(other)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .weekdayCycle(weeks):
            try c.encode("weekdayCycle", forKey: .kind); try c.encode(weeks, forKey: .weeks)
        case let .alternate(start):
            try c.encode("alternate", forKey: .kind); try c.encode(start, forKey: .start)
        }
    }
}

/// Hand this chore's period to whoever missed more than `overMisses` days of `watch` inside it.
public struct MissPenalty: Codable, Sendable, Hashable {
    public let watch: String
    public let overMisses: Int
    public init(watch: String, overMisses: Int) { self.watch = watch; self.overMisses = overMisses }
}
```

`ChoreRotation.assignee` needs `floorDiv`/`mod`; `HouseholdCalendar` has them as instance methods, so add file-private free functions in `Models.swift` (`private func floorDiv(_ a: Int, _ b: Int) -> Int` and `private func mod(_ a: Int, _ b: Int) -> Int`, same bodies) rather than making the enum depend on a calendar. Add `public var other: Person { self == .anne ? .wes : .anne }` to `Person` if it is not already there (grep first).

In `Chore`: two stored properties after `dueDay`, `rotation: ChoreRotation?` and `missPenalty: MissPenalty?`, both `nil` by default in `init`, both in `CodingKeys`, both `decodeIfPresent` in `init(from:)`, both `encodeIfPresent` in `encode(to:)`.

- [ ] **Step 3: Run** — `swift test --package-path Packages/RoostCore` — Expected: 66 tests, 0 failures.
- [ ] **Step 4: Commit** — `git add Packages/RoostCore && git commit -m "RoostCore: a chore can state its rotation and a miss penalty"`

---

### Task 3: RoostCore — `MissCounter`

**Files:** Create `Packages/RoostCore/Sources/RoostCore/MissCounter.swift`, create `Packages/RoostCore/Tests/RoostCoreTests/LitterRotationTests.swift`.

**Consumes:** `Chore.rotation`, `HandoffRules.acceptedOverride`. **Produces:** `MissCounter.misses(...)`, `MissCounter.penalised(_:overMisses:)`.

- [ ] **Step 1: Failing test** — new file; fixtures shared with Task 5's tests:

```swift
@testable import RoostCore
import XCTest

/// Anne's litter rules. Household starts Monday 2026-09-14 (daily period 252, weekly 36, monthly 8).
final class LitterRotationTests: XCTestCase {
    let cal = HouseholdCalendar()
    let scoop = Chore(
        id: "scoop-litter", title: "Scoop litter", cadence: .daily, category: .catCare,
        rotation: .weekdayCycle(weeks: [
            [.anne, .wes, .anne, .wes, .anne, .wes, .anne],
            [.wes, .anne, .wes, .anne, .wes, .anne, .wes],
        ])
    )
    let change = Chore(
        id: "change-litter", title: "Change litter", cadence: .monthly, category: .catCare, dueDay: 25,
        rotation: .alternate(start: .wes), missPenalty: MissPenalty(watch: "scoop-litter", overMisses: 2)
    )
    lazy var activeFrom = cal.date(year: 2026, month: 9, day: 14, hour: 0)
    lazy var scheduler = Scheduler(chores: [scoop, change], activeFrom: activeFrom, calendar: cal)

    func day(_ m: Int, _ d: Int, year: Int = 2026) -> Date { cal.date(year: year, month: m, day: d, hour: 9) }
    func done(_ chore: Chore, _ person: Person, _ date: Date) -> Completion {
        Completion(id: "\(chore.id)-\(date.timeIntervalSince1970)", choreId: chore.id, person: person, completedAt: date)
    }
    /// Misses inside September for the given completions.
    func septemberMisses(_ completions: [Completion], asOf: Date, handoffs: [Handoff] = []) -> [Person: Int] {
        let bounds = cal.periodBounds(.monthly, index: cal.periodIndex(.monthly, containing: day(9, 15)))
        return MissCounter.misses(
            watched: scoop, from: bounds.firstDay, through: bounds.lastDay, asOf: asOf,
            activeFrom: activeFrom, completions: completions, handoffs: handoffs,
            calendar: cal, fallback: RoundRobinRotation()
        )
    }

    func testNothingBeforeTheHouseholdStartedCounts() {
        // Sep 1–13 are before activeFrom; on Sep 15 only Mon 14 has ended.
        XCTAssertEqual(septemberMisses([], asOf: day(9, 15)), [.anne: 1])
    }

    func testTodayIsNeverAMissUntilItIsOver() {
        // Sun 20 is Anne's and unfinished, but it is today: Anne's misses are Mon 14, Wed 16, Fri 18.
        XCTAssertEqual(septemberMisses([], asOf: day(9, 20)), [.anne: 3, .wes: 3])
    }

    func testACompletionByAnyoneClearsTheDay() {
        let covered = [done(scoop, .wes, day(9, 14)), done(scoop, .anne, day(9, 16))]
        XCTAssertEqual(septemberMisses(covered, asOf: day(9, 20)), [.anne: 1, .wes: 3])
    }

    func testAnAcceptedHandoffMovesWhoMissedTheDay() {
        // Wed 16 is Anne's by the table; Wes accepted it, so an empty Wed 16 is Wes's miss.
        let period = cal.periodIndex(.daily, containing: day(9, 16))
        let taken = Handoff(id: "h1", choreId: scoop.id, from: .anne, to: .wes, periodIndex: period,
                            cadence: .daily, state: .accepted, createdAt: day(9, 16))
        let counts = septemberMisses([], asOf: day(9, 20), handoffs: [taken])
        XCTAssertEqual(counts, [.anne: 2, .wes: 4])
    }

    func testPenalisedPicksTheOneOverTheLine() {
        XCTAssertNil(MissCounter.penalised([.anne: 2, .wes: 2], overMisses: 2), "neither is over")
        XCTAssertEqual(MissCounter.penalised([.anne: 3, .wes: 1], overMisses: 2), .anne)
        XCTAssertNil(MissCounter.penalised([.anne: 4, .wes: 5], overMisses: 2), "both over: the rotation stands")
        XCTAssertNil(MissCounter.penalised([.anne: 4, .wes: 4], overMisses: 2), "both over")
    }
}
```

(Check `Handoff`'s real initialiser and `Completion`'s before writing these; use the package's own labels.)

- [ ] **Step 2: Implement**

```swift
import Foundation

/// Counts the days someone owed a chore and nobody did it. Pure: no storage, no clock beyond `asOf`.
///
/// A day is a miss when its period ended before today, started on or after `activeFrom`, was owed by
/// that person (an accepted handoff, then the pin, then the chore's own rotation, then the fallback),
/// and carries no completion by anyone. A partner's cover clears the chore but does not un-miss the
/// day for whoever owed it — the rule is about the person who owed it.
public enum MissCounter {
    public static func misses(
        watched: Chore, from: Date, through: Date, asOf: Date,
        activeFrom: Date, completions: [Completion], handoffs: [Handoff],
        calendar: HouseholdCalendar, fallback: Rotation
    ) -> [Person: Int] {
        let floor = calendar.periodIndex(watched.cadence, containing: activeFrom)
        let today = calendar.periodIndex(watched.cadence, containing: asOf)
        let first = max(calendar.periodIndex(watched.cadence, containing: from), floor)
        let last = min(calendar.periodIndex(watched.cadence, containing: through), today - 1)
        guard first <= last else { return [:] }

        var donePeriods = Set<Int>()
        for completion in completions where completion.choreId == watched.id {
            donePeriods.insert(calendar.periodIndex(watched.cadence, containing: completion.completedAt))
        }

        var counts: [Person: Int] = [:]
        for period in first ... last where !donePeriods.contains(period) {
            let owner = HandoffRules.acceptedOverride(choreId: watched.id, periodIndex: period, handoffs: handoffs)
                ?? watched.fixedAssignee
                ?? watched.rotation?.assignee(periodIndex: period)
                ?? fallback.assignee(for: watched, periodIndex: period)
            counts[owner, default: 0] += 1
        }
        return counts
    }

    /// The person a penalty moves the chore to: the only one over the line, or the one further over.
    /// Nil when neither is over or they are tied, which leaves the rotation's answer standing.
    public static func penalised(_ counts: [Person: Int], overMisses: Int) -> Person? {
        let over = Person.allCases.filter { (counts[$0] ?? 0) > overMisses }
        return over.count == 1 ? over[0] : nil
    }
}
```

Check `HandoffRules.acceptedOverride`'s real signature (it may take a date or return a `Handoff`); adapt the call and take `.toPerson` if so.

- [ ] **Step 3: Run** — Expected: 71 tests, 0 failures.
- [ ] **Step 4: Commit** — `git add Packages/RoostCore && git commit -m "RoostCore: MissCounter — who owed a day nobody did"`

---

### Task 4: RoostCore — the assignment order

**Files:** Modify `Packages/RoostCore/Sources/RoostCore/Scheduler.swift`, `FairnessBalancer.swift`, `Packages/RoostCore/Tests/RoostCoreTests/LitterRotationTests.swift`, `Packages/RoostCore/README.md`.

**Consumes:** `ChoreRotation.assignee(periodIndex:)`, `MissCounter`. **Produces:** the four-step order on both `assignee` overloads.

- [ ] **Step 1: Failing tests** — append to `LitterRotationTests`:

```swift
    func testScoopingRunsFourThreeAndSwapsEachWeek() {
        let week1: [(Int, Person)] = [(14, .anne), (15, .wes), (16, .anne), (17, .wes), (18, .anne), (19, .wes), (20, .anne)]
        for (d, who) in week1 {
            XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: cal.periodIndex(.daily, containing: day(9, d))), who, "Sep \(d)")
        }
        let week2: [(Int, Person)] = [(21, .wes), (22, .anne), (23, .wes), (24, .anne), (25, .wes), (26, .anne), (27, .wes)]
        for (d, who) in week2 {
            XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: cal.periodIndex(.daily, containing: day(9, d))), who, "Sep \(d)")
        }
        // and back: Mon 28 is Anne's again
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: cal.periodIndex(.daily, containing: day(9, 28))), .anne)
        // four days one week, three the next, for each of them
        XCTAssertEqual(week1.filter { $0.1 == .anne }.count, 4)
        XCTAssertEqual(week2.filter { $0.1 == .anne }.count, 3)
    }

    func testAnAcceptedHandoffStillBeatsTheTableAndDoesNotLeakIntoNextWeek() {
        let wed = cal.periodIndex(.daily, containing: day(9, 16))
        let taken = Handoff(id: "h1", choreId: scoop.id, from: .anne, to: .wes, periodIndex: wed,
                            cadence: .daily, state: .accepted, createdAt: day(9, 16))
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: wed, on: day(9, 16), handoffs: [taken]), .wes)
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: wed + 1, on: day(9, 17), handoffs: [taken]), .wes, "Thu is Wes's anyway")
        let nextWed = cal.periodIndex(.daily, containing: day(9, 23))
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: nextWed, on: day(9, 23), handoffs: [taken]), .wes, "week B")
        let weekAfter = cal.periodIndex(.daily, containing: day(9, 30))
        XCTAssertEqual(scheduler.assignee(for: scoop, periodIndex: weekAfter, on: day(9, 30), handoffs: [taken]), .anne, "week A again")
    }

    func testTheChangeAlternatesFromWes() {
        XCTAssertEqual(scheduler.assignee(for: change, periodIndex: cal.periodIndex(.monthly, containing: day(9, 25))), .wes)
        XCTAssertEqual(scheduler.assignee(for: change, periodIndex: cal.periodIndex(.monthly, containing: day(10, 25))), .anne)
        XCTAssertEqual(scheduler.assignee(for: change, periodIndex: cal.periodIndex(.monthly, containing: day(11, 25))), .wes)
    }

    func testTheChangeMovesToWhoeverMissedMoreThanTwoScoops() {
        // Anne scooped none of hers; Wes did all of his through Sep 24, so only Anne is over the line.
        var completions: [Completion] = []
        for d in [15, 17, 19, 21, 23] { completions.append(done(scoop, .wes, day(9, d))) }
        let plan = scheduler.plan(on: day(9, 25), completions: completions)
        let wesRows = plan[.wes]?.map(\.chore.id) ?? []
        let anneRows = plan[.anne]?.map(\.chore.id) ?? []
        XCTAssertTrue(anneRows.contains(change.id), "Anne missed 5 scoops, so September's change is hers")
        XCTAssertFalse(wesRows.contains(change.id), "the rotation said Wes; the penalty moved it")

        // A late scoop that removes Anne's fourth miss is not enough to take her back under 2, but
        // covering all but two is: the change goes back to the rotation's Wes.
        for d in [14, 16, 18] { completions.append(done(scoop, .anne, day(9, d))) }
        let after = scheduler.plan(on: day(9, 25), completions: completions)
        XCTAssertTrue((after[.wes]?.map(\.chore.id) ?? []).contains(change.id), "Anne is back under the line")
    }

    func testTheOtherChoresAreUnaffected() {
        let laundry = Chore(id: "laundry", title: "Laundry", cadence: .weekly, fixedAssignee: .anne, category: .chore)
        let toilet = Chore(id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: .weekly, category: .chore)
        let s = Scheduler(chores: [laundry, toilet], activeFrom: activeFrom, calendar: cal)
        let week = cal.periodIndex(.weekly, containing: day(9, 16))
        XCTAssertEqual(s.assignee(for: laundry, periodIndex: week), .anne, "a pin still wins")
        XCTAssertEqual(
            s.assignee(for: toilet, periodIndex: week),
            RoundRobinRotation().assignee(for: toilet, periodIndex: week),
            "an ordinary chore still hash-rotates"
        )
    }
```

- [ ] **Step 2: Implement** — `Scheduler` grows one private resolver and both `assignee` overloads route through it:

```swift
    /// Who owes `chore` for `periodIndex`, ignoring handoffs: the pin, then a miss penalty, then the
    /// chore's own rotation, then the injected default. `completions` is only read when a penalty is
    /// in play, so the common path allocates nothing.
    func owner(
        for chore: Chore, periodIndex: Int, on date: Date,
        completions: [Completion], handoffs: [Handoff]
    ) -> Person {
        if let pinned = chore.fixedAssignee { return pinned }
        if let penalty = chore.missPenalty,
           let watched = chores.first(where: { $0.id == penalty.watch }) {
            let bounds = calendar.periodBounds(chore.cadence, index: periodIndex)
            let counts = MissCounter.misses(
                watched: watched, from: bounds.firstDay, through: bounds.lastDay, asOf: date,
                activeFrom: activeFrom, completions: completions, handoffs: handoffs,
                calendar: calendar, fallback: rotation
            )
            if let moved = MissCounter.penalised(counts, overMisses: penalty.overMisses) { return moved }
        }
        if let own = chore.rotation { return own.assignee(periodIndex: periodIndex) }
        return rotation.assignee(for: chore, periodIndex: periodIndex)
    }
```

`assignee(for:periodIndex:)` becomes `owner(for:periodIndex:on: Date(), completions: [], handoffs: [])`… **no**: that would make a pure function depend on the clock. Instead keep the two-argument overload as pin → rotation only (documented: it cannot see a penalty, because a penalty needs the day's completions), and add the completions to the overload that already takes `on:` and `handoffs:`:

```swift
    public func assignee(for chore: Chore, periodIndex: Int) -> Person {
        if let pinned = chore.fixedAssignee { return pinned }
        if let own = chore.rotation { return own.assignee(periodIndex: periodIndex) }
        return rotation.assignee(for: chore, periodIndex: periodIndex)
    }

    public func assignee(
        for chore: Chore, periodIndex: Int, on date: Date,
        handoffs: [Handoff], completions: [Completion] = []
    ) -> Person {
        if let override = HandoffRules.acceptedOverride(choreId: chore.id, periodIndex: periodIndex, handoffs: handoffs) {
            return override
        }
        return owner(for: chore, periodIndex: periodIndex, on: date, completions: completions, handoffs: handoffs)
    }
```

The defaulted `completions:` keeps every existing caller compiling. `dueItem(...)` already has the day's completions in hand — pass them through to the `assignee(...)` call it makes, so Today, the widget and the digest all see the penalty. `Tallies` keeps calling the pure overload (a streak walks history and must not re-derive penalties from a partial completion list) — say so in a comment there.

`FairnessBalancer.isReassignable` (or its equivalent predicate) gains `chore.rotation == nil && chore.missPenalty == nil` so an explicit rotation is never optimised away.

- [ ] **Step 3: Run** — `swift test --package-path Packages/RoostCore` — Expected: 76 tests, 0 failures, and every lane-1 due-window test still green.
- [ ] **Step 4: README** — `Packages/RoostCore/README.md`: a "Rotations and penalties" paragraph — the four-step order, the two rotation kinds, what counts as a miss, and the note that the pure `assignee(for:periodIndex:)` cannot see a penalty.
- [ ] **Step 5: Commit** — `git add Packages/RoostCore && git commit -m "RoostCore: handoff, pin, penalty, rotation — in that order"`

---

### Task 5: Server — columns, schema v5, seed and shape

**Files:** Modify `server/src/db.js`, `server/test/migrate.test.js`, `server/test/api.test.js`.

- [ ] **Step 1: Failing tests** — in `migrate.test.js`, copy the v4 test's shape: build a v4 `chores` table with `schemaVersion` 4, open with `openDb`, assert the columns now include `rotation` and `missPenalty`, `schemaVersion` is `"5"`, the old row survives with both null, and a second `openDb` is a no-op. In `api.test.js`, `choresVersion` 4 → 5 everywhere (including the `/sync?choresVersion=` query strings, which also live in `lists.test.js`), the retire test's trimmed `version: 5` → `6`, and add to the seed test:

```js
  const litter = app.db.prepare("SELECT rotation, missPenalty FROM chores WHERE id = 'scoop-litter'").get();
  assert.deepEqual(JSON.parse(litter.rotation).weeks[0], ["anne", "wes", "anne", "wes", "anne", "wes", "anne"]);
  assert.equal(litter.missPenalty, null);
  const shaped = (await call("GET", "/chores", { token: ANNE })).body.chores;
  assert.deepEqual(shaped.find((c) => c.id === "change-litter").rotation, { kind: "alternate", start: "wes" });
  assert.deepEqual(shaped.find((c) => c.id === "change-litter").missPenalty, { watch: "scoop-litter", overMisses: 2 });
  assert.equal(shaped.find((c) => c.id === "laundry").rotation, null);
  assert.equal(shaped.filter((c) => c.rotation != null).length, 2);
```

- [ ] **Step 2: Implement** — `SCHEMA_VERSION = 5`; `CHORES_COLUMNS` gains `,\n  rotation      TEXT,\n  missPenalty   TEXT`; `migrate` gets `if (current < 5) migrateToV5(db);` with the same guarded `ALTER TABLE chores ADD COLUMN` pair as v4; `seedChores` upserts `c.rotation ? JSON.stringify(c.rotation) : null` and `c.missPenalty ? JSON.stringify(c.missPenalty) : null`; `shapeChore` parses both back (or null) and `listChores` selects them.
- [ ] **Step 3: Run** — `cd server && npm test` — Expected: green, one more test than the 154 baseline.
- [ ] **Step 4: Commit** — `git add server && git commit -m "server: chores carry rotation and missPenalty (schema v5, seed, shape)"`

---

### Task 6: Server — the `rules.js` mirror

**Files:** Modify `server/src/rules.js`, `server/test/rules.test.js`, `server/README.md`.

- [ ] **Step 1: Failing tests** — in `rules.test.js`, import `rotationFor`, `missesFor`, `penalisedPerson`; fixtures mirroring the Swift ones:

```js
const scoopL = { id: "scoop-litter", title: "Scoop litter", cadence: "daily", fixedAssignee: null, category: "cat_care",
  rotation: { kind: "weekdayCycle", weeks: [["anne","wes","anne","wes","anne","wes","anne"], ["wes","anne","wes","anne","wes","anne","wes"]] } };
const changeL = { id: "change-litter", title: "Change litter", cadence: "monthly", fixedAssignee: null, category: "cat_care",
  dueDay: 25, rotation: { kind: "alternate", start: "wes" }, missPenalty: { watch: "scoop-litter", overMisses: 2 } };
const start14 = chicagoLocal(2026, 9, 14, 0, 0, 0);
const at = (m, d) => chicagoLocal(2026, m, d, 9, 0, 0);

test("scooping runs four/three and swaps each week", () => {
  const week1 = [[14,"anne"],[15,"wes"],[16,"anne"],[17,"wes"],[18,"anne"],[19,"wes"],[20,"anne"]];
  const week2 = [[21,"wes"],[22,"anne"],[23,"wes"],[24,"anne"],[25,"wes"],[26,"anne"],[27,"wes"]];
  for (const [d, who] of [...week1, ...week2]) {
    assert.equal(rotationFor(scoopL, periodIndex("daily", at(9, d))), who, `Sep ${d}`);
  }
  assert.equal(rotationFor(scoopL, periodIndex("daily", at(9, 28))), "anne");
});

test("the change alternates from Wes", () => {
  assert.equal(rotationFor(changeL, periodIndex("monthly", at(9, 25))), "wes");
  assert.equal(rotationFor(changeL, periodIndex("monthly", at(10, 25))), "anne");
  assert.equal(rotationFor(changeL, periodIndex("monthly", at(11, 25))), "wes");
});

test("misses: nothing before activeFrom, today is never a miss, anyone's completion clears the day", () => {
  const bounds = periodBounds("monthly", periodIndex("monthly", at(9, 15)));
  const count = (completions, asOf, handoffs = []) => missesFor(scoopL, {
    from: bounds.firstDay, through: bounds.lastDay, asOf, activeFrom: start14, completions, handoffs });
  assert.deepEqual(count([], at(9, 15)), { anne: 1 });
  assert.deepEqual(count([], at(9, 20)), { anne: 3, wes: 3 });
  const covered = [{ choreId: "scoop-litter", person: "wes", completedAt: at(9, 14).toISOString() },
                   { choreId: "scoop-litter", person: "anne", completedAt: at(9, 16).toISOString() }];
  assert.deepEqual(count(covered, at(9, 20)), { anne: 1, wes: 3 });
  const taken = [{ id: "h1", choreId: "scoop-litter", fromPerson: "anne", toPerson: "wes",
                   periodIndex: periodIndex("daily", at(9, 16)), cadence: "daily", state: "accepted",
                   createdAt: at(9, 16).toISOString() }];
  assert.deepEqual(count([], at(9, 20), taken), { anne: 2, wes: 4 });
});

test("penalisedPerson: over the line, further over, tied", () => {
  assert.equal(penalisedPerson({ anne: 2, wes: 2 }, 2), null);
  assert.equal(penalisedPerson({ anne: 3, wes: 1 }, 2), "anne");
  assert.equal(penalisedPerson({ anne: 4, wes: 5 }, 2), null, "both over: the rotation stands");
  assert.equal(penalisedPerson({ anne: 4, wes: 4 }, 2), null);
});

test("the change moves to whoever missed more than two scoops", () => {
  const completions = [15, 17, 19, 21, 23].map((d) => ({ choreId: "scoop-litter", person: "wes", completedAt: at(9, d).toISOString() }));
  const plan = dueItems({ chores: [scoopL, changeL], completions, asOf: at(9, 25), activeFrom: start14 });
  assert.ok(plan.anne.some((i) => i.chore.id === "change-litter"), "Anne missed five scoops");
  assert.ok(!plan.wes.some((i) => i.chore.id === "change-litter"));
});
```

- [ ] **Step 2: Implement** — `rules.js` gains, beside `rotationAssignee`:

```js
/** A chore's own rotation, or the hash round-robin. Mirrors ChoreRotation.assignee(periodIndex:). */
export function rotationFor(chore, periodIdx) {
  const r = chore.rotation;
  if (!r) return rotationAssignee(chore.id, periodIdx);
  if (r.kind === "weekdayCycle") {
    const weeks = r.weeks ?? [];
    if (!weeks.length) return "anne";
    const week = weeks[mod(floorDiv(periodIdx, 7), weeks.length)];
    return week?.length === 7 ? week[mod(periodIdx, 7)] : "anne";
  }
  if (r.kind === "alternate") {
    const other = r.start === "anne" ? "wes" : "anne";
    return mod(periodIdx, 2) === 0 ? r.start : other;
  }
  return rotationAssignee(chore.id, periodIdx);
}

/** Days inside [from, through] that `watched` was owed by someone and nobody did. Mirrors MissCounter. */
export function missesFor(watched, { from, through, asOf, activeFrom, completions = [], handoffs = [] }) { … }

/** The person a penalty moves a chore to, or null. Mirrors MissCounter.penalised. */
export function penalisedPerson(counts, overMisses) { … }
```

`missesFor` walks the same period range with the same rules as the Swift version (floor at `activeFrom`'s period, stop at `today − 1`, a completion by anyone clears the day, ownership via `assigneeFor(watched, period, handoffs)` so an accepted handoff moves the miss). `assigneeFor` gains an optional fifth argument `ctx = {}`; when `chore.missPenalty` is set and `ctx.chores`/`ctx.completions`/`ctx.activeFrom` are present it runs the penalty between the pin and the rotation, and its final line becomes `return rotationFor(chore, periodIdx)`. `dueItemFor` passes that context (it already holds the chore list via its caller — thread `chores` through `dueItems` into each `dueItemFor` call).

- [ ] **Step 3: Run** — `cd server && npm test` — Expected: green; report the new count and any push/digest assertion that moved (recompute, never loosen).
- [ ] **Step 4: README** — `server/README.md`: the two columns and the mirror functions, one sentence that the digest and red-alert sweep follow the same order.
- [ ] **Step 5: Commit** — `git add server && git commit -m "server: rules mirror the rotations and the miss penalty"`

---

### Task 7: App — carry the two fields

**Files:** Modify `Roost/Sources/Models/Records.swift`, `Converters.swift`, `Sync/SyncAPI.swift`, `Sync/SyncClient.swift`, `Roost/Tests/SeedTests.swift`, `Roost/Tests/SyncTests.swift`.

- [ ] **Step 1: Failing tests** — `SeedTests`: `choresVersion` 4 → 5, the retire test's trimmed version 5 → 6, and a round-trip test in the shape of `testWindowsRoundTripThroughTheRecord`: seed a `weekdayCycle` chore and an `alternate` + penalty chore, read the records back, assert `toChore()` returns them unchanged, assert the stored text is the JSON, assert re-seeding without the keys clears both columns, and assert a broken `rotation` text throws a conversion error rather than crashing. `SyncTests`: the `trimmed` dictionary carries `"rotation"` and `"missPenalty"`, the stub's `choresVersion` moves 5 → 6, and a sibling `testServerSentChoresCarryRotations` asserts a `/sync` payload with both keys lands on the records.

- [ ] **Step 2: Implement** — `ChoreRecord` gains `var rotation: String?` and `var missPenalty: String?` (JSON text, the `season` pattern) with defaults on `init`. `Converters`: `init(_:sortOrder:)` and `apply` set them through two new `static func rotationText(_:)` / `penaltyText(_:)` helpers; `toChore()` decodes them, throwing `ConversionError.badRotation(text, id:)` / `.badMissPenalty(text, id:)` (add both cases and their description lines). `ChoreDTO` gains `let rotation: ChoreRotation?` and `let missPenalty: MissPenalty?`, both optional so an older server still decodes; `SyncClient.apply` passes them into `Chore(...)`.

- [ ] **Step 3: Run** — `xcodebuild … -only-testing:RoostTests test` — Expected: `** TEST SUCCEEDED **`, 331-ish tests, 0 failures.
- [ ] **Step 4: Commit** — `git add Roost && git commit -m "app: ChoreRecord and sync carry rotation and missPenalty"`

---

### Task 8: Docs and the PR

**Files:** Modify `NOTES.md`, `Roost/README.md`.

- [ ] **Step 1:** `NOTES.md`: `2026-09-15 — Litter: scoop-litter takes a two-week weekdayCycle (Anne 4 / Wes 3, swapping); change-litter alternates from Wes and moves to whoever missed more than two scoop days that month. Assignment order is accepted handoff, pin, miss penalty, rotation. Spec docs/superpowers/specs/2026-09-15-litter-rotations-design.md.` `Roost/README.md`: one line that a chore may state its own rotation and that the app shows no chrome for it in this lane.
- [ ] **Step 2:** Run all four suites on the rebased branch and paste the tails in the PR: validator OK v5; server green; RoostCore 76; app `** TEST SUCCEEDED **`.
- [ ] **Step 3:** `git commit -am "docs: litter rotations"`, rebase on main, push `feat/litter-rotations`, open the PR against main with the tails and the spec's dates table in the body. Do not merge.

## Self-Review

**Spec coverage:** data keys + validator + README (Task 1); `ChoreRotation` / `MissPenalty` / `Chore` fields (2); miss counting incl. handoffs, activeFrom floor and "today is not a miss" (3); the four-step order, the balancer skip, the litter dates (4); server columns and migration (5); the Node mirror on the same dates (6); app record/DTO/sync (7); docs (8). No-UI-this-lane is honoured: no task touches a screen or `Strings.swift`.

**Placeholder scan:** `missesFor` and `penalisedPerson` bodies in Task 6 are stated as mirrors of Task 3's Swift, whose full body is in the plan; every other step carries complete code, commands and expected results. Task 3 and Task 4 flag the two signatures (`HandoffRules.acceptedOverride`, `Handoff.init`) that must be read from the source before writing the tests.

**Type consistency:** `ChoreRotation.assignee(periodIndex:)` (Tasks 2, 3, 4); `MissPenalty(watch:overMisses:)` (2, 3, 4, 5, 6); `MissCounter.misses(watched:from:through:asOf:activeFrom:completions:handoffs:calendar:fallback:)` and `.penalised(_:overMisses:)` (3, 4); `Scheduler.assignee(for:periodIndex:on:handoffs:completions:)` with `completions` defaulted (4, and every existing caller); `rotationFor` / `missesFor` / `penalisedPerson` (6); `ChoreRecord.rotation: String?` / `missPenalty: String?` (7).

**Arithmetic checked:** Monday 2026-09-14 is day index 252 and 252 = 36 × 7, so it is weekday slot 0 of weekly period 36; 36 is even, so week table 0 applies and Monday is Anne's, matching Anne's list. Monday 2026-09-21 is day 259, weekly period 37, odd, so table 1 applies and Monday is Wes's. September 2026 is monthly period 8, even, so `alternate(start: .wes)` gives Wes. On Sep 20 with nothing done, ended-and-owed days are Sep 14–19: Anne 14/16/18 = 3, Wes 15/17/19 = 3.
