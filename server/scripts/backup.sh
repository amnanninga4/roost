#!/usr/bin/env bash
# Consistent SQLite copy via the online backup API, then keep the newest 30.
set -euo pipefail
DB="${ROOST_DB:-/var/lib/roost/roost.db}"
DIR="${ROOST_BACKUP_DIR:-/var/backups/roost}"
KEEP="${ROOST_BACKUP_KEEP:-30}"
OUT="$DIR/roost-$(date -u +%F).db"

sqlite3 "$DB" ".backup '$OUT.tmp'"
mv -f "$OUT.tmp" "$OUT"
ls -1t "$DIR"/roost-*.db | tail -n +"$((KEEP + 1))" | xargs -r rm -f
echo "backup written: $OUT ($(du -h "$OUT" | cut -f1)); kept $(ls -1 "$DIR"/roost-*.db | wc -l)"
