# Home screen

## Current direction — 2026-09-20

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
