// SQLite storage for Roost. All timestamps are ISO-8601 UTC strings.
// Chicago-time logic (due today, streaks, escalation) lives in the app / RoostCore, not here.
//
// Sync cursor: every insert, update and soft-delete of a synced row (completions, shopping items,
// meals, projects, subtasks, wishlist items, handoffs) takes the next value of ONE monotonic `seq` counter shared by every
// table, so a single /sync call carries every delta. Clients sync with `cursor=<last seq seen>`; wall-clock time is
// never used as a cursor, so same-millisecond writes and clock steps cannot lose rows.
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { BONUS_SCHEMA } from "./bonus.js";
import { PAIRING_SCHEMA } from "./pairing.js";
import { PUSH_SCHEMA } from "./push.js";
import { HANDOFFS_SCHEMA, HANDOFFS_COLUMNS, HANDOFFS_INDEXES } from "./handoffs.js";
import { chicagoDateString, CADENCES } from "./rules.js";

/** The household. Single source for the Node side; the CHECK constraints below are built from it. */
export const PEOPLE = Object.freeze(["anne", "wes"]);
const PEOPLE_SQL = PEOPLE.map((p) => `'${p}'`).join(",");

const CADENCES_SQL = CADENCES.map((c) => `'${c}'`).join(",");

/**
 * Bumped when a table's shape changes in a way CREATE TABLE IF NOT EXISTS cannot apply to an existing
 * database (a CHECK, a new column). `migrate` brings an older database up to it, step by step.
 */
export const SCHEMA_VERSION = 4;

/** The chores columns, shared by the schema and the v2 rebuild so the two can never drift. */
export const CHORES_COLUMNS = `
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  cadence       TEXT NOT NULL CHECK (cadence IN (${CADENCES_SQL})),
  fixedAssignee TEXT CHECK (fixedAssignee IN (${PEOPLE_SQL})),
  category      TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
  sortOrder     INTEGER NOT NULL,
  retired       INTEGER NOT NULL DEFAULT 0,
  season        TEXT,
  together      INTEGER NOT NULL DEFAULT 0 CHECK (together IN (0,1)),
  weekdays      TEXT,
  dueDay        INTEGER CHECK (dueDay IS NULL OR dueDay BETWEEN 1 AND 28)`;

export const SCHEMA = `
CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS chores (${CHORES_COLUMNS}
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
CREATE TABLE IF NOT EXISTS shopping_items (
  id        TEXT PRIMARY KEY,
  title     TEXT NOT NULL,
  addedBy   TEXT NOT NULL CHECK (addedBy IN (${PEOPLE_SQL})),
  bought    INTEGER NOT NULL DEFAULT 0 CHECK (bought IN (0,1)),
  boughtBy  TEXT CHECK (boughtBy IN (${PEOPLE_SQL})),
  boughtAt  TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  deletedAt TEXT,
  seq       INTEGER NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS meals (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  tag        TEXT NOT NULL DEFAULT '',
  lastMadeAt TEXT,
  nextUp     INTEGER NOT NULL DEFAULT 0 CHECK (nextUp IN (0,1)),
  createdAt  TEXT NOT NULL,
  updatedAt  TEXT NOT NULL,
  deletedAt  TEXT,
  seq        INTEGER NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS projects (
  id        TEXT PRIMARY KEY,
  title     TEXT NOT NULL,
  dueOn     TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  deletedAt TEXT,
  seq       INTEGER NOT NULL UNIQUE
);
CREATE TABLE IF NOT EXISTS project_subtasks (
  id        TEXT PRIMARY KEY,
  projectId TEXT NOT NULL REFERENCES projects(id),
  title     TEXT NOT NULL,
  sortOrder INTEGER NOT NULL,
  assignee  TEXT CHECK (assignee IN (${PEOPLE_SQL})),
  done      INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0,1)),
  doneBy    TEXT CHECK (doneBy IN (${PEOPLE_SQL})),
  doneAt    TEXT,
  createdAt TEXT NOT NULL,
  updatedAt TEXT NOT NULL,
  deletedAt TEXT,
  seq       INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS project_subtasks_project ON project_subtasks(projectId);
CREATE TABLE IF NOT EXISTS wishlist_items (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  priceCents INTEGER CHECK (priceCents IS NULL OR priceCents BETWEEN 0 AND 99999999),
  addedBy    TEXT NOT NULL CHECK (addedBy IN (${PEOPLE_SQL})),
  bought     INTEGER NOT NULL DEFAULT 0 CHECK (bought IN (0,1)),
  boughtBy   TEXT CHECK (boughtBy IN (${PEOPLE_SQL})),
  boughtAt   TEXT,
  createdAt  TEXT NOT NULL,
  updatedAt  TEXT NOT NULL,
  deletedAt  TEXT,
  seq        INTEGER NOT NULL UNIQUE
);
INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', '0');
`;

export function openDb(path) {
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  db.exec(SCHEMA);
  db.exec(BONUS_SCHEMA);
  db.exec(PAIRING_SCHEMA);
  db.exec(PUSH_SCHEMA);
  db.exec(HANDOFFS_SCHEMA);
  migrate(db);
  return db;
}

/**
 * One-time upgrades for a database created by an older schema string. Runs before seeding, once per
 * open, and each step is idempotent: a fresh database already has the current shape and only records
 * the version. Keyed on meta.schemaVersion (absent = 1).
 */
function migrate(db) {
  const current = Number(getMeta(db, "schemaVersion") ?? 1);
  if (current >= SCHEMA_VERSION) return;
  if (current < 2) migrateToV2(db);
  if (current < 3) migrateToV3(db);
  if (current < 4) migrateToV4(db);
  setMeta(db, "schemaVersion", String(SCHEMA_VERSION));
}

function columnNames(db, table) {
  return db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
}

/**
 * v2 (R-29): chores gains season + together and both cadence CHECKs widen. SQLite cannot alter a CHECK,
 * so chores and handoffs are rebuilt the documented way — new table, copy, drop, rename — with foreign
 * keys off for the drop (a pragma, so it has to sit outside the transaction) and checked before commit.
 * The other tables' REFERENCES chores(id) are text and bind to the renamed table.
 */
function migrateToV2(db) {
  if (columnNames(db, "chores").includes("season")) return; // built from the v2 schema string already
  db.exec("PRAGMA foreign_keys = OFF");
  db.exec("BEGIN");
  try {
    db.exec(`
      CREATE TABLE chores_v2 (${CHORES_COLUMNS}
      );
      INSERT INTO chores_v2 (id, title, cadence, fixedAssignee, category, sortOrder, retired)
        SELECT id, title, cadence, fixedAssignee, category, sortOrder, retired FROM chores;
      DROP TABLE chores;
      ALTER TABLE chores_v2 RENAME TO chores;
      CREATE TABLE handoffs_v2 (${HANDOFFS_COLUMNS}
      );
      INSERT INTO handoffs_v2 (id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq)
        SELECT id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq FROM handoffs;
      DROP TABLE handoffs;
      ALTER TABLE handoffs_v2 RENAME TO handoffs;
      ${HANDOFFS_INDEXES}
    `);
    const broken = db.prepare("PRAGMA foreign_key_check").all();
    if (broken.length) throw new Error(`v2 migration broke foreign keys: ${JSON.stringify(broken)}`);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  } finally {
    db.exec("PRAGMA foreign_keys = ON");
  }
}

/**
 * v3 (R-30): a due day on projects and an owner on subtasks. Both nullable, so ADD COLUMN is enough;
 * each is guarded on the column list so a database built from the v3 schema string is left alone.
 */
function migrateToV3(db) {
  if (!columnNames(db, "projects").includes("dueOn")) {
    db.exec("ALTER TABLE projects ADD COLUMN dueOn TEXT");
  }
  if (!columnNames(db, "project_subtasks").includes("assignee")) {
    db.exec(`ALTER TABLE project_subtasks ADD COLUMN assignee TEXT CHECK (assignee IN (${PEOPLE_SQL}))`);
  }
}

/**
 * v4 (due windows): weekdays (JSON array text) and dueDay on chores. Both nullable, so ADD COLUMN is enough;
 * guarded on the column list so a database built from the v4 schema string is left alone.
 */
function migrateToV4(db) {
  if (!columnNames(db, "chores").includes("weekdays")) {
    db.exec("ALTER TABLE chores ADD COLUMN weekdays TEXT");
  }
  if (!columnNames(db, "chores").includes("dueDay")) {
    db.exec("ALTER TABLE chores ADD COLUMN dueDay INTEGER CHECK (dueDay IS NULL OR dueDay BETWEEN 1 AND 28)");
  }
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
    INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired, season, together, weekdays, dueDay)
    VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      title = excluded.title,
      cadence = excluded.cadence,
      fixedAssignee = excluded.fixedAssignee,
      category = excluded.category,
      sortOrder = excluded.sortOrder,
      retired = 0,
      season = excluded.season,
      together = excluded.together,
      weekdays = excluded.weekdays,
      dueDay = excluded.dueDay
  `);
  const setMeta = db.prepare(
    "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  );
  db.exec("BEGIN");
  try {
    data.chores.forEach((c, i) => {
      upsert.run(
        c.id, c.title, c.cadence, c.fixedAssignee ?? null, c.category, i,
        c.season ? JSON.stringify(c.season) : null,
        c.together ? 1 : 0,
        c.weekdays ? JSON.stringify(c.weekdays) : null,
        c.dueDay ?? null
      );
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

export function setMeta(db, key, value) {
  db.prepare(
    "INSERT INTO meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  ).run(key, String(value));
}

/**
 * Set meta.activeFrom to today (Chicago YYYY-MM-DD) on first pair/mint only.
 * Second call leaves the existing value alone. Returns the effective date string.
 */
export function ensureActiveFrom(db, now = new Date()) {
  const existing = getMeta(db, "activeFrom");
  if (existing) return existing;
  const date = chicagoDateString(now);
  // INSERT OR IGNORE: concurrent first-pairs cannot clobber each other
  db.prepare("INSERT OR IGNORE INTO meta (key, value) VALUES (?, ?)").run("activeFrom", date);
  return getMeta(db, "activeFrom") ?? date;
}

/** A chores row as clients and the rules see it: `season` parsed back to an object (or null), `together` a boolean. */
export function shapeChore(row) {
  return {
    id: row.id,
    title: row.title,
    cadence: row.cadence,
    fixedAssignee: row.fixedAssignee,
    category: row.category,
    season: row.season ? JSON.parse(row.season) : null,
    together: !!row.together,
    weekdays: row.weekdays ? JSON.parse(row.weekdays) : null,
    dueDay: row.dueDay ?? null,
  };
}

export function listChores(db) {
  return db
    .prepare("SELECT id, title, cadence, fixedAssignee, category, season, together, weekdays, dueDay FROM chores WHERE retired = 0 ORDER BY sortOrder")
    .all()
    .map(shapeChore);
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

// ---------------------------------------------------------------------------------------------
// Lists: shopping items, meals, projects + subtasks. Same rules as completions: client-generated
// ids, soft deletes, every changed row takes the next shared seq inside one transaction.
// Table names below are module constants, never request input.

const SHOPPING = "shopping_items";
const MEALS = "meals";
const PROJECTS = "projects";
const SUBTASKS = "project_subtasks";
const WISHLIST = "wishlist_items";

function transact(db, fn) {
  db.exec("BEGIN");
  try {
    const out = fn();
    db.exec("COMMIT");
    return out;
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
}

function rowById(db, table, id) {
  return db.prepare(`SELECT * FROM ${table} WHERE id = ?`).get(id) ?? null;
}

/** Inside a transaction: insert a row with the next seq. `cols` is { column: value } without id/seq/timestamps. */
function insertRowIn(db, table, id, cols, now) {
  const seq = nextSeq(db);
  const all = { id, ...cols, createdAt: now, updatedAt: now, deletedAt: null, seq };
  const names = Object.keys(all);
  db.prepare(`INSERT INTO ${table} (${names.join(", ")}) VALUES (${names.map(() => "?").join(", ")})`).run(
    ...names.map((n) => all[n])
  );
  return rowById(db, table, id);
}

/** Inside a transaction: apply `fields` to a row, stamping updatedAt and a new seq. */
function updateRowIn(db, table, id, fields, now) {
  const seq = nextSeq(db);
  const names = Object.keys(fields);
  const sets = names.map((n) => `${n} = ?`).concat("updatedAt = ?", "seq = ?").join(", ");
  db.prepare(`UPDATE ${table} SET ${sets} WHERE id = ?`).run(...names.map((n) => fields[n]), now, seq, id);
  return rowById(db, table, id);
}

/** Inside a transaction: soft-delete a live row. No-op (no seq) when already deleted. */
function softDeleteIn(db, table, id, now) {
  const row = rowById(db, table, id);
  if (!row || row.deletedAt) return row;
  return updateRowIn(db, table, id, { deletedAt: now }, now);
}

/** Insert if new. Returns { row, created }. Existing rows (deleted or not) are returned untouched. */
function insertRow(db, table, id, cols, now) {
  const existing = rowById(db, table, id);
  if (existing) return { row: existing, created: false };
  return { row: transact(db, () => insertRowIn(db, table, id, cols, now)), created: true };
}

/** Patch a live row. Returns null when the row is unknown or deleted. */
function patchRow(db, table, id, fields, now) {
  const existing = rowById(db, table, id);
  if (!existing || existing.deletedAt) return null;
  return transact(db, () => updateRowIn(db, table, id, fields, now));
}

/** Soft delete, idempotent. Returns null when the row is unknown. */
function deleteRow(db, table, id, now) {
  const existing = rowById(db, table, id);
  if (!existing) return null;
  return transact(db, () => softDeleteIn(db, table, id, now));
}

// --- shopping ---

export function getShoppingItem(db, id) {
  return rowById(db, SHOPPING, id);
}

export function insertShoppingItem(db, { id, title, addedBy }, now) {
  return insertRow(db, SHOPPING, id, { title, addedBy, bought: 0, boughtBy: null, boughtAt: null }, now);
}

/**
 * { title?, bought? }. bought=true stamps boughtBy/boughtAt on the false→true transition (a replay of
 * the same PATCH keeps the first stamp); bought=false clears both.
 */
export function patchShoppingItem(db, id, { title, bought }, person, now) {
  const existing = getShoppingItem(db, id);
  if (!existing || existing.deletedAt) return null;
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (bought === true && !existing.bought) Object.assign(fields, { bought: 1, boughtBy: person, boughtAt: now });
  if (bought === false) Object.assign(fields, { bought: 0, boughtBy: null, boughtAt: null });
  return patchRow(db, SHOPPING, id, fields, now);
}

export function deleteShoppingItem(db, id, now) {
  return deleteRow(db, SHOPPING, id, now);
}


// --- wishlist ---

export function getWishlistItem(db, id) {
  return rowById(db, WISHLIST, id);
}

/** `priceCents` is null or 0..99,999,999 (the route validates; the CHECK is the backstop). */
export function insertWishlistItem(db, { id, title, priceCents = null, addedBy }, now) {
  return insertRow(db, WISHLIST, id, { title, priceCents, addedBy, bought: 0, boughtBy: null, boughtAt: null }, now);
}

/**
 * { title?, priceCents?, bought? }. `priceCents: null` clears the price. `bought` stamps and clears
 * exactly as a shopping item does.
 */
export function patchWishlistItem(db, id, { title, priceCents, bought }, person, now) {
  const existing = getWishlistItem(db, id);
  if (!existing || existing.deletedAt) return null;
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (priceCents !== undefined) fields.priceCents = priceCents;
  if (bought === true && !existing.bought) Object.assign(fields, { bought: 1, boughtBy: person, boughtAt: now });
  if (bought === false) Object.assign(fields, { bought: 0, boughtBy: null, boughtAt: null });
  return patchRow(db, WISHLIST, id, fields, now);
}

export function deleteWishlistItem(db, id, now) {
  return deleteRow(db, WISHLIST, id, now);
}

// --- meals ---

export function getMeal(db, id) {
  return rowById(db, MEALS, id);
}

/** Inside a transaction: clear nextUp on every other live meal, each taking its own seq. */
function clearNextUpIn(db, exceptId, now) {
  const others = db.prepare(`SELECT id FROM ${MEALS} WHERE nextUp = 1 AND deletedAt IS NULL AND id <> ?`).all(exceptId);
  for (const { id } of others) updateRowIn(db, MEALS, id, { nextUp: 0 }, now);
}

export function insertMeal(db, { id, title, tag = "", lastMadeAt = null, nextUp = false }, now) {
  const existing = getMeal(db, id);
  if (existing) return { row: existing, created: false };
  const row = transact(db, () => {
    if (nextUp) clearNextUpIn(db, id, now);
    return insertRowIn(db, MEALS, id, { title, tag, lastMadeAt, nextUp: nextUp ? 1 : 0 }, now);
  });
  return { row, created: true };
}

/** { title?, tag?, lastMadeAt?, nextUp? }. nextUp=true is exclusive: every other meal is cleared. */
export function patchMeal(db, id, { title, tag, lastMadeAt, nextUp }, now) {
  const existing = getMeal(db, id);
  if (!existing || existing.deletedAt) return null;
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (tag !== undefined) fields.tag = tag;
  if (lastMadeAt !== undefined) fields.lastMadeAt = lastMadeAt;
  if (nextUp !== undefined) fields.nextUp = nextUp ? 1 : 0;
  return transact(db, () => {
    if (nextUp === true) clearNextUpIn(db, id, now);
    return updateRowIn(db, MEALS, id, fields, now);
  });
}

export function deleteMeal(db, id, now) {
  return deleteRow(db, MEALS, id, now);
}

// --- projects + subtasks ---

export function getProject(db, id) {
  return rowById(db, PROJECTS, id);
}

export function projectExists(db, id) {
  return !!db.prepare(`SELECT 1 FROM ${PROJECTS} WHERE id = ? AND deletedAt IS NULL`).get(id);
}

export function getSubtask(db, id) {
  return rowById(db, SUBTASKS, id);
}

/** Every subtask of a project (deleted ones included), in list order. */
export function subtasksOf(db, projectId) {
  return db.prepare(`SELECT * FROM ${SUBTASKS} WHERE projectId = ? ORDER BY sortOrder, seq`).all(projectId);
}

/** Creates the project and its `subtasks` [{ id, title }] in order, each row taking its own seq. Steps start unowned. */
export function insertProject(db, { id, title, dueOn = null, subtasks = [] }, now) {
  const existing = getProject(db, id);
  if (existing) return { row: existing, created: false };
  const row = transact(db, () => {
    const project = insertRowIn(db, PROJECTS, id, { title, dueOn }, now);
    subtasks.forEach((s, i) => {
      insertRowIn(
        db,
        SUBTASKS,
        s.id,
        { projectId: id, title: s.title, sortOrder: i, assignee: null, done: 0, doneBy: null, doneAt: null },
        now
      );
    });
    return project;
  });
  return { row, created: true };
}

/** { title?, dueOn? }. `dueOn: null` clears the day. */
export function patchProject(db, id, { title, dueOn }, now) {
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (dueOn !== undefined) fields.dueOn = dueOn;
  return patchRow(db, PROJECTS, id, fields, now);
}

/** Soft-deletes the project and every live subtask under it, each row taking its own seq. */
export function deleteProject(db, id, now) {
  const existing = getProject(db, id);
  if (!existing) return null;
  return transact(db, () => {
    for (const s of subtasksOf(db, id)) softDeleteIn(db, SUBTASKS, s.id, now);
    return softDeleteIn(db, PROJECTS, id, now);
  });
}

/** sortOrder defaults to one past the highest live subtask in the project. Caller checks projectId. */
export function insertSubtask(db, { id, projectId, title, sortOrder, assignee = null }, now) {
  const existing = getSubtask(db, id);
  if (existing) return { row: existing, created: false };
  const row = transact(db, () => {
    let order = sortOrder;
    if (order === undefined) {
      const max = db
        .prepare(`SELECT MAX(sortOrder) AS m FROM ${SUBTASKS} WHERE projectId = ? AND deletedAt IS NULL`)
        .get(projectId).m;
      order = max == null ? 0 : max + 1;
    }
    return insertRowIn(db, SUBTASKS, id, { projectId, title, sortOrder: order, assignee, done: 0, doneBy: null, doneAt: null }, now);
  });
  return { row, created: true };
}

/** { title?, done?, sortOrder?, assignee? }. done=true stamps doneBy/doneAt on the false→true transition; done=false clears both. */
export function patchSubtask(db, id, { title, done, sortOrder, assignee }, person, now) {
  const existing = getSubtask(db, id);
  if (!existing || existing.deletedAt) return null;
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (sortOrder !== undefined) fields.sortOrder = sortOrder;
  if (assignee !== undefined) fields.assignee = assignee;
  if (done === true && !existing.done) Object.assign(fields, { done: 1, doneBy: person, doneAt: now });
  if (done === false) Object.assign(fields, { done: 0, doneBy: null, doneAt: null });
  return patchRow(db, SUBTASKS, id, fields, now);
}

export function deleteSubtask(db, id, now) {
  return deleteRow(db, SUBTASKS, id, now);
}

// --- sync ---

/** Every list row with seq > cursor, per table, ordered by seq. Deleted rows included. */
export function listsAfter(db, cursor) {
  const after = (table) => db.prepare(`SELECT * FROM ${table} WHERE seq > ? ORDER BY seq`).all(cursor);
  return {
    shopping: after(SHOPPING),
    meals: after(MEALS),
    projects: after(PROJECTS),
    subtasks: after(SUBTASKS),
    wishlist: after(WISHLIST),
  };
}
