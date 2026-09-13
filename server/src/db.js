// SQLite storage for Roost. All timestamps are ISO-8601 UTC strings.
// Chicago-time logic (due today, streaks, escalation) lives in the app / RoostCore, not here.
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS chores (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  cadence       TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  fixedAssignee TEXT CHECK (fixedAssignee IN ('anne','wes')),
  category      TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
  sortOrder     INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS completions (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  person      TEXT NOT NULL CHECK (person IN ('anne','wes')),
  completedAt TEXT NOT NULL,
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT
);
CREATE INDEX IF NOT EXISTS completions_updatedAt ON completions(updatedAt);
CREATE TABLE IF NOT EXISTS devices (
  tokenHash TEXT PRIMARY KEY,
  person    TEXT NOT NULL CHECK (person IN ('anne','wes')),
  label     TEXT NOT NULL,
  lastSeen  TEXT
);
`;

export function openDb(path) {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);
  return db;
}

/** Seed or refresh chores from data/chores.json. Idempotent: re-running updates in place. */
export function seedChores(db, choresJsonPath) {
  const data = JSON.parse(readFileSync(choresJsonPath, "utf8"));
  if (!Array.isArray(data.chores) || typeof data.version !== "number") {
    throw new Error(`bad chores file: ${choresJsonPath}`);
  }
  const upsert = db.prepare(`
    INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      cadence = excluded.cadence,
      fixedAssignee = excluded.fixedAssignee,
      category = excluded.category,
      sortOrder = excluded.sortOrder
  `);
  const setMeta = db.prepare(
    "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  );
  db.exec("BEGIN");
  try {
    data.chores.forEach((c, i) => {
      upsert.run(c.id, c.title, c.cadence, c.fixedAssignee ?? null, c.category, i);
    });
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
    .prepare("SELECT id, title, cadence, fixedAssignee, category FROM chores ORDER BY sortOrder")
    .all();
}

export function choreExists(db, id) {
  return !!db.prepare("SELECT 1 FROM chores WHERE id = ?").get(id);
}

export function getCompletion(db, id) {
  return db.prepare("SELECT * FROM completions WHERE id = ?").get(id) ?? null;
}

/** Insert if new. Returns { row, created }. Existing rows are returned untouched (idempotent replay). */
export function insertCompletion(db, { id, choreId, person, completedAt }, now) {
  const existing = getCompletion(db, id);
  if (existing) return { row: existing, created: false };
  db.prepare(
    "INSERT INTO completions (id, choreId, person, completedAt, createdAt, updatedAt, deletedAt) VALUES (?, ?, ?, ?, ?, ?, NULL)"
  ).run(id, choreId, person, completedAt, now, now);
  return { row: getCompletion(db, id), created: true };
}

/** Soft delete so the deletion propagates through /sync deltas. */
export function deleteCompletion(db, id, now) {
  const existing = getCompletion(db, id);
  if (!existing) return null;
  if (!existing.deletedAt) {
    db.prepare("UPDATE completions SET deletedAt = ?, updatedAt = ? WHERE id = ?").run(now, now, id);
  }
  return getCompletion(db, id);
}

/** Completions changed since `since` (exclusive), including soft-deleted ones. Null since = everything. */
export function completionsSince(db, since) {
  if (since) {
    return db
      .prepare("SELECT * FROM completions WHERE updatedAt > ? ORDER BY updatedAt, id")
      .all(since);
  }
  return db.prepare("SELECT * FROM completions ORDER BY updatedAt, id").all();
}

export function touchDevice(db, { tokenHash, person, label }, now) {
  db.prepare(
    `INSERT INTO devices (tokenHash, person, label, lastSeen) VALUES (?, ?, ?, ?)
     ON CONFLICT(tokenHash) DO UPDATE SET person = excluded.person, label = excluded.label, lastSeen = excluded.lastSeen`
  ).run(tokenHash, person, label, now);
}
