#!/usr/bin/env bash
# Copy the newest local Roost SQLite backup to offsite storage on grater, then keep 30.
# Runs as User=hinescreative with Group=roost (dir /var/backups/roost is 750 roost:roost;
# files are typically 644). install.sh adds hinescreative to group roost when present.
set -euo pipefail

DIR="${ROOST_BACKUP_DIR:-/var/backups/roost}"
HOST="${ROOST_OFFSITE_HOST:-grater.tail1cc940.ts.net}"
USER="${ROOST_OFFSITE_USER:-hinescreative}"
REMOTE_DIR="${ROOST_OFFSITE_DIR:-/mnt/storage-sdd/backups/roost}"
KEEP="${ROOST_OFFSITE_KEEP:-30}"

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=30)

newest="$(ls -1t "$DIR"/roost-*.db 2>/dev/null | head -n 1 || true)"
if [[ -z "$newest" ]]; then
  echo "offsite-backup: no roost-*.db in $DIR" >&2
  exit 1
fi

base="$(basename "$newest")"

# Fail closed on SSH / remote prep failure.
ssh "${ssh_opts[@]}" "${USER}@${HOST}" "mkdir -p $(printf '%q' "$REMOTE_DIR")"

scp "${ssh_opts[@]}" "$newest" "${USER}@${HOST}:${REMOTE_DIR}/${base}"

# Prune remote to KEEP newest roost-*.db.
ssh "${ssh_opts[@]}" "${USER}@${HOST}" \
  "cd $(printf '%q' "$REMOTE_DIR") && ls -1t roost-*.db 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f"

remote_count="$(ssh "${ssh_opts[@]}" "${USER}@${HOST}" \
  "ls -1 $(printf '%q' "$REMOTE_DIR")/roost-*.db 2>/dev/null | wc -l" | tr -d ' ')"
echo "offsite-backup: pushed $base to ${USER}@${HOST}:${REMOTE_DIR}/; remote kept ${remote_count} (max ${KEEP})"
