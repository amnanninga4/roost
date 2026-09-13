// SQLite storage for Roost. All timestamps are ISO-8601 UTC strings.
// Chicago-time logic (due today, streaks, escalation) lives in the app / RoostCore, not here.
//
// Sync cursor: every insert and soft-delete of a completion takes the next value of a
// monotonic `seq` counter. Clients sync with `cursor=<last seq seen>`; wall-clock time is
// never used as a cursor, so same-millisecond writes and clock steps cannot lose rows.
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

/** The household. Single source for the Node side; the CHECK constraints below are built from it. */
export const PEOPLE = Object.freeze(["anne", "wes"]);
const PEOPLE_SQL = PEOPLE.map((p) => `'${p}'`).join(",");

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS chores (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  cadence       TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  fixedAssignee TEXT CHECK (fixedAssignee IN (${PEOPLE_SQL})),
  category      TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
  sortOrder     INTEGER NOT NULL,
  retired       INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS completions (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  person      TEXT NOT NULL CHECK (person IN (${PEOPLE_SQL})),
  completedAt TEXT NOT NULL,
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS completions_seq ON completions(seq);
CREATE TABLE IF NOT EXISTS devices (
  tokenHash TEXT PRIMARY KEY,
  person    TEXT NOT NULL CHECK (person IN (${PEOPLE_SQL})),
  label     TEXT NOT NULL,
  lastSeen  TEXT
);
INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', '0');
`;

export function openDb(path) {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);
  return db;
}

function nextSeq(db) {
  db.prepare("UPDATE meta SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) WHERE key = 'seq'").run();
  return Number(db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
}

export function currentSeq(db) {
  return Number(db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
}

/**
 * Seed or refresh chores from data/chores.json. Idempotent. Chores present in the file are upserted;
 * chores missing from the file are marked retired (kept for completion history, hidden from clients).
 */
export function seedChores(db, choresJsonPath) {
  const data = JSON.parse(readFileSync(choresJsonPath, "utf8"));
  if (!Array.isArray(data.chores) || typeof data.version !== "number") {
    throw new Error(`bad chores file: ${choresJsonPath}`);
  }
  const upsert = db.prepare(`
    INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired)
    VALUES (?, ?, ?, ?, ?, ?, 0)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      cadence = excluded.cadence,
      fixedAssignee = excluded.fixedAssignee,
      category = excluded.category,
      sortOrder = excluded.sortOrder,
      retired = 0
  `);
  const setMeta = db.prepare(
    "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  );
  db.exec("BEGIN");
  try {
    data.chores.forEach((c, i) => {
      upsert.run(c.id, c.title, c.cadence, c.fixedAssignee ?? null, c.category, i);
    });
    const ids = data.chores.map((c) => c.id);
    const placeholders = ids.map(() => "?").join(",");
    db.prepare(`UPDATE chores SET retired = 1 WHERE id NOT IN (${placeholders})`).run(...ids);
    setMeta.run("choresVersion", String(data.version));
    setMeta.run("choresSource", String(data.source ?? ""));
    setMeta.run("choresLocked", String(data.locked ?? ""));
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return data.chores.length;
}

export function getMeta(db, key) {
  const row = db.prepare("SELECT value FROM meta WHERE key = ?").get(key);
  return row ? row.value : null;
}

export function listChores(db) {
  return db
    .prepare("SELECT id, title, cadence, fixedAssignee, category FROM chores WHERE retired = 0 ORDER BY sortOrder")
    .all();
}

export function choreExists(db, id) {
  return !!db.prepare("SELECT 1 FROM chores WHERE id = ? AND retired = 0").get(id);
}

export function getCompletion(db, id) {
  return db.prepare("SELECT * FROM completions WHERE id = ?").get(id) ?? null;
}

/** Insert if new. Returns { row, created }. Existing rows are returned untouched (idempotent replay). */
export function insertCompletion(db, { id, choreId, person, completedAt }, now) {
  const existing = getCompletion(db, id);
  if (existing) return { row: existing, created: false };
  db.exec("BEGIN");
  try {
    const seq = nextSeq(db);
    db.prepare(
      "INSERT INTO completions (id, choreId, person, completedAt, createdAt, updatedAt, deletedAt, seq) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)"
    ).run(id, choreId, person, completedAt, now, now, seq);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return { row: getCompletion(db, id), created: true };
}

/** Soft delete so the deletion propagates through /sync deltas. Idempotent. */
export function deleteCompletion(db, id, now) {
  const existing = getCompletion(db, id);
  if (!existing) return null;
  if (!existing.deletedAt) {
    db.exec("BEGIN");
    try {
      const seq = nextSeq(db);
      db.prepare("UPDATE completions SET deletedAt = ?, updatedAt = ?, seq = ? WHERE id = ?").run(now, now, seq, id);
      db.exec("COMMIT");
    } catch (err) {
      db.exec("ROLLBACK");
      throw err;
    }
  }
  return getCompletion(db, id);
}

/** Completions with seq > cursor, including soft-deleted ones. cursor 0 = everything. */
export function completionsAfter(db, cursor) {
  return db.prepare("SELECT * FROM completions WHERE seq > ? ORDER BY seq").all(cursor);
}

export function touchDevice(db, { tokenHash, person, label }, now) {
  db.prepare(
    `INSERT INTO devices (tokenHash, person, label, lastSeen) VALUES (?, ?, ?, ?)
     ON CONFLICT(tokenHash) DO UPDATE SET person = excluded.person, label = excluded.label, lastSeen = excluded.lastSeen`
  ).run(tokenHash, person, label, now);
}
