# server/ — Roost sync API

Small HTTP API the phones sync against. Node 22+ with the built-in `node:sqlite`, no npm dependencies. One process, one SQLite file.

Runs on theoldone, bound to `127.0.0.1:8790`. Public path is a Cloudflare Tunnel at `https://roost.hinescreative.xyz`. Tailscale is the admin path only.

## Model

- **chores** — mirror of `data/chores.json`, seeded on every start (idempotent upsert; ids missing from the file are marked retired, hidden from clients, kept for history). `choresVersion` comes from the JSON `version` field; bump it when the list changes so clients refetch.
- **completions** — `{ id, choreId, person, completedAt, createdAt, updatedAt, deleted, seq }`. `id` is client-generated (1-64 chars of `A-Z a-z 0-9 . _ ~ : @ + -`) so an offline queue can replay a POST safely. Deletes are soft so they propagate through sync deltas. `seq` is a monotonic counter bumped on every insert and delete; it is the sync cursor.
- **shopping** — `{ id, title, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, deleted, seq }`. `addedBy` comes from the token. `bought: true` stamps `boughtBy` (token) and `boughtAt` on the false→true transition (a replayed PATCH keeps the first stamp); `bought: false` clears both.
- **meals** — `{ id, title, tag, lastMadeAt, nextUp, createdAt, updatedAt, deleted, seq }`. `tag` is a freeform string of 0-40 chars (e.g. `"Weeknight"`), default `""`. `lastMadeAt` is ISO UTC or null. `nextUp` is exclusive: setting it true clears it on every other live meal, and each cleared row takes its own `seq` so the change rides the delta.
- **projects** — `{ id, title, createdAt, updatedAt, deleted, seq }`. Deleting a project soft-deletes every live subtask under it, each with its own `seq`; the project takes the last one, so a cursor at the project's `seq` covers the whole cascade.
- **subtasks** — `{ id, projectId, title, sortOrder, done, doneBy, doneAt, createdAt, updatedAt, deleted, seq }`. `done: true` stamps `doneBy` (token) and `doneAt` on the transition; `done: false` clears both. `sortOrder` is a non-negative integer, defaulting to one past the project's highest live subtask.
- **bonus** — `{ id, title, points, claimBy, claimedBy, claimedAt, assignedTo, completedAt, createdBy, createdAt, updatedAt, deleted, seq }`. A one-off "first to claim" task. `points` is an integer 1-10, `claimBy` an ISO UTC deadline (stored normalised to milliseconds), `createdBy` comes from the token. The first person to claim it holds it (`claimedBy`, `claimedAt`); the other person's claim is `409`. Left unclaimed past `claimBy`, it is auto-assigned (`assignedTo`) to the person with fewer bonus points earned in the current Chicago week; a tie goes to the person who did not create it. Auto-assign runs at the start of every `/sync` (and `GET /bonus`), so it needs no timer, and each assignment takes its own `seq` so it reaches both phones. Only `claimedBy` or `assignedTo` may complete it (`403` for anyone else); its points then count for that person in the week of `completedAt`. Deleted tasks earn nothing. Code in `src/bonus.js`.
- **devices** — hash of each token that has been seen, with person, label, lastSeen.
- **pairing codes** — `{ code, person, deviceLabel, createdAt, expiresAt, consumedAt, tokenHash }`. A 6-digit code minted by `src/mkcode.js` that a phone trades for a bearer token at `POST /pair`. Live 15 minutes by default, usable once, unique among the live ones (a consumed or expired number can be drawn again). A consumed row keeps the SHA-256 of the token it produced, so a device traces back to the code that paired it.
- **paired tokens** — `{ tokenHash, person, label, createdAt, revokedAt }`. The SHA-256 of every token minted by `POST /pair`, which is where paired credentials live: the API never writes the tokens file. Read live on every request, so pairing and revoking both take effect on the next one. Revoked rows are kept, not deleted.

Neither table is synced, so neither has a `seq`. Both live in `src/pairing.js`.

Every list row follows the completions rules: client-generated `id` validated by the same pattern, a POST replay for an existing id returns `200` with the stored row untouched (deleted rows included — no resurrection), deletes are soft and idempotent, and PATCH/DELETE on an unknown id is `404`. Titles are 1-200 chars. All six tables share the ONE `seq` counter, so a single `/sync` call carries every delta in order. No seed data: lists start empty.

All stored times are ISO-8601 UTC. Chicago-time rules (due today, streaks, escalation) belong to the app and RoostCore, not the server. The one exception is the bonus auto-assign tally, which needs the current week on the server: Monday 00:00 to the next Monday 00:00 in America/Chicago, the same bounds as `RoostCore.HouseholdCalendar.weekBounds`.

## Auth

Bearer device tokens, no accounts. `/etc/roost/tokens.json`:

```json
{
  "<token>": { "person": "anne", "device": "Anne iPhone · Anne iPhone 15" },
  "<token>": { "person": "wes",  "device": "Wes iPhone · 16 Pro" }
}
```

The file is re-read when it changes, and the API only ever **reads** it: `root:roost 0640`, written by hand with `mktoken.js`, and the unit keeps `/etc` read-only (`ProtectSystem=strict`). A file that fails to parse is logged once, shown as `tokensFileError` in `/health`, and the last good set stays active until it is fixed.

Tokens minted by pairing go in the `paired_tokens` table instead, and a lookup checks the file first, then that table. Rewriting a credential file from inside a request is not atomic — a crash or a full disk mid-write truncates it and locks every device out after the next restart — and a row is also cheaper to revoke: no file edit, no restart, effective on the next request.

### Pairing a phone

Nobody types a 43-character token into a phone. Mint a short-lived code on the host instead:

```bash
sudo -u roost ROOST_DB=/var/lib/roost/roost.db node /opt/roost/server/src/mkcode.js anne "Anne iPhone" [--minutes 15]
# pairing code for anne / Anne iPhone: 048213
# expires 2026-09-13T22:15:00.000Z (15 min); it works once
```

Run the DB tools as the `roost` user, never as root: a root-run CLI leaves `roost.db-wal` and `-shm` owned by root and the service stalls on its next write.

The phone posts that code with its own device name and gets a real token back:

```bash
curl -sS https://roost.hinescreative.xyz/pair -H 'content-type: application/json' \
  -d '{"code":"048213","deviceName":"Anne iPhone 15"}'
# { "token": "…", "person": "anne" }
```

The token's hash is stored in `paired_tokens` with the label `<mkcode label> · <deviceName>`, and the code is spent in the same transaction — so a failure leaves the code live rather than spending it on a token nobody received. It authenticates on the very next request; nothing is reloaded, because that table is read live.

Using the code again is `404 invalid or expired code`, the same answer an unknown or an expired code gets, so a guesser learns nothing from which it was. Two limits sit in front of it, both per minute, both `429`: **10 answered attempts per source address** (`CF-Connecting-IP` behind the tunnel, then `X-Forwarded-For`, then the socket) and **30 across every address**. The global cap is the one that matters: 6 digits is 1,000,000 values, so 30 a minute bounds a 15-minute code to about 450 guesses, roughly 1 in 2,200, however many addresses they come from. `/health` reports `pendingCodes`.

Fallback: `src/mktoken.js` still mints a token straight into the tokens file, for a device that cannot use the pairing screen, or to get back in when the API is not answering. It is the one path that writes that file, and it runs as root:

```bash
sudo ROOST_TOKENS=/etc/roost/tokens.json node /opt/roost/server/src/mktoken.js anne "Anne iPhone"
```

Either way the token prints once. The server stores only its SHA-256.

### Seeing and cutting off devices

```bash
sudo -u roost ROOST_DB=/var/lib/roost/roost.db ROOST_TOKENS=/etc/roost/tokens.json \
  node /opt/roost/server/src/devices.js list
# source  hash      person  label                         lastSeen
# paired  3f9a1c2d  anne    Anne iPhone · Anne iPhone 15  2026-09-13T22:31:04.220Z
# file    a1b2c3d4  wes     Wes iPhone                    2026-09-13T22:12:55.101Z
sudo -u roost ROOST_DB=/var/lib/roost/roost.db node /opt/roost/server/src/devices.js revoke 3f9a1c2d
```

`revoke` takes a hash prefix (4+ hex characters, unambiguous) and works on paired tokens only; a `file` device is refused with a pointer to the tokens file. A revoked token's next request is `401`. A phone can do the same for itself with `DELETE /pair/self`, which is `403` for a hand-minted token.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | no | `{ ok, serverTime, choresVersion, choresSeeded, cursor, devices, pendingCodes, tokensFileError, push, rev, activeFrom, digestLastSent }` |
| POST | `/pair` | no | body `{ code, deviceName }` → `{ token, person }`; one `404 invalid or expired code` for unknown, already used and expired alike; `400` unless `code` is 6 digits and `deviceName` is 1-60 chars; `429` over 10 answered attempts a minute from one address or 30 across all of them |
| DELETE | `/pair/self` | yes | unpairs the calling device: its `paired_tokens` row is marked revoked, its `devices` row is dropped, and the next request with it is `401`; `403` for a hand-minted token, which only the tokens file can revoke |
| GET | `/chores` | yes | full list + version |
| GET | `/me` | yes | `{ person, label, source, createdAt, lastSeen }` — `source` is `file` or `paired`; `createdAt` from `paired_tokens` when paired, else `null`; `lastSeen` from the `devices` table (null until first touch) |
| GET | `/completions?cursor=<n>` | yes | rows with `seq > cursor`, deleted rows included with `deleted: true` |
| POST | `/completions` | yes | body `{ id, choreId, completedAt }`; person comes from the token; `201` new, `200` replay |
| DELETE | `/completions/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/shopping` | yes | body `{ id, title }`; `addedBy` from the token; `201` new, `200` replay |
| PATCH | `/shopping/:id` | yes | body `{ title?, bought? }`; at least one field; `bought: true` stamps `boughtBy`/`boughtAt`, `false` clears them |
| DELETE | `/shopping/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/meals` | yes | body `{ id, title, tag?, lastMadeAt?, nextUp? }`; `201` new, `200` replay |
| PATCH | `/meals/:id` | yes | body `{ title?, tag?, lastMadeAt?, nextUp? }`; `lastMadeAt: null` clears it; `nextUp: true` clears every other meal |
| DELETE | `/meals/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/projects` | yes | body `{ id, title, subtasks?: [{ id, title }] }` (max 100, created in order with `sortOrder` 0..n); response includes `subtasks`; `201` new, `200` replay (extra subtasks on a replay are ignored) |
| PATCH | `/projects/:id` | yes | body `{ title? }`; response includes `subtasks` |
| DELETE | `/projects/:id` | yes | soft delete, cascades to its live subtasks; response includes `subtasks` with their new `seq`s; idempotent, `404` if unknown |
| POST | `/projects/:id/subtasks` | yes | body `{ id, title, sortOrder? }`; `400` if the project is unknown or deleted; `201` new, `200` replay |
| PATCH | `/subtasks/:id` | yes | body `{ title?, done?, sortOrder? }`; `done: true` stamps `doneBy`/`doneAt`, `false` clears them |
| DELETE | `/subtasks/:id` | yes | soft delete, idempotent, `404` if unknown |
| GET | `/bonus?cursor=<n>` | yes | rows with `seq > cursor`, deleted rows included; runs auto-assign first |
| POST | `/bonus` | yes | body `{ id, title, points, claimBy }`; `createdBy` from the token; `201` new, `200` replay |
| POST | `/bonus/:id/claim` | yes | first claim wins: `200` (a repeat by the same person is a `200` replay); `409` when the other person holds it (`claimedBy` in the body) or the deadline has passed / it was auto-assigned; `404` unknown or deleted |
| POST | `/bonus/:id/complete` | yes | `claimedBy` or `assignedTo` only: `200` (repeat is a `200` replay); `403` for anyone else, including on an unclaimed task; `404` unknown or deleted |
| DELETE | `/bonus/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/handoffs` | yes | body `{ id, choreId, to, periodIndex?, cadence? }`; `from` from the token; `201` new pending, `200` replay; on create, push notifies `to` |
| POST | `/handoffs/:id/accept` | yes | `to` person only; `200`; on a real pending→accepted transition, push notifies `from` |
| POST | `/handoffs/:id/decline` | yes | `to` person only; `200`; on a real pending→declined transition, push notifies `from` |
| GET | `/sync?cursor=<n>&choresVersion=<v>` | yes | one call: `serverTime`, `person`, `choresVersion`, `cursor`, then `completions`, `shopping`, `meals`, `projects`, `subtasks`, `bonus`, `handoffs` (every row with `seq > cursor`, deleted rows with `deleted: true`), and `chores` only when the client's version differs. Expired bonus tasks are auto-assigned and past-period open handoffs are expired before the response is built, so those updates ride this same delta |

Validation is `400` with an `error` message: ids outside the pattern, missing or empty titles, titles over 200 chars, tags over 40, non-ISO dates, non-boolean flags, non-integer `sortOrder`, bonus `points` that are not an integer 1-10, an empty PATCH body, an unknown `projectId`, or a subtask id that already exists. Bad ids in a path simply do not route (`404`). A bonus `claimBy` already in the past is accepted (an offline POST replayed late) and assigned on the next sync.

Client loop: start with `cursor=0`, store the `cursor` from each `/sync`, pass it back next time. Replay queued POSTs first, then sync. The cursor is a counter, not a time, so same-millisecond writes and clock changes cannot drop rows. The returned `cursor` is the highest `seq` in the response across all six arrays, and holds at the client's value when nothing changed.

## Run locally

```bash
cd server
ROOST_DB=/tmp/roost.db ROOST_TOKENS=/tmp/tokens.json npm start
ROOST_DB=/tmp/roost.db npm run mkcode -- anne "Anne iPhone"
ROOST_DB=/tmp/roost.db ROOST_TOKENS=/tmp/tokens.json npm run devices -- list
npm test
```

## Deploy (theoldone)

```bash
# first time
gh repo clone amnanninga4/roost ~/roost && cd ~/roost
# every deploy
git pull --ff-only && sudo server/install.sh
```

The script creates the `roost` system user, `/opt/roost` (code), `/var/lib/roost` (DB), `/etc/roost/tokens.json` (0640 root:roost, created empty once, never overwritten, read-only to the API), `/var/backups/roost`, installs `roost.service` plus the nightly backup / offsite / verify timers, and restarts the API. Re-run it to deploy a new version.

### Ops: backup, verify, restore drill

- **Backup** — `roost-backup.timer` runs `backup.sh` at 03:30 host-local (theoldone is America/Chicago) via SQLite's online backup, keeping 30 files in `/var/backups/roost`.
- **Offsite** — `roost-offsite.timer` runs `offsite-backup.sh` at 04:00 host-local and copies the newest file to the grater at `/mnt/storage-sdd/backups/roost/` over the tailnet, also keeping 30.
- **Verify** — `roost-verify.timer` runs `verify-backup.sh` at 04:30 host-local as `User=roost`. It picks the newest `/var/backups/roost/roost-*.db`, runs `src/backupcheck.js` (PRAGMA integrity_check + `meta.seq` cursor + expected tables), and fails closed if none exist or the check fails. Manual: `sudo -u roost /opt/roost/server/verify-backup.sh`.
- **Restore drill** — `restore.sh` verifies a backup then copies it to a non-live path under `/tmp/roost-restore-drill` by default. It refuses to overwrite `/var/lib/roost/roost.db` unless you pass `--live` (and still only prints stop/start reminders — it does not manage the service for you):

```bash
# safe drill (default destination under /tmp/roost-restore-drill)
/opt/roost/server/restore.sh /var/backups/roost/roost-YYYY-MM-DD.db

# live restore (stop the API first)
sudo systemctl stop roost.service
sudo -u roost /opt/roost/server/restore.sh /var/backups/roost/roost-YYYY-MM-DD.db \
  --to /var/lib/roost/roost.db --live
sudo systemctl start roost.service
```

Logs: `journalctl -u roost -f`. Verify runs: `journalctl -u roost-verify -f`.

## Push (APNs)

Optional. Without a key on the host, the API stays healthy and `/health` reports `push: "no key"`; sends are no-ops that log once and never throw.

### Host files (never in git)

`/etc/roost/apns.json` (root:roost `0640`):

```json
{
  "keyPath": "/etc/roost/AuthKey_XXXXXXXXXX.p8",
  "keyId": "XXXXXXXXXX",
  "teamId": "XXXXXXXXXX",
  "bundleId": "xyz.hinescreative.roost",
  "env": "sandbox"
}
```

`env` is `"sandbox"` or `"production"`. Put the matching `.p8` next to the JSON (path in `keyPath`), also **root:roost `0640`**. The process user `roost` must be able to read both.

### Health

`GET /health` includes `push`:

| Value | Meaning |
|---|---|
| `no key` | `apns.json` or `.p8` missing/invalid; sends disabled |
| `sandbox` | key loaded, sandbox APNs host |
| `production` | key loaded, production APNs host |

### Register / unregister

Authenticated device:

- `POST /push/token` `{ "token": "<64-hex>", "platform": "ios" }` — upsert
- `DELETE /push/token` `{ "token": "<64-hex>" }` — unregister (own tokens only)

Dead tokens are pruned automatically when APNs returns `410`, or `400` with reason `BadDeviceToken` / `DeviceTokenNotForTopic`.

### Behaviour

- Completion create notifies the other person (`apns-expiration` = now+3600 seconds).
- Handoff offer (201 only) notifies `to`; accept/decline (real state change only) notify `from`. Bodies use display names (Anne/Wes) and a period phrase from cadence (`today` / `this week` / `this month`). All handoff pushes set `apns-collapse-id: handoff-<id>`. Expiry is silent — no push when `expireOpenHandoffs` runs.
- Every 15 minutes, stage ≥ 3 overdue chores notify the assignee's partner (`apns-collapse-id` = `red-<choreId>`). Sent pairs are stored in `push_alerts` so restarts do not re-blast.
- At/after 08:00 America/Chicago, one push per person with anything due today or overdue (`apns-collapse-id digest-<person>`). Expires at the next Chicago midnight. Meta `digestLastSent` (Chicago date) prevents resends across restarts; nobody with zero items gets one. Exposed on `GET /health` and `GET /status.json` as a YYYY-MM-DD string or `null`.
