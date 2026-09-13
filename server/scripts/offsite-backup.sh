#!/usr/bin/env bash
# Copy the newest local Roost SQLite backup to offsite storage on grater, then keep 30.
# Intended to run as root (systemd oneshot). Reads roost-owned /var/backups/roost (750)
# as root into a staging copy, then scp/ssh as ROOST_OFFSITE_USER so Tailscale SSH keys
# work without putting that user in the roost group (which would expose
# /etc/roost/tokens.json 640 root:roost).
set -euo pipefail

DIR="${ROOST_BACKUP_DIR:-/var/backups/roost}"
HOST="${ROOST_OFFSITE_HOST:-grater.tail1cc940.ts.net}"
USER="${ROOST_OFFSITE_USER:-hinescreative}"
REMOTE_DIR="${ROOST_OFFSITE_DIR:-/mnt/storage-sdd/backups/roost}"
KEEP="${ROOST_OFFSITE_KEEP:-30}"

run_as_user() {
  if [[ $EUID -eq 0 ]]; then
    runuser -u "$USER" -- "$@"
  else
    "$@"
  fi
}

ssh_as() {
  run_as_user ssh -o BatchMode=yes -o ConnectTimeout=30 "${USER}@${HOST}" "$@"
}

scp_as() {
  run_as_user scp -o BatchMode=yes -o ConnectTimeout=30 "$@"
}

newest="$(ls -1t "$DIR"/roost-*.db 2>/dev/null | head -n 1 || true)"
if [[ -z "$newest" ]]; then
  echo "offsite-backup: no roost-*.db in $DIR" >&2
  exit 1
fi

base="$(basename "$newest")"

# Stage a copy root can hand to $USER for scp (roost:roost 750 backups are not
# readable by hinescreative; do not add that user to group roost).
stage="$(mktemp -d /tmp/roost-offsite.XXXXXX)"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT
cp -a "$newest" "$stage/$base"
chown "$USER":"$USER" "$stage/$base"
chmod 400 "$stage/$base"
# Allow $USER to traverse the staging dir
chmod 755 "$stage"

# Fail closed on SSH / remote prep failure.
ssh_as "mkdir -p $(printf '%q' "$REMOTE_DIR")"

scp_as "$stage/$base" "${USER}@${HOST}:${REMOTE_DIR}/${base}"

# Prune remote to KEEP newest roost-*.db (fail closed if listing/rm fails).
ssh_as "cd $(printf '%q' "$REMOTE_DIR") && ls -1t roost-*.db 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f"

remote_count="$(ssh_as "ls -1 $(printf '%q' "$REMOTE_DIR")/roost-*.db 2>/dev/null | wc -l" | tr -d ' ')"
echo "offsite-backup: pushed $base to ${USER}@${HOST}:${REMOTE_DIR}/; remote kept ${remote_count} (max ${KEEP})"
