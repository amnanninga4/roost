# Roost — initial notes (Apple Dev 3.0)

**From:** Apple Dev 3.0 (Wes / Hines Creative)  
**Date:** 2026-09-13  
**Repo state:** concept HTML only (`roost-app-mockup.html`, `chore-master-list.html`), single commit, no issues yet.

## Org

- **Orchestrator:** Anne-app / Aesop on Wes’s M3 (`mac-anne-app-003` on claude-peers)
- **Worker:** Apple Dev 3.0 (this seat) — takes assigned slices; does not drive roost
- Bridge: [issue #1](https://github.com/amnanninga4/roost/issues/1) + peers

## What this is

Shared household app for Anne & Wes: recurring chores + cat care, light competition (streaks / bonus points), shopping, meal ideas, and multi-step projects. Still design-stage — mockup is static HTML (no JS data model).

## What’s already locked in the chore list

Source of truth for recurring tasks: `chore-master-list.html` (locked Sep 13, 2026).

| Cadence   | Count | Notes |
|-----------|------:|-------|
| Daily     | 11    | Includes AM/PM wet food, litter scoop, water, plants, tidy |
| Weekly    | 9     | **Laundry → always Annie**; **garbage to street (Sun) → always Wes** |
| Biweekly  | 5     | Shower, mop floors, rugs, pillows/mattress |
| Monthly   | 6     | Litter change, fridge, ovens, cushions, under couches, bar cart |

Everything else is fair-game split; only those two weekly tasks are pinned.

## Mockup product ideas worth keeping

1. **Head-to-head day streak** (Anne vs Wes) + weekly tally of tasks done.
2. **Bonus / first-to-claim** tasks (`+N pts`); past deadline → auto-assign (purple) so they can’t vanish.
3. **Overdue escalation** (litter-box example): Due today → 1 day → 3 days → 5 days (shared red alert).
4. **Tabs:** Tasks / Shopping / Meals / Projects (projects expand into subtasks).
5. **Cat care** called out as its own section (not buried in chores).

Visual system already has light/dark tokens, Fraunces + IBM Plex Mono, accent / gold / meal / assign / alert colors — good seed for a real design system.

## Gaps / open questions (for Anne’s Claude + humans)

- **Platform:** native iOS/Mac (SwiftUI), shared web (PWA), or both? (I’m the Apple lane — happy to own Swift/signing if we go native.)
- **Auth / sync:** Apple Sign In + CloudKit / private iCloud shared DB vs Firebase / Supabase vs local-first + sync.
- **Two users only?** Assume Anne + Wes forever, or invite model later.
- **Streak rules:** what breaks a streak? midnight CT? any incomplete daily? only assigned-to-me?
- **Auto-assign fairness:** round-robin, least-busy this week, or random?
- **Notifications:** local vs push; who gets the red-alert ping.
- **Naming:** mockup still says “Partner” on one streak side — should be Wes.
- **Data seed:** promote `chore-master-list.html` → real structured data (`chores.json` / Swift models) before UI rewrite.

## Suggested first build slice (proposal)

Don’t boil the ocean. Smallest useful app:

1. Seed the 32 chores as recurring tasks with cadence + fixed assignees.
2. Two-person lists + check-off + shared “done this week” tally.
3. Cat-care block + simple overdue escalation (no bonuses yet).

Shopping / meals / projects / streak gamification = next slices once the chore loop feels good live.

## How agents should talk here

Use **GitHub Issues** on this repo as the shared notepad with Anne’s Claude session:

- One issue per decision or workstream (not a chat dump in commits).
- Tag people/agents in the body; reply in-thread.
- Keep secrets out (no keys, Apple Team IDs, passwords).

Primary bridge issue: see open issues titled for Apple Dev 3.0 ↔ Anne’s Claude.

— Apple Dev 3.0
