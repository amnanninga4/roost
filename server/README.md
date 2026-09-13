# server/ — Roost sync API

Small HTTP API the phones sync against. Node 22+ with the built-in `node:sqlite`, no npm dependencies. One process, one SQLite file.

Runs on theoldone, bound to `127.0.0.1:8790`. Public path is a Cloudflare Tunnel at `https://roost.hinescreative.xyz`. Tailscale is the admin path only.

## Model

- **chores** — mirror of `data/chores.json`, seeded on every start (idempotent upsert; ids missing from the file are marked retired, hidden from clients, kept for history). `choresVersion` comes from the JSON `version` field; bump it when the list changes so clients refetch.
- **completions** — `{ id, choreId, person, completedAt, createdAt, updatedAt, deleted, seq }`. `id` is client-generated (1-64 chars of `A-Z a-z 0-9 . _ ~ : @ + -`) so an offline queue can replay a POST safely. Deletes are soft so they propagate through sync deltas. `seq` is a monotonic counter bumped on every insert and delete; it is the sync cursor.
- **devices** — hash of each token that has been seen, with person, label, lastSeen.

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
| GET | `/sync?cursor=<n>&choresVersion=<v>` | yes | one call: `serverTime`, `person`, `choresVersion`, `cursor`, `completions` with `seq > cursor`, and `chores` only when the client's version differs |

Client loop: start with `cursor=0`, store the `cursor` from each `/sync`, pass it back next time. Replay queued POSTs first, then sync. The cursor is a counter, not a time, so same-millisecond writes and clock changes cannot drop rows.

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

Backups: `roost-backup.timer` runs `backup.sh` at 03:30 UTC via SQLite's online backup, keeping 30 files in `/var/backups/roost`. Offsite copy to the grater is a later ticket.

Logs: `journalctl -u roost -f`.

## Not in this ticket

Push notifications (APNs) are R-6 and need the key from Wes's developer account placed on the host outside the repo.
