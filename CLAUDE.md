# Roost

Household app for Anne and Wes. Native iOS (SwiftUI, SwiftData), a small Node sync server, two Swift packages. Read `NOTES.md` for decisions and `Roost/README.md`, `server/README.md`, `Packages/*/README.md` for how each part works. `docs/STATUS.md` is what is running right now — regenerate it with `scripts/status-report.sh` rather than trusting its timestamp.

## Layout

- `data/chores.json` is the source of truth for recurring chores. `scripts/validate-chores.py` pins its version, counts, and pinned assignments — a change that does not update the validator fails CI.
- `Roost/` is the app. The Xcode project is generated: edit `Roost/project.yml`, then run `xcodegen generate` from `Roost/`. **Never hand-edit the pbxproj.**
- `Packages/RoostCore` is pure logic (scheduling, rotation, escalation, streaks). No UI, no storage. `server/src/rules.js` mirrors it for the digest and push — the two must stay in lockstep, and a cross-language differential over a few months of dates is the only thing that has ever caught them drifting.
- `Packages/RoostDesign` is colors, type, fonts, motion and haptics. Tokens live in `RoostColor.swift` and `RoostType.swift`.
- `server/` runs on theoldone behind a Cloudflare Tunnel. Node 22, built-in sqlite, no dependencies. Run it as the `roost` user, never root — a root-owned `roost.db-wal` stalls the service.

## Who does what

Wes has no teammates. Nothing waits on a human review that is never going to happen.

- **Fable** plans, reviews, merges, and tickets. It merges its own work on green CI — **no PR waits for Wes.** He can read any of them; nothing stalls if he does not.
- **Cursor** (`agent`, the CLI) writes the code, driven from a ticket. `agent -p --trust --model <model> "<task>"`. `--trust` is required per directory or it exits 1 with "Workspace Trust Required", which reads like a hang. Pick the model per ticket on capability, not on the `-fast` suffix — it does not predict wall clock.
- **Apple-Dev-3** (a Grok Bot seat) runs Cursor on the Air and verifies its output before reporting. Relaying an unverified claim is worse than not relaying at all.
- **Wes** decides taste and product questions. Those reach him as **a question in chat**, never as a PR in a queue.

Still ask before: anything irreversible, anything that spends money, anything outward-facing.

## Working rules

- Branch, push, let CI run, merge on green. Rebase onto current `main` first. Parallel branches that both regenerate the Xcode project conflict on the pbxproj; resolve by running `xcodegen generate` on the merged tree.
- Before calling app work done: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test` prints `** TEST SUCCEEDED **`, and any new or changed screen has been rendered in the simulator and looked at.
- Before calling server work done: `cd server && npm test` passes with no network.
- Swift files are formatted by swiftformat and linted by swiftlint through the committed hook in `.claude/hooks`. Configs are `.swiftformat` and `.swiftlint.yml`.
- Agent worktrees live under `.claude/worktrees/`, and swiftformat applies the main clone's config there, so `.swiftformat` must not exclude `.claude`. Run whole-tree formatting only in CI or from a fresh worktree outside the clone; the hook formats one file at a time.
- User-facing strings live in `Roost/Sources/Strings.swift`. Plain wording, no marketing copy. The app does not greet — it names the thing. Anne edits this file directly, so nothing user-visible may be assembled from fragments elsewhere.
- No secrets in the repo: no Team ID, certificates, provisioning profiles, APNs keys, device tokens, **or device UDIDs**. The Team ID lives only in gitignored `Roost/Config/Local.override.xcconfig`. `docs/STATUS.md` is generated into a **public** repo — anything a script prints there is published.
- Do not seed shopping, meals, or projects from the mockup. They start empty. Design for that: a screen that greets a new household with empty cards is a promise the data cannot keep.

## Traps on this machine

Every one of these has cost real time. None are obvious from reading the code.

- **Never run two `xcodebuild` test runs at once.** Fable and Apple-Dev-3 share this Mac and its simulators. Concurrent runs against one simulator is the only thing that has genuinely broken it. Serialize.
- **Pin `OS=26.3.1` in every destination.** The Mac carries iOS 26.3 and 27.0; `OS:latest` resolves to 27.0, which has no iPhone 17 Pro. Unpinned destinations fail with "Unable to find a device matching the provided destination specifier" — a red run that has nothing to do with the diff.
- **Push and merge `.github/workflows/**` over SSH.** The HTTPS remote uses gh's OAuth token, which GitHub refuses on workflow files without the `workflow` scope — on the merge API as well as on push. An SSH key is not an OAuth app and is not checked. `remote.origin.pushurl` is set to SSH in the main clones.
- **CI is the authority when it disagrees with this machine.** CI runs Xcode 26.6; the Mac is on 27.0. Local green does not prove CI green.
- **The app job takes ~18 minutes.** Every merge decision is that far away. The `packages (swift test)` and `server` jobs run in parallel and finish in about a minute.
- **Cursor's first call on a machine pays ~70s of cold start.** Never benchmark on a cold path.

## Product bar

A polished app for a couple, not a template. Use the installed SwiftUI skills (`swiftui-expert-skill`, `swiftui-pro`, `ios-the-final-5-percent`, `ios-interaction-primitives-design`, `motion-design`) when designing or reviewing screens — they are not decoration, they have changed real decisions here. Prefer native APIs over dependencies; the only approved third-party UI dependency so far is ConfettiSwiftUI.
