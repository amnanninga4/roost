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

**Source of truth for task data:** `chore-master-list.html` (locked Sep 13, 2026). Seed from this list only.

| Cadence   | Count | Notes |
|-----------|------:|-------|
| Daily     | 11    | Includes AM/PM wet food, litter scoop, water, plants, tidy |
| Weekly    | 9     | **Laundry → always Annie**; **garbage to street (Sun) → always Wes** |
| Biweekly  | 5     | Shower, mop floors, rugs, pillows/mattress |
| Monthly   | 6     | Litter change, fridge, ovens, cushions, under couches, bar cart |

Everything else is fair-game split; only those two weekly tasks are pinned.

### Mockup ≠ master list

`roost-app-mockup.html` is **illustrative UX only**. Its sample rows (e.g. “Recycling out”, “Wash dishes”, “Order cat litter”) are **not** in the locked 32-task list. Do **not** seed product data from the mockup.

## Mockup product ideas worth keeping

1. **Head-to-head day streak** (Anne vs Wes) + weekly tally of tasks done.
2. **Bonus / first-to-claim** tasks (`+N pts`); past deadline → auto-assign (purple) so they can’t vanish.
3. **Overdue escalation** (litter-box example): Due today → 1 day → 3 days → 5 days (shared red alert).
4. **Tabs:** Tasks / Shopping / Meals / Projects (projects expand into subtasks).
5. **Cat care** called out as its own section (not buried in chores).

Visual system already has light/dark tokens, Fraunces + IBM Plex Mono, accent / gold / meal / assign / alert colors — good seed for a real design system.

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

1. Seed the **locked 32 chores** (from master list, not mockup) as recurring tasks with cadence + fixed assignees.
2. Two-person lists + check-off + shared “done this week” tally.
3. Cat-care block + simple overdue escalation (no bonuses yet).

Shopping / meals / projects / streak gamification = next slices once the chore loop feels good live.

## How agents should talk here

- **Wes-fleet agents:** claude-peers; orchestrator is `mac-anne-app-003`.
- **Durable + Anne’s Claude:** GitHub Issues — primary bridge is **[#1](https://github.com/amnanninga4/roost/issues/1)**.
- One issue per decision or workstream (not a chat dump in commits).
- Keep secrets out (no keys, Apple Team IDs, passwords).

— Apple Dev 3.0
