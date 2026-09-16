# Daily cap — owed vs if you have time — design

2026-09-16. Source: Anne's note on issue #1 ("real assigned tasks capped around 5 per person per day… Anything beyond that becomes a per-person bonus list"), decided with Wes in chat the same day. Grounding: Donetick's time-bucketed list (`~/claude-reports/roost-chore-apps-research-2026-09-16.md`) and the Home fold-at-six that was written to wait for this lane (`docs/superpowers/specs/2026-09-15-home-screen-design.md`, `HomeRowsCollapse.threshold`).

This lane is **not** the unused first-to-claim API in `server/src/bonus.js`. That table stays unused. The word "bonus" in Anne's note means optional extras of today's chores, not +N pts tasks.

## What is true today

`TodayPlanner` / `Scheduler.plan` still puts every due chore on a person. Home then draws this phone's rows with `ChoreRowView` and folds them at six (`HomeRowsView.swift`). The board segment draws the same rows in two columns, unfiltered. `Tallies.streak` requires every daily assigned that day. `FairnessBalancer` is built, tested, and off (`TodayPlanner.swift`, `balancer: nil`).

A quiet weekday is already near five before any weekly window opens: each of you has two pinned cat dailies, plus scoop on your days, plus the rotating house dailies. Saturday garbage (`weekdays [5, 6]`) lands on top. The fold-at-six was a disclosure for that pile, not a cap. The Home spec said the cap wins when it lands.

## The change

A day's plan still assigns every due chore to a person. After that, a pure split marks each of that person's due rows **owed** or **extra**. Owed is the cap. Extra is optional: still theirs, still checkable, not nagged, not in the streak.

The split is a property of the plan, not a Home-only filter. Home, the board, the widget, and the morning digest all read it.

### The number

**5.** `DailyCap.limit`. Anne said "around 5"; Home's fold was 6 so a normal day sat under it. Once the cap exists, owed rows do not fold, because five is the list. Extra rows use the old fold rule on themselves: five or fewer extras render in full; more than five render the heading plus `"N more if you have time"`, expanded in place, persisted as `@AppStorage("roost.home.extrasExpanded")` (default `false`).

### What counts

Every due row on that person's board today: dailies, weeklies and monthlies whose window includes today, and overdue. Done-today rows are not candidates; they stay under owed as they do now (after the due rows, uncheckable-to-undo).

### What never becomes extra

A row is **protected**. Protected rows are always owed, even if that makes owed bigger than 5.

- overdue (`daysOverdue > 0`)
- pinned (`fixedAssignee != nil`)
- together (`together == true`)

A behind week of nags fills the cap and then overflows it. That is the point: you do not hide a five-day-late litter scoop to make room for wiping tables. Donetick puts overdue in its own bucket on top; we fold it into owed so the first screen is "what you must do," not a status board plus a list.

### The split

Walk this person's due rows in the planner's existing order (cat care first, then most-overdue first, `TodayBoard.ordered`).

1. Protected rows → owed, in that order.
2. Remaining slots (`max(0, 5 - owed.count)`) fill from the unprotected rows, still in planner order.
3. Everything left → extra.

If protected is already 6, owed is 6 and every unprotected row is extra. The cap yields to trust; it does not yield to fairness. `FairnessBalancer` stays **off**. This lane trims a list, it does not reshuffle who owns what.

The same function, given the same chores / completions / handoffs / date, returns the same split on both phones and on the server. Put it in RoostCore (`DailyCap.split`) and mirror it in `server/src/rules.js`. `TodayPlanner` is a caller, not the authority.

### Streak, digest, notifications

`Tallies.streak` / `isDayComplete` count only **owed dailies** for that day. Extra dailies do not break a streak if they sit. A day whose owed dailies are all done is complete, even if extras remain. Apply this to any day the function is asked about; a shipped cap will make some historical days look complete that previously were not. Accept that. Do not special-case `activeFrom`.

The morning digest lists owed rows. Extra rows do not appear there and do not get the 9am ping. The later notifications lane inherits this; it does not get to re-open it.

Handoffs still work on extra rows from the board (they are still yours). Home still does not offer; offering is a two-column conversation.

### Home

Top to bottom, replacing "your rows" in the Home spec:

1. Date eyebrow — unchanged.
2. Sentence — counts **owed**, not extras, not done-today. `"5 for you, 4 for Anne."` is five owed. Extra work does not inflate the number.
3. Segmented control — unchanged.
4. **Owed.** This phone, checkable `ChoreRowView`, no fold. Handoff swipe stays off (Home is one column). Title colour stays `textPrimary` unless the stage is `alert` (5+ days); the edge bar and the days-late chip still carry the rest of the ladder. The duplicate subtitle that repeats the title is dropped on Home (board rows keep today's meta).
5. **If you have time.** Extra due rows. Hidden when empty. Section title `Strings.Home.ifYouHaveTime`. Rows use secondary title colour, no late paint, no edge bar, still checkable. Five or fewer extras show in full; more than five fold (see The number).
6. Other-person line — their **owed** count. `"Anne still has 4"` means four owed, not four plus extras.
7. Doors — unchanged. Empty rooms still show the word and no dash.
8. Sync notice — last, unchanged.

Done-today rows stay under owed, after the due owed rows, as today.

The old `"N more"` fold on the mixed list is deleted. `HomeRowsCollapse.threshold` becomes `DailyCap.limit` or goes away.

### Board

Each column is owed, then extras. Same visual rules as Home (extras quieter, no late paint). The streak card stays above the columns, unchanged. A column that has extras and no owed still shows the extras section; it does not pretend the person is clear.

### Widget

Owed only. The small widget is a count; the medium widget is the first owed titles. Extras do not appear.

## Voice

`Strings.swift` only. The app does not greet, and it does not say "bonus."

- `If you have time` — section title for extras.
- `3 more if you have time` — the extras fold, if it shows.
- Sentence, other-person line, all-caught, nothing-due: unchanged strings, new counts (owed).

Out of bounds: `Bonus`, `Optional chores`, `Stretch goals`, `Nice to have`, `You're crushing it`.

## Accessibility

- Owed list is the main content. Extra section is a heading plus rows; collapsed it announces the count and that it is collapsed.
- Checking off an extra does not move VoiceOver focus to owed.
- Existing Home audit covers both sections (`accessibilityIdentifier("home.owed")`, `home.extras`, `home.extras.more`).

## What this gives up

The board is no longer "everything due, equal weight." That is the product. Someone who wants the old wall uses the extras section, or waits; we do not add a "show all as owed" toggle.

Extra work can sit undone forever. It does not escalate. A weekly that was extra on Saturday is a new period next week and comes back through the split again. We do not carry extras as a backlog.

## Out of scope

- Wiring `server/src/bonus.js` / first-to-claim / points. Separate, if ever.
- Turning on `FairnessBalancer`.
- Add-a-chore, step deadlines, Movies & TV.
- Donetick's adaptive dates, NFC, completion-window lock, kitchen impersonation.
- Changing `chores.json`. The cap is a rule over the existing list.

## Tests

RoostCore, no simulator:

- Protected overdue / pin / together never extra, even when owed would exceed 5.
- Unprotected fill remaining slots in planner order; cat-care unprotected beats a later household row.
- Together counts toward both people's 5.
- A Saturday with three garbage rows + pins: garbage is owed if it fits, extra if protected already filled the 5.
- Streak: owed dailies all done, extras sitting → day complete. One owed daily undone → not complete.
- Same inputs → same split (determinism).

App:

- `HomeSummary` sentence and `otherCount` use owed.
- Home renders extras only when non-empty; fold default collapsed.
- Board columns show both groups.
- Widget medium lists owed titles only.
- `paired` UI-test fixture: Home's first checkable rows are owed; extras, if any, sit under `home.extras`.

Server:

- `rules.js` split matches RoostCore on a handful of Chicago dates (the same differential style that already guards due windows).
- Digest payload includes owed, omits extra.

## Files

- `Packages/RoostCore/Sources/RoostCore/DailyCap.swift` — `limit`, `split`, protected rule. Tests `DailyCapTests.swift`. Streak walks owed dailies (`Tallies.swift`).
- `server/src/rules.js` — the mirror; digest uses it. Tests `rules.test.js`.
- `Roost/Sources/Models/TodayPlanner.swift` — plan carries owed/extra per person.
- `Roost/Sources/Models/HomeSummary.swift` — sentence and other-count from owed.
- `Roost/Sources/Home/HomeRowsView.swift` — owed list; extras section. `HomeRowsCollapse` follows the cap or dies.
- `Roost/Sources/Screens/TodayScreen.swift` / column views — same two groups.
- `Roost/Widget/TodayWidgetView.swift` — owed only.
- `Roost/Sources/Strings.swift` — extras copy.
- `Packages/RoostCore/README.md`, `NOTES.md`, Home spec's fold ruling is superseded here.

Do not copy Donetick or Vikunja source (AGPL). The buckets are the idea; the split is ours.
