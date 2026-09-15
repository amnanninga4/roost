# Home screen — the front door — design

Tab one stops being the chore board. It becomes Home: a place you arrive, that shows your own
work, names the other person, and points at the rest of the house. The two-column board is not
deleted and not demoted to More — it becomes the second segment of the same tab.

Decided with Wes 2026-09-15 from a three-screen mockup (`~/claude-reports/roost-home-mockup/`).
The grounding dig is `~/claude-reports/roost-home-page-dig-2026-09-15.md`.

## What is true today

`RootTabView` has three tabs — Tasks, Lists, More — and opens on Tasks
(`Roost/Sources/Root/RootTabView.swift:8`, `:39`). Tasks is `TodayScreen`: a header, then both
people's columns, always both on screen so nobody can filter the other away
(`Roost/Sources/Screens/TodayScreen.swift:4-5`).

The header is the problem. Measured at default Dynamic Type in the real first-open state
(collapsed), it costs **~190–210 pt** from the nav bar to the first checkable chore title, and
**~360 pt** expanded. The largest single piece is the Anne-vs-Wes streak card
(`StreakHeaderView.swift`), which the household already defaults to collapsed
(`StreakSummaryView` in `StreakHeaderView.swift`) because it is in the way.

So the app does not open onto tasks. It opens onto a third of a screen of scoreboard, and then
tasks. That is the thing Wes was reacting to, and it is a status board — the thing he explicitly
said he did not want.

## The change

### Tab one

`RootTab.tasks` becomes `RootTab.home` (title "Home", symbol `house`). Still first, still the
default, still where a push lands (`RootTabView.swift:69-73` is unchanged in behaviour). **No
fourth tab.** A fourth root tab would make Home read as a promotion and the board as a demotion,
and would spend a tab on a foyer.

Inside that tab, a two-segment control:

- **Home** — arrival. Default.
- **Anne & Wes** — the existing two-column board, unchanged.

Use the existing `RoostSegmentedControl` (`Roost/Sources/Screens/RoostSegmentedControl.swift`),
the same control `ListsScreen` already uses, so the gesture vocabulary matches: a tap and a
horizontal swipe do the same thing (`ListsScreen.swift:2`). Selection persists across launches;
it does **not** reset to Home on foreground, because someone who lives on the board should be
allowed to.

### Home, top to bottom

1. **Date eyebrow.** Unchanged from `TodayHeaderView` — mono, accent, uppercase, and it keeps
   `accessibilityIdentifier("dateEyebrow")`.
2. **One sentence**, in `displayLarge`. `"5 for you, 4 for Anne."` It is the orientation line and
   it replaces the word "Today". See **Voice** below for the full set.
3. **The segmented control.**
4. **Your rows.** This phone's person only, from the same `TodayPlanner` / `ChoreRowView` the
   board uses — genuinely checkable, so the standing-in-the-kitchen tick still happens on the
   first screen. Order is the planner's existing order (most overdue first).
5. **The other person, as one line.** `"Anne still has 4"`, tappable, switches to the
   Anne & Wes segment. Not a second column.
6. **Doors.** Shopping, Meals, Projects, Wishlist. One word each, plus a count when the room has
   anything in it. Never an empty-state sentence.
7. **The sync notice.** Existing `SyncNoticeLine`, unchanged, last.

The streak block and week bar **leave Home**. They move to the Anne & Wes segment, above the
columns, keeping their existing collapsed-by-default behaviour and their `@AppStorage` key. They
are a scoreboard; a scoreboard belongs on the board.

### Collapse and hide — the rule, not a feature

Two behaviours, and they are rules every section on Home obeys. They are not a framework and not
a priority engine.

**Hide.** A section with nothing to say does not render at all. No empty card, no placeholder, no
"nothing here yet" essay. The four lists start empty by design (`CLAUDE.md`: do not seed
shopping, meals, or projects), so on day one a household sees doors with no counts and no other
sections — not four empty boxes. A door is always shown; its count is shown only when > 0.

**Collapse.** A section that would run long collapses to a one-line summary with a tap to open,
and the open/shut state persists. The app already does exactly this once, and that implementation
is the pattern to copy, including the storage key shape:
`@AppStorage("roost.today.streakExpanded")` (`TodayHeaderView.swift:13`). New keys follow
`roost.home.<section>Expanded`.

Only one section on Home needs collapse at launch: **your rows**, when the count exceeds a
threshold. Everything else is one line or four words. Do not build collapse for sections that
cannot be long — that is the overengineering this rule exists to prevent.

Ruling: **the threshold is 6.** Six or fewer rows render in full. More than six render the first
six plus a `"3 more"` line that expands in place. Six is chosen because Anne's brief asks for a
daily cap "around 5" (issue #1), so a normal day is under the threshold and the collapse is the
exception, not the greeting. Revisit when the cap lane lands; the cap and this threshold should
agree, and if they disagree the cap wins.

Expansion is animated with `.animation(_:value:)` bound to the expanded flag — never a bare
`withAnimation` around a state write inside a gesture — and respects Reduce Motion.

### Performance

`TodayScreen` re-renders every 60 seconds under a `TimelineView` so the date line and days-late
counts stay honest (`TodayScreen.swift:8-9`). Home inherits that. Therefore:

- Each Home section is its **own extracted subview**, so a minute tick cannot rebuild the whole
  screen. Extraction is what lets SwiftUI skip a body whose inputs did not change.
- The segment selection lives in `RootNavigation` (already `@Observable`,
  `RootTabView.swift:36`), not in a new environment key. Do not put frequently-changing values
  in the environment: every write to any environment key forces every reader in the subtree to be
  checked.
- Home and the board must not both build a full plan. `TodayPlanner` runs **once** per tick and
  both segments read from that one result. Home filters it to this phone's person; it does not
  re-plan.

### Voice

`Roost/Sources/Strings.swift` only, as always. Plain wording. The app does not greet — it names
the thing. Lines that belong:

- `5 for you, 4 for Anne.`
- `Litter is yours today.`
- `Anne still has 4`
- `All caught up.`
- `Nothing due today`

Lines that are out of bounds regardless of how warm they are: `Good morning, Anne.`,
`Your household at a glance.`, `Welcome back.`, `Let's make today count.` The names are already
on the rows and the date is already the eyebrow; anything on top of that is marketing, and
`Strings.swift` exists so Anne can delete it.

The sentence has a defined value in every state: both clear → `All caught up.`; only this phone
clear → `Nothing left for you. Anne still has 4.`; fresh household before anything is due →
`Nothing due today`.

### Accessibility

- The sentence carries `.isHeader`, replacing the trait currently on "Today"
  (`TodayHeaderView.swift:25`).
- The segmented control is reachable and labelled; the existing
  `Roost/UITests/AccessibilityAuditTests.swift` must cover Home as it covers Today.
- A collapsed section announces its count and its state, not just "3 more".
- Every door is a `Button`, not a tappable `HStack`.
- Tap targets stay at the existing 44 pt minimum.

## What this gives up

Both columns are no longer on screen at arrival. That is an explicit product rule, written into
`TodayScreen.swift:4-5`: both columns always visible so nobody has to switch a filter to see
whether the other person is keeping up.

Accepted knowingly by Wes on 2026-09-15. The rule survives — the board is one tap away in the
same tab, and Home still names the other person's count on every screen. "Is she keeping up?" is
a real question and a less frequent one than "what do I have to do right now."

## Out of scope (later lanes)

- The daily cap and the bonus list. The collapse threshold above anticipates it and defers to it.
- Movies & TV as a fifth door.
- Project step deadlines, and any notification work — the server still reports `push: "no key"`.
- Turning on the fairness balancer, which is built and tested and off
  (`TodayPlanner.swift:85`, `balancer: nil`).
- `tabBarMinimizeBehavior(.onScrollDown)` and other iOS 26 tab chrome. Real, free, and a separate
  decision from this one.

## Files

- `Roost/Sources/Root/RootTabView.swift` — `tasks` → `home`; segment state on `RootNavigation`.
- `Roost/Sources/Screens/HomeScreen.swift` — new; the arrival screen and its sections.
- `Roost/Sources/Screens/TodayScreen.swift` — becomes the board segment; loses the header block.
- `Roost/Sources/Tasks/TodayHeaderView.swift` — the sentence; streak block moves out.
- `Roost/Sources/Screens/StreakHeaderView.swift` — reparented under the board segment.
- `Roost/Sources/Strings.swift` — the sentence, the doors, the collapse line.
- `Roost/UITests/AccessibilityAuditTests.swift`, `Roost/Tests/*` — Home coverage.
