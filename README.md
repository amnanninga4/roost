# Roost

[![CI](https://github.com/amnanninga4/roost/actions/workflows/ci.yml/badge.svg)](https://github.com/amnanninga4/roost/actions/workflows/ci.yml)

A shared household app for Anne & Wes: chores, cat care, a head-to-head streak, shopping, meal ideas, and bigger projects broken into subtasks. Native iOS app, plus a small sync server the two phones share.

## What's in here

- **`Roost/`** — the iOS app (SwiftUI, SwiftData). The Xcode project is generated from `Roost/project.yml` with XcodeGen; never hand-edit the pbxproj. See `Roost/README.md`.
- **`Packages/RoostCore`** — scheduling, rotation, escalation, and streak logic. Pure Swift, no UI, no storage. See `Packages/RoostCore/README.md`.
- **`Packages/RoostDesign`** — colors, type scale, and the bundled fonts. See `Packages/RoostDesign/README.md`.
- **`server/`** — the sync server. Node 22 with the built-in SQLite, no dependencies. Runs on a home machine behind a Cloudflare Tunnel. See `server/README.md`.
- **`data/chores.json`** — the master list of recurring chores. Source of truth for both the app and the server. See `data/README.md`.
- **`roost-app-mockup.html`** and **`chore-master-list.html`** — the original concept mockup and the reference chore list the JSON came from. Open either in a browser.
- **`NOTES.md`** — decisions and how the work is organized.

## Checks

App (needs Xcode 26 and the iPhone 17 Pro simulator):

```bash
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Server:

```bash
cd server && npm test
```

Chore seed (Python 3 stdlib only):

```bash
python3 scripts/validate-chores.py
```

CI runs the app and server checks on every pull request and on `main`.

## Status

Early working build. The app runs in the simulator, pairs with the server, and syncs chore completions between two devices. Shopping, meals, and projects are being wired up. Not on TestFlight yet.
