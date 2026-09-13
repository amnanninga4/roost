# Roost

Household app for Anne and Wes. Native iOS (SwiftUI, SwiftData), a small Node sync server, two Swift packages. Read `NOTES.md` for decisions and `Roost/README.md`, `server/README.md`, `Packages/*/README.md` for how each part works.

## Layout

- `data/chores.json` is the source of truth for recurring chores; `chore-master-list.html` is where it came from. The mockup HTML is illustrative only.
- `Roost/` is the app. The Xcode project is generated: edit `Roost/project.yml`, then run `xcodegen generate` from `Roost/`. Never hand-edit the pbxproj.
- `Packages/RoostCore` is pure logic (scheduling, rotation, escalation, streaks). No UI, no storage.
- `Packages/RoostDesign` is colors, type, and fonts. The app palette is the mockup's `.app-shell` block.
- `server/` runs on theoldone behind a Cloudflare Tunnel. Node 22, built-in sqlite, no dependencies.

## Working rules

- `main` takes pull requests only. Open the PR, do not merge it yourself.
- Rebase onto current `main` before opening a PR. Parallel branches that both regenerate the Xcode project will conflict on the pbxproj; resolve by running `xcodegen generate` on the merged tree.
- Before calling app work done: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` prints `** TEST SUCCEEDED **`, and any new or changed screen has been rendered in the simulator and looked at.
- Before calling server work done: `cd server && npm test` passes with no network.
- Swift files are formatted by swiftformat and linted by swiftlint through the committed hook in `.claude/hooks`. Configs are `.swiftformat` and `.swiftlint.yml`.
- User-facing strings live in `Roost/Sources/Strings.swift`. Plain wording, no marketing copy.
- No secrets in the repo: no Team ID, certificates, provisioning profiles, APNs keys, or device tokens.
- Do not seed shopping, meals, or projects from the mockup. They start empty.

## Product bar

A polished app for a couple, not a template. Use the installed SwiftUI skills (`swiftui-expert-skill`, `swiftui-pro`, `ios-the-final-5-percent`, `ios-interaction-primitives-design`, `motion-design`) when designing or reviewing screens. Prefer native APIs over dependencies; the only approved third-party UI dependency so far is ConfettiSwiftUI.
