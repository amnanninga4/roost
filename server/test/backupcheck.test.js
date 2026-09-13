import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { checkBackup, readSeq, integrityOf, openReadonly } from "../src/backupcheck.js";

const here = dirname(fileURLToPath(import.meta.url));
const cli = resolve(here, "../src/backupcheck.js");

function makeValidDb(dir, seq = 42) {
  const path = join(dir, "good.db");
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE chores (id TEXT PRIMARY KEY, title TEXT NOT NULL);
    CREATE TABLE completions (id TEXT PRIMARY KEY, choreId TEXT NOT NULL);
    INSERT INTO meta (key, value) VALUES ('seq', '${seq}');
    INSERT INTO chores (id, title) VALUES ('c1', 'Sweep');
  `);
  db.close();
  return path;
}

test("backupcheck: good DB passes with cursor and row counts", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-bc-good-"));
  try {
    const path = makeValidDb(dir, 99);
    const result = checkBackup(path);
    assert.equal(result.ok, true, result.error);
    assert.equal(result.integrity, "ok");
    assert.equal(result.seq, 99);
    assert.deepEqual(result.missingTables, []);
    assert.equal(result.rowCounts.meta, 1);
    assert.equal(result.rowCounts.chores, 1);
    assert.equal(result.rowCounts.completions, 0);
    assert.equal(result.error, null);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("backupcheck: missing file fails closed", () => {
  const result = checkBackup("/tmp/roost-bc-does-not-exist-" + Date.now() + ".db");
  assert.equal(result.ok, false);
  assert.match(result.error, /file not found/);
});

test("backupcheck: empty / corrupt file fails", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-bc-bad-"));
  try {
    const empty = join(dir, "empty.db");
    writeFileSync(empty, "");
    const emptyResult = checkBackup(empty);
    assert.equal(emptyResult.ok, false);
    assert.match(emptyResult.error, /empty|open failed|not a file|integrity/i);

    const garbage = join(dir, "garbage.db");
    writeFileSync(garbage, "this is not a sqlite database at all");
    const garbageResult = checkBackup(garbage);
    assert.equal(garbageResult.ok, false);
    assert.ok(garbageResult.error, "expected an error message");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("backupcheck: cursor read works via readSeq helper", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-bc-seq-"));
  try {
    const path = makeValidDb(dir, 7);
    const db = openReadonly(path);
    try {
      assert.equal(readSeq(db), 7);
      assert.equal(integrityOf(db), "ok");
    } finally {
      db.close();
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("backupcheck: missing meta.seq fails", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-bc-noseq-"));
  try {
    const path = join(dir, "noseq.db");
    const db = new DatabaseSync(path);
    db.exec(`
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE chores (id TEXT PRIMARY KEY);
      CREATE TABLE completions (id TEXT PRIMARY KEY);
    `);
    db.close();
    const result = checkBackup(path);
    assert.equal(result.ok, false);
    assert.match(result.error, /meta\.seq/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("backupcheck: CLI exits 0 on good DB and prints seq", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-bc-cli-"));
  try {
    const path = makeValidDb(dir, 12);
    const run = spawnSync(
      process.execPath,
      ["--no-warnings=ExperimentalWarning", cli, path],
      { encoding: "utf8" },
    );
    assert.equal(run.status, 0, run.stderr + run.stdout);
    const parsed = JSON.parse(run.stdout);
    assert.equal(parsed.ok, true);
    assert.equal(parsed.seq, 12);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("backupcheck: CLI exits non-zero on missing file", () => {
  const run = spawnSync(
    process.execPath,
    ["--no-warnings=ExperimentalWarning", cli, "/tmp/roost-bc-missing-cli.db"],
    { encoding: "utf8" },
  );
  assert.notEqual(run.status, 0);
  const parsed = JSON.parse(run.stdout);
  assert.equal(parsed.ok, false);
});

test("backupcheck: checkBackup leaves no -wal/-shm sidecars", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-bc-nowal-"));
  try {
    const path = makeValidDb(dir, 3);
    // Seed stale sidecars as if a prior RW open left them; check must not recreate after cleanup+open.
    writeFileSync(path + "-wal", "stale");
    writeFileSync(path + "-shm", "stale");
    // Remove them to mimic a clean backup dir; the assertion is that checkBackup itself creates none.
    rmSync(path + "-wal", { force: true });
    rmSync(path + "-shm", { force: true });
    const result = checkBackup(path);
    assert.equal(result.ok, true, result.error);
    assert.equal(existsSync(path + "-wal"), false, "unexpected -wal sidecar");
    assert.equal(existsSync(path + "-shm"), false, "unexpected -shm sidecar");
    const leftovers = readdirSync(dir).filter((n) => n.endsWith("-wal") || n.endsWith("-shm"));
    assert.deepEqual(leftovers, []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
