import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync, utimesSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import { seedChores, PEOPLE } from "../src/db.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");

const ANNE = "anne-token-0123456789abcdef";
const WES = "wes-token-0123456789abcdef";

let dir, base, app, tokensPath;
const logged = [];
let clock = new Date("2026-09-14T12:00:00.000Z");
const tick = (ms = 1000) => (clock = new Date(clock.getTime() + ms));

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-test-"));
  tokensPath = join(dir, "tokens.json");
  writeFileSync(
    tokensPath,
    JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" }, [WES]: { person: "wes", device: "Wes test" } })
  );
  app = createApp({ dbPath: join(dir, "roost.db"), choresPath: CHORES, tokensPath, now: () => clock, log: (m) => logged.push(m) });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});

after(async () => {
  await new Promise((r) => app.server.close(r));
  app.db.close();
  rmSync(dir, { recursive: true, force: true });
});

const call = async (method, path, { token, body, raw } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined || raw !== undefined ? { "content-type": "application/json" } : {}),
    },
    body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
};

const plain = (rows) => rows.map((r) => ({ ...r }));

test("seed is idempotent: 31 chores, 2 pinned, re-seed keeps 31", () => {
  assert.equal(app.seeded, 31);
  const count = () => app.db.prepare("SELECT COUNT(*) AS n FROM chores WHERE retired = 0").get().n;
  assert.equal(count(), 31);
  seedChores(app.db, CHORES);
  assert.equal(count(), 31);
  const pinned = plain(
    app.db.prepare("SELECT id, fixedAssignee FROM chores WHERE fixedAssignee IS NOT NULL ORDER BY id").all()
  );
  assert.deepEqual(pinned, [
    { id: "garbage-can-to-street-sunday", fixedAssignee: "wes" },
    { id: "laundry", fixedAssignee: "anne" },
  ]);
  assert.deepEqual([...PEOPLE], ["anne", "wes"]);
});

test("health needs no auth; everything else does", async () => {
  const h = await call("GET", "/health");
  assert.equal(h.status, 200);
  assert.equal(h.body.ok, true);
  assert.equal(h.body.choresVersion, 1);
  assert.equal(h.body.cursor, 0);
  assert.equal(h.body.devices, 2);
  assert.equal(h.body.tokensFileError, null);
  assert.equal(typeof h.body.rev, "string", "/health must include rev");
  assert.ok(h.body.rev.length > 0);

  assert.equal((await call("GET", "/chores")).status, 401);
  assert.equal((await call("GET", "/chores", { token: "wrong-token-0123456789" })).status, 401);
  assert.equal((await call("GET", "/sync")).status, 401);
  assert.equal((await call("POST", "/completions", { body: { id: "x" } })).status, 401);

  const ok = await call("GET", "/chores", { token: ANNE });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.chores.length, 31);
  assert.equal(ok.body.version, 1);
});

test("/health rev prefers ROOST_REV env", async () => {
  const prev = process.env.ROOST_REV;
  process.env.ROOST_REV = "test-rev-sha-abc123";
  try {
    const h = await call("GET", "/health");
    assert.equal(h.status, 200);
    assert.equal(h.body.rev, "test-rev-sha-abc123");
  } finally {
    if (prev === undefined) delete process.env.ROOST_REV;
    else process.env.ROOST_REV = prev;
  }
});

test("completion POST is idempotent on client id and stamps person from token", async () => {
  tick();
  const body = { id: "c-anne-1", choreId: "scoop-litter", completedAt: "2026-09-14T11:30:00.000Z" };
  const first = await call("POST", "/completions", { token: ANNE, body });
  assert.equal(first.status, 201);
  assert.equal(first.body.person, "anne");
  assert.equal(first.body.deleted, false);
  assert.equal(first.body.seq, 1);

  tick();
  const replay = await call("POST", "/completions", { token: ANNE, body });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, first.body, "replay returns the original row unchanged");

  const rows = app.db.prepare("SELECT COUNT(*) AS n FROM completions").get().n;
  assert.equal(rows, 1);
});

test("completion validation: unknown chore, bad dates, bad ids, null/array/invalid bodies are 400 not 500", async () => {
  const at = "2026-09-14T11:30:00.000Z";
  const post = (body) => call("POST", "/completions", { token: WES, body });
  assert.equal((await post({ id: "bad-1", choreId: "nope", completedAt: at })).status, 400);
  assert.equal((await post({ id: "bad-2", choreId: "laundry", completedAt: "yesterday" })).status, 400);
  assert.equal((await post({ choreId: "laundry", completedAt: at })).status, 400);
  assert.equal((await post({ id: "has space/slash", choreId: "laundry", completedAt: at })).status, 400, "id charset is the DELETE charset");
  assert.equal((await post({ id: "x".repeat(65), choreId: "laundry", completedAt: at })).status, 400);
  assert.equal((await call("POST", "/completions", { token: WES, raw: "null" })).status, 400);
  assert.equal((await call("POST", "/completions", { token: WES, raw: "[1,2]" })).status, 400);
  assert.equal((await call("POST", "/completions", { token: WES, raw: "{not json" })).status, 400);
  assert.equal((await call("GET", "/completions?cursor=notanumber", { token: WES })).status, 400);
  assert.equal((await call("GET", "/sync?cursor=-1", { token: WES })).status, 400);
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("sync cursor: same-tick write after a sync is still delivered; deletes propagate; chores only when version differs", async () => {
  // Client syncs and gets a cursor. Another write lands in the SAME clock tick (no tick()).
  const before = await call("GET", "/sync?choresVersion=1", { token: ANNE });
  assert.equal(before.status, 200);
  assert.equal(before.body.cursor, 1);
  assert.equal(before.body.chores, undefined, "matching choresVersion → chores omitted");

  const wes = await call("POST", "/completions", {
    token: WES,
    body: { id: "c-wes-1", choreId: "garbage-can-to-street-sunday", completedAt: "2026-09-14T13:00:00.000Z" },
  });
  assert.equal(wes.status, 201);
  assert.equal(wes.body.seq, 2);

  const delta = await call("GET", `/sync?cursor=${before.body.cursor}&choresVersion=1`, { token: ANNE });
  assert.deepEqual(delta.body.completions.map((c) => c.id), ["c-wes-1"], "same-tick write is not lost");
  assert.equal(delta.body.cursor, 2);

  const full = await call("GET", "/sync", { token: ANNE });
  assert.equal(full.body.person, "anne");
  assert.equal(full.body.chores.length, 31, "no choresVersion param → chores included");
  assert.equal(full.body.completions.length, 2);

  const stale = await call("GET", "/sync?choresVersion=0", { token: ANNE });
  assert.equal(stale.body.chores.length, 31, "stale choresVersion → chores included");

  const idle = await call("GET", "/sync?cursor=2&choresVersion=1", { token: ANNE });
  assert.deepEqual(idle.body.completions, []);
  assert.equal(idle.body.cursor, 2, "cursor holds when nothing changed");

  const del = await call("DELETE", "/completions/c-anne-1", { token: WES });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  assert.equal(del.body.seq, 3, "soft delete takes a new seq");
  const delAgain = await call("DELETE", "/completions/c-anne-1", { token: WES });
  assert.equal(delAgain.status, 200, "delete is idempotent");
  assert.equal(delAgain.body.seq, 3, "second delete does not bump seq");
  assert.equal((await call("DELETE", "/completions/never-existed", { token: WES })).status, 404);

  const after = await call("GET", "/sync?cursor=2&choresVersion=1", { token: ANNE });
  assert.deepEqual(after.body.completions.map((c) => [c.id, c.deleted]), [["c-anne-1", true]]);
  assert.equal(after.body.cursor, 3);

  const total = app.db.prepare("SELECT COUNT(*) AS n FROM completions").get().n;
  assert.equal(total, 2, "soft delete keeps the row");
});

test("chores removed from the JSON are retired: hidden from clients, rejected on POST, history kept", async () => {
  const data = JSON.parse(readFileSync(CHORES, "utf8"));
  const trimmed = { ...data, version: 2, chores: data.chores.filter((c) => c.id !== "scoop-litter") };
  const path = join(dir, "chores-v2.json");
  writeFileSync(path, JSON.stringify(trimmed));
  seedChores(app.db, path);

  const chores = await call("GET", "/chores", { token: ANNE });
  assert.equal(chores.body.version, 2);
  assert.equal(chores.body.chores.length, 30);
  assert.ok(!chores.body.chores.some((c) => c.id === "scoop-litter"));

  const post = await call("POST", "/completions", {
    token: ANNE,
    body: { id: "c-retired", choreId: "scoop-litter", completedAt: "2026-09-14T14:00:00.000Z" },
  });
  assert.equal(post.status, 400);

  const history = await call("GET", "/completions", { token: ANNE });
  assert.ok(history.body.completions.some((c) => c.choreId === "scoop-litter"), "old completion still returned");

  seedChores(app.db, CHORES);
  assert.equal((await call("GET", "/chores", { token: ANNE })).body.chores.length, 31, "re-adding un-retires");
});

test("tokens file: broken edit is logged once and reported in /health; last good set stays active", async () => {
  const good = readFileSync(tokensPath, "utf8");
  writeFileSync(tokensPath, good.replace(/}\s*$/, "},"));
  utimesSync(tokensPath, new Date(clock.getTime() + 5000), new Date(clock.getTime() + 5000));

  assert.equal((await call("GET", "/chores", { token: ANNE })).status, 200, "old token still works");
  assert.equal((await call("GET", "/chores", { token: ANNE })).status, 200);
  const errs = logged.filter((m) => String(m).includes("tokens file"));
  assert.equal(errs.length, 1, "logged exactly once for that mtime");
  const h = await call("GET", "/health");
  assert.match(h.body.tokensFileError, /not applied/);

  writeFileSync(tokensPath, good);
  utimesSync(tokensPath, new Date(clock.getTime() + 10000), new Date(clock.getTime() + 10000));
  assert.equal((await call("GET", "/health")).body.tokensFileError, null);

  writeFileSync(tokensPath, JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" } }));
  utimesSync(tokensPath, new Date(clock.getTime() + 15000), new Date(clock.getTime() + 15000));
  assert.equal((await call("GET", "/health")).body.devices, 1, "health reports the device count after reload, not before");
  writeFileSync(tokensPath, good);
  utimesSync(tokensPath, new Date(clock.getTime() + 20000), new Date(clock.getTime() + 20000));
});

test("devices table records lastSeen per token, throttled to once a minute", () => {
  const rows = plain(app.db.prepare("SELECT person, label, lastSeen FROM devices ORDER BY person").all());
  assert.equal(rows.length, 2);
  assert.equal(rows[0].person, "anne");
  assert.equal(rows[0].label, "Anne test");
  assert.ok(rows[0].lastSeen);
  const seenBefore = rows[0].lastSeen;
  return (async () => {
    tick(10_000);
    await call("GET", "/chores", { token: ANNE });
    assert.equal(app.db.prepare("SELECT lastSeen FROM devices WHERE person='anne'").get().lastSeen, seenBefore, "no write within 60s");
    tick(60_000);
    await call("GET", "/chores", { token: ANNE });
    assert.notEqual(app.db.prepare("SELECT lastSeen FROM devices WHERE person='anne'").get().lastSeen, seenBefore, "written after 60s");
  })();
});
