#!/usr/bin/env bash
# Verify the newest local Roost SQLite backup: integrity_check + meta.seq cursor.
# Intended for roost-verify.timer (after nightly backup + offsite). Fail closed.
set -euo pipefail

DIR="${ROOST_BACKUP_DIR:-/var/backups/roost}"
NODE="${NODE:-$(command -v node)}"

# Prefer the installed tree; fall back to repo layout next to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f /opt/roost/server/src/backupcheck.js ]]; then
  CHECK_JS=/opt/roost/server/src/backupcheck.js
elif [[ -f "$SCRIPT_DIR/../src/backupcheck.js" ]]; then
  CHECK_JS="$SCRIPT_DIR/../src/backupcheck.js"
elif [[ -f "$SCRIPT_DIR/src/backupcheck.js" ]]; then
  # install.sh copies scripts flat into /opt/roost/server/
  CHECK_JS="$SCRIPT_DIR/src/backupcheck.js"
else
  echo "verify-backup: backupcheck.js not found (looked under /opt/roost/server/src and $SCRIPT_DIR)" >&2
  exit 1
fi

# Drop stale SQLite sidecars left by earlier read-write opens next to backups we check.
cleanup_sidecars() {
  shopt -s nullglob
  for f in "$DIR"/roost-*.db-wal "$DIR"/roost-*.db-shm; do
    rm -f -- "$f"
  done
  shopt -u nullglob
}

cleanup_sidecars

newest="$(ls -1t "$DIR"/roost-*.db 2>/dev/null | head -n 1 || true)"

if [[ -z "$newest" ]]; then
  echo "verify-backup: no roost-*.db in $DIR" >&2
  exit 1
fi

out="$("$NODE" --no-warnings=ExperimentalWarning "$CHECK_JS" "$newest")"
ok="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s); process.stdout.write(j.ok?"1":"0");})')"

# Same sidecar cleanup after the check (success or fail) so a non-immutable open cannot leave residue.
cleanup_sidecars

if [[ "$ok" != "1" ]]; then
  echo "verify-backup: FAILED for $newest: $out" >&2
  exit 1
fi

seq="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s); process.stdout.write(String(j.seq));})')"
echo "verify-backup: ok $newest integrity=ok seq=$seq"
