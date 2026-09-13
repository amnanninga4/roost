#!/usr/bin/env bash
# Verify the newest local Roost SQLite backup: integrity_check + meta.seq cursor.
# Intended for roost-verify.timer (after nightly backup + offsite). Fail closed.
# Writes ROOST_VERIFY_STATUS (default /var/lib/roost/verify-status.json) after every run.
set -euo pipefail

DIR="${ROOST_BACKUP_DIR:-/var/backups/roost}"
NODE="${NODE:-$(command -v node)}"
STATUS_PATH="${ROOST_VERIFY_STATUS:-/var/lib/roost/verify-status.json}"

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

# Atomic JSON status for /health + /status.json. Always write on success or failure.
# Args: ok(0|1) seq(number|empty) integrity backup_path
write_status() {
  local ok_flag="$1" seq_val="${2:-}" integrity_val="$3" backup_val="$4"
  local tmp dir
  dir="$(dirname -- "$STATUS_PATH")"
  mkdir -p -- "$dir"
  tmp="${STATUS_PATH}.tmp.$$"
  # Build JSON via node so integrity/backup strings are escaped safely.
  if ! "$NODE" --no-warnings=ExperimentalWarning -e '
const fs = require("node:fs");
const [okFlag, seqVal, integrity, backup, out] = process.argv.slice(1);
const seq = seqVal === "" || seqVal === "null" ? null : Number(seqVal);
const obj = {
  at: new Date().toISOString(),
  ok: okFlag === "1",
  seq: Number.isFinite(seq) ? seq : null,
  integrity,
  backup,
};
fs.writeFileSync(out, JSON.stringify(obj) + "\n");
' "$ok_flag" "$seq_val" "$integrity_val" "$backup_val" "$tmp"; then
    echo "verify-backup: failed to write status temp $tmp" >&2
    rm -f -- "$tmp"
    return 1
  fi
  mv -f -- "$tmp" "$STATUS_PATH"
  # Readable by roost; if timer/manual run is root, hand ownership back.
  chmod 644 -- "$STATUS_PATH" 2>/dev/null || true
  if [[ "$(id -u)" -eq 0 ]]; then
    chown roost:roost -- "$STATUS_PATH" 2>/dev/null || true
  fi
}

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
  write_status 0 "" "no roost-*.db in $DIR" ""
  echo "verify-backup: no roost-*.db in $DIR" >&2
  exit 1
fi

out="$("$NODE" --no-warnings=ExperimentalWarning "$CHECK_JS" "$newest")" || true
ok="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s); process.stdout.write(j.ok?"1":"0");}catch{process.stdout.write("0");}})')"

# Same sidecar cleanup after the check (success or fail) so a non-immutable open cannot leave residue.
cleanup_sidecars

if [[ "$ok" != "1" ]]; then
  integrity="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s); process.stdout.write(String(j.integrity ?? j.error ?? s));}catch{process.stdout.write(s||"check failed");}})')"
  seq="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{try{const j=JSON.parse(s); process.stdout.write(j.seq==null?"":String(j.seq));}catch{}})')"
  write_status 0 "$seq" "$integrity" "$newest"
  echo "verify-backup: FAILED for $newest: $out" >&2
  exit 1
fi

seq="$(printf '%s' "$out" | "$NODE" -e 'let s="";process.stdin.on("data",d=>s+=d);process.stdin.on("end",()=>{const j=JSON.parse(s); process.stdout.write(String(j.seq));})')"
write_status 1 "$seq" "ok" "$newest"
echo "verify-backup: ok $newest integrity=ok seq=$seq"
