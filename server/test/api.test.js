import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import { seedChores } from "../src/db.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");

const ANNE = "anne-token-0123456789abcdef";
const WES = "wes-token-0123456789abcdef";

let dir, base, app;
let clock = new Date("2026-09-14T12:00:00.000Z");
const tick = () => (clock = new Date(clock.getTime() + 1000));

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-test-"));
  const tokensPath = join(dir, "tokens.json");
  writeFileSync(
    tokensPath,
    JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" }, [WES]: { person: "wes", device: "Wes test" } })
  );
  app = createApp({ dbPath: join(dir, "roost.db"), choresPath: CHORES, tokensPath, now: () => clock });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});

after(async () => {
  await new Promise((r) => app.server.close(r));
  app.db.close();
  rmSync(dir, { recursive: true, force: true });
});

const call = async (method, path, { token, body } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(body ? { "content-type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
};

test("seed is idempotent: 31 chores, 2 pinned, re-seed keeps 31", () => {
  assert.equal(app.seeded, 31);
  const count = () => app.db.prepare("SELECT COUNT(*) AS n FROM chores").get().n;
  assert.equal(count(), 31);
  seedChores(app.db, CHORES);
  assert.equal(count(), 31);
  const pinned = app.db
    .prepare("SELECT id, fixedAssignee FROM chores WHERE fixedAssignee IS NOT NULL ORDER BY id")
    .all()
    .map((r) => ({ id: r.id, fixedAssignee: r.fixedAssignee }));
  assert.deepEqual(pinned, [
    { id: "garbage-can-to-street-sunday", fixedAssignee: "wes" },
    { id: "laundry", fixedAssignee: "anne" },
  ]);
});

test("health needs no auth; everything else does", async () => {
  const h = await call("GET", "/health");
  assert.equal(h.status, 200);
  assert.equal(h.body.ok, true);
  assert.equal(h.body.choresVersion, 1);

  assert.equal((await call("GET", "/chores")).status, 401);
  assert.equal((await call("GET", "/chores", { token: "wrong-token-0123456789" })).status, 401);
  assert.equal((await call("GET", "/sync")).status, 401);
  assert.equal((await call("POST", "/completions", { body: { id: "x" } })).status, 401);

  const ok = await call("GET", "/chores", { token: ANNE });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.chores.length, 31);
  assert.equal(ok.body.version, 1);
});

test("completion POST is idempotent on client id and stamps person from token", async () => {
  tick();
  const body = { id: "c-anne-1", choreId: "scoop-litter", completedAt: "2026-09-14T11:30:00.000Z" };
  const first = await call("POST", "/completions", { token: ANNE, body });
  assert.equal(first.status, 201);
  assert.equal(first.body.person, "anne");
  assert.equal(first.body.deleted, false);

  tick();
  const replay = await call("POST", "/completions", { token: ANNE, body });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, first.body, "replay returns the original row unchanged");

  const rows = app.db.prepare("SELECT COUNT(*) AS n FROM completions").get().n;
  assert.equal(rows, 1);
});

test("completion validation", async () => {
  assert.equal(
    (await call("POST", "/completions", { token: WES, body: { id: "bad-1", choreId: "nope", completedAt: "2026-09-14T11:30:00.000Z" } })).status,
    400
  );
  assert.equal(
    (await call("POST", "/completions", { token: WES, body: { id: "bad-2", choreId: "laundry", completedAt: "yesterday" } })).status,
    400
  );
  assert.equal((await call("POST", "/completions", { token: WES, body: { choreId: "laundry", completedAt: "2026-09-14T11:30:00.000Z" } })).status, 400);
  assert.equal((await call("GET", "/completions?since=notadate", { token: WES })).status, 400);
});

test("sync delta: since is exclusive, deletes propagate, chores only when version differs", async () => {
  tick();
  const mark = clock.toISOString();
  tick();
  const wes = await call("POST", "/completions", {
    token: WES,
    body: { id: "c-wes-1", choreId: "garbage-can-to-street-sunday", completedAt: "2026-09-14T13:00:00.000Z" },
  });
  assert.equal(wes.status, 201);

  const full = await call("GET", "/sync", { token: ANNE });
  assert.equal(full.status, 200);
  assert.equal(full.body.person, "anne");
  assert.equal(full.body.choresVersion, 1);
  assert.equal(full.body.chores.length, 31, "no choresVersion param → chores included");
  assert.equal(full.body.completions.length, 2);

  const delta = await call("GET", `/sync?since=${encodeURIComponent(mark)}&choresVersion=1`, { token: ANNE });
  assert.equal(delta.body.chores, undefined, "matching choresVersion → chores omitted");
  assert.deepEqual(
    delta.body.completions.map((c) => c.id),
    ["c-wes-1"],
    "only rows updated after `since`"
  );

  const stale = await call("GET", "/sync?choresVersion=0", { token: ANNE });
  assert.equal(stale.body.chores.length, 31, "stale choresVersion → chores included");

  tick();
  const mark2 = clock.toISOString();
  tick();
  const del = await call("DELETE", "/completions/c-anne-1", { token: WES });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  const delAgain = await call("DELETE", "/completions/c-anne-1", { token: WES });
  assert.equal(delAgain.status, 200, "delete is idempotent");
  assert.equal(delAgain.body.updatedAt, del.body.updatedAt, "second delete does not bump updatedAt");
  assert.equal((await call("DELETE", "/completions/never-existed", { token: WES })).status, 404);

  const after = await call("GET", `/sync?since=${encodeURIComponent(mark2)}&choresVersion=1`, { token: ANNE });
  assert.deepEqual(after.body.completions.map((c) => [c.id, c.deleted]), [["c-anne-1", true]]);

  const total = app.db.prepare("SELECT COUNT(*) AS n FROM completions").get().n;
  assert.equal(total, 2, "soft delete keeps the row");
});

test("devices table records lastSeen per token", () => {
  const rows = app.db.prepare("SELECT person, label, lastSeen FROM devices ORDER BY person").all();
  assert.equal(rows.length, 2);
  assert.equal(rows[0].person, "anne");
  assert.equal(rows[0].label, "Anne test");
  assert.ok(rows[0].lastSeen);
});
