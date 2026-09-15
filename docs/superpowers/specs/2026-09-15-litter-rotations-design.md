# Litter: two rotations and a consequence — design

2026-09-15. Source: Anne's feedback on issue #1 (2026-09-14): "Litter — two separate rotations, don't merge them. Scooping (daily): Anne does Mon/Wed/Fri/Sun (4 days), Wes does Tue/Thu/Sat (3 days). The extra day swaps between us each week, so whoever had 4 days last week has 3 this week and vice versa. Changing (monthly, full litter change): alternates month to month, starting with Wes, then Anne the following month, etc. Consequence rule: if someone misses their scooping day more than 2 times in a given month, they get automatically assigned that month's full litter change instead of whoever was originally scheduled for it." Status: approved by Wes in chat (2026-09-15 07:15), lane 2 of the design round. Lane 1 (due windows) is on main at 0262174 and live on the server.

## What is true today

- An unpinned chore's owner comes from `RoundRobinRotation`: a stable FNV-1a hash of the chore id picks a starting person, then the person alternates every period. `scoop-litter` is daily, so it alternates every day; `change-litter` is monthly, so it alternates every month, and which person it starts with is an accident of the hash.
- Assignment order is: an accepted handoff for that exact period, then `chore.fixedAssignee`, then the rotation. The optional `FairnessBalancer` can move an unpinned, un-handed-off, in-period item, and is switched off in production on both sides.
- Nothing counts misses. A missed period is only visible as `daysOverdue` on the item that is still due, and completing a chore now clears every older missed period (one nag, not a backlog).
- `server/src/rules.js` mirrors all of this for the digest and the red-alert push.

## The change

Three additions, all driven by data in `data/chores.json` (version 5). Nothing in code knows the word "litter": the same keys work for any chore that wants a weekday table, a fixed starting person, or a miss consequence.

### 1. `rotation` on a chore

A chore may carry an optional `rotation` object instead of taking the default hash-and-alternate. Two kinds:

- **`{"kind": "weekdayCycle", "weeks": [[…], […]]}`** — allowed only on a `daily` chore. `weeks` is a list of 1 to 4 week tables; each table is seven entries, Monday first, each `"anne"` or `"wes"`. The table used for a given day is `weeks[weekIndex mod weeks.count]`, where `weekIndex` is the chore's week number from the household anchor (`periodIndex(.weekly, containing: day)`), and the entry used is that day's ISO weekday minus one. Scooping gets two tables, so a week of Anne-heavy alternates with a week of Wes-heavy.
- **`{"kind": "alternate", "start": "wes"}`** — allowed on any cadence. `start` owns every period whose index is even, the other person owns the odd ones. Period indexes count from the fixed household anchor (January 2026 is monthly period 0), so September 2026 is period 8, an even one, and Wes owns September's change with Anne taking October. This is the default rotation with the hash replaced by a stated person. It deliberately does **not** key off `activeFrom`: a rotation that shifted when the household start date was corrected would silently reassign months that had already happened. To flip the order, swap the person in `start`.

A chore with a `rotation` has no `fixedAssignee` (a pin and a rotation would contradict each other), and it is never moved by the fairness balancer even when the balancer is on — an explicit rotation is a decision, not a default to be optimised.

### 2. `missPenalty` on a chore

A chore may carry `{"missPenalty": {"watch": "<chore id>", "overMisses": 2}}`. The rule: within the penalised chore's own period — its calendar period, not its due window, so "this month" means the whole month — count each person's **missed days** on the watched chore; if **exactly one** person is over `overMisses`, that person owes the penalised chore for that period, whoever the rotation named. If both are over, or neither is, the rotation stands.

Both-are-over deliberately does nothing rather than picking whoever is further over. The penalty exists to move a chore onto someone who let the other carry it; when both let it slide there is no fairness claim to act on. "Whoever is further over" also cannot be lived with: the watched chore alternates daily, so the miss lead alternates daily, and the penalised chore would change owner every single day — measured at 26 owner changes in 35 days on the real litter data. Under the stated rule the owner changes only when someone crosses the line.

A **missed day** on a watched chore is a period of that chore which (a) ended before today, (b) began on or after `activeFrom`, (c) was assigned to that person by the watched chore's own rotation or pin (handoffs count: if Wes accepted Tuesday, Tuesday is Wes's to miss), and (d) has no completion inside it by anyone. Today is never a miss until it is over — the same rule streaks use. A partner's cover does not erase the miss: Anne's rule is about the person who owed the day, and a completion by the partner still clears the chore itself, it just does not un-miss the day for the person who owed it.

The count is recomputed every time the due list is built, so the change flips to the misser the moment they cross the line and flips back if a late completion inside the period removes the miss.

### 3. Assignment order

An accepted handoff still wins, then the pin, then the penalty, then the rotation. In full:

1. accepted handoff for that exact chore and period
2. `fixedAssignee`
3. `missPenalty` (only when it names exactly one person for that period)
4. `rotation`: `weekdayCycle`, `alternate`, or the default hash round-robin

Streaks, the escalation ladder, due windows, handoff offers and the digest are untouched: they all read the assignee through this same order.

## The data (`data/chores.json` version 5)

Two chores change; the other 39 rows and every count stay as they are.

```json
{
  "id": "scoop-litter",
  "title": "Scoop litter",
  "cadence": "daily",
  "fixedAssignee": null,
  "category": "cat_care",
  "rotation": {
    "kind": "weekdayCycle",
    "weeks": [
      ["anne", "wes", "anne", "wes", "anne", "wes", "anne"],
      ["wes", "anne", "wes", "anne", "wes", "anne", "wes"]
    ]
  }
}
```

Week 0 (the week of Monday 2026-09-14, weekly period 36, an even index) is Anne on Mon/Wed/Fri/Sun and Wes on Tue/Thu/Sat, exactly Anne's list; week 1 swaps them. `change-litter` keeps its `dueDay` of 25 from lane 1 and gains:

```json
  "rotation": { "kind": "alternate", "start": "wes" },
  "missPenalty": { "watch": "scoop-litter", "overMisses": 2 }
```

September 2026 is monthly period 8, so Wes owns September's change, Anne October's (period 9), Wes November's, absent a penalty.

The validator learns both keys: shape, the allowed kinds, `weeks` of 1–4 tables of exactly seven valid people, `weekdayCycle` only on `daily`, `start` a valid person, `overMisses` an integer 0–30, `watch` an id that exists in the file, no `rotation` on a pinned chore, no `missPenalty` on a chore whose watched chore is itself penalised (no chains). It pins the two chores' rotation and penalty the way it pins the window map, so a silent edit fails loudly.

## Dates that must hold (test fixtures on both sides)

`activeFrom` 2026-09-14, no completions unless stated.

- Scooping: Mon 14 Anne, Tue 15 Wes, Wed 16 Anne, Thu 17 Wes, Fri 18 Anne, Sat 19 Wes, Sun 20 Anne. Mon 21 Wes, Tue 22 Anne, … Sun 27 Wes. Mon 28 Anne again.
- Scooping with an accepted handoff Anne→Wes for Wed 16: Wes owes Wed 16; Thu 17 is still Wes's by the table; Wed 23 is Wes's by the table, unaffected by last week's handoff.
- The change, no misses: September Wes, October Anne, November Wes.
- The change, penalty: with no completions at all, on Sep 25 Anne has missed Mon 14, Wed 16, Fri 18, Sun 20 (4) and Wes Tue 15, Thu 17, Sat 19, Mon 21, Wed 23 (5, since Mon 21 starts the swapped week) — both over 2, Wes has more, so September's change is Wes's, which is also the rotation's answer. Seed completions so only Anne is over: Anne owes the change instead.
- Both at 2 misses exactly: nobody is over, the rotation stands.
- A miss removed by a late completion inside the period flips the assignment back on the next build of the list.
- Today never counts: on Sep 20 with nothing done, Sun 20 is not yet a miss for Anne.
- Every other chore is unchanged: `laundry` is still pinned, `clean-toilet-bowl` still hash-rotates, and the due-window tests from lane 1 still pass as written.

## Out of scope

No UI for any of this in this lane. All chores keeps showing the cadence, the pin chip and the window line; it says nothing about whose turn today is or how many scoops someone missed. Today already shows the person's own rows, which is where the answer is visible. A "3 missed scoops" note on the change row, a per-person turn calendar, and any notification about the penalty are separate design questions if Anne asks for them.

The daily cap and the bonus list (lane 3) will read assignment through the same order and are unaffected.

## Files

Data and validator: `data/chores.json`, `scripts/validate-chores.py`, `data/README.md`. RoostCore: `Models.swift` (`ChoreRotation`, `MissPenalty`, the two `Chore` fields), `Rotation.swift` (`WeekdayCycleRotation`, `AlternateRotation`, and `RoundRobinRotation` staying the default), a new `MissCounter.swift` (pure: watched chore, period, completions, handoffs → misses per person), `Scheduler.swift` (the assignment order), `FairnessBalancer.swift` (skip a chore with an explicit rotation), tests `ChoreListTests`, `CalendarAndRotationTests`, a new `LitterRotationTests`. Server: `db.js` (a `rotation TEXT` and `missPenalty TEXT` column, schema v5, seed, shape), `rules.js` (the mirror: `rotationAssignee` gains the two kinds, `missesFor`, `assigneeFor` order), tests `rules.test.js`, `api.test.js`, `migrate.test.js`. App: `Records.swift`, `Converters.swift`, `SyncAPI.swift`, `SyncClient.swift`, tests `SeedTests`, `SyncTests`. Docs: `Packages/RoostCore/README.md`, `server/README.md`, `NOTES.md`.
