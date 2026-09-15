# Roost — open items

One line per thing that is not done, with who owns it and when it was last moved.
This file outlives any single plan. A per-plan ledger (`.superpowers/sdd/<plan>/progress.md`)
tracks the lane in flight; anything that outlives the lane belongs here instead.

**Read and report this file at the start of every lane**, not when it occurs to someone.
An item that has not moved gets louder, not quieter. Delete an item only when it is done or
explicitly dropped; say which in the commit message.

_Last swept: 2026-09-15 13:28 CDT (Fable)_

## Blocked on Wes

| Item | Since | Why it matters |
|---|---|---|
| Anne's phone has never appeared on this Mac | 2026-09-13 | Wes's phone now runs main (installed 2026-09-15 12:32, build f5aff0e). Anne's is still on whatever it had on 09-13. It needs its own install session: unlock the phone, have it on this network, then `./scripts/install-device.sh <id>`. |
| PR #65 — Appearance choice in Settings | 2026-09-14 | Green. Unreviewed. |
| `TAILSCALE_API_KEY` in `~/.fleet-secrets/live/integrations.env` is invalid | 2026-09-14 | Needs minting. Nothing currently depends on it; `fssh` works. |
| peers-fleet decisions | 2026-09-14 | Report `~/claude-reports/peers-fleet-2026-09-14.md`. Open: ponytail cuts, dashboard LaunchAgent, Kimi bridge, clarsmini push key. No sessions are running; that lead is stopped, not working. |

## Waiting on Anne

| Item | Since | Why it matters |
|---|---|---|
| Three questions on issue #1 | 2026-09-13 | Garbage third location; which months mowing runs; whether the hair chore is right as every-two-months pinned to Anne. Asked 09-13, re-asked 09-14 twice, no reply since. Chore data is not final until these land. This sat under **Blocked on Wes** for two days, which was simply wrong — Wes cannot answer them for her. |

## Owned by Fable

| Item | Since | Note |
|---|---|---|
| APNs key is live — `env` must flip to `production` for TestFlight | 2026-09-15 | Installed 17:53 CDT: `/etc/roost/AuthKey_2K6FF2VMGK.p8` + `apns.json`, root:roost 0640, `/health` reports `push: "sandbox"`. Debug builds get sandbox tokens and TestFlight builds get production ones; a mismatch fails silently with no error. The key itself covers both environments, so this is a one-line config change on the day the phones move to TestFlight. Backup of the `.p8` is in `~/.fleet-secrets/live/` — Apple will not reissue it. |
| Push over SSH, not HTTPS, for anything under `.github/workflows/` | 2026-09-15 | `remote.origin.pushurl` is now `git@github.com:amnanninga4/roost.git` in this clone. The HTTPS remote uses gh's OAuth token, which is refused on workflow files without the `workflow` scope; an SSH key is not an OAuth app and is not checked. This sat on the blocked-on-Wes list for an hour as "needs `gh auth refresh`" — it was never his to unblock. Wes caught it: "you literally have ssh". |
| CI runner sometimes has no iPhone 17 Pro simulator | 2026-09-14 | Seen once: `xcodebuild` found no matching destination on the macos-26 image. Fix is a step that creates the simulator on the newest installed runtime when it is missing. **PR #90, open.** |
| Handoffs ignore early due windows | 2026-09-15 | Shipped knowingly. `HandoffRules` counts calendar periods, so a chore with a `dueDay` of 1–6 (window opens in the previous month) refuses a handoff until the 1st. Documented in the due-windows spec. |
| Density scorecard test unowned | 2026-09-13 | Flagged in the UX audit, never picked up. |
| This Mac is on Xcode 27.0 / Swift 6.4; CI is on 26.6 | 2026-09-15 | Local green no longer proves CI green. CI is the authority on disagreement. |

## In flight

| Item | State |
|---|---|
| Lane 2 — litter rotations | **Done.** Merged as #87 (main f5aff0e); server deployed and verified at chores v5 / schema v5. A stale worktree for it is still checked out at `~/Developer/roost-bot-work/worktrees/l1-litter` on the bot's machine-side clone. |
| Lanes 3–6, unstarted | daily cap + bonus list; step deadlines + approaching notifications; add-a-chore from the app; Movies & TV watchlist. Order is Fable's; 4 and 6 depend on the APNs key above. |
