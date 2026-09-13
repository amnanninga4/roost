# Roost/ — the iOS app

SwiftUI + SwiftData, iOS 18+, offline-first. The phone keeps its own store and syncs it against `server/` when it can reach it. R-2 built the store and the chore list; R-8 added the Today screen, check-off, pairing, and the sync client; R-10 added the tab shell, the streak header, and the escalation copy; R-11 added the Shopping, Meals, and Projects tabs and their sync; R-17 added Kitchen mode, the counter display; D-3 made the three list tabs finished screens (a composer, a Bought section, a five-second undo on every delete, drag-to-reorder steps, finished projects); D-4 added first-run onboarding, pairing by six-digit code, and the Settings screen.

| Tasks | Shopping | Meals | Projects |
| --- | --- | --- | --- |
| ![Tasks tab](docs/tasks-r10.png) | ![Shopping tab](docs/shopping.png) | ![Meals tab](docs/meals.png) | ![Projects tab](docs/projects.png) |
|  | ![Shopping tab in dark mode](docs/shopping-dark.png) | ![Meals tab in dark mode](docs/meals-dark.png) | ![Projects tab in dark mode](docs/projects-dark.png) |

| Kitchen mode |
| --- |
| ![Kitchen mode](docs/kitchen-r17.png) |

| First run | The code | A code that didn't work | Settings |
| --- | --- | --- | --- |
| ![Onboarding](docs/onboarding.png) | ![Pairing](docs/pairing.png) | ![Pairing error](docs/pairing-error.png) | ![Settings](docs/settings.png) |

One file per screen, replaced in place rather than kept per ticket. Tasks and Kitchen mode are a fresh, unpaired simulator install: the streaks are tied at 0 so nobody is tagged as ahead, nothing is overdue yet so no row has a subtitle, and Kitchen mode is the same install later that day with three of Anne's chores checked off (12 + 16 = 28 of 31 still due), so it shows the calm state.

The three list screens are paired as Anne against a local server, each in light and dark. Shopping has four rows still to buy over a Bought section with "Clear bought"; "Oat milk" carries the "Didn't sync" marker because the server had already deleted that row, which is what the marker is for. Meals has one idea marked NEXT UP and three with a tag and a "last made" line, one of them a weekday and one a date. Projects has a finished card open (DONE chip, full bar, Archive) over a second card at 2/4.

## Layout

```
Roost/
  project.yml                 XcodeGen spec — the source of truth for the project
  Roost.xcodeproj             generated; regenerate, don't hand-edit
  Sources/
    RoostApp.swift            @main: registers fonts, opens (or rebuilds) the store, seeds, owns SyncCoordinator, shows RootGate
    Strings.swift             every user-facing string: tab titles, list headers, placeholders and empty states, the undo and "Didn't sync" wording, streak labels, escalation copy, Kitchen mode, onboarding and Settings
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
    Models/ListActions.swift  every local list write (add, buy, next up, made today, start, step, done, reorder, remove, restore), shared by the screens and the tests
    Models/ListPresentation.swift pure: the list screens' arithmetic — the bought/to-buy split, project progress, the sortOrder plan for a drag, the "last made" wording
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
    Screens/TodayScreen.swift Tasks tab: date, streak header, Anne/Wes sections, check-off, escalation color + copy, gear menu
    Screens/KitchenScreen.swift Kitchen mode: full-screen counter view of both people, screen stays on; Gear -> "Kitchen mode"
    Screens/StreakHeaderView.swift the head-to-head block from the mockup
    Screens/ShoppingScreen.swift Shopping tab: composer, to-buy rows, Bought section + "Clear bought", check-off, swipe to delete with undo
    Screens/MealsScreen.swift Meals tab: composer (title + tag), NEXT UP badge, "Made it" + "last made …", tag chips, swipe to delete with undo
    Screens/ProjectsScreen.swift Projects tab: composer, one card per project with an animated bar and a counting number, steps reorderable by drag, DONE chip + Archive
    Screens/ListParts.swift   pieces the three list tabs share: header + sync line, the composer, check circle, avatar, chips, the "Didn't sync" marker, empty states, swipe-to-delete, the undo bar and its five-second window
    Screens/SettingsScreen.swift Gear -> Settings: paired as, server, last sync, Unpair, version
    Screens/ChoreListScreen.swift the R-2 list, reachable from the gear menu as "All chores"
  Tests/                      in-memory ModelContainer + URLProtocol stub; no network
  docs/onboarding.png         simulator screenshot, first run (no token in the Keychain)
  docs/pairing.png            simulator screenshot, the code half typed in
  docs/pairing-error.png      simulator screenshot, a code the server answered 404 to
  docs/settings.png           simulator screenshot, Settings while paired against a local server
  docs/tasks-r10.png          simulator screenshot, Tasks tab (fresh unpaired install: tied streaks, nothing overdue)
  docs/shopping.png           simulator screenshot, Shopping tab; docs/shopping-dark.png is the same screen in dark mode
  docs/meals.png              simulator screenshot, Meals tab; docs/meals-dark.png in dark mode
  docs/projects.png           simulator screenshot, Projects tab; docs/projects-dark.png in dark mode
  docs/kitchen-r17.png        simulator screenshot, Kitchen mode (unpaired, three chores checked off, nothing overdue: "All caught up.")
  docs/today-r8.png           the R-8 screenshot, kept for history
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

126 tests: seed (31 rows, 2 pinned, idempotent, retire/restore, converters), sync (pairing stores person/cursor/token; 401 stores nothing; a queued completion is POSTed once and marked synced; a 400 marks it rejected and it is never retried; offline keeps the queue; a delete replays as DELETE; a delta with `deleted: true` hides the local row; server-sent chores re-seed; overlapping syncs coalesce), the list replay (a local shopping add is POSTed once and marked synced, with `addedBy` taken from the server's reply; a meal add carries its tag and every other field, so a 201 leaves nothing to PATCH; edits made before a create is replayed outlive the server's stale 200 and go out as a PATCH; a project with first steps goes out as one POST and every step comes back synced; a step added to a synced project POSTs to `/projects/:id/subtasks` and its check-off PATCHes only `done`; a bought toggle PATCHes only `bought`, un-buying PATCHes again, and acknowledged edits are not replayed; "made it today" and "next up" ride one PATCH and the old holder is cleared locally without a request; a delete replays as DELETE and a row the server never saw sends nothing; removing a project cascades locally and sends one DELETE), the list failure modes (a 400 create is kept and never retried; a 503 keeps the queue; a rate-limited DELETE stays queued while the pull still runs; a DELETE the server refuses is acknowledged and never retried; a dead connection ends the pass at the first row with the queue intact), the list delta (a delta with `deleted: true` removes the local row without echoing a DELETE; next-up exclusivity is reflected after a delta; a project delta with subtasks lands in both tables and a cascade delta empties them; the cursor advances to the server's value and holds when nothing changed; a pending local edit outlives a delta carrying the server's older copy of the same row), planning (pinned chores land on the right person; cat care sorts first; a completion today shows as a done row and counts in the tally; overdue days map to the escalation stage), the streak header (the higher streak leads; a tie, including 0 vs 0, has no leader; sides come out Anne then Wes with missing values as 0; the tally line reads `Anne · 14   Wes · 11`; it builds from a plan), the escalation copy (no subtitle for due today; nudge names the chore; pointed depends on category; alert capitalizes the chore; every overdue stage has copy for both categories; rows flow through their stage and done rows get nothing), the root tabs (four tabs in order with their SF Symbols; the list headers read like the mockup, singular and plural), notifications (fixture plan yields the expected ids, Chicago fire times and titles; a replan clears the previous set; the other person's chores never appear; badge count; overlapping replans coalesce), pairing (the sixth digit submits and five do not; a 404 clears the boxes, counts a rejection and offers no retry; a 429 and a dead connection keep the code and offer one; a retry after a transport failure pairs; a pasted code with spaces or words around it fills every box and submits once; a short paste waits; deleting a digit clears the message without resubmitting; digits arriving mid-attempt are ignored; every status code maps to one sentence; the device name is trimmed to the server's 60; the stored base URL beats production and junk does not; POST /pair carries the code and the device name and no bearer, and its 404/429/400/403/500 and a dead connection come back typed; DELETE /pair/self carries the bearer and reads the label, and its 403 is `forbidden`; pairing by code stores the token the server minted and a failure stores nothing; unpairing tells the server then forgets the token, a hand-minted device is forgotten locally with a note, an unreachable server still unpairs this phone, and a phone that was never paired sends nothing), and Kitchen mode (overdue rows group by person and sort by stage descending with the right copy; alert-stage rows from both people land in the banner, most days late first; an empty plan and an all-due-today plan are both caught up; a 5-day-overdue litter box for Wes is a "Scoop litter emergency" in the banner; a missing `activeFrom` falls back to today; the synced line), the list craft (`ListCraftTests`: the bought/to-buy split keeps its two orders and tolerates a missing `boughtAt`; undo of a delete that never left the phone un-removes the same row and sends nothing, undo of one that did inserts a copy under a new id with `bought` flagged for the PATCH that follows the create, and a synced row's pending edit survives either way; "Clear bought" empties the section and restores all of it; a meal's copy carries every field; undoing a project restores exactly the steps that cascaded with it, and rebuilds them with new ids once the server has cascaded too; `SubtaskOrder` sends one midpoint row when there is a gap, `previous + 16` at the end, `first / 2` at the front, renumbers on a stride only when there is no room, stays strictly increasing inside the server's range, and sends nothing for a no-op move; a project is finished only when it has steps and all of them are done, and ticking or deleting the last one flips it; the progress fraction; `MealDates` reads today / yesterday / the weekday / the date against a pinned Chicago calendar; removing a rejected row sends nothing; and the five-second window commits on lapse, restores on undo, and is replaced by a newer deletion), the list craft against a real pass (`ListUndoSyncTests`: undo inside the window sends no DELETE at all; undo after it went out POSTs the copy once, PATCHes `bought`, never resends the DELETE, and settles with one live row; a drag PATCHes only the step that moved, with `sortOrder` and no `title`).

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

The three list tabs share one shape (`ListParts.swift`): the tab title in the display face over a count line and the same sync status line the Tasks tab uses (`SyncCoordinator.statusLine`, so "Offline · will retry" reads the same everywhere), then a composer, then inset cards on the page color. Every row reads from SwiftData through `@Query`; every write goes through `ListActions` (store first, then `SyncCoordinator.syncSoon()`), so the tap is on screen before the network is involved and works the same offline. Every colour is a `RoostColor.Role`, every size a `RoostType.Style`, every gap a `RoostSpacing`, every corner a `RoostRadius`, every animation a `RoostMotion` — the four screen files hold no hex, no point sizes, and no loose spacing numbers.

**The composer.** A rounded field with a plus badge, its border dashed at rest and a solid accent line when focused, lifted off the page with `.roostElevation(.card)`. Return adds the line and keeps the keyboard up (`refocus`), so a shopping trip or a batch of ideas can be typed in one go; Return on a blank field clears the stray spaces and lets the keyboard go. Adding fires `RoostHaptic.selection`. `ListActions` trims text and cuts it to the server's limits (200 characters for a title, 40 for a tag, 100 first steps on a create) rather than letting the create be refused. To VoiceOver the composer is one element labelled with its placeholder plus the hint "Return adds it and keeps the keyboard up".

**Delete and undo.** Swipe left on any row. The row is soft-deleted in the store at once, but **its sync is held** for five seconds while an undo pill sits above the tab bar ("Oat milk removed · Undo"). `ListUndo` owns that window: `offer(message:restore:commit:)` starts it, tapping Undo runs `restore`, and letting it lapse — or deleting something else — runs `commit`, which is what actually kicks the sync. So the common case never sends a DELETE the server has to undo. `ListActions.restore…` still covers the case where the DELETE did go out (another trigger synced first): if `deleteReachedServer` is false the same row is simply un-removed, and if it is true a fresh copy is inserted under a new id, keeping `createdAt` and flagging `bought` / `done` so the PATCH that follows the create carries the state a create body cannot. A soft delete is permanent server-side, so re-POSTing the old id would land on the dead row; this is why the copy gets a new one.

**Rows the server refused.** A row with `rejected == true` keeps its place and shows a small notice-role "Didn't sync" marker, and its swipe action reads "Remove" rather than "Delete" — it only ever existed on this phone, so nothing is sent when it goes.

**Accessibility.** A row with a check circle is its title to VoiceOver, with the state ("Bought", "Still needed") as the value and what a tap does as the hint; "Didn't sync" joins the value so it is spoken, not just drawn. Glyph sizes are capped (`listGlyphCeiling`), and at an accessibility Dynamic Type size the badges and markers drop to their own line instead of squeezing the title, so the largest size stays legible on all three tabs. Steps, which are reordered by a drag VoiceOver cannot make, also carry "Move up" / "Move down" accessibility actions.

### Tasks

`TodayPlanner.plan` feeds `RoostCore.Scheduler` the active chores and non-removed completions, with `activeFrom` = the household start (fixed on first render as the earlier of today and the earliest completion, then persisted in `SyncState`). For each person it lists what is due, cat care first, most overdue first, followed by rows completed today so they can be un-checked. The header shows the Chicago date, the streak block, the week's tallies, and the sync status line.

**Streak header.** `StreakHeaderModel` takes the plan's per-person streaks (`RoostCore.Tallies.streak`, so `activeFrom` comes from `SyncState`) and weekly tallies. Each side shows the name, the streak number, and "day streak". The side with the strictly higher streak gets a "CURRENTLY AHEAD" tag and its number in `RoostColor.gold`; a tie tags nobody. Under the block a mono line carries the week's completions: `Anne · 14   Wes · 11`.

**Escalation.** Row color follows `EscalationStage`: due today = ink, 1–2 days = gold, 3–4 = tease, 5+ = alert, with a `ND LATE` badge when overdue. `EscalationCopy.subtitle` adds a line under the title once a row is overdue: nudge → "Still no <title>…" (title lowercased to read mid-sentence, unless it starts with an acronym like "PM wet cat food"), pointed → "The cat has feelings about this." for cat-care rows and "Getting overdue." for home rows, alert → "<Title> emergency". Due-today rows and done rows show no subtitle.

Checking a row inserts a `CompletionRecord` (UUID id, `completedAt` now, UTC) and kicks a sync. Tapping a done row soft-deletes it.

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

Header: "N items · M already bought" (total live rows, and how many are ticked). "Add an item…" inserts a `ShoppingItemRecord` with a UUID id, `addedBy` = the paired person (blank when unpaired; the server stamps it from the token and the reply overwrites it). Rows show the check circle, the title, and the adder's initial in a small `assigned` avatar.

`ShoppingSplit` does the sorting: still-to-buy rows stay newest first, and ticked rows drop into a **Bought** section below, struck through, most recently bought first. Tapping a row flips `bought` (with a local `boughtBy`/`boughtAt` preview the server's stamp replaces), flags it for PATCH, and plays `RoostTransition.checkOff` with `RoostHaptic.checkOff`; un-ticking buzzes `RoostHaptic.undo`. The Bought header carries **Clear bought**, which soft-deletes the whole section in one go (`ListActions.clearBought`) behind one undo pill that says how many went ("4 items removed") and restores all of them.

Empty, the screen reads "Nothing on the list." over "Type what you need above."

### Meals

Header: "N saved ideas". "Add an idea…" takes a title and, once there is one, a tag ("Weeknight"); Return on either field saves. Rows show a flame glyph in the mockup's meal colors, the title, and a meta line of the tag as a small chip and "last made …" when set. `MealDates.lastMade` picks the wording by distance: "today", "yesterday", the weekday inside a week ("last made Friday"), then the date ("last made Aug 30").

The meal with `nextUp` sorts first and carries a `NEXT UP` badge in the bonus role, a flame plus mono label, arriving and leaving on `RoostTransition.badge`. Swipe right for "Next up" / "Clear next up" and for **Made it**, which stamps `lastMadeAt` now; both are also in the long-press menu. Setting next-up clears it on every other local meal at once; those rows are not flagged, because the server clears them itself and the next delta confirms it.

Empty, the screen reads "No meal ideas yet." over "Save something you both like."

### Projects

Header: "N active projects". "Start a project…" takes a title and, once there is one, a "First steps, one per line" field and a Start button (Return on the title also starts). Each project is its own card: the title, a chevron, and a progress bar with "done/total" over its live steps. Tapping the card opens it (the first card opens on its own, like the mockup): the steps with check-off (strikethrough when done, `doneBy`/`doneAt` previewed locally) and an "Add a step…" row that appends after the highest `sortOrder`, the server's default.

**Progress.** `ProjectProgress` is the card's arithmetic. The bar's width and the count share one `.roostAnimation(.standard, value: progress)`, so they move together rather than racing, and the count is a `.contentTransition(.numericText(value:))` in the mono tally face, so "2/4" rolls to "3/4" a digit at a time.

**Reordering.** Steps are draggable (`.onMove` on the open card's `ForEach`; no edit mode needed). `SubtaskOrder.plan` computes the new `sortOrder` values and touches as few rows as it can: if the gap between the step's new neighbours is 2 or more it PATCHes exactly one row with the midpoint, dropping to `first / 2` at the front and `previous + 16` at the end; only when there is no room does it renumber the list on a stride of 16. Values stay integers inside the server's [0, 1_000_000], and `ListActions.reorderSubtasks` flags `.sortOrder` on just the rows whose number actually changed, so a drag is usually one PATCH carrying one field.

**Finished projects.** When the last step is ticked, `ProjectProgress.isFinished` gives the card a `DONE` chip in the success role, `RoostHaptic.milestone`, and an **Archive** row that soft-deletes the project (its steps cascade locally, and the server cascades its own). Untick a step and the chip and the row go away again.

Swipe a project or a step to delete, each with the same five-second undo; undoing a project restores the steps that were cascaded with it.

Empty, the screen reads "No projects yet." over "Name one and list its first steps."

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
