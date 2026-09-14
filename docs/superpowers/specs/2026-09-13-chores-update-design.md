# Chores update — design

2026-09-13. Source: Anne's notes on issue #1 (18:05 CDT) and Wes's decisions in chat the same evening. Status: draft for Wes and Anne to review before implementation.

## What this changes

The household list gains six chores, replaces one, and splits one into three. Three of those need mechanics the app does not have yet:

- two longer cadences: every two months and every three months;
- a seasonal pause, so mowing stops being due in winter;
- a chore both people do together, which shows on both boards, clears with one check-off, and credits both.

Everything else in this document exists so those three land without breaking the rules that already work (rotation, escalation, streaks, handoffs, the kitchen board, the digest).

## The list after the change

`data/chores.json` goes to `version: 2` (the version bump is what makes both phones re-fetch the list). Entries keep their five keys; two optional keys are added, described below.

| Change | id | Title | Cadence | Assignee | Notes |
|---|---|---|---|---|---|
| add | `clean-garbage-cans` | Clean garbage cans | quarterly | rotation | |
| add | `wipe-down-doors` | Wipe down doors | quarterly | rotation | |
| add | `clean-medicine-cabinet` | Clean inside medicine cabinet | monthly | rotation | |
| add | `wash-all-rugs` | Wash all rugs (washer) | monthly | anne | distinct from `clean-rugs`, which is vacuuming |
| add | `mow-lawn` | Mow lawn | weekly | anne | `season: {"months": [4,5,6,7,8,9,10]}` |
| add | `trim-wes-hair` | Trim Wes's hair | bimonthly | anne | Anne listed this as a reminder; it recurs, so it is a chore |
| replace | `clean-out-fridge-pantry` replaces `clean-out-fridge` | Clean out fridge and pantry | quarterly | together | old id retired, its history kept |
| split | `take-out-garbage-basement`, `take-out-garbage-bathroom`, `take-out-garbage-kitchen` replace `take-out-garbages` | Take out garbage: basement / bathroom / kitchen | weekly | rotation | the third location is Anne's call, see open questions |

Counts after the change: daily 11, weekly 12, biweekly 5, monthly 7, bimonthly 1, quarterly 3, total 39. Pinned: `laundry` and `wash-all-rugs` and `mow-lawn` and `trim-wes-hair` to Anne, `garbage-can-to-street-sunday` to Wes.

The file stays grouped by cadence in this order: daily, weekly, biweekly, monthly, bimonthly, quarterly. Order is meaning: it becomes `sortOrder` on both stores and breaks ties on the Today board.

Anne's other requests in the same note are not chores and are handled elsewhere: shopping items and projects are entered in the app, reminders are their own design.

## New cadences: bimonthly and quarterly

Both are month-based, the way `monthly` already is. With `monthIndex = (year - 2026) * 12 + (month - 1)` in America/Chicago:

| Cadence | Period index | Period bounds |
|---|---|---|
| monthly (unchanged) | `monthIndex` | that calendar month |
| bimonthly | `floorDiv(monthIndex, 2)` | two calendar months, starting Jan, Mar, May, … |
| quarterly | `floorDiv(monthIndex, 3)` | three calendar months, starting Jan, Apr, Jul, Oct |

Period 0 contains the anchor (Monday 2026-01-05) for both, which is the invariant the existing calendar tests assert. Escalation stays cadence-independent: a quarterly chore not done by the end of its quarter is one day late on the first day of the next, exactly like a daily. Streaks stay daily-only.

Fairness weights (the balancer is off in the app and off by default on the server, but the tables must be complete): bimonthly 10, quarterly 13, continuing the provisional series 1, 3, 5, 8.

Where the cadence set is written down today, all of which change together:

- `Packages/RoostCore/Sources/RoostCore/Models.swift` — `Cadence` gains `.bimonthly` and `.quarterly`. Being `CaseIterable`, the All chores screen groups them automatically.
- `Packages/RoostCore/Sources/RoostCore/HouseholdCalendar.swift` — `periodIndex` and `periodBounds` gain the two arms. One private helper, `months(per cadence)`, so monthly, bimonthly and quarterly share one code path.
- `Packages/RoostCore/Sources/RoostCore/FairnessBalancer.swift` — `FairnessWeights` gains two fields and two switch arms; the doc comment and the README table follow.
- `server/src/rules.js` — `periodIndex`, `periodBounds`, `FAIRNESS_WEIGHTS`, mirroring the Swift bit for bit; the existing rules tests that pin the anchor at period 0 and the weight table gain the two cadences.
- `server/src/db.js` — the `chores` table `CHECK (cadence IN …)` and the `handoffs` table's copy of it. See migration below.
- `server/src/handoffs.js` — the literal cadence array in request validation.
- `server/src/push.js` and `Roost/Sources/Strings.swift` and `Roost/Sources/Models/HandoffPresentation.swift` — the period phrase for handoff pushes and copy: "this month" for monthly, "these two months" for bimonthly, "this quarter" for quarterly. The server and the app must say the same words; one test on each side holds them together.
- `Roost/Sources/Screens/ChoreListScreen.swift` and `Strings.Chores` — section labels "Every two months" and "Every three months".
- `scripts/validate-chores.py` — `VALID_CADENCES`, the expected total, the per-cadence counts, and the pinned set (now a list of five, not "exactly 2").

## Seasonal pause

An optional key on a chore:

```json
"season": { "months": [4, 5, 6, 7, 8, 9, 10] }
```

A chore with a season is due only in periods whose first day falls in one of those months. Outside the season it is not due and cannot be overdue; a period that started in October and runs into November stays due until it is done or its period ends, the same as any other. No chore with a season may be `together` or have a cadence longer than monthly (the validator enforces this; nothing needs it).

- `Packages/RoostCore` — `Chore` gains `season: Season?` (`Season` is a struct with `months: Set<Int>`); `Scheduler.dueItem(for:on:…)` returns nil when the period start is out of season. `ChoreList` decodes the optional key.
- `server/src/rules.js` — `dueItemFor` applies the same rule; `db.js` adds a nullable `season` TEXT column holding the JSON, seeded from the file, returned on `/chores` and in `/sync` chores.
- `Roost/Sources/Models/Records.swift` — `ChoreRecord` gains `season: String?` (JSON text, decoded in the converter). Adding an optional property is a lightweight SwiftData migration; nothing else is needed. `ChoreDTO` gains the optional field.
- The All chores row shows "April to October" under a seasonal chore, from a new `Strings.Chores.season(...)` line.

Anne's note says "pauses in winter". April through October is the proposal for Chicago; she can change the months in the JSON at any time, and the validator checks they are 1 to 12.

## Together chores

An optional key on a chore:

```json
"together": true
```

A together chore has no assignee (`fixedAssignee` must be null, no rotation) and is owed by both people at once.

Rules, on both sides:

1. **Two rows.** `Scheduler.plan` and the server's `dueItems` emit one `DueItem` per person for a together chore, same chore and period, `person` anne and wes. The item id, today `"<choreId>#<periodIndex>"`, becomes `"<choreId>#<periodIndex>#<person>"` for together items only; every other id is unchanged, so the balancer's maps, notification identifiers and the widget snapshot keep working.
2. **One check-off clears both.** Period completeness is already credit-blind (any completion in the period completes the chore), so the first person to check it off removes it from both boards on the next sync. Un-checking restores it for both.
3. **Both get credit.** There is one completion row, by whoever tapped (the server already stamps `person` from the token). Credit is a rule, not a second row: `Tallies.doneThisWeek` and the server's week tally count a together chore's completion for both people. The head-to-head bar therefore moves for both.
4. **No handoffs, no balancing.** A together chore cannot be offered (nothing to hand over); `HandoffRules` and the app's offer affordance treat it as pinned. The balancer never moves it.
5. **Copy and boards.** The Tasks row carries a "Together" chip where the pinned name chip goes today. The kitchen board lists it under both names but the alert banner shows it once. The red alert for a together chore goes to both phones with a body that names nobody ("Clean out fridge and pantry is 5 days late"). The morning digest counts it for both, which it already would.

Where this lands:

- `Packages/RoostCore` — `Chore.together: Bool` (default false), the two-row emission in `Scheduler.plan` and `dueItem`, the id rule in `DueItem`, `Tallies.doneThisWeek` credit rule, `HandoffRules.canOffer` false. `TodayPlannerTests` today asserts every chore is due for exactly one person on day one; that invariant becomes "exactly one, except together chores, which are due for both".
- `server/src/rules.js` — `dueItems`, `dueItemId`, `viaHandoff` (false for together), `boardStats` week count, `isReassignable` false; `handoffs.js` rejects offers on together chores with `400 together`; `push.js` red-alert branch for together items; `db.js` adds `together INTEGER NOT NULL DEFAULT 0`, seeded from the file, returned on `/chores` and `/sync`.
- `Roost/` — `ChoreRecord.together`, `ChoreDTO.together`, the converter, `TodayRow` id, the Together chip in `ChoreRowView`, `HandoffPresentation`/offer gating, `KitchenModel` banner dedupe, `SnapshotBuilder` unchanged.

## Garbage split

Three weekly chores replace `take-out-garbages`. Each rotates on its own (the rotation seed is the chore id, so the three will not all land on the same person in the same week by construction; they may by chance). The old id is retired by the seeders on both sides and its completions stay in history, which keeps past weeks' tallies honest.

## Server schema migration

`CREATE TABLE IF NOT EXISTS` leaves the deployed database's `CHECK (cadence IN ('daily','weekly','biweekly','monthly'))` in place, so widening the enum in the schema string is not enough. `db.js` gains a one-time migration keyed on a new `meta.schemaVersion`:

1. If `schemaVersion` is absent or below 2: with foreign keys off inside one transaction, rebuild `chores` and `handoffs` with the widened CHECK and the two new `chores` columns (`season` TEXT NULL, `together` INTEGER NOT NULL DEFAULT 0), copy every row, drop the old tables, rename, recreate the indexes, then set `schemaVersion = 2`.
2. Fresh databases get the new schema directly and `schemaVersion = 2` on creation.

The migration runs before seeding, is idempotent, and has a test that opens a database built from the version-1 schema string, migrates it, and proves rows, sequences and constraints survive. The nightly backup verifier's expected-tables check is unchanged.

## Rollout order

1. Merge and deploy the server first. Older app builds that receive a cadence they do not know drop those chores locally (the converter fails and the seeder retires them); that is invisible on the board and fully reversed the moment the new build runs, because the seeder un-retires on re-apply. Wes's phone is the only paired phone and gets the new build by cable the same day.
2. Bump `data/chores.json` to version 2 in the same server deploy, so `/sync` hands out the new list once.
3. Install the new app build on Wes's phone; Anne's first install is already the new build.

## Tests

Update: `ChoreListTests` (counts, pinned list), `CalendarAndRotationTests` (period 0 at the anchor for six cadences, bounds for the two new ones), `FairnessBalancerTests` (weights), `SeedTests` (39, pinned), `TodayPlannerTests` (the together invariant), `HandoffPlanningTests` (period phrases), server `api.test.js` (39, retire test), `rules.test.js` (anchor, bounds, weights), `pairing.test.js` (39), `data/README.md` and the validator's own numbers.

Add: period index and bounds for bimonthly and quarterly across a year boundary; a seasonal chore not due in March and due in April; together chore emits two items, one completion clears both, credit counts for both, no offer; handoff request on a together chore is refused; server migration from schema 1; the red alert for a together chore reaches both phones once; the kitchen banner lists a together alert once; validator rejects a together chore with an assignee and a season with month 13.

## Docs

`data/README.md` (field table, counts), `scripts/validate-chores.py` header, `Packages/RoostCore/README.md` (periods, weights, "31 chores"), `Roost/README.md` (All chores groups, seed counts), `server/README.md` (chores table, period phrases, migration), `NOTES.md` (the two new cadences and the together rule as decisions), and the `notes` string inside `data/chores.json`.

## Not in this change

- Reminders, the calendar, the new tab bar, Wishlist, project due dates: separate designs.
- Sub-items on a single chore row: the split covers the garbage case with no new concept.
- Per-cadence escalation: a quarterly chore escalates by days late like every other; revisit only if it proves wrong in use.
- Recurring reminders: anything that recurs is a chore, which is why the haircut is one.

## Open questions for Anne

1. The garbage split's third location: the master list says basement, bathroom, kitchen; her later note says basement, bedroom, bathroom. The spec uses the master list until she answers.
2. Mowing months: April through October is the proposal.
3. "Trim Wes's hair" as a chore pinned to Anne every two months: right person, right rhythm?
