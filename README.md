# Roost

[![CI](https://github.com/amnanninga4/roost/actions/workflows/ci.yml/badge.svg)](https://github.com/amnanninga4/roost/actions/workflows/ci.yml)

A shared household app for Anne & Wes: chores, cat care, a head-to-head streak, shopping, a wishlist, meal ideas, and bigger projects broken into subtasks. Native iOS app, plus a small sync server the two phones share.

## What's in here

- **`Roost/`** — the iOS app (SwiftUI, SwiftData). The Xcode project is generated from `Roost/project.yml` with XcodeGen; never hand-edit the pbxproj. See `Roost/README.md`.
- **`Packages/RoostCore`** — scheduling, rotation, escalation, and streak logic. Pure Swift, no UI, no storage. See `Packages/RoostCore/README.md`.
- **`Packages/RoostDesign`** — colors, type scale, and the bundled fonts. See `Packages/RoostDesign/README.md`.
- **`server/`** — the sync server. Node 22.13+ with the built-in SQLite, no dependencies. Runs on a home machine behind a Cloudflare Tunnel. See `server/README.md`.
- **`data/chores.json`** — the master list of recurring chores. Source of truth for both the app and the server. See `data/README.md`.
- **`roost-app-mockup.html`** and **`chore-master-list.html`** — the original concept mockup and the reference chore list the JSON came from. Open either in a browser.
- **`NOTES.md`** — decisions and how the work is organized.
- **`docs/RELEASE.md`** — how a build gets onto the two phones through TestFlight: what to set up once in the developer portal and App Store Connect, where the Team ID and keys live (never in here), and `scripts/release.sh`.

## Checks

App (needs Xcode 26 and the iPhone 17 Pro simulator):

```bash
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test
```

Server:

```bash
nvm use
cd server && npm test
```

Chore seed (Python 3 stdlib only):

```bash
python3 scripts/validate-chores.py
```

CI runs the app and server checks on every pull request and on `main`.

## Releasing

`scripts/release.sh` archives the app, uploads it to App Store Connect, and TestFlight hands it to both phones. It needs a Team ID in `Roost/Config/Local.override.xcconfig` (gitignored) and an App Store Connect API key outside the repo; it refuses to run without them. `docs/RELEASE.md` is the runbook — first-time setup, the day-to-day loop, pairing a new phone, and the errors people actually hit.

```bash
scripts/release.sh --dry-run     # check everything, change nothing
scripts/release.sh
```

## Status

The app has Home, Lists, and More tabs, pairs with the server by six-digit code, and syncs chores, shopping, wishlist, meals, projects, bonus, and handoffs. Home shows both people side by side. `docs/STATUS.md` is a generated server and GitHub snapshot; regenerate it before relying on it. `OPEN-ITEMS.md` tracks unresolved work. TestFlight 0.1.0 (376) was verified available to the Household group on 2026-09-21; Anne and Wes are both members. Availability does not prove each phone has installed that build. See `docs/RELEASE.md` for the release process.
