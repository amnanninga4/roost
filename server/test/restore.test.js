import { test } from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  writeFileSync,
  chmodSync,
  rmSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { spawnSync } from "node:child_process";

const here = dirname(fileURLToPath(import.meta.url));
const restoreSh = resolve(here, "../scripts/restore.sh");

function makeValidDb(dir, name = "good.db", seq = 42) {
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

/** Stub `systemctl is-active roost` → inactive (or other state). */
function writeSystemctlStub(binDir, state = "inactive") {
  const path = join(binDir, "systemctl");
  writeFileSync(
    path,
    `#!/usr/bin/env bash
# test stub — never touches the real service
if [[ "$1" == "is-active" && "$2" == "roost" ]]; then
  echo "${state}"
  if [[ "${state}" == "active" ]]; then exit 0; fi
  exit 3
fi
echo "systemctl-stub: unexpected args: $*" >&2
exit 99
`,
  );
  chmodSync(path, 0o755);
  return path;
}

test("restore --live: parks previous DB+wal as replaced-* and clears sidecars", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-restore-live-"));
  try {
    const binDir = join(dir, "bin");
    mkdirSync(binDir);
    writeSystemctlStub(binDir, "inactive");

    const liveDb = join(dir, "roost.db");
    const backupDir = join(dir, "backups");
    mkdirSync(backupDir);

    // Existing live DB + fake WAL (would corrupt a naive overwrite).
    makeValidDb(dir, "roost.db", 10);
    writeFileSync(`${liveDb}-wal`, "fake-wal-bytes-not-a-real-wal");
    writeFileSync(`${liveDb}-shm`, "fake-shm");

    const source = makeValidDb(dir, "source.db", 99);

    const run = spawnSync("bash", [restoreSh, source, "--to", liveDb, "--live"], {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${binDir}:${process.env.PATH}`,
        ROOST_DB: liveDb,
        ROOST_BACKUP_DIR: backupDir,
        NODE: process.execPath,
      },
    });

    assert.equal(run.status, 0, `stderr=${run.stderr}\nstdout=${run.stdout}`);
    assert.match(run.stdout, /sudo systemctl start roost\.service/);
    assert.match(run.stdout + run.stderr, /backupcheck/);

    // Restored file is the new source (seq 99) and sidecars are gone.
    assert.ok(existsSync(liveDb), "restored live DB missing");
    assert.equal(existsSync(`${liveDb}-wal`), false, "stale -wal must be gone");
    assert.equal(existsSync(`${liveDb}-shm`), false, "stale -shm must be gone");

    const replaced = readdirSync(backupDir).filter((f) => f.startsWith("replaced-"));
    assert.ok(
      replaced.some((f) => f.endsWith(".db") && !f.endsWith("-wal") && !f.endsWith("-shm")),
      `expected replaced-*.db in ${backupDir}, got ${replaced.join(",")}`,
    );
    assert.ok(
      replaced.some((f) => f.endsWith(".db-wal")),
      `expected replaced-*.db-wal, got ${replaced.join(",")}`,
    );
    assert.ok(
      replaced.some((f) => f.endsWith(".db-shm")),
      `expected replaced-*.db-shm, got ${replaced.join(",")}`,
    );

    // Replaced DB should still be the old content (seq 10).
    const replacedDb = join(
      backupDir,
      replaced.find((f) => f.endsWith(".db") && !f.includes("-wal") && !f.includes("-shm")),
    );
    const oldBytes = readFileSync(replacedDb);
    assert.ok(oldBytes.length > 0, "replaced DB empty");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test("restore --live: refuses when roost.service is active", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-restore-active-"));
  try {
    const binDir = join(dir, "bin");
    mkdirSync(binDir);
    writeSystemctlStub(binDir, "active");

    const liveDb = join(dir, "roost.db");
    makeValidDb(dir, "roost.db", 1);
    const source = makeValidDb(dir, "source.db", 2);
    const backupDir = join(dir, "backups");
    mkdirSync(backupDir);

    const run = spawnSync("bash", [restoreSh, source, "--to", liveDb, "--live"], {
      encoding: "utf8",
      env: {
        ...process.env,
        PATH: `${binDir}:${process.env.PATH}`,
        ROOST_DB: liveDb,
        ROOST_BACKUP_DIR: backupDir,
        NODE: process.execPath,
      },
    });

    assert.equal(run.status, 1, `expected exit 1, got ${run.status}\n${run.stderr}`);
    assert.match(run.stderr, /sudo systemctl stop roost\.service/);
    assert.equal(existsSync(`${liveDb}-wal`), false);
    // Live DB untouched (still present, not moved).
    assert.ok(existsSync(liveDb));
    assert.equal(readdirSync(backupDir).length, 0, "must not move files when refused");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
