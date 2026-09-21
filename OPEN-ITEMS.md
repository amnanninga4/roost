# Roost — open items

One line per thing that is not done, with who owns it and when it was last moved.
This file outlives any single plan. A per-plan ledger (`.superpowers/sdd/<plan>/progress.md`)
tracks the lane in flight; anything that outlives the lane belongs here instead.

**Read and report this file at the start of every lane**, not when it occurs to someone.
An item that has not moved gets louder, not quieter. Delete an item only when it is done or
explicitly dropped; say which in the commit message.

_Last swept: 2026-09-20 (source and read-only GitHub reconciliation)._

No pull requests were open at this sweep. Appearance (#65), simulator setup (#90),
package CI (#94), and Home work are merged. Home's tab-bar clearance concern was
dropped as misdiagnosed; preserve the measurement in `NOTES.md`.

The cleanup adds a verified empty-room fixture and Home navigation test, pins the
Node runtime used locally and in CI, and covers Shopping composer scaling and
submission at the largest text size. The matching custom-font audit false positive
is narrowly allowed; the remaining accessibility checks still run. See GitHub CI
for validation of the current revision.

## Blocked on Wes

| Item | Since | Why it matters |
|---|---|---|
| Confirm Anne’s installed TestFlight build | 2026-09-21 | Wes confirmed both phones use TestFlight. Apple reports build 376 valid and in beta testing, and the Household group containing Anne and Wes has access. Wes confirmed his phone is on build 376; Anne’s installed build has not been independently verified. Build 377 is the pending release candidate, not a confirmed upload or installed build. |
| Historical Tailscale credential follow-up | 2026-09-14 | September 14 notes reported an invalid `TAILSCALE_API_KEY` and working `fssh`. Neither the credential nor current fleet state was checked in this cleanup; revalidate before acting. |
| peers-fleet decisions | 2026-09-14 | Report `~/claude-reports/peers-fleet-2026-09-14.md`. September 14 follow-ups: ponytail cuts, dashboard LaunchAgent, Kimi bridge, clarsmini push key. That report said the lead had stopped and no sessions were running; current session state was not checked. |

## Waiting on Anne

| Item | Since | Why it matters |
|---|---|---|
| Three questions on issue #1 | 2026-09-13 | Garbage third location; which months mowing runs; whether the hair chore is right as every-two-months pinned to Anne. All 19 issue #1 comments were checked September 20. These questions were asked September 14 and repeated September 15; the latest comment (September 15, 02:13 UTC) still lists all three as open, with no later reply. No explicit confirmation was found in the thread; do not infer approval from shipped chore data. |

## Owned by Fable

| Item | Since | Note |
|---|---|---|
| Match APNs to the confirmed TestFlight route | 2026-09-21 | Wes confirmed both phones use TestFlight; health still reports `sandbox`. The server needs a separately authorized production-environment change and delivery verification. Uploading build 376 did not change server configuration. |
| Handoffs ignore early due windows | 2026-09-15 | Shipped knowingly. `HandoffRules` counts calendar periods, so a chore with a `dueDay` of 1–6 (window opens in the previous month) refuses a handoff until the 1st. Documented in the due-windows spec. |
| Density scorecard test unowned | 2026-09-13 | Flagged in the UX audit, never picked up. |
| This Mac is on Xcode 27.0 / Swift 6.4; CI is on 26.6 | 2026-09-15 | Local green no longer proves CI green. CI is the authority on disagreement. |

## In flight

| Item | State |
|---|---|
| Lanes 3–6, unstarted | daily cap + bonus list; step deadlines + approaching notifications; add-a-chore from the app; Movies & TV watchlist. Retained backlog, not authorized by the cleanup. |

Litter rotations merged as #87, and Home is on main (latest change `ea0c0c2`).
The previously noted litter worktree on another clone has not been inspected or removed.
Fleet-only entries above are retained historical follow-ups, not verified current fleet faults.
