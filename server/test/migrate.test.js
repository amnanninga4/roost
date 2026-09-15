// R-29: a database built by the version-1 schema string is rebuilt on open — wider cadence CHECKs, the two
// new chores columns — with every row, seq, and foreign key intact; a fresh database records the version.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { openDb, getMeta, listChores, SCHEMA_VERSION } from "../src/db.js";

// The chores and handoffs tables exactly as db.js / handoffs.js created them before R-29.
const V1 = `
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS chores (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  cadence       TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  fixedAssignee TEXT CHECK (fixedAssignee IN ('anne','wes')),
  category      TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
  sortOrder     INTEGER NOT NULL,
  retired       INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS completions (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  person      TEXT NOT NULL CHECK (person IN ('anne','wes')),
  completedAt TEXT NOT NULL,
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS completions_seq ON completions(seq);
CREATE TABLE IF NOT EXISTS handoffs (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  fromPerson  TEXT NOT NULL,
  toPerson    TEXT NOT NULL,
  periodIndex INTEGER NOT NULL,
  cadence     TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  state       TEXT NOT NULL CHECK (state IN ('pending','accepted','declined','expired')),
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS handoffs_seq ON handoffs(seq);
CREATE INDEX IF NOT EXISTS handoffs_chore_period ON handoffs(choreId, periodIndex);
INSERT OR IGNORE INTO meta (key, value) VALUES ('seq', '2');
`;

function v1Database(dir) {
  const path = join(dir, "v1.db");
  const db = new DatabaseSync(path);
  db.exec("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;");
  db.exec(V1);
  db.prepare("INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .run("laundry", "Laundry", "weekly", "anne", "chore", 15, 0);
  db.prepare("INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired) VALUES (?, ?, ?, ?, ?, ?, ?)")
    .run("old-one", "Retired chore", "monthly", null, "chore", 30, 1);
  db.prepare("INSERT INTO completions (id, choreId, person, completedAt, createdAt, updatedAt, deletedAt, seq) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)")
    .run("c1", "laundry", "anne", "2026-09-10T18:00:00.000Z", "2026-09-10T18:00:00.000Z", "2026-09-10T18:00:00.000Z", 1);
  db.prepare("INSERT INTO handoffs (id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)")
    .run("h1", "laundry", "anne", "wes", 36, "weekly", "accepted", "2026-09-14T12:00:00.000Z", "2026-09-14T12:00:00.000Z", 2);
  db.close();
  return path;
}

const columns = (db, table) => db.prepare(`PRAGMA table_info(${table})`).all().map((c) => c.name);
const sqlOf = (db, table) => db.prepare("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?").get(table).sql;

test("a version-1 database is rebuilt to version 2 with rows, seqs and foreign keys intact", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-"));
  try {
    const path = v1Database(dir);
    const db = openDb(path);
    assert.equal(getMeta(db, "schemaVersion"), String(SCHEMA_VERSION));
    assert.ok(columns(db, "chores").includes("season"));
    assert.ok(columns(db, "chores").includes("together"));
    assert.match(sqlOf(db, "chores"), /'quarterly'/);
    assert.match(sqlOf(db, "handoffs"), /'bimonthly'/);

    // Every row survived with its values.
    const laundry = db.prepare("SELECT * FROM chores WHERE id = 'laundry'").get();
    assert.equal(laundry.fixedAssignee, "anne");
    assert.equal(laundry.sortOrder, 15);
    assert.equal(laundry.season, null);
    assert.equal(laundry.together, 0);
    assert.equal(db.prepare("SELECT retired FROM chores WHERE id = 'old-one'").get().retired, 1);
    assert.equal(db.prepare("SELECT seq FROM completions WHERE id = 'c1'").get().seq, 1);
    const h = db.prepare("SELECT * FROM handoffs WHERE id = 'h1'").get();
    assert.equal(h.seq, 2);
    assert.equal(h.state, "accepted");
    assert.equal(getMeta(db, "seq"), "2", "the shared counter is untouched");
    assert.deepEqual(db.prepare("PRAGMA foreign_key_check").all(), []);
    assert.equal(db.prepare("PRAGMA foreign_keys").get().foreign_keys, 1, "foreign keys are back on");
    assert.deepEqual(
      db.prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'handoffs' AND name NOT LIKE 'sqlite_%' ORDER BY name").all().map((r) => r.name),
      ["handoffs_chore_period", "handoffs_seq"]
    );

    // The widened CHECK takes the new cadences, and the FK still points at chores.
    db.prepare("INSERT INTO chores (id, title, cadence, fixedAssignee, category, sortOrder, retired, season, together) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)")
      .run("pantry", "Clean out fridge and pantry", "quarterly", null, "chore", 38, null, 1);
    assert.throws(
      () => db.prepare("INSERT INTO completions (id, choreId, person, completedAt, createdAt, updatedAt, deletedAt, seq) VALUES ('c2', 'nope', 'anne', 'x', 'x', 'x', NULL, 9)").run(),
      /FOREIGN KEY/
    );
    assert.deepEqual(listChores(db).map((c) => [c.id, c.season, c.together]), [["laundry", null, false], ["pantry", null, true]]);

    // Opening again is a no-op.
    db.close();
    const again = openDb(path);
    assert.equal(again.prepare("SELECT COUNT(*) AS n FROM chores").get().n, 3);
    assert.equal(getMeta(again, "schemaVersion"), String(SCHEMA_VERSION));
    again.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a fresh database gets the version-2 shape directly and records the version", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-fresh-"));
  try {
    const db = openDb(join(dir, "fresh.db"));
    assert.equal(getMeta(db, "schemaVersion"), String(SCHEMA_VERSION));
    assert.ok(columns(db, "chores").includes("together"));
    assert.ok(columns(db, "chores").includes("weekdays"));
    assert.ok(columns(db, "chores").includes("dueDay"));
    assert.match(sqlOf(db, "chores"), /'bimonthly'/);
    db.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a version-2 database gains projects.dueOn and project_subtasks.assignee and records version 3", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-v3-"));
  try {
    const path = join(dir, "v2.db");
    const raw = new DatabaseSync(path);
    raw.exec(`
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO meta VALUES ('seq', '2'), ('schemaVersion', '2');
      CREATE TABLE projects (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
        deletedAt TEXT, seq INTEGER NOT NULL UNIQUE
      );
      CREATE TABLE project_subtasks (
        id TEXT PRIMARY KEY, projectId TEXT NOT NULL REFERENCES projects(id), title TEXT NOT NULL,
        sortOrder INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0,1)),
        doneBy TEXT CHECK (doneBy IN ('anne','wes')), doneAt TEXT, createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL, deletedAt TEXT, seq INTEGER NOT NULL UNIQUE
      );
      INSERT INTO projects VALUES ('p1', 'Fence', 'x', 'x', NULL, 1);
      INSERT INTO project_subtasks VALUES ('s1', 'p1', 'Posts', 0, 0, NULL, NULL, 'x', 'x', NULL, 2);
    `);
    raw.close();

    const db = openDb(path);
    // migrate runs through to SCHEMA_VERSION (4); v3 columns still land.
    assert.equal(getMeta(db, "schemaVersion"), String(SCHEMA_VERSION));
    assert.ok(columns(db, "projects").includes("dueOn"));
    assert.ok(columns(db, "project_subtasks").includes("assignee"));
    assert.equal(db.prepare("SELECT dueOn FROM projects WHERE id = 'p1'").get().dueOn, null);
    assert.equal(db.prepare("SELECT assignee FROM project_subtasks WHERE id = 's1'").get().assignee, null);
    db.prepare("UPDATE project_subtasks SET assignee = 'wes' WHERE id = 's1'").run();
    assert.throws(() => db.prepare("UPDATE project_subtasks SET assignee = 'bob' WHERE id = 's1'").run(), /CHECK/);
    assert.equal(db.prepare("SELECT seq FROM project_subtasks WHERE id = 's1'").get().seq, 2, "rows untouched");
    db.close();

    const again = openDb(path);
    assert.equal(getMeta(again, "schemaVersion"), String(SCHEMA_VERSION), "opening again is a no-op");
    again.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("a version-3 database gains chores.weekdays and chores.dueDay and records version 4", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-v4-"));
  try {
    const path = join(dir, "v3.db");
    const raw = new DatabaseSync(path);
    raw.exec(`
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO meta VALUES ('seq', '1'), ('schemaVersion', '3');
      CREATE TABLE chores (
        id TEXT PRIMARY KEY, title TEXT NOT NULL,
        cadence TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly','bimonthly','quarterly')),
        fixedAssignee TEXT CHECK (fixedAssignee IN ('anne','wes')),
        category TEXT NOT NULL CHECK (category IN ('chore','cat_care')),
        sortOrder INTEGER NOT NULL, retired INTEGER NOT NULL DEFAULT 0,
        season TEXT, together INTEGER NOT NULL DEFAULT 0
      );
      INSERT INTO chores VALUES ('laundry', 'Laundry', 'weekly', 'anne', 'chore', 15, 0, NULL, 0);
    `);
    raw.close();

    const db = openDb(path);
    assert.equal(getMeta(db, "schemaVersion"), "4");
    assert.ok(columns(db, "chores").includes("weekdays"));
    assert.ok(columns(db, "chores").includes("dueDay"));
    const row = db.prepare("SELECT weekdays, dueDay FROM chores WHERE id = 'laundry'").get();
    assert.equal(row.weekdays, null);
    assert.equal(row.dueDay, null);
    db.close();

    const again = openDb(path);
    assert.equal(getMeta(again, "schemaVersion"), "4", "opening again is a no-op");
    again.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
