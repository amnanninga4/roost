# Due windows — weekday windows and monthly due days — design

2026-09-14. Source: Anne's feedback on issue #1 after using the app (2026-09-14 evening): weekly chores should be assigned Monday and due by Sunday; "take out all garbages" belongs on Friday or Saturday; "garbage can to street" is Sunday (pickup is Monday); monthly chores all land on the 1st with a one-day deadline and should be spread across the month, with "Change litter" due on the 25th. Status: approved by Wes in chat (2026-09-14 21:57), first lane of the design round. Inventory the design rests on: `~/claude-reports/roost-design-round-dig-kimi-2026-09-14.md`.

## What is true today

- Every cadence has a period (`HouseholdCalendar.periodBounds`): daily = the day, weekly = Monday to Sunday, biweekly = 14 days, monthly/bimonthly/quarterly = whole calendar months from the 1st. A chore is due for its whole period and late from the day after the period's last day (`Scheduler.dueItem`, `daysOverdue`). The server mirrors this in `server/src/rules.js` for the digest and the red-alert push.
- Nothing can say "Sunday" or "the 25th". `garbage-can-to-street-sunday` carries Sunday in its title only; the three `take-out-garbage-*` rows are ordinary weekly rotators; every monthly chore is due from the 1st.
- The only chore-level extensions are `season` and `together`, threaded JSON → validator → RoostCore `Chore` → `ChoreRecord` → both seeders → `rules.js` → `ChoreDTO` → tests. A window follows the same chain.

## The change

A chore may carry one optional due window inside its period. The period, the rotation, pins, handoffs, streaks and the escalation ladder do not change; the window only narrows when the chore is due and moves the day "late" starts.

### Data (`data/chores.json` version 4)

Two new optional keys on a chore:

- `weekdays`: a non-empty array of ISO weekday numbers, Monday = 1 … Sunday = 7, ascending, unique. Allowed only on `weekly`. The window runs from the earliest listed day to the latest listed day of the period's week. `[5, 6]` is Friday–Saturday; `[7]` is Sunday.
- `dueDay`: an integer 1–28. Allowed only on `monthly`, `bimonthly` and `quarterly`, and **required** on those three cadences so nothing bunches on the 1st. The window is the seven days ending on `dueDay` of the **last month** of the period (a quarterly chore for January–March with `dueDay` 28 is due March 22–28).

`daily` and `biweekly` chores take neither key. `weekdays` and `dueDay` never appear together (the cadence rules make that impossible). `season` and `together` combine freely with a window.

The v4 file (41 chores, ten pins, counts unchanged):

| Chore | Window |
|---|---|
| take-out-garbage-basement, -bathroom, -kitchen | weekdays [5, 6] |
| garbage-can-to-street-sunday | weekdays [7] |
| clean-under-cushions | dueDay 5 |
| wash-all-rugs | dueDay 8 |
| trim-wes-hair (bimonthly) | dueDay 10 |
| clean-inside-ovens | dueDay 12 |
| clean-garbage-cans (quarterly) | dueDay 14 |
| wipe-dust-bar-cart | dueDay 15 |
| clean-under-couches | dueDay 19 |
| wipe-down-doors (quarterly) | dueDay 21 |
| clean-medicine-cabinet | dueDay 22 |
| change-litter | dueDay 25 |
| clean-out-fridge-pantry (quarterly, together) | dueDay 28 |

Every other weekly chore stays whole-week. The numbers are data: Anne or Wes edit the file and bump the version; nothing in code knows a specific day.

`scripts/validate-chores.py` learns both keys (types, ranges, cadence rules, `dueDay` required on month-based cadences), pins `EXPECTED_VERSION = 4`, and pins the window map above the same way it pins `EXPECTED_PINNED`, so a silent edit fails loudly. `data/README.md` documents the keys and the table.

### RoostCore

- `Chore` gains `weekdays: [Int]?` and `dueDay: Int?` with decoder defaults of nil, so v1–v3 files still decode. `Chore.hasWindow` is true when either is set.
- `HouseholdCalendar.dueWindow(for chore: Chore, periodIndex:) -> (firstDay: Date, lastDay: Date)`: the period bounds when the chore has no window; for `weekdays`, period first day + (min − 1) days through period first day + (max − 1) days; for `dueDay`, the seven days ending on `dueDay` of the period's last month. One function, one place the arithmetic lives.
- `DueItem` gains `dueFirstDay` and `dueLastDay` (equal to the period bounds when there is no window). `daysOverdue` becomes `max(0, dayIndex(date) − dayIndex(dueLastDay))`. `periodStart`/`periodLastDay` stay for callers that show the period.
- `Scheduler.dueItem` keeps its "oldest incomplete period" rule and adds two window rules. **Never owed**: when the floor period (the one containing `activeFrom`) has a window whose last day is before `activeFrom`'s day, the floor moves to the next period — a window that closed before the household started was never owed, so go-live on the 14th does not show "Clean under cushions" nine days late. **Not yet**: when the oldest incomplete period is the **current** period and `date < dueFirstDay`, the chore is not due yet and the function returns nil. A missed window from an older period is still returned, with `daysOverdue` counted from that period's window end, and completing now still clears the backlog (one nag, not a backlog).
- Nothing else in the package changes semantics: rotation is by period index, `HandoffRules.canOffer` still asks "do you owe the current period" (you can hand off Sunday's can on Tuesday), `FairnessBalancer` and `Tallies` read `daysOverdue` and completions as before, `EscalationStage.stage(daysOverdue:)` is untouched.

### Server

- `CHORES_COLUMNS` gains `weekdays TEXT` (JSON array text) and `dueDay INTEGER`; schema version 4 adds the two columns with `ALTER TABLE` (no rebuild) and `migrate.test.js` covers v3 → v4. `seedChores` upserts both; `shapeChore` returns `weekdays` as an array (or null) and `dueDay` as a number (or null); `/chores` and `/sync` carry them.
- `rules.js` mirrors RoostCore exactly: `dueWindow(chore, cadence, periodIndex)`, `dueFirstDay`/`dueLastDay` on the due item, `daysOverdue` from the window end, the not-yet exclusion in `dueItemFor`. The digest ("N for you today") and the red-alert sweep read `dueItems` and follow without their own changes. `rules.test.js` pins the same calendar cases the Swift tests pin, on the same dates, so the two sides cannot drift.

### App

- `ChoreRecord` gains `weekdays: String?` (JSON text, the `season` pattern) and `dueDay: Int?`; converters, `ChoreSeeder` and `ChoreDTO`/`SyncClient.apply` carry them; v4 rides the existing `choresVersion` path, so both phones refetch on the next sync. A phone on an older build ignores the keys and keeps whole-period behaviour until it is updated.
- Today needs no new chrome: a windowed chore simply appears when its window opens and shows the existing days-late chip once it is late. `TodayPlanner` and `NotificationPlanner` use `Scheduler` and follow.
- All chores (More → All chores, `ChoreListScreen.swift`) shows the window as static copy on the row's meta: "Fri–Sat", "Sun", "by the 5th" — a `WindowCopy.swift` beside `SeasonCopy.swift`, strings beside the season copy in `Strings.swift`; weekday names from the calendar's locale symbols, the ordinal from `NumberFormatter`.
- Widget: reads the due list; no change beyond rebuilding.

### Dates that must hold (test fixtures on both sides)

Anchor week Monday 2026-09-14 (`activeFrom` 2026-09-14), household calendar, no completions unless stated:

- Garbage (`[5, 6]`): Mon 14 – Thu 17 not due; Fri 18 due, `daysOverdue` 0; Sat 19 due, 0; Sun 20 late, 1; Mon 21 the oldest incomplete period is still week 14–20, `daysOverdue` 2 (window end Sat 19); a completion on Sun 20 clears it and Mon 21 – Thu 24 are not due (next window opens Fri 25).
- Can (`[7]`): Mon 14 – Sat 19 not due; Sun 20 due, 0; Mon 21 late, 1.
- Change litter (`dueDay` 25): Sep 1–18 not due; Sep 19 due, 0; Sep 25 due, 0; Sep 26 late, 1; a completion on Sep 20 clears September and Oct 1–18 are not due.
- Trim Wes's hair (bimonthly, `dueDay` 10): period September–October is due Oct 4–10, late from Oct 11.
- Fridge and pantry (quarterly, together, `dueDay` 28): period July–September is due Sep 22–28 for both people; one completion clears both rows.
- Clean under cushions (`dueDay` 5) with `activeFrom` Sep 14: not due at all in September (its window closed on the 5th, before the start); due Sep 29 – Oct 5, late Oct 6. The same rule with `activeFrom` Sunday Sep 13 leaves the three garbage chores (window Sep 11–12) not due until Fri Sep 18.
- A weekly chore with no window (laundry): due Mon 14 – Sun 20, late Mon 21, exactly as today.
- Decoder: a v3 chore object without the keys decodes with both nil; a v4 object round-trips both.

### Out of scope (later lanes)

Litter as two rotations and the misses rule, the daily cap and bonus list, deadlines on project steps, adding a chore from the app, Movies & TV. Each gets its own spec; this one gives them `dueDay` on `change-litter` to build on.

## Files

Data and validator: `data/chores.json`, `scripts/validate-chores.py`, `data/README.md`. RoostCore: `Models.swift` (`Chore`), `HouseholdCalendar.swift` (`dueWindow`), `Scheduler.swift` (`DueItem`, `dueItem`), tests `ChoreListTests`, `CalendarAndRotationTests`, `SchedulerAndTalliesTests`, README. Server: `db.js` (columns, migration v4, seed, shape), `rules.js` (window, due item), tests `rules.test.js`, `api.test.js`, `migrate.test.js`, `push.test.js` (digest fixture dates), README. App: `Records.swift`, `Converters.swift`, `ChoreSeeder.swift`, `SyncAPI.swift`, `SyncClient.swift`, `ChoreListScreen.swift`, `WindowCopy.swift`, `Strings.swift`, tests `SeedTests`, `SyncTests`, `TodayPlannerTests`, `NotificationTests`, plus a UI test on a new `pairedWindows` fixture (the `paired` seed plus one quarterly chore with a due day, completed today so Today never shows it) that All chores renders the window line. Today's absence outside the window is a unit-test claim (`TodayPlannerTests` on fixed dates), not a UI one: the UI fixture runs on the real date.
