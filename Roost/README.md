# Roost/ — the iOS app

SwiftUI + SwiftData, iOS 18+, offline-first. The phone keeps its own store and syncs it against `server/` when it can reach it. R-2 built the store and the chore list; R-8 added the Today screen, check-off, pairing, and the sync client; R-10 added the tab shell, the streak header, and the escalation copy; R-11 added the Shopping, Meals, and Projects tabs and their sync; R-17 added Kitchen mode, the counter display; D-4 added first-run onboarding, pairing by six-digit code, and the Settings screen; D-2 was a craft pass over the Tasks tab (design tokens throughout, the check-off interaction, visible escalation, the empty and offline states, and one celebration a day).

| Tasks | Shopping | Meals | Projects |
| --- | --- | --- | --- |
| ![Tasks tab](docs/tasks.png) | ![Shopping tab](docs/shopping-r11.png) | ![Meals tab](docs/meals-r11.png) | ![Projects tab](docs/projects-r11.png) |

| Kitchen mode |
| --- |
| ![Kitchen mode](docs/kitchen-r17.png) |

| First run | The code | A code that didn't work | Settings |
| --- | --- | --- | --- |
| ![Onboarding](docs/onboarding.png) | ![Pairing](docs/pairing.png) | ![Pairing error](docs/pairing-error.png) | ![Settings](docs/settings.png) |

| Tasks, dark | Tasks, largest accessibility size |
| --- | --- |
| ![Tasks tab in dark mode](docs/tasks-dark.png) | ![Tasks tab at accessibility size 5](docs/tasks-ax.png) |

The three Tasks screenshots are one phone paired as Anne against a local server seeded with a fortnight of
history, so the whole escalation ladder is on screen at once: 5 days late in the danger role, 3 days late in the
warning role, two rows 1 day late in the notice role, then the rows that are simply due today — loudest first,
so the colour only gets calmer going down the card. Wes's own column, its rows, and the celebration are below
the fold. `tasks-ax.png` is the same screen at the largest accessibility text size, where the two streak cards
stack instead of sitting side by side; further down, the person header stacks name / YOU / count and the week
tally goes one line per person.

The four tab screenshots are a fresh, unpaired simulator install: the streaks are tied at 0 so nobody is tagged as ahead, nothing is overdue yet so no row has a subtitle, and the list rows were typed in through the UI. Unpaired, the phone does not know who it is, so the shopping rows carry no initial; the avatar appears once the server stamps `addedBy` from the token. The Kitchen mode screenshot is the same unpaired simulator later that day with three of Anne's chores already checked off (12 + 16 = 28 of 31 still due) and still nothing overdue, so it shows the calm state.

## Layout

```
Roost/
  project.yml                 XcodeGen spec — the source of truth for the project
  Roost.xcodeproj             generated; regenerate, don't hand-edit
  Sources/
    RoostApp.swift            @main: registers fonts, opens (or rebuilds) the store, seeds, owns SyncCoordinator, shows RootGate
    Strings.swift             every R-10 and R-11 user-facing string: tab titles, list headers and placeholders, streak labels, escalation copy; plus the Kitchen mode strings
    Root/RootTabView.swift    the tab bar (RootTab: Tasks, Shopping, Meals, Projects) and the screen behind each
    Onboarding/RootGate.swift the first thing shown: the flow while there is no token, the tabs once there is
    Onboarding/OnboardingFlow.swift the four steps and the transition between them
    Onboarding/OnboardingPage.swift the shape every step shares: eyebrow, title, line, content, bottom action; the dots
    Onboarding/WelcomeStep.swift  what this is, in one sentence
    Onboarding/CodeStep.swift     the six digits, what went wrong, and the token link
    Onboarding/CodeEntryField.swift six boxes drawn over one invisible text field; one VoiceOver element
    Onboarding/ConfirmStep.swift  "You're Anne", in Anne's colour
    Onboarding/NotificationsStep.swift the rationale, then the system prompt; "Not now" allowed
    Onboarding/TokenSheet.swift   the hand-minted fallback, behind a small link on the code screen
    Onboarding/PairingModel.swift pure: the pairing state machine (typing, pasting, the four failures) + DeviceName
    Onboarding/ServerEndpoint.swift which server this phone talks to (production, stored, or the DEBUG override)
    Models/Records.swift      SwiftData models: ChoreRecord, CompletionRecord, SyncState (and the schema list)
    Models/ListRecords.swift  SwiftData models for the lists: ShoppingItemRecord, MealRecord, ProjectRecord, SubtaskRecord; the ListRecord sync bookkeeping + PatchFields
    Models/ListActions.swift  every local list write (add, buy, next up, made today, start, step, done, remove), shared by the screens and the tests
    Models/Converters.swift   record <-> RoostCore value types
    Models/ChoreSeeder.swift  idempotent seed from the bundled chores.json (also used for server-sent chores)
    Models/TodayPlanner.swift pure: records -> per-person rows via RoostCore Scheduler/Tallies
    Models/StreakHeaderModel.swift pure: streaks + weekly tallies -> two sides, the leader (nil on a tie), the tally line
    Models/EscalationCopy.swift pure: EscalationStage + category -> row subtitle (nil for dueToday and done rows)
    Models/KitchenModel.swift pure: TodayPlan -> Anne/Wes columns (due count, overdue by stage) + the shared alert list; caught-up rule; "Synced …" line
    Sync/TokenStore.swift     Keychain (app) / in-memory (tests) storage for the device token
    Sync/SyncAPI.swift        typed HTTP client for server/ — no policy, no storage
    Sync/SyncAPI+Lists.swift  the shopping / meals / projects / subtasks endpoints and DTOs
    Sync/SyncClient.swift     @ModelActor: the replay + delta policy, in-flight guard
    Sync/ListSync.swift       the list half of a pass: replay creates/edits/removals, apply the four list deltas
    Sync/ListSync+Records.swift how each list record takes a server row (minus pending edits) and builds its PATCH body
    Sync/SyncCoordinator.swift @Observable main-actor face for the views; owns NotificationScheduler
    Notifications/NotificationCenterClient.swift  the slice of UNUserNotificationCenter we use, behind a protocol
    Notifications/NotificationPlanner.swift       pure: one day's due list -> ids, copy, Chicago fire times
    Notifications/NotificationScheduler.swift     reads the store, clears + reschedules, badge, foreground observer
    Screens/TodayScreen.swift Tasks tab: the store queries, the plan, check-off and un-check, the celebration counter, the gear menu
    Tasks/TodayBoard.swift    pure: the card's order, the celebration rule, the week's split, the status line and its wording
    Tasks/TaskStyle.swift     which RoostColor role each EscalationStage wears, and which RoostPerson each Person is
    Tasks/TodayHeaderView.swift the date eyebrow, "Today", the streak block, and the one-line sync notice
    Tasks/PersonColumnView.swift one person's header ("Anne  YOU  9 DUE") and their card of rows
    Tasks/ChoreRowView.swift  the row: the 44 pt check control, the title, the escalation copy, the days-late chip
    Tasks/CelebrationView.swift the one burst a day, or a checkmark that scales in under Reduce Motion
    Screens/KitchenScreen.swift Kitchen mode: full-screen counter view of both people, screen stays on; Gear -> "Kitchen mode"
    Screens/StreakHeaderView.swift the head-to-head block from the mockup
    Screens/ShoppingScreen.swift Shopping tab: count line, add row, check-off with bought rows sinking, adder avatar, swipe to delete
    Screens/MealsScreen.swift Meals tab: count line, add row (title + tag), NEXT UP badge, "Made it today", swipe to delete
    Screens/ProjectsScreen.swift Projects tab: count line, start row (title + first steps), one card per project with progress, steps, add-step row
    Screens/ListParts.swift   pieces the three list tabs share: header, dashed add row, check circle, avatar, badge, chrome, refocus
    Screens/SettingsScreen.swift Gear -> Settings: paired as, server, last sync, Unpair, version
    Screens/ChoreListScreen.swift the R-2 list, reachable from the gear menu as "All chores"
  Tests/                      in-memory ModelContainer + URLProtocol stub; no network
  docs/onboarding.png         simulator screenshot, first run (no token in the Keychain)
  docs/pairing.png            simulator screenshot, the code half typed in
  docs/pairing-error.png      simulator screenshot, a code the server answered 404 to
  docs/settings.png           simulator screenshot, Settings while paired against a local server
  docs/tasks.png              simulator screenshot, Tasks tab (paired as Anne, one row at every escalation stage)
  docs/tasks-dark.png         the same screen in dark mode
  docs/tasks-ax.png           the same screen at the largest accessibility text size
  docs/shopping-r11.png       simulator screenshot, Shopping tab (six rows typed in, two bought)
  docs/meals-r11.png          simulator screenshot, Meals tab (four ideas, one NEXT UP, one made today)
  docs/projects-r11.png       simulator screenshot, Projects tab (one card open with its steps)
  docs/kitchen-r17.png        simulator screenshot, Kitchen mode (unpaired, three chores checked off, nothing overdue: "All caught up.")
  docs/shopping-r10.png       the R-10 placeholder screenshot, kept for history
```

Packages are referenced by relative path: `../Packages/RoostCore` (models, scheduler, streaks) and `../Packages/RoostDesign` (colors, fonts). The seed file is `../data/chores.json`, added to the target as a bundle resource in place, so the repo has one copy.

Bundle identifier: `xyz.hinescreative.roost`. Signing is automatic with the team left blank; set the team in Xcode locally, never commit it.

## Build

```bash
brew install xcodegen            # once
cd Roost && xcodegen generate     # after editing project.yml or adding files
open Roost.xcodeproj
```

## Test (headless)

```bash
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

117 tests: seed (31 rows, 2 pinned, idempotent, retire/restore, converters), sync (pairing stores person/cursor/token; 401 stores nothing; a queued completion is POSTed once and marked synced; a 400 marks it rejected and it is never retried; offline keeps the queue; a delete replays as DELETE; a delta with `deleted: true` hides the local row; server-sent chores re-seed; overlapping syncs coalesce), the list replay (a local shopping add is POSTed once and marked synced, with `addedBy` taken from the server's reply; a meal add carries its tag and every other field, so a 201 leaves nothing to PATCH; edits made before a create is replayed outlive the server's stale 200 and go out as a PATCH; a project with first steps goes out as one POST and every step comes back synced; a step added to a synced project POSTs to `/projects/:id/subtasks` and its check-off PATCHes only `done`; a bought toggle PATCHes only `bought`, un-buying PATCHes again, and acknowledged edits are not replayed; "made it today" and "next up" ride one PATCH and the old holder is cleared locally without a request; a delete replays as DELETE and a row the server never saw sends nothing; removing a project cascades locally and sends one DELETE), the list failure modes (a 400 create is kept and never retried; a 503 keeps the queue; a rate-limited DELETE stays queued while the pull still runs; a DELETE the server refuses is acknowledged and never retried; a dead connection ends the pass at the first row with the queue intact), the list delta (a delta with `deleted: true` removes the local row without echoing a DELETE; next-up exclusivity is reflected after a delta; a project delta with subtasks lands in both tables and a cascade delta empties them; the cursor advances to the server's value and holds when nothing changed; a pending local edit outlives a delta carrying the server's older copy of the same row), planning (pinned chores land on the right person; cat care sorts first; a completion today shows as a done row and counts in the tally; overdue days map to the escalation stage), the streak header (the higher streak leads; a tie, including 0 vs 0, has no leader; sides come out Anne then Wes with missing values as 0; the tally line reads `Anne · 14   Wes · 11`; it builds from a plan), the escalation copy (no subtitle for due today; nudge names the chore; pointed depends on category; alert capitalizes the chore; every overdue stage has copy for both categories; rows flow through their stage and done rows get nothing), the root tabs (four tabs in order with their SF Symbols; the list headers read like the mockup, singular and plural), notifications (fixture plan yields the expected ids, Chicago fire times and titles; a replan clears the previous set; the other person's chores never appear; badge count; overlapping replans coalesce), pairing (the sixth digit submits and five do not; a 404 clears the boxes, counts a rejection and offers no retry; a 429 and a dead connection keep the code and offer one; a retry after a transport failure pairs; a pasted code with spaces or words around it fills every box and submits once; a short paste waits; deleting a digit clears the message without resubmitting; digits arriving mid-attempt are ignored; every status code maps to one sentence; the device name is trimmed to the server's 60; the stored base URL beats production and junk does not; POST /pair carries the code and the device name and no bearer, and its 404/429/400/403/500 and a dead connection come back typed; DELETE /pair/self carries the bearer and reads the label, and its 403 is `forbidden`; pairing by code stores the token the server minted and a failure stores nothing; unpairing tells the server then forgets the token, a hand-minted device is forgotten locally with a note, an unreachable server still unpairs this phone, and a phone that was never paired sends nothing), the Tasks board (the card runs loudest first and inside one stage keeps the planner's order, done rows sink to the bottom, and nothing is lost or duplicated; the week bar's split, including the empty track before anybody has done anything; every escalation stage maps to its own colour role and soft fill, and only from three days is a row “on the other phone too”; clearing your own column fires the celebration once a day and never for the other person's column, an un-check, or an unpaired phone; and the status line reads unpaired, syncing, offline-with-a-time, synced-just-now and not-synced-yet, with the days-late wording shared with Kitchen mode), and Kitchen mode (overdue rows group by person and sort by stage descending with the right copy; alert-stage rows from both people land in the banner, most days late first; an empty plan and an all-due-today plan are both caught up; a 5-day-overdue litter box for Wes is a "Scoop litter emergency" in the banner; a missing `activeFrom` falls back to today; the synced line).

## Pairing

First run has no token in the Keychain, so `RootGate` shows `OnboardingFlow` instead of the tabs: four screens,
one job each.

1. **What this is.** One sentence, and the two people the app has.
2. **The code.** Six boxes. Anne or Wes mints a code on the host — `sudo -u roost ROOST_DB=/var/lib/roost/roost.db
   node /opt/roost/server/src/mkcode.js anne "Anne iPhone"` — and the phone POSTs it to `/pair` with
   `UIDevice.current.name` trimmed to the 60 characters the server accepts. The sixth digit submits; there is no
   button. A paste of anything containing six digits fills every box. `404` (unknown, used, or expired) clears the
   boxes, shakes them once and says so; `429` and a dead connection keep the code and offer one retry, because the
   code was probably fine. The token comes back in that one response and goes straight to the **Keychain**
   (`kSecClassGenericPassword`, this device only, after first unlock); `SyncState` keeps the base URL and the
   `person` the server named.
3. **Who you are.** "You're Anne" in Anne's colour. The person is not a choice — it comes from the code.
4. **Reminders.** One screen saying what Roost will send (the 9am list, the 6pm nudge) and then the system prompt.
   "Not now" leaves it unasked, which keeps the one shot at that prompt unspent.

The tabs appear after step 4, not after step 2: pairing succeeds in the middle of the flow, and `needsOnboarding`
stays true until the flow says otherwise, so the notification question never arrives behind a tab bar.

The token is never written to UserDefaults, the SwiftData store, or logs.

### Settings

Gear → Settings (`SettingsScreen`) replaced the old paste-a-token Pairing sheet:

- **This phone** — the person the server paired, in their colour, and this device's name.
- **Server** — the host. In a DEBUG build it is an editable field; see below.
- **Sync** — when the last pass landed, and what state it left behind ("Up to date", "Syncing…",
  "Offline · will retry").
- **Unpair this phone** — a confirmation, then `DELETE /pair/self`. On a `200` the app drops back to onboarding.
  On a `403` (the token came from the tokens file, so only that file can revoke it) or on no answer at all, the
  local token is cleared anyway and an alert explains what is still live on the server before onboarding returns.
- The app version and build at the bottom, from the bundle.

The hand-minted path still exists for a phone that cannot use a code, or for getting back in when the API is not
answering: "Enter a token instead", a small link under the boxes on the code screen, takes a token from
`src/mktoken.js` and validates it with a real `GET /sync` before keeping it.

### Pointing a DEBUG build at a local server

`ServerEndpoint` resolves the base URL in this order: the DEBUG launch-argument override, then whatever pairing
stored, then `https://roost.hinescreative.xyz`. Release builds compile the override out.

```bash
cd server
ROOST_DB=/tmp/d4.db ROOST_TOKENS=/tmp/tokens.json npm start      # write an empty {} tokens file first
ROOST_DB=/tmp/d4.db node src/mkcode.js anne "Anne test"          # prints a six-digit code

xcrun simctl install booted <path>/Roost.app
xcrun simctl launch booted xyz.hinescreative.roost -roostServer http://127.0.0.1:8790
```

A leading-dash launch argument lands in `UserDefaults`, so `-roostServer <url>` needs no parsing. Settings shows
the same value in an editable field in DEBUG; changing it does not re-pair, so the next step after changing it is
Unpair and a fresh code.

## Sync

`SyncClient` is a `@ModelActor` with its own context. Every pass does, in order:

1. **Replay POSTs.** Each `CompletionRecord` with `syncedAt == nil` is POSTed with its client-generated id, so a retry after a crash or a dead connection is a no-op on the server (201 new, 200 replay). Success stamps `syncedAt` and `seq`. A 400 (unknown or retired chore) sets `rejected`; the row stays visible locally and is never sent again.
2. **Replay DELETEs.** Each row with `removed && !deleteSynced` is DELETEd; 200 or 404 both mark `deleteSynced`. A row that was un-checked before it ever reached the server is marked `deleteSynced` immediately, so nothing is sent.
3. **Replay the lists** (`ListSync.swift`), under the same rules. Creates first: shopping items and meals with their client ids; a project with every step still pending in one `POST /projects` (on a 200 replay the server ignores steps it has not seen, so whatever did not come back in the reply goes through `POST /projects/:id/subtasks` next, as does any step added to a project the server already has). Then edits: each row with `pendingPatch != 0` is PATCHed with only the fields flagged there (`PatchFields`: title, bought, tag, lastMadeAt, nextUp, done, sortOrder), so a stale copy of a field the other phone edited is never sent; success clears the flags and applies the server's row. Then removals: steps, then projects (the server cascades a project's steps, so `ListActions.removeProject` acknowledges them locally and only the project is sent; the reply carries the steps' new seqs), then shopping items and meals. 2xx marks a row synced: a 201 create clears the flags for the fields the body carried, while a 200 replay ignored the body, so every flag stays and the edit goes out as a PATCH in the same pass. 400 (or a 404 on a PATCH) marks a row `rejected` and it is never retried; a DELETE the server refuses is acknowledged the same way, and a 404 there counts as done. 401 and a transport failure end the pass with everything so far saved and the queue intact. Anything else (429, 5xx, an unreadable reply) is one row's problem for one pass: it stays queued, the next row goes ahead, and so does the pull, so a stuck row never blocks what the other phone did.
4. **Pull the delta.** `GET /sync?cursor=<SyncState.cursor>&choresVersion=<SyncState.choresVersion>`. Completions, shopping, meals, projects, and subtasks are upserted by id, honoring `deleted`; a local row with a pending delete keeps its local intent until the DELETE has run, and a row with a pending edit keeps its flagged fields and takes the rest from the server. A meal arriving with `nextUp` clears it on every other local meal that has no pending edit, mirroring the server. If the server included `chores` (version mismatch), they are re-seeded through `ChoreSeeder` exactly like the bundle. The new `cursor` (the max seq across all five arrays, as the server reports it) and `choresVersion` are stored.

It runs on launch, when the app returns to the foreground, after every check-off and every list write, and from Gear → Sync now. An in-flight guard coalesces overlapping calls into at most one extra pass.

**Offline is not an error.** A transport failure or 5xx leaves the queue untouched, returns `.failed`, and the next trigger retries. Only a 401 aborts the pass (the token was revoked; re-pair).

## Screens

The root is `RootTabView`, a `TabView` over the `RootTab` enum: Tasks (`checklist`), Shopping (`cart`), Meals (`fork.knife`), Projects (`hammer`), tinted `RoostColor.accent`. The gear menu (Kitchen mode, All chores, Pairing…, Sync now) stays on Tasks.

Every user-facing string, the tab titles, the list headers and placeholders, the streak labels, and the escalation copy, lives in `Sources/Strings.swift`, so the wording can change without touching a screen. R-17's Kitchen mode strings sit in the same file under `Strings.Kitchen`.

The three list tabs share one shape (`ListParts.swift`): the tab title in the display face over a count line, a dashed "Add…" row with a plus badge, then inset cards on the page color. Every row reads from SwiftData through `@Query`; every write goes through `ListActions` (store first, then `SyncCoordinator.syncSoon()`), so the tap is on screen before the network is involved and works the same offline. Return on an add row keeps the field focused (`refocus`), so several lines can be typed in a row; Return on a blank row clears it and lets the keyboard go. `ListActions` trims text and cuts it to the server's limits (200 characters for a title, 40 for a tag, 100 first steps on a create) rather than letting the create be refused. Swipe left on any row to delete it. To VoiceOver a row with a check circle is its title, with the state ("Bought", "Not done") as the value and what a tap does as the hint.

### Tasks

`TodayPlanner.plan` feeds `RoostCore.Scheduler` the active chores and non-removed completions, with `activeFrom` = the household start (fixed on first render as the earlier of today and the earliest completion, then persisted in `SyncState`). For each person it lists what is due, cat care first, most overdue first, followed by rows completed today so they can be un-checked. The header shows the Chicago date, the streak block, the week's tallies, and the sync status line.

**Streak header.** `StreakHeaderModel` takes the plan's per-person streaks (`RoostCore.Tallies.streak`, so `activeFrom` comes from `SyncState`) and weekly tallies. Each side shows the name, the streak number, and "day streak". The side with the strictly higher streak gets a "CURRENTLY AHEAD" tag and its number in `RoostColor.gold`; a tie tags nobody. Under the block a mono line carries the week's completions: `Anne · 14   Wes · 11`.

**Escalation.** `EscalationStage` picks a `RoostColor.Role`, and everything on the row follows it (`TaskStyle.swift`): due today = `textPrimary` on no fill, 1–2 days = `notice`, 3–4 = `warning`, 5+ = `danger`, each overdue stage on its `…Soft` fill. The card runs loudest first (`TodayBoard.ordered`): alert, then pointed, then nudge, then what is merely due today, with the planner's own order (cat care first, then most days late) deciding inside one stage — the same order Kitchen mode uses, so the two screens agree. Going down a card the colour only gets calmer, the five-day row cannot be scrolled past, and a mono "N DAYS LATE" chip carries the count, so the state is never colour alone. From 3 days a caption says "On the other phone too", because that is when it stops being a private problem. `EscalationCopy.subtitle` adds a line under the title once a row is overdue: nudge → "Still no <title>…" (title lowercased to read mid-sentence, unless it starts with an acronym like "PM wet cat food"), pointed → "The cat has feelings about this." for cat-care rows and "Getting overdue." for home rows, alert → "<Title> emergency". Due-today rows and done rows show no subtitle.

**Check-off.** Checking a row inserts a `CompletionRecord` (UUID id, `completedAt` now, UTC) and kicks a sync; tapping a done row soft-deletes it. The whole row is the button, and the check control holds `RoostSpacing.minTapTarget` (44 pt) on its own inside it. A press scales the row 2% and steps its fill up to `surfaceElevated` on `RoostMotion.quick`; the circle becomes a filled checkmark through `.contentTransition(.symbolEffect(.replace))`; the row itself moves on `RoostTransition.checkOff`; the "N DUE" count and the week's tallies roll with `.contentTransition(.numericText())` on `RoostMotion.standard`; and `RoostHaptic.checkOff` / `.undo` fire on the tap through the `.roostHaptic(_:trigger:)` counters, so a cold launch or a delta arriving from the other phone never buzzes. Every animation goes through `RoostMotion.reduceMotionAware`, which under Reduce Motion is `nil` — no animation, not a faster one.

**States.** `TodayBoard.notice` produces the one line under the header: "Syncing…" while a pass is in flight, "Not paired yet · gear menu → Settings" when the phone has a token but the server has not named a person yet, "Offline · last synced 5 minutes ago" in the `notice` role when the last pass failed, and "Synced just now" otherwise. Offline is never a modal. A person with no chores on the day reads "Nothing due today"; a person who has checked off everything they owed reads "Nothing left" above their done rows, which stay there to be un-checked. Pull down anywhere on the screen to run `SyncCoordinator.syncNow()`.

**The celebration.** Clearing the last of *your own* rows for the day fires one confetti burst (ConfettiSwiftUI 3.0.0, pinned exactly in `project.yml`; its own haptic is off, `RoostHaptic.milestone` does that) — 20 pieces, under a second, non-interactive and hidden from VoiceOver. `TodayBoard.Celebration` remembers the day it fired, so it happens once: not on the next check-off, not for the other person's column, not on an un-check, and not on a phone that is not paired as anybody. Under Reduce Motion it is a checkmark that scales in on `RoostMotion.bouncyCelebration` instead.

**Dynamic Type.** The screen is built for `accessibility5`, not merely survivable at it. `AnyLayout` swaps four rows into stacks at accessibility sizes: the streak cards, the person header (name / YOU / count), the week tally, and a row's meta line. The "CURRENTLY AHEAD" pill is laid out invisibly at normal sizes so taking the lead does not shove the cards, and dropped entirely when stacked, where an invisible pill would be a blank line of 40 pt type. The category badge — decoration, already `accessibilityHidden` — drops out at accessibility sizes rather than costing the title a third of its column. No title truncates at any size.

**VoiceOver.** A row is one element: label = the chore's title, value = its state ("Done", "Due today", "3 days late", plus "Always Anne" when pinned), hint = what the tap will do. Each person's header is one element with the `.isHeader` trait, as is "Today". The streak cards read as "Anne, 9 day streak, currently ahead"; the week bar reads its tally line.

### Kitchen mode

Gear → Kitchen mode presents `KitchenScreen` full-screen (`fullScreenCover`, no navigation chrome) for a phone propped on the counter. It shows both people at once and is read-only; check-off stays on the Tasks tab. Tap anywhere, or the Close pill, to leave.

`KitchenModel` is built from the same `TodayPlanner.plan` as the Tasks tab, so the two can never disagree. Top to bottom:

- **Date line** in the mono eyebrow style, with Close on the right.
- **Alert banner**, only when something is at the alert stage (5+ days): a full-width `alertSoft` panel with an `alert` border headed "VISIBLE TO BOTH OF YOU", listing every alert-stage chore from *either* person, most days late first, each as its `EscalationCopy` line ("Scoop litter emergency") over the person's name and "N DAYS LATE".
- **Two columns, Anne | Wes.** Each has the name, a big number of everything the person owes today (overdue included, the same count as the Tasks tab's "N DUE"), and "DUE TODAY". Under it, the person's overdue chores as cards sorted by stage descending (alert, pointed, nudge; within a stage the Tasks tab's order, cat care first then most days late), in the stage's color with the stage label, the title, and the escalation copy. A person with nothing overdue while the other has something reads "Nothing overdue."
- **"All caught up."** replaces the cards when neither person has anything overdue; due-today rows do not count.
- **"Synced 5 minutes ago"** at the bottom, from `SyncCoordinator.lastSyncAt` ("Synced just now" inside a minute, "Not synced yet" before the first sync).

It follows the system appearance through the `RoostColor` tokens (ink on `bg` in light, the dark set in dark). While it is up `UIApplication.shared.isIdleTimerDisabled` is true, and the previous value is put back on dismiss. It re-renders on every store change (the `@Query` rows), on the coordinator's published sync state, and every 60 seconds through a `TimelineView`, so days-late counts and the synced line move on their own.

### Shopping

Header: "N items · M already bought" (total live rows, and how many are ticked). "Add an item…" inserts a `ShoppingItemRecord` with a UUID id, `addedBy` = the paired person (blank when unpaired; the server stamps it from the token and the reply overwrites it). Rows show the check circle, the title, and the adder's initial in a small `RoostColor.assign` avatar. Tapping a row flips `bought` (with a local `boughtBy`/`boughtAt` preview the server's stamp replaces) and flags it for PATCH; bought rows sink to the bottom, struck through, most recently bought first, while unbought rows stay newest first.

### Meals

Header: "N saved ideas". "Add an idea…" takes a title and, once there is one, a tag ("Weeknight"); Return on either field saves. Rows show a flame badge in the mockup's meal colors, the title in the display face, and a meta line of tag and "last made <Mon d>" when set. The meal with `nextUp` carries a `NEXT UP` badge and sorts first. Swipe right, or long-press, for "Next up" / "Clear next up"; the context menu also has "Made it today" (sets `lastMadeAt` to now) and Delete. Setting next-up clears it on every other local meal at once; those rows are not flagged, because the server clears them itself and the next delta confirms it.

### Projects

Header: "N active projects". "Start a project…" takes a title and, once there is one, a "First steps, one per line" field and a Start button (Return on the title also starts). Each project is its own card: the title, a chevron, and a progress bar with "done/total" over its live steps. Tapping the card opens it (the first card opens on its own, like the mockup): the steps with check-off (strikethrough when done, `doneBy`/`doneAt` previewed locally) and an "Add a step…" row that appends after the highest `sortOrder`, the server's default. Swipe a project or a step to delete; deleting a project removes its steps locally too.

## Store rules

- `ChoreRecord.retired` hides chores removed from the list without losing completion history.
- `CompletionRecord.id` is client-generated; the server dedupes on it. `syncedAt` stays nil until acknowledged. `removed` is the soft-delete flag (named to avoid CoreData's reserved `isDeleted`); `deleteSynced` and `rejected` are sync bookkeeping.
- `ShoppingItemRecord`, `MealRecord`, `ProjectRecord`, and `SubtaskRecord` (`ListRecords.swift`) mirror their server rows field for field and share the completion bookkeeping through the `ListRecord` protocol (`syncedAt`, `removed`, `deleteSynced`, `rejected`, `seq`) plus `pendingPatch`, a `PatchFields` bitmask of the fields edited locally since the server last saw the row. `needsPost` / `needsPatch` / `needsDelete` read the state machine; `markEdited` and `markRemoved` write it. Subtasks point at their project by `projectId`, not a relationship.
- `SyncState` is a single row: `cursor` (server seq), `choresVersion`, `baseURL`, `person`, `activeFrom`, `lastSyncAt`.
- Pre-release: if the on-disk store cannot be migrated, `RoostApp` deletes it and rebuilds. Chores re-seed from the bundle and completions come back from the server on the next sync. This goes away once the schema is stable.

## Notifications

Local only (`UserNotifications`, no server involvement). `NotificationScheduler.replan()` rewrites the pending set after every successful sync and whenever the app becomes active (launch and foreground); overlapping replans coalesce. Each pass clears every pending Roost notification, then schedules, for the paired person only:

- **09:00 Chicago** one digest listing what is due that day (skipped when nothing is due).
- **18:00 Chicago** one notification per overdue chore, worded by `EscalationStage` as in the mockup: nudge "Still no <title>…", pointed "The cat has feelings about this." (cat care) or "Getting overdue." (home), alert "<Title> emergency".

Identifiers are deterministic per chore and date (`roost.overdue.<choreId>.<yyyy-MM-dd>`, `roost.digest.<yyyy-MM-dd>`), so a replan replaces rather than duplicates. The plan covers today and tomorrow (tomorrow assumes nothing else gets done and is replaced by the next replan) so a phone opened after 18:00 still gets the next ping. The app badge is the paired person's overdue count, updated with each replan. An unpaired phone gets nothing and a zero badge.

Permission (alert, sound, badge) is requested by the onboarding step that explains it (D-4), not on first launch and not silently at the moment pairing succeeds.

The other person's chores never produce a local notification here, so the mockup's "red alert visible to both of you" needs a push from the server: that is ticket R-6b (APNs), waiting on a key. Kitchen mode's banner shows both people's alerts on whichever phone is on the counter, but it is a display, not a ping.
