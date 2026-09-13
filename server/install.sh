#!/usr/bin/env bash
# Install or update the Roost sync API on a Linux host with systemd. Idempotent. Run with sudo from the repo:
#   sudo server/install.sh
# Layout:
#   /opt/roost            code (server/ + data/chores.json), owned by root, read by roost
#   /var/lib/roost        SQLite database, owned by roost
#   /etc/roost/tokens.json device tokens, root:roost 0640
#   /var/backups/roost    nightly DB copies, 30 kept
#   offsite (grater)      roost-offsite.timer ~04:00 UTC → /mnt/storage-sdd/backups/roost, 30 kept
set -euo pipefail

if [[ $EUID -ne 0 ]]; then echo "run with sudo" >&2; exit 1; fi

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
NODE="${NODE:-$(command -v node)}"

if ! "$NODE" -e 'require("node:sqlite")' >/dev/null 2>&1; then
  echo "node at $NODE lacks node:sqlite (need >= 22.13)" >&2; exit 1
fi

command -v sqlite3 >/dev/null || { echo "sqlite3 CLI missing (needed by backup.sh): apt install sqlite3" >&2; exit 1; }

id -u roost >/dev/null 2>&1 || useradd --system --home-dir /var/lib/roost --shell /usr/sbin/nologin roost

install -d -o root -g root -m 755 /opt/roost /opt/roost/server /opt/roost/data
install -d -o roost -g roost -m 750 /var/lib/roost
install -d -o root -g roost -m 750 /etc/roost
install -d -o roost -g roost -m 750 /var/backups/roost

# code
rm -rf /opt/roost/server/src
cp -R "$HERE/src" /opt/roost/server/src
cp "$HERE/package.json" /opt/roost/server/package.json
cp "$HERE/scripts/backup.sh" /opt/roost/server/backup.sh
chmod 755 /opt/roost/server/backup.sh
cp "$HERE/scripts/offsite-backup.sh" /opt/roost/server/offsite-backup.sh
chmod 755 /opt/roost/server/offsite-backup.sh
cp "$REPO/data/chores.json" /opt/roost/data/chores.json
chown -R root:root /opt/roost
chmod -R a+rX /opt/roost

# tokens file: create empty on first install, never overwrite
if [[ ! -f /etc/roost/tokens.json ]]; then
  echo '{}' > /etc/roost/tokens.json
fi
chown root:roost /etc/roost/tokens.json
chmod 640 /etc/roost/tokens.json

# units
sed "s|@NODE@|$NODE|g" "$HERE/systemd/roost.service" > /etc/systemd/system/roost.service
cp "$HERE/systemd/roost-backup.service" /etc/systemd/system/roost-backup.service
cp "$HERE/systemd/roost-backup.timer" /etc/systemd/system/roost-backup.timer
cp "$HERE/systemd/roost-offsite.service" /etc/systemd/system/roost-offsite.service
cp "$HERE/systemd/roost-offsite.timer" /etc/systemd/system/roost-offsite.timer
systemctl daemon-reload
systemctl enable --now roost-backup.timer
systemctl enable --now roost-offsite.timer
systemctl enable roost.service
systemctl restart roost.service

sleep 1
systemctl --no-pager --lines=3 status roost.service || true
echo
echo "health:"; curl -fsS http://127.0.0.1:8790/health || echo "(not answering yet)"
echo
echo "devices in /etc/roost/tokens.json: $("$NODE" -e 'console.log(Object.keys(require("/etc/roost/tokens.json")).length)')"
echo "add one: sudo ROOST_TOKENS=/etc/roost/tokens.json $NODE /opt/roost/server/src/mktoken.js anne \"Anne iPhone\""
