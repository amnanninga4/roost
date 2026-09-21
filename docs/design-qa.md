# Household redesign — build 377

Date: 2026-09-21. Target: the four connected Home, Anne, Matchup, and Shopping concepts approved before implementation.

## Evidence and normalization

The approved PNGs are saved locally under `build/home-flow-2026-09-21/{home,anne,matchup,shopping}.png` (853 × 1844). Native iPhone 17 Pro captures are 1206 × 2622 pixels, representing 402 × 874 points at 3×. Each source and native capture was proportionally resized to a 402-point-wide comparison and placed together in one image under `build/household-qa/`. Full-resolution native captures are committed under `Roost/docs/household-*.png` and displayed in `Roost/README.md`.

The concepts omit the system status bar and depict a custom tab bar. Implementation uses the real iOS status bar, navigation bar/back gesture, and floating tab bar; these consume more vertical space. Comparison therefore judged app content and interaction hierarchy, not identical screen coordinates. Fixture counts and history are real outputs of the offline seeded household, not the illustrative numbers in the concepts. The fixture also deliberately includes unsynced and declined-handoff states.

## Comparison and fixes

| Area | Finding | Fix and post-fix evidence |
| --- | --- | --- |
| Home | System-black background differed from the navy target; summary footer was unnecessarily tall. | Applied the background token and placed weekly context beside the separate Matchup action at normal text size. `household-home-dark.png` shows the corrected surface, profile links, one full-width list, and separate completion controls. |
| Profile | Legacy board chips, category icons, colored titles, and one enclosing card competed with chore names. | Personal view uses separate Overdue/Today cards, neutral titles, amber lateness, left check controls, and retains meaningful handoff notes. `household-profile-dark.png` shows the revised rows and compact Review action. The legacy board keeps its established presentation. |
| Matchup | Small identity marks and completion totals weakened the comparison. | Larger person markers and semantic large-title totals. `household-matchup-dark.png` shows independent profile links, weekly completions, work left, streak explanation, and read-only recent completions. |
| Shopping | Old pill selector and dashed composer did not fit the selected direction. | Underlined text selection and solid composer stroke; native grouped list behavior retained. `household-shopping-dark.png` shows the final treatment, owner markers, bought state, and honest sync metadata. |
| Accessibility | Initials used a fixed font; Home accessibility wrappers obscured individual button identifiers. | Semantic scalable initials and distinct accessible buttons. Largest-text Home capture preserves both names and profile widths; connected navigation and check-off tests pass. |

Full-view comparisons resolved composition and density. At the normalized size, labels, metadata, controls, and borders remained legible; full-resolution native captures were also inspected for the same regions. No image assets or custom illustration require separate asset fidelity review. Flat semantic surfaces and native corner/control geometry intentionally replace the mockups' slight gradients and custom chrome.

## Interaction and appearance checks

- Home → Matchup → Anne → back through both screens; Home → Anne → Matchup → back; Shopping through Lists.
- Completing a Home chore removes its open row; together chores are represented once without changing personal counts.
- Dark and light screenshots reviewed. Explicit saved appearance is preserved; dark applies when no preference exists.
- Largest-text Home switches the people summary to a vertical stack with full-width profile buttons.
- Shopping's Bought controls have a dedicated normal/largest-text sizing and clear-action test. Both labels grew by more than 1.5×, stacked without overlap, and clearing bought items preserved unbought items. The native supplementary-header audit still reports those two nodes as partially unsupported; narrow, named exceptions cite this measured regression test and `household-shopping-largest.png`.

The broader screen pass also reviewed Meals, Projects, Wishlist, More, Settings, and the legacy board. More version and Projects Archive labels passed measured >1.5× largest-text growth checks; exact audit exceptions cite that evidence. Settings now uses its standard native navigation title. Kitchen mode uses uncapped semantic counts and stacked columns at accessibility sizes. Its shared-alert heading is visibly complete across three lines in `household-kitchen-largest.png`; a named clipping-audit exception records this evidence.

Visual comparison final result: passed. No remaining P0/P1/P2 visual discrepancy in the approved native adaptation. Full application tests and CI remain release gates; this document does not establish upload or installation.
