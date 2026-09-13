import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  writeFileSync,
  rmSync,
  existsSync,
  mkdirSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const verifySh = resolve(here, "../scripts/verify-backup.sh");

function makeValidDb(dir, name = "roost-2026-09-13.db", seq = 42) {
  const path = join(dir, name);
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

test("verify-backup.sh: writes status JSON after ok run", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-verify-ok-"));
  try {
    const backupDir = join(dir, "backups");
    mkdirSync(backupDir);
    makeValidDb(backupDir, "roost-2026-09-13.db", 77);
    const statusPath = join(dir, "verify-status.json");

    const run = spawnSync("bash", [verifySh], {
      encoding: "utf8",
      env: {
        ...process.env,
        ROOST_BACKUP_DIR: backupDir,
        ROOST_VERIFY_STATUS: statusPath,
        NODE: process.execPath,
      },
    });

    assert.equal(run.status, 0, `stderr=${run.stderr}\nstdout=${run.stdout}`);
    assert.match(run.stdout, /verify-backup: ok/);
    assert.ok(existsSync(statusPath), "status file missing after ok run");
    const status = JSON.parse(readFileSync(statusPath, "utf8"));
    assert.equal(status.ok, true);
    assert.equal(status.seq, 77);
    assert.equal(status.integrity, "ok");
    assert.equal(typeof status.at, "string");
    assert.match(status.at, /^\d{4}-\d{2}-\d{2}T/);
    assert.ok(status.backup.endsWith("roost-2026-09-13.db"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("verify-backup.sh: writes status JSON after failing integrity check", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-verify-fail-"));
  try {
    const backupDir = join(dir, "backups");
    mkdirSync(backupDir);
    // Corrupt / non-sqlite content named like a backup.
    const bad = join(backupDir, "roost-2026-09-13.db");
    writeFileSync(bad, "this is not a sqlite database");
    const statusPath = join(dir, "verify-status.json");

    const run = spawnSync("bash", [verifySh], {
      encoding: "utf8",
      env: {
        ...process.env,
        ROOST_BACKUP_DIR: backupDir,
        ROOST_VERIFY_STATUS: statusPath,
        NODE: process.execPath,
      },
    });

    assert.notEqual(run.status, 0, `expected non-zero\n${run.stderr}\n${run.stdout}`);
    assert.match(run.stderr, /FAILED|verify-backup/);
    assert.ok(existsSync(statusPath), "status file missing after failed run");
    const status = JSON.parse(readFileSync(statusPath, "utf8"));
    assert.equal(status.ok, false);
    assert.equal(status.seq, null);
    assert.equal(typeof status.integrity, "string");
    assert.ok(status.integrity.length > 0);
    assert.equal(typeof status.at, "string");
    assert.ok(status.backup.endsWith("roost-2026-09-13.db"));
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
