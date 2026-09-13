# server/ — Roost sync API

Small HTTP API the phones sync against. Node 22+ with the built-in `node:sqlite`, no npm dependencies. One process, one SQLite file.

Runs on theoldone, bound to `127.0.0.1:8790`. Public path is a Cloudflare Tunnel at `https://roost.hinescreative.xyz`. Tailscale is the admin path only.

## Model

- **chores** — mirror of `data/chores.json`, seeded on every start (idempotent upsert). `choresVersion` comes from the JSON `version` field; bump it when the list changes so clients refetch.
- **completions** — `{ id, choreId, person, completedAt, createdAt, updatedAt, deleted }`. `id` is client-generated so an offline queue can replay a POST safely. Deletes are soft so they propagate through sync deltas.
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

The file is re-read when it changes. To revoke a device, delete its line. To add one:

```bash
sudo ROOST_TOKENS=/etc/roost/tokens.json node /opt/roost/server/src/mktoken.js anne "Anne iPhone"
```

The token prints once. The server stores only its SHA-256.

## Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | no | `{ ok, serverTime, choresVersion, choresSeeded }` |
| GET | `/chores` | yes | full list + version |
| GET | `/completions?since=<iso>` | yes | changed after `since` (exclusive), deleted rows included with `deleted: true` |
| POST | `/completions` | yes | body `{ id, choreId, completedAt }`; person comes from the token; `201` new, `200` replay |
| DELETE | `/completions/:id` | yes | soft delete, idempotent, `404` if unknown |
| GET | `/sync?since=<iso>&choresVersion=<n>` | yes | one call: `serverTime`, `person`, `choresVersion`, `completions` delta, and `chores` only when the client's version differs |

Client loop: store `serverTime` from each `/sync`, pass it back as `since` next time. Replay queued POSTs first, then sync.

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
