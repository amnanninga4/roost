# Roost — initial notes (Apple Dev 3.0)

**From:** Apple Dev 3.0 (Wes / Hines Creative)  
**Date:** 2026-09-13  
**Repo state:** concept HTML + this notes file; see commits on `main`.

## Org

- **Orchestrator (Wes fleet):** anne-app seat on Wes’s M3 — peers id `mac-anne-app-003` (Aesop / Fable; Wes’s Claude on `~/hines/projects/anne-app`). Assigns work to workers over **claude-peers**.
- **Worker:** Apple Dev 3.0 / peers id `grok_bot_app_dev3` — takes assigned slices; does not drive the project.
- **Anne’s personal Claude:** **not on peers.** She watches through **GitHub repo comments/issues only** → [issue #1](https://github.com/amnanninga4/roost/issues/1). Do not expect her on the peer bus.
- **Buses:** peers = Wes-fleet agent chat. GitHub = Anne-facing + durable human thread.

## What this is

Shared household app for Anne & Wes: recurring chores + cat care, light competition (streaks / bonus points), shopping, meal ideas, and multi-step projects. Still design-stage — mockup is static HTML (no JS data model).

## What’s already locked in the chore list

**2026-09-13, Anne + Wes:** six more chores, one replaced, one split; two new cadences (every two months, every three months, month-based like monthly); a seasonal pause (`season.months`); together chores (`together: true`, both boards, one check-off, credit for both, no handoffs). Spec: docs/superpowers/specs/2026-09-13-chores-update-design.md.

**2026-09-14 — Due windows:** weekdays on weekly chores, a dueDay on every month-based chore (window = 7 days ending on it, in the period's last month); never-owed and not-yet rules; overdue counts from the window end. Spec docs/superpowers/specs/2026-09-14-due-windows-design.md.

**2026-09-15 — Litter:** scoop-litter takes a two-week weekdayCycle (Anne 4 / Wes 3, swapping); change-litter alternates from Wes and the miss penalty fires only when exactly one person missed more than two scoop days that month (both over or neither → rotation stands). Assignment order is accepted handoff, pin, miss penalty, rotation. Spec docs/superpowers/specs/2026-09-15-litter-rotations-design.md.

**Source of truth for task data:** `chore-master-list.html` (locked Sep 13, 2026). Seed from this list only.

| Cadence   | Count | Notes |
|-----------|------:|-------|
| Daily     | 11    | Includes AM/PM wet food, litter scoop, water, plants, tidy |
| Weekly    | 9     | **Laundry → always Annie**; **garbage to street (Sun) → always Wes** |
| Biweekly  | 5     | Shower, mop floors, rugs, pillows/mattress |
| Monthly   | 6     | Litter change, fridge, ovens, cushions, under couches, bar cart |

Everything else is fair-game split; only those two weekly tasks are pinned.

### Mockup ≠ master list

`roost-app-mockup.html` is **illustrative UX only**. Its sample rows (e.g. “Recycling out”, “Wash dishes”, “Order cat litter”) are **not** in the locked 31-task list. Do **not** seed product data from the mockup.

## Mockup product ideas worth keeping

1. **Head-to-head day streak** (Anne vs Wes) + weekly tally of tasks done.
2. **Bonus / first-to-claim** tasks (`+N pts`); past deadline → auto-assign (purple) so they can’t vanish.
3. **Overdue escalation** (litter-box example): Due today → 1 day → 3 days → 5 days (shared red alert).
4. **Tabs:** Tasks / Lists (Shopping · Meals · Projects · Wishlist) / More. Calendar slots in second when the reminders design ships. (Decided 2026-09-13; spec in docs/superpowers/specs/2026-09-13-new-bar-lists-design.md.)
   **Projects (2026-09-13):** a due day per project and an owner per step, from Anne's issue #1 notes; the morning-of reminder is local to the phone until the reminders design moves it to the server.
   **UI polish (2026-09-14):** the component kit (RoostButtonStyle / RoostCard / RoostAvatar, plus the press haptic) and the density diet — collapsed streak line, two-slot chore meta, the escalation edge bar, row menus and a Hand-off swipe, the sliding Lists pill, and Edit on Shopping/Wishlist rows. The streak card's expand state persists at `@AppStorage("roost.today.streakExpanded")` (default collapsed; `paired` UI-test launch clears the key).
5. **Cat care** called out as its own section (not buried in chores).

Visual system already has light/dark tokens, Fraunces + IBM Plex Mono, accent / gold / meal / assign / alert colors — good seed for a real design system.

## The iOS 26 floating tab bar does not need a clearance constant (measured 2026-09-16)

A scrolling screen inside the tab bar needs **no** bottom clearance of its own, and a
`RoostSpacing.tabBarClearance` was proposed and rejected on measurement. On an iPhone 17 Pro at
OS 26.3.1, read from a `GeometryReader` in the tab's content: the bottom safe-area inset is **83 pt**
— the 49-pt glass bar plus the 34-pt home indicator, the exact band `XCUIElement` reports for the tab
bar, `(0, 791, 402, 83)` in an 874-pt window. The `ScrollView` inside `HomeTabScreen`'s `VStack`
receives that 83 pt and insets its scroll content by it. So `.padding(.bottom, RoostSpacing.xxl)` is
32 pt of breathing room **on top of** the bar, not instead of it: at rest Home's last section stops
32 pt above the bar's top edge, measured. Adding 96 pt on top would have parked 179 pt of dead air
under the last row.

What was mistaken for the bug is content passing under the glass **during** a flick, which is iOS 26
drawing content under the bar deliberately and is not changed by any amount of padding. The audit that
was believed to fail on this state (`testHomeScrolledToTheDoorsAudit`) passes and is now in the suite.

## Gaps / open questions (Wes + Anne)

**Decided by Wes, 2026-09-13:** native iOS, SwiftUI. Wes has an Apple Developer account. Web/PWA is off the table.

**Sync:** not CloudKit by default. Both phones can go on Wes's Tailscale, so the leading option is a self-hosted sync API on the fleet reached over the tailnet, with the app offline-first (local store, queued writes). Push for overdue escalation goes through APNs. Final call pending on issue #1.

**Distribution while building:** TestFlight to Anne's and Wes's phones. Apple Dev 3.0 owns signing. No Team ID, certs, or provisioning material in this repo.

Other open items:

- **Sync transport:** confirm tailnet self-hosted vs CloudKit; name the fleet host.
- **Two users only?** Assume Anne + Wes forever, or invite model later.
- **Streak rules:** what breaks a streak? midnight CT? any incomplete daily? only assigned-to-me?
- **Auto-assign fairness:** round-robin, least-busy this week, or random?
- **Notifications:** local vs push; who gets the red-alert ping.
- **Naming:** mockup still says “Partner” on one streak side — should be Wes.
- **Data seed:** promote `chore-master-list.html` → structured data (`chores.json` / app models) before UI rewrite.

## Suggested first build slice (proposal)

Don’t boil the ocean. Smallest useful app:

1. Seed the **locked 31 chores** (from master list, not mockup) as recurring tasks with cadence + fixed assignees.
2. Two-person lists + check-off + shared “done this week” tally.
3. Cat-care block + simple overdue escalation (no bonuses yet).

Shopping / meals / projects / streak gamification = next slices once the chore loop feels good live.

## How agents should talk here

- **Wes-fleet agents:** claude-peers; orchestrator is `mac-anne-app-003`.
- **Durable + Anne’s Claude:** GitHub Issues — primary bridge is **[#1](https://github.com/amnanninga4/roost/issues/1)**.
- One issue per decision or workstream (not a chat dump in commits).
- Keep secrets out (no keys, Apple Team IDs, passwords).

— Apple Dev 3.0
