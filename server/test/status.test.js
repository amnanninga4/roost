import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");
const ANNE = "anne-token-0123456789abcdef";

let dir, base, app, tokensPath;
let clock = new Date("2026-09-14T17:00:00.000Z"); // afternoon Chicago on Sep 14

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-status-"));
  tokensPath = join(dir, "tokens.json");
  writeFileSync(
    tokensPath,
    JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" } })
  );
  app = createApp({
    dbPath: join(dir, "roost.db"),
    choresPath: CHORES,
    tokensPath,
    now: () => clock,
  });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});

after(async () => {
  await new Promise((r) => app.server.close(r));
  app.db.close();
  rmSync(dir, { recursive: true, force: true });
});

test("GET /status returns 200 text/html with a completion title after POST", async () => {
  const post = await fetch(base + "/completions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${ANNE}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      id: "status-c1",
      choreId: "scoop-litter",
      completedAt: "2026-09-14T16:30:00.000Z",
    }),
  });
  assert.equal(post.status, 201);
  const created = await post.json();
  assert.equal(created.choreId, "scoop-litter");

  const res = await fetch(base + "/status");
  assert.equal(res.status, 200);
  const ct = res.headers.get("content-type") || "";
  assert.match(ct, /text\/html/);
  const html = await res.text();
  assert.match(html, /Scoop litter/);
  assert.match(html, /http-equiv="refresh"/i);
  assert.match(html, /Streak \d+ · Week \d+/);
  assert.match(html, /Overdue/);
  assert.match(html, /updated \d{2}:\d{2}/);
});

test("GET /status shows overdue stage labels when chores are past due", async () => {
  // clock is Mon Sep 14 afternoon CT; activeFrom Sep 7 → weekly of Sep 7 ended Sun Sep 13 → 1 day overdue
  const res = await fetch(base + "/status");
  const html = await res.text();
  assert.match(html, /1 day late|3 days late|5\+ days late|due today/);
  assert.match(html, /stage-chip/);
  assert.match(html, /Streak/);
});

test("GET /fonts serves a real file with immutable cache and 404s missing/traversal", async () => {
  const ok = await fetch(base + "/fonts/Fraunces-Variable.ttf");
  assert.equal(ok.status, 200);
  const cache = ok.headers.get("cache-control") || "";
  assert.match(cache, /immutable/i);
  assert.match(cache, /max-age=/i);
  const buf = Buffer.from(await ok.arrayBuffer());
  assert.ok(buf.byteLength > 1000);

  const missing = await fetch(base + "/fonts/no-such-font.ttf");
  assert.equal(missing.status, 404);

  // Encoded ".." so the path still hits /fonts/* after URL parsing
  const traversal = await fetch(base + "/fonts/" + encodeURIComponent("../package.json"));
  assert.equal(traversal.status, 404);

  const nested = await fetch(base + "/fonts/subdir/Fraunces-Variable.ttf");
  assert.equal(nested.status, 404);
});

test("GET /status.json returns people with streak/week and titles", async () => {
  const res = await fetch(base + "/status.json");
  assert.equal(res.status, 200);
  const ct = res.headers.get("content-type") || "";
  assert.match(ct, /application\/json/);
  const body = await res.json();
  assert.ok(Array.isArray(body.people));
  assert.equal(body.people.length, 2);
  const ids = body.people.map((p) => p.id).sort();
  assert.deepEqual(ids, ["anne", "wes"]);
  for (const p of body.people) {
    assert.equal(typeof p.name, "string");
    assert.equal(typeof p.streak, "number");
    assert.equal(typeof p.week, "number");
    assert.ok(Array.isArray(p.today));
    assert.ok(Array.isArray(p.due));
    for (const item of p.today) assert.equal(typeof item.title, "string");
    for (const item of p.due) {
      assert.equal(typeof item.title, "string");
      assert.equal(typeof item.stage, "string");
    }
  }
  const anne = body.people.find((p) => p.id === "anne");
  assert.ok(anne.today.some((t) => t.title === "Scoop litter") || anne.week >= 1);
});

test("GET /status HTML has Anne and Wes columns plus stage class names", async () => {
  const res = await fetch(base + "/status");
  const html = await res.text();
  assert.match(html, /person-anne/);
  assert.match(html, /person-wes/);
  assert.match(html, />Anne\s/);
  assert.match(html, />Wes\s/);
  assert.match(html, /stage-nudge|stage-pointed|stage-alert|warning|danger/);
  assert.match(html, /--accent:\s*#2F8F72/i);
  assert.match(html, /Fraunces/);
  assert.match(html, /Nunito Sans/);
  assert.match(html, /IBM Plex Mono/);
});

test("GET /favicon.ico returns SVG before auth with long cache", async () => {
  const res = await fetch(base + "/favicon.ico");
  assert.equal(res.status, 200);
  const ct = res.headers.get("content-type") || "";
  assert.match(ct, /image\/svg\+xml/);
  const cache = res.headers.get("cache-control") || "";
  assert.match(cache, /max-age=31536000/i);
  assert.match(cache, /immutable/i);
  const body = await res.text();
  assert.match(body, /<svg/i);
  assert.match(body, /#2F8F72/i);
});

test("status.json includes activeFrom and board honors meta value", async () => {
  const { setMeta } = await import("../src/db.js");
  // Far-future activeFrom → nothing should be overdue yet relative to clock (Sep 14 2026)
  setMeta(app.db, "activeFrom", "2026-09-14");

  const res = await fetch(base + "/status.json");
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.activeFrom, "2026-09-14");

  // With activeFrom = today, periods starting today are dueToday / not multi-day late.
  // At minimum: overdue list should not treat pre-activeFrom history as ancient debt.
  for (const p of body.people) {
    for (const item of p.due) {
      assert.notEqual(item.stage, "alert", "fresh household start should not show 5+ day alert for never-done chores yet");
    }
  }

  // Push activeFrom back to Sep 1 and expect some overdue again
  setMeta(app.db, "activeFrom", "2026-09-01");
  const late = await (await fetch(base + "/status.json")).json();
  assert.equal(late.activeFrom, "2026-09-01");
  const anyDue = late.people.some((p) => p.due.length > 0);
  assert.ok(anyDue, "earlier activeFrom surfaces due/overdue chores on the board");
});

test("GET /health and /status.json expose backup from verify-status fixture", async () => {
  const prev = process.env.ROOST_VERIFY_STATUS;
  const statusPath = join(dir, "verify-status.json");
  try {
    writeFileSync(
      statusPath,
      JSON.stringify({
        at: "2026-09-13T09:30:00.000Z",
        ok: true,
        seq: 123,
        integrity: "ok",
        backup: "/var/backups/roost/roost-2026-09-13.db",
      }) + "\n",
    );
    process.env.ROOST_VERIFY_STATUS = statusPath;

    const health = await fetch(base + "/health");
    assert.equal(health.status, 200);
    const h = await health.json();
    assert.deepEqual(h.backup, { at: "2026-09-13T09:30:00.000Z", ok: true, seq: 123 });

    const sj = await (await fetch(base + "/status.json")).json();
    assert.deepEqual(sj.backup, { at: "2026-09-13T09:30:00.000Z", ok: true, seq: 123 });

    // HTML board stays household-only — no ops backup blob.
    const html = await (await fetch(base + "/status")).text();
    assert.doesNotMatch(html, /verify-status|2026-09-13T09:30:00/);
  } finally {
    if (prev === undefined) delete process.env.ROOST_VERIFY_STATUS;
    else process.env.ROOST_VERIFY_STATUS = prev;
  }
});

test("GET /health and /status.json backup is null when verify-status absent", async () => {
  const prev = process.env.ROOST_VERIFY_STATUS;
  try {
    process.env.ROOST_VERIFY_STATUS = join(dir, "no-such-verify-status.json");
    const h = await (await fetch(base + "/health")).json();
    assert.equal(h.backup, null);
    const sj = await (await fetch(base + "/status.json")).json();
    assert.equal(sj.backup, null);
  } finally {
    if (prev === undefined) delete process.env.ROOST_VERIFY_STATUS;
    else process.env.ROOST_VERIFY_STATUS = prev;
  }
});

test("GET /health and /status.json backup is null when verify-status malformed", async () => {
  const prev = process.env.ROOST_VERIFY_STATUS;
  const statusPath = join(dir, "verify-status-bad.json");
  try {
    writeFileSync(statusPath, "{not-json");
    process.env.ROOST_VERIFY_STATUS = statusPath;
    const h = await (await fetch(base + "/health")).json();
    assert.equal(h.backup, null);
    const sj = await (await fetch(base + "/status.json")).json();
    assert.equal(sj.backup, null);
  } finally {
    if (prev === undefined) delete process.env.ROOST_VERIFY_STATUS;
    else process.env.ROOST_VERIFY_STATUS = prev;
  }
});
