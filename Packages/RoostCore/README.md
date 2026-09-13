# RoostCore

Pure-logic Swift package for Roost. No UI, no SwiftData, no networking. The app and the server both stay dumb about scheduling; this package is the one place that decides what is due, for whom, how overdue it is, and how the tallies and streaks read.

## What's in it

- **Models** — `Chore`, `Cadence`, `ChoreCategory`, `Person` (anne, wes), `Completion`. `Chore` decodes straight from `data/chores.json`; `ChoreList.load(from:)` reads the file.
- **HouseholdCalendar** — all day/week/month arithmetic in America/Chicago, weeks start Monday. Every cadence gets an integer period index counted from an anchor Monday (2026-01-05), so both phones compute identical periods.
- **Rotation** — protocol deciding who an unpinned chore belongs to in a period. Pinned chores never consult it.
  - `RoundRobinRotation` (the type default) alternates every period; the starting person comes from a stable FNV-1a hash of the chore id.
  - `FairnessRotation` gives the chore to whoever has done less over the trailing 14 Chicago days, and falls back to round robin when the two are level. **This is the one to ship** — see [Which rotation](#which-rotation).
- **Scheduler** — `plan(on:completions:handoffs:)` returns `[Person: [DueItem]]` (`due(on:completions:)` is the older name for the same call). Each `DueItem` carries the chore, the assignee, the period, `daysOverdue`, and an `EscalationStage`. It takes any `Rotation`, so the app picks.
- **Handoff** — one person offering their turn at a chore to the other for a single period: `{ id, choreId, from, to, periodIndex, cadence, createdAt, state }`, state `pending | accepted | declined | expired`. Accepted outranks the pin and the rotation, for that period only.
- **HandoffRules** — `canOffer(chore, from:on:)`, `offer(...)`, and the `resolve(...)` pair: answer one offer, or sweep the set and expire what is past its period.
- **EscalationStage** — `dueToday` (0 days), `nudge` (1–2), `pointed` (3–4), `alert` (5+). The mockup's copy for each stage lives in the app.
- **Tallies** — `doneThisWeek(asOf:completions:)` and `streak(for:asOf:completions:)`.

## Rules (provisional)

These are defaults so the app can be built. None of them are confirmed by Anne or Wes yet; change them here and everything downstream follows.

- **Periods.** Daily = each Chicago day. Weekly = Monday–Sunday. Biweekly = two of those, counted from the anchor. Monthly = calendar month.
- **Due / overdue.** A chore is complete for a period if any completion falls inside it. The scheduler shows the *oldest* incomplete period on or after `activeFrom` (the day the household started using Roost). `daysOverdue` is 0 while that period is still open, otherwise whole days past its last day. Completing the chore now clears all older missed periods: one nag, not a backlog.
- **Assignment.** Three layers, in order: an accepted handoff for that exact period wins; otherwise the chore's pin; otherwise the rotation. Pinned chores never reach the rotation, and a handoff is the only thing that can move a pinned chore.
- **Fairness load.** Every completion in the trailing 14 Chicago days (today plus the 13 before it) counts for the weight of its chore's cadence. The unpinned chore goes to the lower total; equal totals fall through to round robin, so ties still alternate off the same FNV-1a seed.

  | Cadence | Weight |
  |---------|-------:|
  | daily | 1 |
  | weekly | 3 |
  | biweekly | 5 |
  | monthly | 8 |

  The weights are a guess at effort — cleaning inside the ovens is most of an evening, scooping the litter is two minutes — and so is the 14-day window. Both live in `FairnessWeights.provisional` and `FairnessRotation.windowDays`; change them there and everything downstream follows. A weekly is worth more than two dailies today, and nobody has argued about whether it should be.
- **Handoffs.** Only the person who owes the chore for the current period can offer it, and there can be one open offer (pending or accepted) per chore per period. Accepting moves that one period; declining changes nothing and lets the offerer ask again; the offer dies when the period ends, so the next period reverts to the pin or the rotation. Answering after the period ended expires the offer instead of accepting it.
- **Week tally.** Completions per person from Monday 00:00 to the next Monday 00:00, Chicago.
- **Streak.** Consecutive days on which the person completed every daily chore assigned to them. Today counts once it is fully done; an unfinished today does not break the streak. A day with no dailies assigned counts as complete. Days before `activeFrom` never count.

## Which rotation

Use `FairnessRotation`. Strict alternation is only fair if both people are equally around and equally free every period, and no real week looks like that. Two cases show why:

**A heavy week gets punished.** Round robin does not care what happened yesterday. If Anne clears six things on Saturday because Wes is buried at work, Sunday still hands her every other chore, and the reward for catching up is more chores. Fairness looks back two weeks and points the next chore at whoever has done less, so a heavy day buys a lighter one.

**One person travels.** Wes is gone Monday to Friday and Anne does everything. Round robin splits the following week down the middle as though the week had been even — there is no mechanism that ever pays her back. Fairness carries the gap: when Wes gets home his load is the low one, so unpinned work points at him until the two are level.

Two rough edges, both real, neither solved:

- **The load is a person's, not a chore's.** While Wes is away his load stays at the bottom, so *every* unpinned chore is assigned to him and sits overdue in his column until he is back. Handoffs are the manual release valve; an explicit "away" flag is the real fix, and nobody has needed one yet because nobody has used this for a week.
- **It is a snapshot, not history.** A `FairnessRotation` answers every question from the loads at the `date` it was built with. `Tallies.streak` walks backwards through past days asking the rotation who owed what, so a streak computed off a fairness-backed `Scheduler` reads history with today's loads. Build the streak's `Scheduler` with `RoundRobinRotation`, or accept the smear.

## Tests

```bash
cd Packages/RoostCore
swift build && swift test
```

The tests read the real `data/chores.json` from the repo (31 chores, 2 pinned) via a path computed from `#filePath`, so moving the package or the data file will fail loudly.
