#!/usr/bin/env bash
# Roost restore drill — safe by default. Verifies a backup, then copies it to a
# non-live destination. Refuses to overwrite the production DB unless --live is
# passed explicitly (and still prints stop/start reminders).
#
# Usage:
#   restore.sh <backup.db> [--to <dest.db>]
#   restore.sh <backup.db> --to /var/lib/roost/roost.db --live
#
# Defaults:
#   ROOST_RESTORE_DIR=/tmp/roost-restore-drill
#   destination = $ROOST_RESTORE_DIR/roost-restored-YYYYMMDD-HHMMSS.db
#
# Does NOT stop/start roost.service for you. For a live restore you must:
#   sudo systemctl stop roost.service
#   sudo -u roost /opt/roost/server/restore.sh /var/backups/roost/roost-YYYY-MM-DD.db \
#        --to /var/lib/roost/roost.db --live
#   sudo systemctl start roost.service
set -euo pipefail

LIVE_DB="${ROOST_DB:-/var/lib/roost/roost.db}"
RESTORE_DIR="${ROOST_RESTORE_DIR:-/tmp/roost-restore-drill}"
NODE="${NODE:-$(command -v node)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /opt/roost/server/src/backupcheck.js ]]; then
  CHECK_JS=/opt/roost/server/src/backupcheck.js
elif [[ -f "$SCRIPT_DIR/../src/backupcheck.js" ]]; then
  CHECK_JS="$SCRIPT_DIR/../src/backupcheck.js"
elif [[ -f "$SCRIPT_DIR/src/backupcheck.js" ]]; then
  CHECK_JS="$SCRIPT_DIR/src/backupcheck.js"
else
  echo "restore: backupcheck.js not found" >&2
  exit 1
fi

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

BACKUP=""
DEST=""
LIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      DEST="${2:-}"; shift 2 ;;
    --live)
      LIVE=1; shift ;;
    -h|--help)
      usage ;;
    -*)
      echo "restore: unknown flag $1" >&2; usage ;;
    *)
      if [[ -z "$BACKUP" ]]; then BACKUP="$1"; shift
      else echo "restore: unexpected arg $1" >&2; usage
      fi ;;
  esac
done

if [[ -z "$BACKUP" ]]; then
  echo "restore: backup path required" >&2
  usage
fi
if [[ ! -f "$BACKUP" ]]; then
  echo "restore: backup not found: $BACKUP" >&2
  exit 1
fi

if [[ -z "$DEST" ]]; then
  mkdir -p "$RESTORE_DIR"
  DEST="$RESTORE_DIR/roost-restored-$(date +%Y%m%d-%H%M%S).db"
fi

# Resolve absolute-ish paths for the live-DB guard (best-effort; no readlink -f required).
abs_of() {
  local p="$1"
  if [[ "$p" = /* ]]; then printf '%s' "$p"; else printf '%s' "$(pwd)/$p"; fi
}
dest_abs="$(abs_of "$DEST")"
live_abs="$(abs_of "$LIVE_DB")"

if [[ "$dest_abs" == "$live_abs" && "$LIVE" -ne 1 ]]; then
  echo "restore: refusing to overwrite live DB $LIVE_DB without --live" >&2
  echo "restore: for a drill, omit --to or point --to under $RESTORE_DIR" >&2
  exit 1
fi
if [[ "$dest_abs" == "$live_abs" && "$LIVE" -eq 1 ]]; then
  echo "restore: LIVE restore requested → $LIVE_DB" >&2
  echo "restore: ensure roost.service is STOPPED before continuing:" >&2
  echo "restore:   sudo systemctl stop roost.service" >&2
  echo "restore: after restore: sudo systemctl start roost.service" >&2
fi

echo "restore: verifying source $BACKUP"
out="$("$NODE" --no-warnings=ExperimentalWarning "$CHECK_JS" "$BACKUP")"
ok="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s); process.stdout.write(j.ok?"1":"0");})')"
if [[ "$ok" != "1" ]]; then
  echo "restore: source failed backupcheck: $out" >&2
  exit 1
fi
seq="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s); process.stdout.write(String(j.seq));})')"

mkdir -p "$(dirname "$DEST")"
# Prefer sqlite online backup into the destination (consistent copy); fall back to cp.
if command -v sqlite3 >/dev/null 2>&1; then
  tmp="$DEST.tmp.$$"
  sqlite3 "$BACKUP" ".backup '$tmp'"
  mv -f "$tmp" "$DEST"
else
  cp -f "$BACKUP" "$DEST"
fi

# Re-check the restored file.
out2="$("$NODE" --no-warnings=ExperimentalWarning "$CHECK_JS" "$DEST")"
ok2="$(printf '%s' "$out2" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s); process.stdout.write(j.ok?"1":"0");})')"
if [[ "$ok2" != "1" ]]; then
  echo "restore: destination failed backupcheck: $out2" >&2
  exit 1
fi

echo "restore: wrote $DEST (seq=$seq); source verified"
