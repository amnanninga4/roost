# server/ — Roost sync API

Small HTTP API the phones sync against. Node 22+ with the built-in `node:sqlite`, no npm dependencies. One process, one SQLite file.

Runs on theoldone, bound to `127.0.0.1:8790`. Public path is a Cloudflare Tunnel at `https://roost.hinescreative.xyz`. Tailscale is the admin path only.

## Model

- **chores** — mirror of `data/chores.json`, seeded on every start (idempotent upsert; ids missing from the file are marked retired, hidden from clients, kept for history). `choresVersion` comes from the JSON `version` field; bump it when the list changes so clients refetch. `season` (`{ months: [1..12] }` or null), `together` (boolean), `weekdays` (JSON array of ISO weekdays Mon=1…Sun=7, or null), and `dueDay` (1–28 or null) come from the file; the rules module applies them (a seasonal chore is due only in periods that start in season; a together chore is one row per person, one completion clears both, credit for both, no handoffs; `dueWindow` / `hasWindow` narrow owed days inside the period — weekday range for weekly, seven days ending on `dueDay` for month-based).
- **completions** — `{ id, choreId, person, completedAt, createdAt, updatedAt, deleted, seq }`. `id` is client-generated (1-64 chars of `A-Z a-z 0-9 . _ ~ : @ + -`) so an offline queue can replay a POST safely. Deletes are soft so they propagate through sync deltas. `seq` is a monotonic counter bumped on every insert and delete; it is the sync cursor.
- **shopping** — `{ id, title, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, deleted, seq }`. `addedBy` comes from the token. `bought: true` stamps `boughtBy` (token) and `boughtAt` on the false→true transition (a replayed PATCH keeps the first stamp); `bought: false` clears both.
- **meals** — `{ id, title, tag, lastMadeAt, nextUp, createdAt, updatedAt, deleted, seq }`. `tag` is a freeform string of 0-40 chars (e.g. `"Weeknight"`), default `""`. `lastMadeAt` is ISO UTC or null. `nextUp` is exclusive: setting it true clears it on every other live meal, and each cleared row takes its own `seq` so the change rides the delta.
- **projects** — `{ id, title, dueOn, createdAt, updatedAt, deleted, seq }`. `dueOn` is a Chicago calendar day (`2026-09-20`) or null, set on create or PATCH and cleared with null. Deleting a project soft-deletes every live subtask under it, each with its own `seq`; the project takes the last one, so a cursor at the project's `seq` covers the whole cascade.
- **subtasks** — `{ id, projectId, title, sortOrder, assignee, done, doneBy, doneAt, createdAt, updatedAt, deleted, seq }`. `done: true` stamps `doneBy` (token) and `doneAt` on the transition; `done: false` clears both. `sortOrder` is a non-negative integer, defaulting to one past the project's highest live subtask. `assignee` is `anne`, `wes` or null: who the step is meant for. Completing it stamps `doneBy` with whoever did it; the two can differ.
- **wishlist** — `{ id, title, priceCents, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, deleted, seq }`. Shopping with a price: `priceCents` is null or an integer 0–99,999,999 (whole cents), settable on create and PATCH, cleared with null. `bought` stamps and clears exactly as shopping does.
- **bonus** — `{ id, title, points, claimBy, claimedBy, claimedAt, assignedTo, completedAt, createdBy, createdAt, updatedAt, deleted, seq }`. A one-off "first to claim" task. `points` is an integer 1-10, `claimBy` an ISO UTC deadline (stored normalised to milliseconds), `createdBy` comes from the token. The first person to claim it holds it (`claimedBy`, `claimedAt`); the other person's claim is `409`. Left unclaimed past `claimBy`, it is auto-assigned (`assignedTo`) to the person with fewer bonus points earned in the current Chicago week; a tie goes to the person who did not create it. Auto-assign runs at the start of every `/sync` (and `GET /bonus`), so it needs no timer, and each assignment takes its own `seq` so it reaches both phones. Only `claimedBy` or `assignedTo` may complete it (`403` for anyone else); its points then count for that person in the week of `completedAt`. Deleted tasks earn nothing. Code in `src/bonus.js`.
- **handoffs** — `{ id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq }`. Offer a chore turn to the other person for one period. `state` is `pending` | `accepted` | `declined` | `expired`. `fromPerson` comes from the token; `periodIndex` and `cadence` may be omitted (server fills from the chore + now) but must not invent a different cadence or a future period. Cadence validation accepts `daily|weekly|biweekly|monthly|bimonthly|quarterly`. Together chores cannot be handed off (`400`). Past-period open offers expire at the start of `/sync` (and on the status board), each taking its own `seq`. Soft-deleted like the other lists. Code in `src/handoffs.js`.
- **devices** — hash of each token that has been seen, with person, label, lastSeen.
- **pairing codes** — `{ code, person, deviceLabel, createdAt, expiresAt, consumedAt, tokenHash }`. A 6-digit code minted by `src/mkcode.js` that a phone trades for a bearer token at `POST /pair`. Live 15 minutes by default, usable once, unique among the live ones (a consumed or expired number can be drawn again). A consumed row keeps the SHA-256 of the token it produced, so a device traces back to the code that paired it.
- **paired tokens** — `{ tokenHash, person, label, createdAt, revokedAt }`. The SHA-256 of every token minted by `POST /pair`, which is where paired credentials live: the API never writes the tokens file. Read live on every request, so pairing and revoking both take effect on the next one. Revoked rows are kept, not deleted.

**Schema versions.** `meta.schemaVersion` (4). `db.js` `migrate` runs on open, before seeding; v2 rebuilt `chores` and `handoffs` to widen the cadence CHECK and add season/together; v3 added `projects.dueOn` and `project_subtasks.assignee` with `ALTER TABLE … ADD COLUMN`; v4 added `chores.weekdays` and `chores.dueDay` the same way. A fresh database gets the current shape and only records the version.

Neither table is synced, so neither has a `seq`. Both live in `src/pairing.js`.

Every list row follows the completions rules: client-generated `id` validated by the same pattern, a POST replay for an existing id returns `200` with the stored row untouched (deleted rows included — no resurrection), deletes are soft and idempotent, and PATCH/DELETE on an unknown id is `404`. Titles are 1-200 chars. All eight sync tables (completions, shopping, meals, projects, subtasks, wishlist, bonus, handoffs) share the ONE `seq` counter, so a single `/sync` call carries every delta in order. No seed data: lists start empty.

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

### Household start date

`meta.activeFrom` is the Chicago calendar day the household started (streaks and overdue floor). Every `/sync` carries it. Print or set it with `src/household.js` (run as `roost`, never as root):

```bash
sudo -u roost ROOST_DB=/var/lib/roost/roost.db node /opt/roost/server/src/household.js active-from
# activeFrom: 2026-09-07 (default)   # or (meta) when set
sudo -u roost ROOST_DB=/var/lib/roost/roost.db node /opt/roost/server/src/household.js active-from 2026-09-07
# activeFrom set to 2026-09-07
```

Unset meta falls back to the code default (`2026-09-07`). The first successful `POST /pair` or `mktoken` stamps today's Chicago date if unset; later ones leave it alone. Setting it by hand changes what both phones treat as overdue.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | no | `{ ok, serverTime, choresVersion, choresSeeded, cursor, devices, pendingCodes, tokensFileError, push, rev, activeFrom, digestLastSent, backup }` — `devices` is file tokens + unrevoked paired tokens; `backup` is `{ at, ok, seq }` from the nightly verify status file, or `null` if absent/unparseable |
| GET | `/status` | no | kitchen status board HTML (names/titles only); refreshes itself |
| GET | `/status.json` | no | same board as JSON — see field list below |
| GET | `/favicon.ico` | no | tiny SVG icon |
| GET | `/fonts/<file>` | no | allowlisted RoostDesign `.ttf` only; `404` on anything else; immutable cache on 200 |
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
| POST | `/wishlist` | yes | body `{ id, title, priceCents? }`; `addedBy` from the token; `201` new, `200` replay |
| PATCH | `/wishlist/:id` | yes | body `{ title?, priceCents?, bought? }`; `priceCents: null` clears it; `bought` stamps and clears as shopping |
| DELETE | `/wishlist/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/meals` | yes | body `{ id, title, tag?, lastMadeAt?, nextUp? }`; `201` new, `200` replay |
| PATCH | `/meals/:id` | yes | body `{ title?, tag?, lastMadeAt?, nextUp? }`; `lastMadeAt: null` clears it; `nextUp: true` clears every other meal |
| DELETE | `/meals/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/projects` | yes | body `{ id, title, dueOn?, subtasks?: [{ id, title }] }` (max 100, created in order with `sortOrder` 0..n); response includes `subtasks`; `201` new, `200` replay (extra subtasks on a replay are ignored) |
| PATCH | `/projects/:id` | yes | body `{ title?, dueOn? }`; response includes `subtasks` |
| DELETE | `/projects/:id` | yes | soft delete, cascades to its live subtasks; response includes `subtasks` with their new `seq`s; idempotent, `404` if unknown |
| POST | `/projects/:id/subtasks` | yes | body `{ id, title, sortOrder?, assignee? }`; `400` if the project is unknown or deleted; `201` new, `200` replay |
| PATCH | `/subtasks/:id` | yes | body `{ title?, done?, sortOrder?, assignee? }`; `done: true` stamps `doneBy`/`doneAt`, `false` clears them |
| DELETE | `/subtasks/:id` | yes | soft delete, idempotent, `404` if unknown |
| GET | `/bonus?cursor=<n>` | yes | rows with `seq > cursor`, deleted rows included; runs auto-assign first |
| POST | `/bonus` | yes | body `{ id, title, points, claimBy }`; `createdBy` from the token; `201` new, `200` replay |
| POST | `/bonus/:id/claim` | yes | first claim wins: `200` (a repeat by the same person is a `200` replay); `409` when the other person holds it (`claimedBy` in the body) or the deadline has passed / it was auto-assigned; `404` unknown or deleted |
| POST | `/bonus/:id/complete` | yes | `claimedBy` or `assignedTo` only: `200` (repeat is a `200` replay); `403` for anyone else, including on an unclaimed task; `404` unknown or deleted |
| DELETE | `/bonus/:id` | yes | soft delete, idempotent, `404` if unknown |
| POST | `/handoffs` | yes | body `{ id, choreId, to, periodIndex?, cadence? }`; `from` from the token; `201` new pending, `200` replay; on create, push notifies `to`; `400` on a together chore |
| POST | `/handoffs/:id/accept` | yes | `to` person only; `200`; on a real pending→accepted transition, push notifies `from` |
| POST | `/handoffs/:id/decline` | yes | `to` person only; `200`; on a real pending→declined transition, push notifies `from` |
| GET | `/sync?cursor=<n>&choresVersion=<v>` | yes | one call: `serverTime`, `person`, `choresVersion`, `activeFrom`, `cursor`, then `completions`, `shopping`, `meals`, `projects`, `subtasks`, `wishlist`, `bonus`, `handoffs` (every row with `seq > cursor`, deleted rows with `deleted: true`), and `chores` only when the client's version differs. Expired bonus tasks are auto-assigned and past-period open handoffs are expired before the response is built, so those updates ride this same delta |
| POST | `/push/token` | yes | body `{ token, platform: "ios" }` — register APNs device token (64-hex); see Push |
| DELETE | `/push/token` | yes | body `{ token }` — unregister (own tokens only); see Push |

Validation is `400` with an `error` message: ids outside the pattern, missing or empty titles, titles over 200 chars, tags over 40, non-ISO dates, non-boolean flags, non-integer `sortOrder`, a `priceCents` that is not null or an integer 0–99,999,999, a `dueOn` that is not null or a real `YYYY-MM-DD` day, an `assignee` that is not null, `anne` or `wes`, bonus `points` that are not an integer 1-10, an empty PATCH body, an unknown `projectId`, or a subtask id that already exists. Bad ids in a path simply do not route (`404`). A bonus `claimBy` already in the past is accepted (an offline POST replayed late) and assigned on the next sync.

Client loop: start with `cursor=0`, store the `cursor` from each `/sync`, pass it back next time. Replay queued POSTs first, then sync. The cursor is a counter, not a time, so same-millisecond writes and clock changes cannot drop rows. The returned `cursor` is the highest `seq` in the response across all eight sync arrays, and holds at the client's value when nothing changed.

### `GET /status.json` fields

No auth. Names and titles only (no token hashes). Shape:

```json
{
  "date": "Sunday, September 13, 2026",
  "updated": "11:30",
  "activeFrom": "2026-09-07",
  "digestLastSent": "2026-09-13",
  "people": [
    {
      "id": "anne",
      "name": "Anne",
      "streak": 0,
      "week": 0,
      "today": [{ "title": "…" }],
      "due": [{ "title": "…", "stage": "alert", "viaHandoff": false, "person": "anne" }],
      "bonus": [{ "title": "…", "points": 3 }]
    }
  ],
  "bonus": [{ "title": "…", "points": 3 }],
  "recent": [{ "person": "Anne", "title": "…", "time": "11:30" }],
  "backup": { "at": "…Z", "ok": true, "seq": 0 }
}
```

- `date` / `updated` — Chicago display strings for the board clock.
- `activeFrom` — YYYY-MM-DD Chicago calendar day (meta or code default).
- `digestLastSent` — YYYY-MM-DD or `null` (same meta as `/health`).
- `people[]` — one entry per household person; `today` is completions with a Chicago date of today; `due` is overdue plus due-today rows that arrived via handoff; `bonus` is open tasks claimed by or assigned to that person.
- `bonus` (top-level) — open bonus tasks still unclaimed and unassigned.
- `recent` — up to 10 latest completions (display name + title + Chicago time).
- `backup` — `{ at, ok, seq }` from the verify status file, or `null` if absent/unparseable (ops-only; not shown on the HTML board).

`GET /status` renders the same board as HTML (no `backup` blob).

## Run locally

```bash
cd server
ROOST_DB=/tmp/roost.db ROOST_TOKENS=/tmp/tokens.json npm start
ROOST_DB=/tmp/roost.db npm run mkcode -- anne "Anne iPhone"
ROOST_DB=/tmp/roost.db ROOST_TOKENS=/tmp/tokens.json npm run devices -- list
ROOST_DB=/tmp/roost.db npm run household -- active-from
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

- **Backup** — `roost-backup.timer` runs `backup.sh` ~03:30 host-local (theoldone is America/Chicago; `RandomizedDelaySec=10min`) via SQLite's online backup, keeping 30 files in `/var/backups/roost`.
- **Offsite** — `roost-offsite.timer` runs `offsite-backup.sh` ~04:00 host-local and copies the newest file to the grater at `/mnt/storage-sdd/backups/roost/` over the tailnet, also keeping 30.
- **Verify** — `roost-verify.timer` runs `verify-backup.sh` ~04:30 host-local as `User=roost` on the service. It picks the newest `/var/backups/roost/roost-*.db`, runs `src/backupcheck.js` (PRAGMA integrity_check + `meta.seq` cursor + expected tables), and fails closed if none exist or the check fails. Every run (ok or fail) writes `/var/lib/roost/verify-status.json` (`ROOST_VERIFY_STATUS`; atomic temp+mv, `roost:roost`). `GET /health` and `GET /status.json` expose `backup: { at, ok, seq }` from that file, or `null` if absent/unparseable (never throws). Manual: `sudo -u roost /opt/roost/server/verify-backup.sh`.
- **Restore drill** — `restore.sh` verifies a backup then copies it to a non-live path under `/tmp/roost-restore-drill` by default. It refuses to overwrite `/var/lib/roost/roost.db` without `--live`. A live restore also refuses unless `roost.service` is exactly `inactive`, parks the previous DB (+ wal/shm) under `/var/backups/roost/replaced-*.db`, then prints the start command — it does not stop/start the service for you:

```bash
# safe drill (default destination under /tmp/roost-restore-drill)
/opt/roost/server/restore.sh /var/backups/roost/roost-YYYY-MM-DD.db

# live restore (stop the API first)
sudo systemctl stop roost.service
sudo -u roost /opt/roost/server/restore.sh /var/backups/roost/roost-YYYY-MM-DD.db \
  --to /var/lib/roost/roost.db --live
sudo systemctl start roost.service
```

Logs: `journalctl -u roost -f`. Verify runs: `journalctl -u roost-verify -f`. Last verify result is also in `/var/lib/roost/verify-status.json` and on `/health` + `/status.json` as `backup`.

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
- Handoff offer (201 only) notifies `to`; accept/decline (real state change only) notify `from`. Bodies use display names (Anne/Wes) and a period phrase from cadence (`today` / `this week` / `this month` / `these two months` / `this quarter`). All handoff pushes set `apns-collapse-id: handoff-<id>`. Expiry is silent — no push when `expireOpenHandoffs` runs.
- Every 15 minutes, stage ≥ 3 overdue chores notify the assignee's partner (`apns-collapse-id` = `red-<choreId>`). Sent pairs are stored in `push_alerts` so restarts do not re-blast. A together chore's red alert goes to both phones with `<title> is N days late`.
- At/after 08:00 America/Chicago, one push per person with anything due today or overdue (`apns-collapse-id digest-<person>`). Expires at the next Chicago midnight. Meta `digestLastSent` (Chicago date) prevents resends across restarts; nobody with zero items gets one. Exposed on `GET /health` and `GET /status.json` as a YYYY-MM-DD string or `null`. Digest and red-alert sweeps use the same `dueItems` path, so they follow each chore's due window (`dueWindow` / `hasWindow`), not the full period.
