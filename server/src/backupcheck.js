/** Shared SQLite backup integrity + sync-cursor reader for Roost.
 *
 * Importable:
 *   import { checkBackup } from "./backupcheck.js";
 *   const result = checkBackup("/var/backups/roost/roost-2026-09-13.db");
 *
 * CLI:
 *   node src/backupcheck.js <dbPath>
 *   Exit 0 on ok, non-zero on fail. Prints one JSON object to stdout.
 *
 * Opens the file read-only (never creates -wal/-shm sidecars). Does not mutate the DB.
 */
import { DatabaseSync } from "node:sqlite";
import { existsSync, statSync } from "node:fs";

/** Tables a Roost backup is expected to have at minimum. */
export const EXPECTED_TABLES = Object.freeze(["meta", "chores", "completions"]);

/**
 * @typedef {object} BackupCheckResult
 * @property {boolean} ok
 * @property {string} path
 * @property {string|null} integrity  // "ok" or the PRAGMA message
 * @property {number|null} seq        // meta.seq cursor, or null if unreadable
 * @property {string[]} missingTables
 * @property {Record<string, number>|null} rowCounts
 * @property {string|null} error
 */

/**
 * Open a SQLite file read-only if the API supports it; fall back to default open.
 * Caller must close.
 * @param {string} path
 */
export function openReadonly(path) {
  try {
    return new DatabaseSync(path, { readOnly: true });
  } catch {
    // Older node:sqlite builds without { readOnly: true } — URI form.
    const uri = path.startsWith("file:")
      ? (path.includes("?") ? path : `${path}?mode=ro`)
      : `file:${path}?mode=ro`;
    return new DatabaseSync(uri);
  }
}

/**
 * Run integrity_check (full). Falls back to quick_check if integrity_check throws.
 * @param {import("node:sqlite").DatabaseSync} db
 * @returns {string} "ok" or the first non-ok message
 */
export function integrityOf(db) {
  try {
    const rows = db.prepare("PRAGMA integrity_check").all();
    const messages = rows.map((r) => String(Object.values(r)[0] ?? ""));
    if (messages.length === 1 && messages[0] === "ok") return "ok";
    return messages.join("; ") || "integrity_check returned no rows";
  } catch (e) {
    try {
      const rows = db.prepare("PRAGMA quick_check").all();
      const messages = rows.map((r) => String(Object.values(r)[0] ?? ""));
      if (messages.length === 1 && messages[0] === "ok") return "ok";
      return `quick_check: ${messages.join("; ") || "no rows"}`;
    } catch (e2) {
      return `integrity failed: ${e?.message ?? e}; quick_check failed: ${e2?.message ?? e2}`;
    }
  }
}

/**
 * Read meta.seq (shared sync cursor). Returns null if missing/unreadable.
 * @param {import("node:sqlite").DatabaseSync} db
 * @returns {number|null}
 */
export function readSeq(db) {
  try {
    const row = db.prepare("SELECT value FROM meta WHERE key = ?").get("seq");
    if (!row || row.value == null) return null;
    const n = Number(row.value);
    return Number.isFinite(n) ? n : null;
  } catch {
    return null;
  }
}

/**
 * List table names present in sqlite_master (type=table, no sqlite_ internals).
 * @param {import("node:sqlite").DatabaseSync} db
 * @returns {string[]}
 */
export function listTables(db) {
  try {
    return db
      .prepare(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .all()
      .map((r) => String(r.name));
  } catch {
    return [];
  }
}

/**
 * @param {import("node:sqlite").DatabaseSync} db
 * @param {string[]} tables
 * @returns {Record<string, number>}
 */
export function countRows(db, tables) {
  /** @type {Record<string, number>} */
  const out = {};
  for (const t of tables) {
    try {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(t)) {
        out[t] = -1;
        continue;
      }
      const row = db.prepare(`SELECT COUNT(*) AS n FROM ${t}`).get();
      out[t] = Number(row?.n ?? 0);
    } catch {
      out[t] = -1;
    }
  }
  return out;
}

/**
 * Full backup check. Never throws — failures land in the result.
 * @param {string} path
 * @param {{ expectedTables?: string[], withRowCounts?: boolean }} [opts]
 * @returns {BackupCheckResult}
 */
export function checkBackup(path, opts = {}) {
  const expected = opts.expectedTables ?? [...EXPECTED_TABLES];
  const withRowCounts = opts.withRowCounts !== false;

  /** @type {BackupCheckResult} */
  const result = {
    ok: false,
    path,
    integrity: null,
    seq: null,
    missingTables: [],
    rowCounts: null,
    error: null,
  };

  if (!path || typeof path !== "string") {
    result.error = "path required";
    return result;
  }
  if (!existsSync(path)) {
    result.error = `file not found: ${path}`;
    return result;
  }
  try {
    const st = statSync(path);
    if (!st.isFile() || st.size === 0) {
      result.error = st.size === 0 ? `empty file: ${path}` : `not a file: ${path}`;
      return result;
    }
  } catch (e) {
    result.error = `stat failed: ${e?.message ?? e}`;
    return result;
  }

  let db;
  try {
    db = openReadonly(path);
  } catch (e) {
    result.error = `open failed: ${e?.message ?? e}`;
    return result;
  }

  try {
    const integrity = integrityOf(db);
    result.integrity = integrity;
    if (integrity !== "ok") {
      result.error = `integrity_check failed: ${integrity}`;
      return result;
    }

    const tables = listTables(db);
    result.missingTables = expected.filter((t) => !tables.includes(t));
    if (result.missingTables.length) {
      result.error = `missing tables: ${result.missingTables.join(", ")}`;
      return result;
    }

    result.seq = readSeq(db);
    if (result.seq == null) {
      result.error = "meta.seq missing or unreadable";
      return result;
    }

    if (withRowCounts) {
      result.rowCounts = countRows(db, expected);
    }

    result.ok = true;
    return result;
  } finally {
    try {
      db.close();
    } catch {
      /* ignore */
    }
  }
}

function main(argv) {
  const dbPath = argv[2];
  if (!dbPath) {
    console.error("usage: node backupcheck.js <dbPath>");
    process.exit(2);
  }
  const result = checkBackup(dbPath);
  console.log(JSON.stringify(result));
  process.exit(result.ok ? 0 : 1);
}

// Runnable as CLI when invoked directly (path ends with backupcheck.js).
const entry = process.argv[1] ? process.argv[1].replace(/\\/g, "/") : "";
if (entry.endsWith("/backupcheck.js") || entry.endsWith("backupcheck.js")) {
  main(process.argv);
}
