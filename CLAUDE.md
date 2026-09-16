# Roost (test clone for Apple-Dev-3)

Household app for Anne and Wes. This clone runs tests only. Read `NOTES.md`, `Roost/README.md`, `server/README.md`.

- Xcode project is generated: edit `Roost/project.yml`, run `xcodegen generate`. Never hand-edit the pbxproj.
- App done means `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' test` prints `** TEST SUCCEEDED **`. Server done means `cd server && npm test` passes offline.
- Never run two xcodebuild test runs at once on this Mac.
- No secrets in the repo: Team ID, certs, profiles, APNs keys, device tokens, UDIDs.
- Strings in `Roost/Sources/Strings.swift`, plain wording.
