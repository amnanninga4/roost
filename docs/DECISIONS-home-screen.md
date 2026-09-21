# Home screen

## Current direction — 2026-09-21

Wes approved the connected Sleeper-inspired household direction for implementation and release.

- **Home:** a compact two-person summary, followed by shared, full-width checkable chore rows.
  Both people remain visible without splitting the chore list into narrow columns.
- **Profiles:** each person is tappable and opens their own day of chores.
- **Matchup:** a separate destination for weekly comparison statistics and read-only completion
  activity. Historical activity is not a second place to toggle current chores.
- **Lists:** Shopping, Meals, Projects, and Wishlist remain four sections within Lists.
- **Navigation:** Home, Lists, and More remain the tab shell. The legacy chore board is reachable
  through More; Home is the household front door.
- **Theme:** dark navy backgrounds, slate cards with thin blue-gray borders, native semantic sans
  type, teal actions, mint Anne, pink Wes, and amber overdue metadata. Resting cards are flat.
- **Appearance:** dark when no preference is saved; preserve explicitly selected System, Light,
  or Dark. Light remains a usable pale/slate equivalent, and text retains Dynamic Type support.

The September 20 and September 15 sections below preserve earlier decisions. This direction
supersedes their Home layout and typography choices. Current tokens and typography live in
`Packages/RoostDesign`; the original HTML mockup is historical reference.

## Previous direction — 2026-09-20 (historical)

Wes approved a polish pass after reviewing simulator screenshots. Keep Roost's colors, fonts, and two-person comparison:

- At normal text sizes, show both people side by side with three checkable chore previews each. The remaining count opens that person's day.
- Label the totals as “N left” and overdue chores as “Nd late”.
- At accessibility text sizes, give each person a full-width header directly above their own chores. Names and the YOU badge must remain whole.
- Use the existing secondary-text color for neutral unchecked controls and input prompts; keep decorative dividers quiet.
- Tighten the shared list headers and section spacing without shrinking row tap targets or changing bottom safe-area handling.

The September 15 plan below is historical. Home was implemented and subsequently changed to the side-by-side overview in PR #103.

## Original plan — 2026-09-15

## Changes

- App opens on **Home**, not the chore board.
- Home: date, one line ("5 for you, 4 for Anne"), your chores checkable, Anne's count, four doors.
- **Board keeps both columns**, one tap over. Same tab.
- No new tab.
- Streaks move off the front door.
- Empty lists show no count.
- Over six chores folds to "3 more". Remembers.

## Cost

Both columns aren't on screen the second you open it. One tap instead. Reversible.

## Not this round

Daily cap. Movies & TV. Project deadlines. Notifications.

## Original status

The original spec was in PR #93; the current implementation and direction above supersede this planning snapshot.
