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
- **devices** — hash of each token that has been seen, with person, label, lastSeen.

Every list row follows the completions rules: client-generated `id` validated by the same pattern, a POST replay for an existing id returns `200` with the stored row untouched (deleted rows included — no resurrection), deletes are soft and idempotent, and PATCH/DELETE on an unknown id is `404`. Titles are 1-200 chars. All five tables share the ONE `seq` counter, so a single `/sync` call carries every delta in order. No seed data: lists start empty.

All stored times are ISO-8601 UTC. Chicago-time rules (due today, streaks, escalation) belong to the app and RoostCore, not the server.

## Auth

Bearer device tokens, no accounts. `/etc/roost/tokens.json`:

```json
{
  "<token>": { "person": "anne", "device": "Anne iPhone" },
  "<token>": { "person": "wes",  "device": "Wes iPhone" }
}
```

The file is re-read when it changes. To revoke a device, delete its line. A file that fails to parse is logged once, shown as `tokensFileError` in `/health`, and the last good set stays active until it is fixed. To add one:

```bash
sudo ROOST_TOKENS=/etc/roost/tokens.json node /opt/roost/server/src/mktoken.js anne "Anne iPhone"
```

The token prints once. The server stores only its SHA-256.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | no | `{ ok, serverTime, choresVersion, choresSeeded, cursor, devices, tokensFileError }` |
| GET | `/chores` | yes | full list + version |
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
| GET | `/sync?cursor=<n>&choresVersion=<v>` | yes | one call: `serverTime`, `person`, `choresVersion`, `cursor`, then `completions`, `shopping`, `meals`, `projects`, `subtasks` (every row with `seq > cursor`, deleted rows with `deleted: true`), and `chores` only when the client's version differs |

Validation is `400` with an `error` message: ids outside the pattern, missing or empty titles, titles over 200 chars, tags over 40, non-ISO dates, non-boolean flags, non-integer `sortOrder`, an empty PATCH body, an unknown `projectId`, or a subtask id that already exists. Bad ids in a path simply do not route (`404`).

Client loop: start with `cursor=0`, store the `cursor` from each `/sync`, pass it back next time. Replay queued POSTs first, then sync. The cursor is a counter, not a time, so same-millisecond writes and clock changes cannot drop rows. The returned `cursor` is the highest `seq` in the response across all five arrays, and holds at the client's value when nothing changed.

## Run locally

```bash
cd server
ROOST_DB=/tmp/roost.db ROOST_TOKENS=/tmp/tokens.json npm start
npm test
```

## Deploy (theoldone)

```bash
# first time
gh repo clone amnanninga4/roost ~/roost && cd ~/roost
# every deploy
git pull --ff-only && sudo server/install.sh
```

The script creates the `roost` system user, `/opt/roost` (code), `/var/lib/roost` (DB), `/etc/roost/tokens.json` (0640 root:roost, created empty once, never overwritten), `/var/backups/roost`, installs `roost.service` plus a nightly backup service and timer, and restarts the API. Re-run it to deploy a new version.

Backups: `roost-backup.timer` runs `backup.sh` at 03:30 host-local time (theoldone is America/Chicago) via SQLite's online backup, keeping 30 files in `/var/backups/roost`. `roost-offsite.timer` runs `offsite-backup.sh` at 04:00 host-local and copies the newest file to the grater at `/mnt/storage-sdd/backups/roost/` over the tailnet, also keeping 30.

Logs: `journalctl -u roost -f`.

## Not in this ticket

Push notifications (APNs) are R-6 and need the key from Wes's developer account placed on the host outside the repo.
