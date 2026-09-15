# RoostCore

Pure-logic Swift package for Roost. No UI, no SwiftData, no networking. The app and the server both stay dumb about scheduling; this package is the one place that decides what is due, for whom, how overdue it is, and how the tallies and streaks read.

## What's in it

- **Models** — `Chore`, `Cadence`, `ChoreCategory`, `Person` (anne, wes), `Completion`, `Season`, `ChoreRotation`, `MissPenalty`. `Chore` carries optional `season`, `together`, `weekdays`, `dueDay`, `rotation`, and `missPenalty` (all default when absent) and decodes straight from `data/chores.json`; `ChoreList.load(from:)` reads the file. `Chore.hasWindow` is true when either window key is set.
- **HouseholdCalendar** — all day/week/month arithmetic in America/Chicago, weeks start Monday. Every cadence gets an integer period index counted from an anchor Monday (2026-01-05), so both phones compute identical periods. `dueWindow(for:periodIndex:)` returns the days a chore is actually due inside a period.
- **Rotation** — protocol deciding who an unpinned chore belongs to in a period. `RoundRobinRotation` (the default) alternates every period; the starting person comes from a stable FNV-1a hash of the chore id. Pinned chores never consult it. A chore may also carry its own `ChoreRotation` (`weekdayCycle` / `alternate`).
- **MissCounter** — pure: watched chore + calendar bounds + completions + handoffs → misses per person, and `penalised(_:overMisses:)` picks who a miss penalty moves the chore to.
- **Scheduler** — `plan(on:completions:handoffs:)` returns `[Person: [DueItem]]` (`due(on:completions:)` is the older name for the same call); `dueItems(for:…)` is the per-chore answer (`dueItem` is the one-row view). A together chore is one row per person. Each `DueItem` carries the chore, the assignee, the period, `dueFirstDay`/`dueLastDay`, `daysOverdue`, and an `EscalationStage`.
- **FairnessBalancer** — optional pass inside `plan`, off unless you hand one to `Scheduler(balancer:)`. It spreads a period's *reassignable* work across the two of them instead of deciding chore by chore — see [How balancing works](#how-balancing-works). `FairnessWeights` is what a chore counts for.
- **Handoff** — one person offering their turn at a chore to the other for a single period: `{ id, choreId, from, to, periodIndex, cadence, createdAt, state }`, state `pending | accepted | declined | expired`. Accepted outranks the pin and the rotation, for that period only — but for that period permanently, since only a pending offer expires.
- **HandoffRules** — `canOffer(chore, from:on:)`, `offer(...)`, and the `resolve(...)` pair: answer one offer, or sweep the set and expire the offers nobody answered.
- **EscalationStage** — `dueToday` (0 days), `nudge` (1–2), `pointed` (3–4), `alert` (5+). The mockup's copy for each stage lives in the app.
- **Tallies** — `doneThisWeek(asOf:completions:)` and `streak(for:asOf:completions:handoffs:)`.

## Rules (provisional)

These are defaults so the app can be built. None of them are confirmed by Anne or Wes yet; change them here and everything downstream follows.

- **Periods.** Daily = each Chicago day. Weekly = Monday–Sunday. Biweekly = two of those, counted from the anchor. Monthly = calendar month. Bimonthly = two calendar months, quarterly = three, both counted from January 2026 (Jan–Feb, Mar–Apr, …; Jan–Mar, Apr–Jun, …).
- **Due / overdue.** A chore is complete for a period if any completion falls inside it. The scheduler shows the *oldest* incomplete period on or after `activeFrom` (the day the household started using Roost). `daysOverdue` is 0 while the window (or period) is still open, otherwise whole days past `dueLastDay`. Completing the chore now clears all older missed periods: one nag, not a backlog.
- **Due windows.** Optional `weekdays` (weekly only: ISO Mon=1…Sun=7; window = earliest…latest day of the period's week) and `dueDay` (monthly/bimonthly/quarterly: 1…28; window = the seven days ending on that day of the period's last month). Two rules on top of the oldest-incomplete logic: **never owed** — if the floor period's window closed before `activeFrom`, the floor moves to the next period; **not yet** — if the oldest incomplete period is the current one and today is before `dueFirstDay`, the chore is not due yet. Unwindowed chores keep whole-period behaviour (`dueFirstDay`/`dueLastDay` equal the period bounds).
- **Season.** A chore with a `season` is due only in periods whose first day falls in one of its months; outside the season it is neither due nor overdue, and the season's first period is the floor, so last year's misses do not carry into spring.
- **Together.** A together chore is owed by both people at once: two rows (one per person), one completion clears both, credit for both, no handoffs, and not balanced or weighed.
- **Assignment.** Four layers, in order: an accepted handoff for that exact period wins; otherwise the chore's pin; otherwise a `missPenalty` (when it names exactly one person for that period); otherwise the chore's own `rotation` (`weekdayCycle` or `alternate`), else the default hash round-robin. Pinned chores never reach the rotation. With a balancer, a further step runs over the finished list: see below. The pure `assignee(for:periodIndex:)` cannot see a penalty (no completions, no clock).
- **Rotations and penalties.** A chore may state a `weekdayCycle` (daily only: 1–4 Monday-first week tables; day index from the household Monday anchor picks the week and weekday) or an `alternate` (`start` owns every even period index). A `missPenalty` watches another chore over this chore's **calendar** period: a missed day ended before today, started on or after `activeFrom`, was owed by that person (handoff → pin → rotation), and has no completion by anyone. Exactly one person over `overMisses` owes the penalised chore; both over → more misses; tie or neither → the rotation stands. An explicit rotation or miss penalty is never moved by `FairnessBalancer`.
- **Balancing weights.** A chore counts for the weight of its cadence, and the load that matters is the trailing 14 Chicago days (today plus the 13 before it).

  | Cadence | Weight |
  |---------|-------:|
  | daily | 1 |
  | weekly | 3 |
  | biweekly | 5 |
  | monthly | 8 |
  | bimonthly | 10 |
  | quarterly | 13 |

  The weights are a guess at effort — cleaning inside the ovens is most of an evening, scooping the litter is two minutes — and so is the 14-day window. Both live in `FairnessWeights.provisional` and `FairnessBalancer.windowDays`; change them there and everything downstream follows. A weekly is worth more than two dailies today, and nobody has argued about whether it should be.
- **Handoffs.** Only the person who owes the chore for the current period can offer it, and there can be one open offer (pending or accepted) per chore per period. Accepting moves that one period, and it moves it permanently: **an accepted handoff never expires.** The next period reverts to the pin or the rotation because it is a different period, not because the handoff died — and anything that reads the past still gets the right answer, so a streak knows the chore was not the offerer's that day and an overdue item from a handed-off period stays with the person who took it. Declining changes nothing and lets the offerer ask again. Only a pending offer expires, when its period ends, and that is all `resolve(on:)` sweeps; answering after the period ended expires the offer instead of accepting it.
- **Week tally.** Completions per person from Monday 00:00 to the next Monday 00:00, Chicago.
- **Streak.** Consecutive days on which the person completed every daily chore assigned to them. Today counts once it is fully done; an unfinished today does not break the streak. A day with no dailies assigned counts as complete. Days before `activeFrom` never count. Who a daily was assigned to on a past day follows the handoff accepted for that day, which never expires, so giving a daily away moves it out of the offerer's streak and into the receiver's for that day alone, and a sweep does not change the number — the balancer never enters it (see below).

## How balancing works

Strict alternation is only fair if both of them are equally around and equally free every period, and no real week looks like that. Two cases show why:

**A heavy week gets punished.** Round robin does not care what happened yesterday. If Anne clears six things on Saturday because Wes is buried at work, Sunday still hands her every other chore, and the reward for catching up is more chores.

**One person travels.** Wes is gone Monday to Friday and Anne does everything. Round robin splits the following week down the middle as though the week had been even — nothing ever pays her back.

The fix is not a different way to pick one chore's person. It is a pass over the whole period's list, because "fair" is a property of the list, not of any single chore. `Scheduler.plan` builds the day the usual way — handoff, then pin, then rotation — and then, if it has a balancer, walks the **master chore list in order** (`chores`, identical on both phones) and hands each reassignable item to whoever is carrying less so far.

An item is reassignable only if all three hold: it is **unpinned**, **no accepted handoff** covers it, and it is **still inside its own period** (`daysOverdue == 0`). Everything else keeps the person it already had. Overdue items in particular are never moved — that person was already told it was theirs, and probably notified about it, and shuffling a nag between columns is how an app loses trust.

Each of them starts the walk carrying a **background load**: weighted completions over the trailing 14 Chicago days, *minus* whatever they did inside a chore's current period. Current-period work is not lost — it is counted at that chore's own slot in the walk instead, for whoever actually did it. The totals come out the same; only the position changes. That is what makes the pass **stable**: finishing something turns it from a chosen item into a fixed one at the same position with the same weight, so every other item on the list keeps its person. Without it, checking one thing off at lunchtime would reshuffle the rest of the day — which is exactly what the first attempt at this did.

A level tie is the rotation's call, so two equally-loaded people still alternate off the FNV-1a seed rather than always starting with the same person.

Worked example. Anne is on 4 (she did all four dailies yesterday), Wes on 0, and he has one overdue chore of his own:

| Slot | Chore | Owner | Why | Anne | Wes |
|------|-------|-------|-----|-----:|----:|
| — | background | — | last 14 days, current period excluded | 4 | 0 |
| 1 | his overdue daily | Wes | overdue, never moved | 4 | 1 |
| 2 | scoop litter | Wes | he is carrying less | 4 | 2 |
| 3 | wipe tables | Wes | still less | 4 | 3 |
| 4 | wash dishes | Wes | still less | 4 | 4 |
| 5 | water plants | rotation | level, so the rotation decides | — | — |

What it still does not do, all of it deliberate:

- **Nobody is marked away.** A person who is simply absent stops getting new work once their overdue pile outweighs the other person's load, which is the useful half of an away flag without the flag. The other half — not nagging them for the days they were gone — is not built.
- **A big chore can overshoot.** Weights are coarse, so handing out one monthly (8) can leave a day lopsided until later periods even it out. Nobody has watched this happen yet.
- **`plan` only.** `assignee(for:periodIndex:)` and `dueItem(...)` answer for one chore and cannot balance a list they cannot see, so `Tallies.streak` and anything else walking history get the unbalanced answer — handoff, then pin, then rotation. That is intentional: rewriting who owed what last Tuesday would rewrite the streaks too.
- **Off by default.** `Scheduler(balancer:)` is nil unless a caller passes one, so switching the app over is a deliberate, separate change.

## Tests

```bash
cd Packages/RoostCore
swift build && swift test
```

The tests read the real `data/chores.json` from the repo (41 chores, 10 pinned, 15 windows) via a path computed from `#filePath`, so moving the package or the data file will fail loudly. RoostCore currently runs 64 tests.
