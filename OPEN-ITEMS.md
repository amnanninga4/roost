# Roost — open items

One line per thing that is not done, with who owns it and when it was last moved.
This file outlives any single plan. A per-plan ledger (`.superpowers/sdd/<plan>/progress.md`)
tracks the lane in flight; anything that outlives the lane belongs here instead.

**Read and report this file at the start of every lane**, not when it occurs to someone.
An item that has not moved gets louder, not quieter. Delete an item only when it is done or
explicitly dropped; say which in the commit message.

_Last swept: 2026-09-15 23:40 CDT (home-screen lane)_

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
| Home draws no sync notice | 2026-09-15 | The home-screen spec lists `SyncNoticeLine` as Home's last section; it was never built. Only the board says "Not paired yet" or how long ago the last pass was, so the screen the app opens on is silent about being unpaired or offline. Either build it or strike item 7 from the spec. |
| The Home/board segment does not survive a launch | 2026-09-15 | The spec says the selection persists and does not reset to Home on foreground. `RootNavigation.segment` is plain in-memory state, so every cold launch lands on Home. Someone who lives on the board is sent back to the foyer each morning. |
| `TodayScreen` still builds its own `NavigationStack` | 2026-09-15 | It is now inside `HomeTabScreen`'s. It happens to render without a second bar, but it is a nested stack: a push from a board row would go onto the inner one, and the board's title and toolbar are dead configuration. |
| Scroll screens do not reserve room for the floating tab bar | 2026-09-15 | `RoostSpacing.xxl` is 32 pt and the iOS 26 floating tab bar is roughly 90. At the **end** of the scroll — not mid-flick — Home's door counts sit behind the bar; whether they do depends on content height, which is why it is intermittent to the eye. `/tmp/home-screen-shots/home-doors-under-tabbar.png` is it happening. An accessibility audit of that state fails with "Potentially inaccessible text" every run, which is how it was found. Home, the board and the list pages all use the same `.padding(.bottom, RoostSpacing.xxl)`, so the fix is one decision for all of them — a bottom safe-area inset rather than a bigger magic number — and not a one-screen patch. `RoostUITestCase.scrollIntoView` has been working around this since before this lane. Once fixed, add the scrolled Home audit that is commented out in `AccessibilityAuditTests.swift`. |
| No UI-test fixture with empty rooms | 2026-09-15 | `paired` fills all four lists, so the empty-household door strip — the state the spec designs for, and the one a new household actually arrives in — cannot be audited or screenshotted by the suite. It was checked once by hand against a throwaway fixture and reads correctly (four titles over four grey dashes). A `paired-empty-rooms` seed would make that checkable. |
| A new `@AppStorage` key needs adding to the UI-test launch reset | 2026-09-15 | `UITestSeed.makeContainer()` clears the keys by hand, and `roost.home.rowsExpanded` was missed when Task 5 added it — so the fixture launched with Home's row fold already open, which is not a fresh install. Fixed for that key; the next one will be missed the same way unless the reset is driven off a list. |

## In flight

| Item | State |
|---|---|
| Lane 2 — litter rotations | **Done.** Merged as #87 (main f5aff0e); server deployed and verified at chores v5 / schema v5. A stale worktree for it is still checked out at `~/Developer/roost-bot-work/worktrees/l1-litter` on the bot's machine-side clone. |
| Home screen — the front door | **Built.** Tasks 1–8 of the lane are done and sitting in the working tree on `feat/home-screen`; Wes commits and opens the PR. The measurement is in the spec's "What it measured": 156 pt to the first checkable row against ~190–210 pt on the old screen. What outlived the lane is on the Fable list above. |
| Lanes 3–6, unstarted | daily cap + bonus list; step deadlines + approaching notifications; add-a-chore from the app; Movies & TV watchlist. Order is Fable's; 4 and 6 depend on the APNs key above. |
