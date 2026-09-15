# Roost — open items

One line per thing that is not done, with who owns it and when it was last moved.
This file outlives any single plan. A per-plan ledger (`.superpowers/sdd/<plan>/progress.md`)
tracks the lane in flight; anything that outlives the lane belongs here instead.

**Read and report this file at the start of every lane**, not when it occurs to someone.
An item that has not moved gets louder, not quieter. Delete an item only when it is done or
explicitly dropped; say which in the commit message.

_Last swept: 2026-09-15 09:25 CDT (Fable)_

## Blocked on Wes

| Item | Since | Why it matters |
|---|---|---|
| APNs key not installed — `/health` reports `push: "no key"` | 2026-09-13 | Every notification path is a no-op in production: morning digest, red alerts, handoff offers, completion pings. Two planned lanes (step deadlines, Movies & TV monthly nudge) are **only** notifications and cannot pay off until this exists. |
| Cable a phone to this Mac, unlock, tap Trust | 2026-09-15 | The app half of due windows (and everything since) is not on either phone. `devicectl` currently sees no physical device at all. |
| Anne's phone has never appeared on this Mac | 2026-09-13 | Separate install session from Wes's. "The phones" has always been one phone. |
| PR #60 — CI: swiftformat --lint fatal | 2026-09-13 | Green. Would have caught the formatting slips hand-patched twice on 2026-09-14. |
| PR #61 — CI: swiftlint whole tree | 2026-09-13 | Green. Carries the swiftlint-config decision. |
| PR #65 — Appearance choice in Settings | 2026-09-14 | Green. Unreviewed. |
| Anne's three questions on issue #1 | 2026-09-13 | Garbage third location; which months mowing runs; whether the hair chore is right as every-two-months pinned to Anne. Asked 09-13, re-asked 09-15 twice. Chore data is not final until these land. |
| `TAILSCALE_API_KEY` in `~/.fleet-secrets/live/integrations.env` is invalid | 2026-09-14 | Needs minting. Nothing currently depends on it; `fssh` works. |
| peers-fleet decisions | 2026-09-14 | Report `~/claude-reports/peers-fleet-2026-09-14.md`. Open: ponytail cuts, dashboard LaunchAgent, Kimi bridge, clarsmini push key. No sessions are running; that lead is stopped, not working. |

## Owned by Fable

| Item | Since | Note |
|---|---|---|
| CI runner sometimes has no iPhone 17 Pro simulator | 2026-09-14 | Seen once: `xcodebuild` found no matching destination on the macos-26 image. Permanent fix is a workflow step that creates the simulator on the newest installed runtime when it is missing. Diagnosed, never ticketed. |
| Handoffs ignore early due windows | 2026-09-15 | Shipped knowingly. `HandoffRules` counts calendar periods, so a chore with a `dueDay` of 1–6 (window opens in the previous month) refuses a handoff until the 1st. Documented in the due-windows spec. |
| Density scorecard test unowned | 2026-09-13 | Flagged in the UX audit, never picked up. |
| This Mac is on Xcode 27.0 / Swift 6.4; CI is on 26.6 | 2026-09-15 | Local green no longer proves CI green. CI is the authority on disagreement. |

## In flight

| Item | State |
|---|---|
| Lane 2 — litter rotations | Spec + plan on `specs/litter-rotations` @ f9a9ffd. Bot delivered Tasks 1–4 on `feat/litter-rotations` @ f833a3b (validator OK v5, RoostCore 76/76, verified here). L-1a perf patch sent. Tasks 5–8 (server, app, docs) queued. |
| Lanes 3–6, unstarted | daily cap + bonus list; step deadlines + approaching notifications; add-a-chore from the app; Movies & TV watchlist. Order is Fable's; 4 and 6 depend on the APNs key above. |
