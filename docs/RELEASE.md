# Releasing Roost to Anne's and Wes's phones

Roost goes onto the two phones through TestFlight. One script does the build and the
upload; everything else here is setup you do once.

No Team ID, key ID, certificate, provisioning profile, or APNs key is in this repo, and
none of the steps below put one there. Every placeholder on this page — `ABCDE12345`,
`00000000-0000-0000-0000-000000000000` — is made up.

Every portal path and command on this page was checked against Apple's current
documentation on **2026-09-13**, against Xcode 26.3 (build 17C529), and the pages are
linked where they are used. Apple moves things; if a step does not match what you see,
the linked page is the authority, not this file.

## Prerequisites

| What | Where it comes from | Where it lives |
|---|---|---|
| Apple Developer Program membership | [developer.apple.com/programs](https://developer.apple.com/programs/) | — |
| Xcode 26 and `xcodegen` | Mac App Store; `brew install xcodegen` | — |
| Team ID | developer.apple.com/account → Membership details | `Roost/Config/Local.override.xcconfig` (gitignored) |
| App Store Connect team API key | App Store Connect → Users and Access → Integrations | `~/.config/roost/release.env` + a `.p8` outside the repo |
| APNs Auth Key | developer.apple.com/account → Keys | theoldone, `/etc/roost/` |

A build only needs the first three. The APNs key is what makes the pushes in
`server/README.md` actually send; without it the server stays healthy and `/health`
reports `push: "no key"`.

### The Team ID

Ten letters and digits, on [developer.apple.com/account](https://developer.apple.com/account)
under **Membership details**. It is the only build setting that differs per machine, so it
lives in a gitignored file:

```bash
cp Roost/Config/Local.override.xcconfig.example Roost/Config/Local.override.xcconfig
$EDITOR Roost/Config/Local.override.xcconfig       # DEVELOPMENT_TEAM = ABCDE12345
```

`Roost/Config/Local.xcconfig` is committed, holds no values, and does one thing:
`#include? "Local.override.xcconfig"`. The `?` means "if it is there". So a checkout
without the override generates and builds exactly as CI does — no team, no signing — and a
checkout with one signs for your team. Both targets, app and widget, read it.

Nothing else belongs in that file, and `git status` should never show it.

### The bundle identifiers

Two, both explicit, both registered before the first upload:

| Bundle ID | Target | Capabilities that must be on the identifier |
|---|---|---|
| `xyz.hinescreative.roost` | the app | App Groups, Push Notifications |
| `xyz.hinescreative.roost.widget` | the widget extension | App Groups |

The widget needs App Groups and nothing else: it reads one JSON file out of the shared
container and never touches the network. The app needs Push Notifications for the server's
red alerts and handoff pushes, and App Groups to write that file.

To register each one — [Register an App ID](https://developer.apple.com/help/account/manage-identifiers/register-an-app-id)
(role: Account Holder or Admin):

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources),
   click **Identifiers**, then the add button (+).
2. Select **App IDs**, click **Continue**, confirm the type is **App**, **Continue**.
3. Put something readable in **Description** (`Roost`, `Roost Widget`).
4. Select **Explicit App ID** and enter the bundle ID exactly as in the table above. It has
   to match `PRODUCT_BUNDLE_IDENTIFIER` in `Roost/project.yml`.
5. Tick the capabilities for that identifier.
6. **Continue**, review, **Register**.

Capabilities can be changed later on an existing App ID, with one consequence worth
knowing before you need it: *"Provisioning profiles that contain a modified App ID become
invalid."* You have to regenerate the profiles that use it — see
[Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities).
`scripts/release.sh` passes `-allowProvisioningUpdates`, so in practice Xcode regenerates
them for you on the next run; the troubleshooting section below covers it when that is not
enough.

### The App Group

One group, `group.xyz.hinescreative.roost`, shared by the app and the widget. It is in both
entitlements files already (generated from `project.yml`), so all that is left is
registering it and assigning it to both App IDs.

Register it — [Register an App Group](https://developer.apple.com/help/account/manage-identifiers/register-an-app-group):

1. In Certificates, Identifiers & Profiles, click **Identifiers**, then the add button (+).
2. Select **App Groups**, **Continue**.
3. Enter a description and the identifier `group.xyz.hinescreative.roost`, **Continue**,
   **Register**.

Then assign it to each of the two App IDs — [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities):

1. Open the App ID, enable **App Groups**, click **Configure**.
2. Tick `group.xyz.hinescreative.roost`, **Continue**.
3. Review, **Assign**, **Done**.

Both identifiers must name the same group. If only one does, the app builds, installs, and
the widget is permanently blank.

### The App Store Connect API key

The script authenticates with an App Store Connect API key rather than an Apple ID, so
there is no password and no interactive prompt.

It has to be a **team** key, not an individual one:
[Creating API Keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)
says *"Individual keys aren't able to use Provisioning endpoints"*, and
`-allowProvisioningUpdates` is exactly the thing that uses them. An individual key gets you
a signing failure that does not mention keys at all.

Generating one needs an Admin account in App Store Connect:

1. In [App Store Connect](https://appstoreconnect.apple.com/), select **Users and Access**,
   then the **Integrations** tab.
2. Select **App Store Connect API** in the left column.
3. Make sure **Team Keys** is selected.
4. Click **Generate API Key** (or +).
5. Name it — the name is for you, it is not part of the key. `Roost release` will do.
6. Under **Access**, choose the role. **App Manager** is enough to upload builds and manage
   TestFlight. Admin works and grants much more than this needs.
7. **Generate**.

Then download the private half. **It is downloadable once** — Apple keeps no copy:

1. Same page, **Team Keys**.
2. Click **Download API Key** next to the new key.

You get `AuthKey_<KEYID>.p8`. Put it somewhere outside this repo. The conventional place,
which Apple's own tools search, is `~/.appstoreconnect/private_keys/`:

```bash
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_ABCDE12345.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_ABCDE12345.p8
```

The page also shows the **Key ID** and, above the table, the **Issuer ID** (a UUID) for the
whole team. The script wants three values, from the environment or from a file it reads at
`~/.config/roost/release.env`:

```bash
mkdir -p ~/.config/roost
cat > ~/.config/roost/release.env <<'EOF'
ASC_KEY_ID=ABCDE12345
ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
ASC_KEY_PATH=/Users/you/.appstoreconnect/private_keys/AuthKey_ABCDE12345.p8
EOF
chmod 600 ~/.config/roost/release.env
```

That path is outside the repo on purpose, so there is no version of this that ends with a
key in a commit. `ROOST_RELEASE_ENV` points the script at a different file if you keep
yours elsewhere. If the key is ever lost or exposed, revoke it in App Store Connect
immediately and generate another; nothing else has to change.

### The APNs Auth Key, and putting it on theoldone

This is what turns the server's pushes on. It is a different key from the App Store Connect
one, from a different page, and it is also downloadable only once.

Create it — [Create a private key](https://developer.apple.com/help/account/keys/create-a-private-key):

1. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources),
   click **Keys**, then the add button (+).
2. Under **Key Name**, something like `Roost APNs`.
3. Tick **Apple Push Notification service (APNs)**.
4. Click **Configure** next to it and choose the environment configuration and the key type
   — **Team Scoped** (works for every one of your app's topics) or **Topic Specific**
   (pinned to chosen bundle IDs). Team Scoped is the simpler choice for a two-phone
   household; Topic Specific is tighter. Either works with the server.
5. **Continue**, review, **Confirm**.
6. **Download**. You get a `.p8` in `~/Downloads`. **Done**.

Note the **Key ID** from the key's detail page. Then put the key and its description on
theoldone, where the server reads them. The shape is the one in `server/README.md`:

```bash
# on theoldone
sudo install -d -o root -g roost -m 0750 /etc/roost
sudo install -o root -g roost -m 0640 ~/AuthKey_ABCDE12345.p8 /etc/roost/AuthKey_ABCDE12345.p8

sudo tee /etc/roost/apns.json >/dev/null <<'EOF'
{
  "keyPath": "/etc/roost/AuthKey_ABCDE12345.p8",
  "keyId": "ABCDE12345",
  "teamId": "ABCDE12345",
  "bundleId": "xyz.hinescreative.roost",
  "env": "production"
}
EOF
sudo chown root:roost /etc/roost/apns.json
sudo chmod 0640 /etc/roost/apns.json
sudo systemctl restart roost.service
```

Both files are **root:roost 0640** — the `roost` user has to be able to read them, and
nobody else should. `teamId` is the same Team ID as the build.

`env` has to match how the app was signed, and this is the part that catches people:

| How the app got on the phone | `aps-environment` in the app | `env` in apns.json |
|---|---|---|
| Xcode, straight to a cabled phone | `development` | `sandbox` |
| TestFlight or the App Store | `production` | `production` |

The repo commits `aps-environment: development`, which is the honest value for a checkout
with no team, and **TestFlight rewrites it to `production` at export**. So the moment the
phones are on TestFlight builds, `/etc/roost/apns.json` needs `"env": "production"`. A
mismatch is silent in the app: the token registers fine and no push ever arrives.

Check the server took it:

```bash
curl -s https://roost.hinescreative.xyz/health | python3 -m json.tool
```

`push` reads `no key` (missing or unreadable files, sends disabled), `sandbox`, or
`production`. You want `production` once TestFlight is the delivery route. `no key` when
you have just installed one is almost always permissions — the `roost` user cannot read
`/etc/roost/apns.json` or the `.p8` it points at.

## First time, in App Store Connect

Register both App IDs first (above); you cannot pick a bundle ID here that does not exist
yet. The Account Holder also has to have signed the current agreement under **Business**,
or the + button does nothing useful.

Create the app record — [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
(role: Account Holder, Admin, or App Manager):

1. In **Apps**, click the add button (+) at the top left.
2. Select **New App**.
3. Fill in the dialog:
   - **Platforms**: iOS
   - **Name**: `Roost` — App Store names are globally unique, so if it is taken, pick
     another; it is only ever seen by the two of you in TestFlight.
   - **Primary Language**: English (U.S.)
   - **Bundle ID**: `xyz.hinescreative.roost`
   - **SKU**: anything, it is internal. `roost`.
4. Under **User Access**, **Full Access** is fine for a two-person team.
5. **Create**.

Then the internal TestFlight group —
[Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers):

1. Anne and Wes both need to be users on the App Store Connect team with a role that can
   test: **Account Holder, Admin, App Manager, Developer, or Marketing**. Invite Anne under
   **Users and Access** if she is not there, and have her accept the email.
2. In **Apps**, select Roost, click the **TestFlight** tab.
3. In the sidebar, click the add button (+) next to **Internal Testing**.
4. Name the group — `Household` — and click **Create**.
5. Open the group, click **Invite Testers**, tick Anne and Wes, **Add**.
6. Turn on **Automatic Distribution** for the group. That is what makes every later upload
   arrive on both phones without you touching App Store Connect again.

Internal testing **does not require App Review**, so there is no wait for approval and no
review to fail. Builds stay installable for **90 days**, and the group holds up to 100
testers — two is fine.

Both of you then install **TestFlight** from the App Store and accept the invitation.

## Every release after that

```bash
scripts/release.sh --dry-run     # optional: check credentials and print the plan
scripts/release.sh
```

What it does, in order: reads the Team ID and refuses without one; works out the build
number from `git rev-list --count HEAD` (or `--build N`); writes that into
`CURRENT_PROJECT_VERSION` in `Roost/project.yml` and runs `xcodegen generate`; archives the
`Roost` scheme for `generic/platform=iOS` with automatic signing and
`-allowProvisioningUpdates`; then exports and uploads with `scripts/ExportOptions.plist`.
It prints the build number and where to find it when it is done.

`--dry-run` stops before anything is written, so `git status` stays clean.

The upload is a single `xcodebuild -exportArchive` with `destination: upload` in the export
options — the same route Xcode's own **Distribute App → Upload** takes. The header of
`scripts/release.sh` records why that rather than `xcrun altool --upload-app`, and what to
fall back to if Apple changes it.

Then:

1. The build shows in **App Store Connect → Apps → Roost → TestFlight → iOS builds** as
   **Processing**. A few minutes, sometimes half an hour.
2. When processing finishes, Automatic Distribution hands it to the Household group and
   TestFlight notifies both phones. If a build is ever rejected, App Store Connect emails
   the reason — it does not appear in the app.
3. Commit the build number bump the script made on a branch and open a pull request, since
   `main` takes pull requests only.

   ```bash
   git checkout -b release-0.1.0-128
   git commit -am "Release 0.1.0 (128)"
   git push -u origin release-0.1.0-128
   ```

Roost has no export-compliance questions to answer because `ITSAppUsesNonExemptEncryption`
is already `false` in the Info.plist.

## A new phone

TestFlight puts the app on the phone; the app still has to be told which person it is and
be given a token. That is pairing, and it is the same six-digit flow as a simulator build.

1. On theoldone, mint a code for that person:

   ```bash
   sudo -u roost ROOST_DB=/var/lib/roost/roost.db \
     node /opt/roost/server/src/mkcode.js anne "Anne iPhone"
   # pairing code for anne / Anne iPhone: 048213
   # expires 2026-09-13T22:15:00.000Z (15 min); it works once
   ```

   As the `roost` user, never root — a root-run CLI leaves `roost.db-wal` owned by root and
   the API stalls on its next write. The label you type here is the half of the device name
   the household recognises, and it is what Settings shows.

2. Open Roost on the phone. With no token it starts at onboarding. Step two is six boxes:
   type the code. The sixth digit submits; there is no button. The token comes back in that
   one response and goes to the Keychain.

3. Step three names the person — that comes from the code, not a choice. Step four asks for
   notifications, which is what the server's pushes need.

The code is good for 15 minutes and works once. `404` means unknown, used, or expired: mint
another. `429` means the rate limiter, so wait a minute and retry the same code.

Afterwards, `devices.js list` on the host shows the phone, and Settings on the phone shows
the person, the label, and the pairing date. To take a phone off, use **Unpair this phone**
in Settings, or `devices.js revoke <hash prefix>` on the host.

## When it goes wrong

**"No profiles for 'xyz.hinescreative.roost' were found"**, or signing fails on the widget
while the app is fine.

Almost always a capability that is on the entitlement but not on the identifier. The
entitlements files are generated from `project.yml` and ask for App Groups (both targets)
and push (the app); the portal has to grant the same things. Check both App IDs against the
table above, in particular that **both** name `group.xyz.hinescreative.roost`. Fix the
identifier, then re-run `scripts/release.sh` — `-allowProvisioningUpdates` regenerates the
profile. Changing a capability invalidates existing profiles, so this failure is expected
the first run after an identifier edit and should not survive the second.

**The wrong team, or no team.**
`scripts/release.sh` refuses outright when `Roost/Config/Local.override.xcconfig` is missing
or blank. If it has the wrong Team ID you get an authentication or entitlement error
instead. Check what the build actually resolved:

```bash
xcodebuild -project Roost/Roost.xcodeproj -target Roost -configuration Release \
  -showBuildSettings | grep DEVELOPMENT_TEAM
xcodebuild -project Roost/Roost.xcodeproj -target RoostWidget -configuration Release \
  -showBuildSettings | grep DEVELOPMENT_TEAM
```

Both must print the same Team ID. If they print nothing, the override file is missing,
empty, or in the wrong place — it belongs at `Roost/Config/Local.override.xcconfig`, next
to the committed `Local.xcconfig`. If the App Store Connect key belongs to a different team
than the one in that file, the upload is rejected however well the archive went.

**Provisioning profile mismatch on the widget.**
The app and the extension are signed separately, and the appex is embedded in the app, so a
team or a profile that is right for one and wrong for the other fails late — after the app
has built. Both targets read the same xcconfig, so the Team ID cannot drift; what does
drift is the App Group assignment on `xyz.hinescreative.roost.widget`, which is easy to
register and then forget to configure. Re-run after fixing it. If a stale profile is
wedged, Xcode → Settings → Accounts → your team → Manage Certificates, and delete the
profiles in `~/Library/MobileDevice/Provisioning Profiles/`; they are regenerated.

**"Invalid Binary" or an upload that processes and then disappears.**
App Store Connect emails the reason. The recurring causes for an app shaped like this one
are a build number that is not higher than a build already uploaded for the same version
(pass `--build N` with something larger), and a missing icon. The build number comes from
the commit count, which only goes up, so this mostly bites after a rebase or a re-upload of
the same commit.

**"Individual keys aren't able to use Provisioning endpoints".**
The API key is an individual key. Generate a team key with the App Manager role instead;
see above.

**No pushes on a TestFlight build.**
`aps-environment` is `production` in anything TestFlight exported, so
`/etc/roost/apns.json` needs `"env": "production"`. Check
`curl -s https://roost.hinescreative.xyz/health` reports `push: "production"`. `no key`
means the server cannot read the files: both must be root:roost 0640 and `keyPath` must
point at the `.p8` that is actually there.
