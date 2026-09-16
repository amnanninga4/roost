# Home list grouping — design

2026-09-16. Anne asked for a lighter day (issue #1: around five assigned, the rest optional). Wes: do the UI, not the scheduler. Limits, streak, digest, and a hard cap of 5 are later.

Grounding: Donetick's list (`~/claude-reports/roost-chore-apps-research-2026-09-16.md`) and the Home screen as shipped (`docs/superpowers/specs/2026-09-15-home-screen-design.md`).

This is not `server/src/bonus.js`. That table stays unused.

## What is true today

Home draws this phone's due rows as one stack of `ChoreRowView`, folded at six. Every row has the same weight: title colour from the escalation stage, days-late chip, edge bar, and often a subtitle that repeats the title. The board is the same rows in two columns. Assignment, streak, widget, and digest already work. Leave them.

## The change

Group the existing rows. Do not reassign them.

### Home

Keep the date, the sentence, the segment control, the other-person line, the doors, the sync notice.

Replace the single folded stack with Donetick-style buckets, from the rows `TodayPlanner` already ordered:

1. **Overdue** — `daysOverdue > 0`
2. **Today** — due, not overdue
3. **If you have time** — the rest of this phone's due rows that are still in a later window (tomorrow, later this week). Hidden when empty.

Each bucket is a heading plus rows. Empty buckets do not render. The old `"N more"` fold on the mixed list goes away; a bucket with many rows can fold on its own the way the streak block already does (`@AppStorage("roost.home.<bucket>Expanded")`).

**Today** keeps today's `ChoreRowView` (checkable, edge bar, chip). Drop the subtitle when it is the same words as the title.

**Overdue** keeps the chip and the edge bar so late is still obvious. Title stays `textPrimary` unless the stage is `alert` (5+ days). No more a wall of red titles.

**If you have time** is quieter: secondary title colour, no edge bar, no late paint, still checkable. Heading: `Strings.Home.ifYouHaveTime`.

Done-today rows stay under Today, after the due ones, as now.

Handoff swipe stays off on Home. Sentence and "Anne still has 4" keep counting every due row. Do not invent an owed-count until a later lane actually caps anything.

### Board

Same three buckets inside each column. Streak card stays above. Widget unchanged.

## Voice

`Strings.swift` only. No greetings, and do not say "bonus."

- `Overdue`
- `Today`
- `If you have time`

Out of bounds: `Bonus`, `Optional chores`, `Stretch goals`.

## Out of scope

Anything that changes who owes a chore, whether a day counts for a streak, what the digest pings, or a numeric cap. `FairnessBalancer` stays off. `chores.json` is untouched. Add-a-chore, step deadlines, Movies & TV are other lanes.

## Tests

No RoostCore tests. This is grouping of `TodayRow`.

- Home shows overdue / today / later from a fixture that has one of each; empty buckets omitted.
- A row whose subtitle equals its title does not print the subtitle on Home.
- Overdue titles are not the danger colour unless 5+ days late.
- "If you have time" rows are checkable and do not draw the edge bar.
- Accessibility audit still covers Home. Identifiers: `home.overdue`, `home.today`, `home.later`.

## Files

- `Roost/Sources/Home/HomeRowsView.swift` — buckets instead of one fold.
- `Roost/Sources/Tasks/ChoreRowView.swift` — a quiet style for later rows; skip duplicate subtitle.
- Column views on the board — same buckets.
- `Roost/Sources/Strings.swift` — the three headings.
- `Roost/UITests/HomeScreenUITests.swift` / the Home audit.

Do not add `DailyCap.swift`. Do not touch `Tallies`, `rules.js`, or the widget in this lane.
