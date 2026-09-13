# Roost/ — the iOS app

SwiftUI + SwiftData, iOS 18+, local store only. R-2 scaffold: it seeds the chore list and shows it. No sync, no check-off, no streaks yet.

## Layout

```
Roost/
  project.yml            XcodeGen spec — the source of truth for the project
  Roost.xcodeproj        generated; regenerate, don't hand-edit
  Sources/
    RoostApp.swift       @main: registers fonts, opens the store, seeds
    Models/Records.swift SwiftData models: ChoreRecord, CompletionRecord, SyncState
    Models/Converters.swift  record <-> RoostCore value types
    Models/ChoreSeeder.swift idempotent seed from the bundled chores.json
    Screens/ChoreListScreen.swift  the one screen, grouped by cadence
  Tests/SeedTests.swift  in-memory ModelContainer tests
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

Tests cover: 31 rows and exactly 2 pinned after seeding, re-seed keeps 31 with no duplicates, a chore dropped from the file is retired (kept for history) and restored when re-added, and record/value-type round trips.

## Store rules

- `ChoreRecord.retired` hides chores removed from the list without losing completion history.
- `CompletionRecord.id` is client-generated; the server dedupes on it. `syncedAt` stays nil until acknowledged; `deleted` is a soft flag.
- `SyncState` is a single row: `cursor` (server seq) and `choresVersion`.

Sync against `server/` is ticket R-8.
