# RoostCore

Pure-logic Swift package for Roost. No UI, no SwiftData, no networking. The app and the server both stay dumb about scheduling; this package is the one place that decides what is due, for whom, how overdue it is, and how the tallies and streaks read.

## What's in it

- **Models** — `Chore`, `Cadence`, `ChoreCategory`, `Person` (anne, wes), `Completion`. `Chore` decodes straight from `data/chores.json`; `ChoreList.load(from:)` reads the file.
- **HouseholdCalendar** — all day/week/month arithmetic in America/Chicago, weeks start Monday. Every cadence gets an integer period index counted from an anchor Monday (2026-01-05), so both phones compute identical periods.
- **Rotation** — protocol deciding who an unpinned chore belongs to in a period. `RoundRobinRotation` (default) alternates every period; the starting person comes from a stable FNV-1a hash of the chore id. Pinned chores never consult it.
- **Scheduler** — `due(on:completions:)` returns `[Person: [DueItem]]`. Each `DueItem` carries the chore, the assignee, the period, `daysOverdue`, and an `EscalationStage`.
- **EscalationStage** — `dueToday` (0 days), `nudge` (1–2), `pointed` (3–4), `alert` (5+). The mockup's copy for each stage lives in the app.
- **Tallies** — `doneThisWeek(asOf:completions:)` and `streak(for:asOf:completions:)`.

## Rules (provisional)

These are defaults so the app can be built. None of them are confirmed by Anne or Wes yet; change them here and everything downstream follows.

- **Periods.** Daily = each Chicago day. Weekly = Monday–Sunday. Biweekly = two of those, counted from the anchor. Monthly = calendar month.
- **Due / overdue.** A chore is complete for a period if any completion falls inside it. The scheduler shows the *oldest* incomplete period on or after `activeFrom` (the day the household started using Roost). `daysOverdue` is 0 while that period is still open, otherwise whole days past its last day. Completing the chore now clears all older missed periods: one nag, not a backlog.
- **Assignment.** Pinned chores go to their person, always. Unpinned chores alternate per period via `RoundRobinRotation`.
- **Week tally.** Completions per person from Monday 00:00 to the next Monday 00:00, Chicago.
- **Streak.** Consecutive days on which the person completed every daily chore assigned to them. Today counts once it is fully done; an unfinished today does not break the streak. A day with no dailies assigned counts as complete. Days before `activeFrom` never count.

## Tests

```bash
cd Packages/RoostCore
swift build && swift test
```

The tests read the real `data/chores.json` from the repo (31 chores, 2 pinned) via a path computed from `#filePath`, so moving the package or the data file will fail loudly.
