# UI polish — the density diet and the component kit — design

2026-09-14. Source: Wes's read on the current build (chat): it feels cluttered, nothing answers a long-press, and the app feels "light". Status: draft for the team to review before implementation.

This is a feel pass, not a feature pass. The token layer in RoostDesign is finished and the screens follow it; what is missing is the component rung above tokens and restraint in how much each surface shows at once. Everything below keeps the current layout, palette, type ramp and navigation shape. The one functional addition is editing a Shopping or Wishlist row, which the server already supports (`PATCH /shopping/:id` and `PATCH /wishlist/:id` accept a title, and the wishlist route takes `priceCents`); the work is app-side UI over the existing replay-edits sync path.

## The component kit (RoostDesign)

Three pieces, all in `Packages/RoostDesign`, all themed from existing tokens, all with Reduce Motion and Reduce Transparency behaviour matching the package's conventions:

- **`RoostButtonStyle`** — the press vocabulary the README specifies but nothing implements: scale to 0.97 and opacity to 0.85 on touch-down with the `quick` spring, back on release, and a new `RoostHaptic.press` moment (light impact, fired on touch-down only). Applied to every button and tappable row in the app; the hand-rolled press effects in `ChoreRowView`, `HandoffOfferCard` and `ListParts` are deleted in favour of it.
- **`RoostCard`** — one modifier that applies the surface fill, the `card` radius and the `card` elevation together, replacing the per-screen `.background(Role.surface.color, in: RoostRadius.cardShape)` + `.roostElevation(.card, …)` pairs.
- **`RoostAvatar(person:)`** — the person dot/avatar the rows assemble by hand, one component driven by `RoostPerson`'s colours.

The swatchbook gains a section per component so the kit is reviewable in isolation.

## Today: the header

The streak chrome (VS block, AHEAD pill, week bar, both tallies) collapses into a single line under the title: "You 6 — 4 Anne · 12-day streak ›", set in `monoTally` with each person's score in their own colour. Tapping the line (or its chevron) expands the full streak card as it exists today, with the `standard` spring; tapping again collapses it. Collapsed is the default on every launch — the tally is the glance, the card is the reveal. The date eyebrow, the "Today" title and the sync notice line do not move.

The trade-off to name plainly: the head-to-head is Anne's favourite part, and collapsing it hides the week bar by default. The line keeps the score and the streak visible at all times; the bar is one tap away. If review says the VS card should greet people, the expand state can persist in `AppStorage` instead — flagged here so the decision is explicit.

## Today: the chore row

`ChoreRowView` currently stacks a category badge, a title, an escalation subtitle, and a meta line of up to five elements (days-late chip, TOGETHER/name chip, "from X" chip, handoff note, "on the other phone" text), and it tints the whole row by escalation stage. Two changes:

**Meta line cap.** At most two inline elements, chosen by urgency: the days-late chip first, then an active handoff note, then the together/name chip. "From X" is dropped as text — the chip's person colour already says it. "On the other phone" is dropped entirely — the row's not-synced marker carries that meaning.

**Escalation becomes an edge, not a wash.** The full-row stage tint is replaced by a 3-point rounded bar along the row's leading edge in the stage colour; the days-late chip keeps its tinted fill. A bad day still reads at a glance, but the screen is no longer painted wall to wall.

**Long-press answers everywhere.** Every chore row gains a context menu with a preview: the row lifts into a card showing the complete metadata (cadence, who it's for, how late, handoff state) above the actions. Actions: Hand off / Withdraw (as today), plus Show in All chores. This is the gradual-revelation answer to "can't hold down things for more options" — the row shows the day-to-day minimum, the press reveals the rest.

**Swipe.** Trailing swipe on a chore row offers Hand off when the chore is eligible, in the assign colour. No leading swipe — tap already toggles done, and a second done gesture adds nothing.

## Lists: context menus and editing

Shopping and Wishlist rows gain a context menu: Edit and Delete (destructive). Edit presents a small sheet at the medium detent reusing the composer's styling — the title field for Shopping; title and price fields for Wishlist. Saving patches through the existing `ListActions` edit path and syncs like any other edit. Meals already has its menu and Projects already have theirs; neither changes.

The Lists segmented control is rebuilt as a small `RoostSegmentedControl` component: same four segments and symbols, same `AppStorage` persistence, but the selection indicator is a pill that slides between segments via `matchedGeometryEffect` with the `quick` spring. At accessibility text sizes it keeps the symbol-only behaviour the audits already check.

## Motion wiring

Three uses of the motion system that exists but is barely switched on:

- **Stagger.** The rows in each person card on Today stagger in on first appearance, 40 ms per row using the existing `RoostMotion.staggerDelay` (which nothing calls today), capped per the constant. First appearance per launch only — never on scroll, never on re-render.
- **Check-off flourish.** The check circle adds a scale beat — 1.0 → 1.15 → 1.0 on the `quick` spring — alongside the existing symbol replace, strikethrough and sink-down. The success haptic and the daily-gated confetti are unchanged.
- **The sliding pill**, above. Push navigation stays on the system default everywhere.

## What does not change

- No new features beyond list-row editing. No snooze, no skip, no new chore actions — anything needing a model change is out.
- No palette, font, or type-ramp changes. No gradients. Everyday motion stays on the existing `quick`/`standard`/`gentle` springs; `bouncyCelebration` stays gated to the celebration.
- Kitchen mode, the widget, onboarding, the server, and RoostCore are untouched.
- The tab bar is untouched — this design sits on top of the merged new-bar work.

## Tests

App: unit tests for the meta-line ordering (the two-slot urgency pick) and the streak line's tally wording in the existing craft-test style; the Today UI audits updated for the collapsed header, the expand tap, the edge bar and the context menu; the Lists audits updated for `RoostSegmentedControl` (including the AX-size symbol mode); an audit that a Shopping row edits and re-syncs. RoostDesign: value tests for any new tokens (none expected — the kit composes existing tokens) and swatchbook previews per component. The `paired` UI-test fixture needs one chore in a handoff state and one late chore so the menu and edge bar are exercised.

## Docs and screenshots

`Roost/README.md`: the Screens section and the layout listing for the new header, row chrome and menus. `Packages/RoostDesign/README.md`: the component kit section. Screenshots: `today.png` recaptured (collapsed and expanded streak), plus dark variants; `lists.png` recaptured for the new segmented control.

## Not in this change

- Persisting the streak card's expand state (the review flag above may change this).
- Editing chores themselves — the chore list still comes from `chores.json`.
- Reordering Shopping or Wishlist rows.
- Any restructure of the Tasks screen beyond the header and row chrome (the "rooms" direction is a future design if this pass lands well).
