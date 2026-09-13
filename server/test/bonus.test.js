// R-15: bonus "first to claim" tasks share the seq counter and ride /sync; unclaimed past claimBy → auto-assigned.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import {
  chicagoWeek,
  weekPoints,
  autoAssignExpired,
  insertBonus,
  claimBonus,
  completeBonus,
  deleteBonus,
} from "../src/bonus.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");

const ANNE = "anne-token-0123456789abcdef";
const WES = "wes-token-0123456789abcdef";

let dir, base, app;
const logged = [];
// Monday 2026-09-14 07:00 America/Chicago (CDT).
let clock = new Date("2026-09-14T12:00:00.000Z");
const tick = (ms = 1000) => (clock = new Date(clock.getTime() + ms));
const HOUR = 3_600_000;
const inHours = (h) => new Date(clock.getTime() + h * HOUR).toISOString();

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-bonus-test-"));
  const tokensPath = join(dir, "tokens.json");
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

const count = () => app.db.prepare("SELECT COUNT(*) AS n FROM bonus_tasks").get().n;
const seqOf = () => Number(app.db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
const create = (token, body) => call("POST", "/bonus", { token, body });
const claim = (token, id) => call("POST", `/bonus/${id}/claim`, { token });
const complete = (token, id) => call("POST", `/bonus/${id}/complete`, { token });
const sync = (token, cursor) => call("GET", `/sync?cursor=${cursor}&choresVersion=1`, { token });

test("bonus POST: 201 with createdBy from the token and a seq from the shared counter; replay is 200 and unchanged", async () => {
  const body = { id: "b-1", title: "  Pay internet bill  ", points: 2, claimBy: "2026-09-20T04:59:59Z" };
  assert.equal((await call("POST", "/bonus", { body })).status, 401);
  assert.equal((await call("GET", "/bonus")).status, 401);

  const first = await create(ANNE, body);
  assert.equal(first.status, 201);
  assert.deepEqual(first.body, {
    id: "b-1",
    title: "Pay internet bill",
    points: 2,
    claimBy: "2026-09-20T04:59:59.000Z",
    claimedBy: null,
    claimedAt: null,
    assignedTo: null,
    completedAt: null,
    createdBy: "anne",
    createdAt: clock.toISOString(),
    updatedAt: clock.toISOString(),
    deleted: false,
    seq: 1,
  });
  assert.equal(seqOf(), 1, "bonus rows take the same meta.seq counter as completions");

  tick();
  const replay = await create(WES, { ...body, title: "Changed on replay", points: 9 });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, first.body, "replay returns the original row unchanged");
  assert.equal(count(), 1);
});

test("bonus validation: bad id, title, points, claimBy and bodies are 400; unknown ids are 404; no 500s", async () => {
  const ok = { id: "b-v", title: "Valid", points: 1, claimBy: "2026-09-20T05:00:00.000Z" };
  const bad = async (patch, why) => assert.equal((await create(WES, { ...ok, ...patch })).status, 400, why);
  await bad({ id: "has space/slash" }, "id charset");
  await bad({ id: "x".repeat(65) }, "id length");
  await bad({ id: undefined }, "id missing");
  await bad({ title: undefined }, "title missing");
  await bad({ title: "" }, "title empty");
  await bad({ title: "   " }, "title blank");
  await bad({ title: "x".repeat(201) }, "title too long");
  await bad({ title: 42 }, "title type");
  await bad({ points: undefined }, "points missing");
  await bad({ points: 0 }, "points below 1");
  await bad({ points: 11 }, "points above 10");
  await bad({ points: 2.5 }, "points fraction");
  await bad({ points: "3" }, "points string");
  await bad({ claimBy: undefined }, "claimBy missing");
  await bad({ claimBy: "sunday" }, "claimBy words");
  await bad({ claimBy: "2026-09-20T05:00:00+00:00" }, "claimBy must be the Z form");
  await bad({ claimBy: "2026-09-20" }, "claimBy date only");
  assert.equal((await call("POST", "/bonus", { token: WES, raw: "null" })).status, 400);
  assert.equal((await call("POST", "/bonus", { token: WES, raw: "[1,2]" })).status, 400);
  assert.equal((await call("POST", "/bonus", { token: WES, raw: "{not json" })).status, 400);
  assert.equal((await call("GET", "/bonus?cursor=notanumber", { token: WES })).status, 400);
  assert.equal((await claim(WES, "never-existed")).status, 404);
  assert.equal((await complete(WES, "never-existed")).status, 404);
  assert.equal((await call("DELETE", "/bonus/never-existed", { token: WES })).status, 404);
  assert.equal((await call("POST", "/bonus/b-1/nope", { token: WES })).status, 404, "unknown verb does not route");
  assert.equal((await call("PATCH", "/bonus/b-1", { token: WES, body: { title: "x" } })).status, 404, "no PATCH");
  assert.equal(count(), 1, "nothing was created");
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("claim: first person wins, the other gets 409 with claimedBy, the claimer's repeat is a 200 replay", async () => {
  tick();
  const made = await create(WES, { id: "b-race", title: "Return the library books", points: 3, claimBy: inHours(24) });
  assert.equal(made.status, 201);

  tick();
  const anne = await claim(ANNE, "b-race");
  assert.equal(anne.status, 200);
  assert.equal(anne.body.claimedBy, "anne");
  assert.equal(anne.body.claimedAt, clock.toISOString());
  assert.equal(anne.body.updatedAt, clock.toISOString());
  assert.equal(anne.body.assignedTo, null);
  assert.equal(anne.body.seq, made.body.seq + 1, "a claim takes a new seq");

  tick();
  const wes = await claim(WES, "b-race");
  assert.equal(wes.status, 409);
  assert.equal(wes.body.claimedBy, "anne");

  const again = await claim(ANNE, "b-race");
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, anne.body, "replay keeps the first claimedAt and seq");
});

test("claim after claimBy is 409; at exactly claimBy it still counts; a deleted task is 404", async () => {
  tick();
  const at = clock.toISOString();
  await create(ANNE, { id: "b-edge", title: "Edge", points: 1, claimBy: at });
  await create(ANNE, { id: "b-late", title: "Late", points: 1, claimBy: at });
  assert.equal((await claim(WES, "b-edge")).status, 200, "now == claimBy is not past the deadline");

  tick(1);
  const late = await claim(WES, "b-late");
  assert.equal(late.status, 409);
  assert.match(late.body.error, /deadline/);

  assert.equal((await call("DELETE", "/bonus/b-edge", { token: ANNE })).status, 200);
  assert.equal((await claim(WES, "b-edge")).status, 404);
  assert.equal((await call("DELETE", "/bonus/b-late", { token: ANNE })).status, 200, "deleted rows are never auto-assigned");
});

test("auto-assign on /sync: unclaimed past claimBy goes to the person with fewer points this week; ties to the non-creator", async () => {
  tick();
  // Anne earns 3 points this week by claiming and completing a task Wes posted.
  await create(WES, { id: "b-pts-anne", title: "Descale the kettle", points: 3, claimBy: inHours(24) });
  assert.equal((await claim(ANNE, "b-pts-anne")).status, 200);
  assert.equal((await complete(ANNE, "b-pts-anne")).status, 200);
  assert.deepEqual(weekPoints(app.db, clock), { anne: 3, wes: 0 });

  // Two tasks expire, one posted by each person: both go to Wes, who has fewer points.
  await create(ANNE, { id: "b-exp-a", title: "Posted by Anne", points: 2, claimBy: inHours(1) });
  await create(WES, { id: "b-exp-w", title: "Posted by Wes", points: 2, claimBy: inHours(1) });
  const before = seqOf();
  assert.deepEqual(autoAssignExpired(app.db, clock), [], "nothing has expired yet");
  tick(2 * HOUR);
  const s = await sync(ANNE, before);
  assert.equal(s.status, 200);
  assert.deepEqual(
    s.body.bonus.map((b) => [b.id, b.assignedTo, b.claimedBy, b.updatedAt]),
    [
      ["b-exp-a", "wes", null, clock.toISOString()],
      ["b-exp-w", "wes", null, clock.toISOString()],
    ]
  );
  assert.deepEqual(s.body.bonus.map((b) => b.seq), [before + 1, before + 2], "each assignment takes a new seq");
  assert.equal(s.body.cursor, before + 2, "the cursor folds the bonus seqs in");
  assert.deepEqual(autoAssignExpired(app.db, clock), [], "a second pass assigns nothing");

  // Wes catches up to 3 points; now ties go to whoever did not post the task.
  await create(ANNE, { id: "b-pts-wes", title: "Fix the wobbly shelf", points: 3, claimBy: inHours(24) });
  assert.equal((await claim(WES, "b-pts-wes")).status, 200);
  assert.equal((await complete(WES, "b-pts-wes")).status, 200);
  assert.deepEqual(weekPoints(app.db, clock), { anne: 3, wes: 3 });
  await create(ANNE, { id: "b-tie-a", title: "Tie, posted by Anne", points: 1, claimBy: inHours(1) });
  await create(WES, { id: "b-tie-w", title: "Tie, posted by Wes", points: 1, claimBy: inHours(1) });
  tick(2 * HOUR);
  const rows = autoAssignExpired(app.db, clock);
  assert.deepEqual(
    rows.map((r) => [r.id, r.assignedTo]),
    [
      ["b-tie-a", "wes"],
      ["b-tie-w", "anne"],
    ]
  );

  // A claimBy already in the past is accepted (an offline POST replayed late) and assigned on the next sync.
  const past = await create(WES, { id: "b-past", title: "Posted after its own deadline", points: 1, claimBy: inHours(-1) });
  assert.equal(past.status, 201);
  assert.equal(past.body.assignedTo, null);
  const next = await sync(WES, past.body.seq - 1);
  assert.deepEqual(next.body.bonus.map((b) => [b.id, b.assignedTo, b.seq]), [["b-past", "anne", past.body.seq + 1]]);
  assert.equal(next.body.cursor, past.body.seq + 1);
});

test("week tally: Monday 00:00 America/Chicago is the boundary; deleted tasks do not count", () => {
  const db = app.db;
  const lastWeek = "2026-09-14T04:59:59.999Z"; // Sunday 23:59:59.999 CDT
  const thisWeek = "2026-09-14T05:00:00.000Z"; // Monday 00:00:00.000 CDT
  for (const [id, points, at] of [
    ["b-wk-old", 5, lastWeek],
    ["b-wk-new", 4, thisWeek],
  ]) {
    assert.equal(insertBonus(db, { id, title: id, points, claimBy: thisWeek, createdBy: "wes" }, at).created, true);
    assert.equal(claimBonus(db, id, "anne", at).status, "claimed");
    assert.equal(completeBonus(db, id, "anne", at).row.completedAt, at);
  }
  assert.deepEqual(weekPoints(db, clock), { anne: 3 + 4, wes: 3 }, "the Sunday-night completion belongs to last week");
  assert.deepEqual(weekPoints(db, new Date(lastWeek)), { anne: 5, wes: 0 });
  assert.ok(deleteBonus(db, "b-wk-new", thisWeek).deletedAt);
  assert.deepEqual(weekPoints(db, clock), { anne: 3, wes: 3 }, "a deleted task stops counting");
});

test("complete: 403 unless the caller claimed or was assigned the task; repeat is a 200 replay", async () => {
  tick();
  await create(ANNE, { id: "b-done", title: "Clean the grill", points: 2, claimBy: inHours(24) });
  assert.equal((await complete(ANNE, "b-done")).status, 403, "unclaimed: not even the poster");
  assert.equal((await complete(WES, "b-done")).status, 403);
  assert.equal((await claim(ANNE, "b-done")).status, 200);
  assert.equal((await complete(WES, "b-done")).status, 403, "the other person");

  tick();
  const done = await complete(ANNE, "b-done");
  assert.equal(done.status, 200);
  assert.equal(done.body.completedAt, clock.toISOString());
  assert.equal(done.body.seq, seqOf(), "completion takes a new seq");

  tick();
  const again = await complete(ANNE, "b-done");
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, done.body, "replay keeps the first completedAt and seq");

  // Auto-assigned (previous test): the assignee may complete, the other person may not, nobody may claim.
  assert.equal((await complete(ANNE, "b-exp-a")).status, 403);
  const wes = await complete(WES, "b-exp-a");
  assert.equal(wes.status, 200);
  assert.equal(wes.body.assignedTo, "wes");
  assert.equal(wes.body.claimedBy, null);
  assert.equal((await claim(ANNE, "b-exp-w")).status, 409);
  assert.equal(weekPoints(app.db, clock).wes, 3 + 2, "an assignee's completion earns the points");

  assert.equal((await call("DELETE", "/bonus/b-done", { token: WES })).status, 200);
  assert.equal((await complete(ANNE, "b-done")).status, 404);
});

test("/sync carries the bonus delta and folds its seq into the cursor; GET /bonus is the same delta", async () => {
  const c0 = seqOf();
  const idle = await sync(ANNE, c0);
  assert.deepEqual(idle.body.bonus, []);
  assert.equal(idle.body.cursor, c0, "cursor holds when nothing changed");

  tick();
  const made = await create(WES, { id: "b-sync", title: "Sync me", points: 1, claimBy: inHours(24) });
  assert.equal(made.body.seq, c0 + 1);
  const s1 = await sync(ANNE, c0);
  assert.deepEqual(s1.body.completions, []);
  assert.deepEqual(s1.body.bonus, [made.body]);
  assert.equal(s1.body.cursor, c0 + 1, "a bonus-only change moves the cursor");

  // A completion and a bonus delete interleave on the one counter.
  const comp = await call("POST", "/completions", {
    token: ANNE,
    body: { id: "c-1", choreId: "scoop-litter", completedAt: clock.toISOString() },
  });
  assert.equal(comp.body.seq, c0 + 2);
  const del = await call("DELETE", "/bonus/b-sync", { token: ANNE });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  assert.equal(del.body.seq, c0 + 3);
  assert.equal((await call("DELETE", "/bonus/b-sync", { token: ANNE })).body.seq, c0 + 3, "second delete does not bump seq");

  const s2 = await sync(WES, c0 + 1);
  assert.deepEqual(s2.body.completions.map((c) => c.id), ["c-1"]);
  assert.deepEqual(s2.body.bonus.map((b) => [b.id, b.deleted, b.seq]), [["b-sync", true, c0 + 3]]);
  assert.equal(s2.body.cursor, c0 + 3);

  const s3 = await sync(WES, c0 + 2);
  assert.deepEqual(s3.body.completions, []);
  assert.equal(s3.body.cursor, c0 + 3, "a bonus seq beyond the last completion is folded in");

  const full = await sync(WES, 0);
  assert.equal(full.body.bonus.length, count(), "cursor 0 returns every bonus row, deleted included");
  assert.equal(full.body.cursor, seqOf());

  const list = await call("GET", `/bonus?cursor=${c0 + 1}`, { token: WES });
  assert.equal(list.status, 200);
  assert.deepEqual(list.body.bonus, s2.body.bonus);
  assert.equal(list.body.cursor, c0 + 3);
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("chicagoWeek: Monday 00:00 America/Chicago to the next Monday, across both DST changes", () => {
  const week = (iso) => chicagoWeek(new Date(iso));
  // Monday 2026-09-14 07:00 CDT.
  assert.deepEqual(week("2026-09-14T12:00:00Z"), { start: "2026-09-14T05:00:00.000Z", end: "2026-09-21T05:00:00.000Z" });
  // Sunday 2026-09-13 23:59:59 CDT is still the previous week.
  assert.deepEqual(week("2026-09-14T04:59:59Z"), { start: "2026-09-07T05:00:00.000Z", end: "2026-09-14T05:00:00.000Z" });
  // Fall back on Sunday 2026-11-01: the week starts in CDT (05:00Z) and ends in CST (06:00Z).
  assert.deepEqual(week("2026-11-01T12:00:00Z"), { start: "2026-10-26T05:00:00.000Z", end: "2026-11-02T06:00:00.000Z" });
  // Spring forward on Sunday 2026-03-08: starts in CST, ends in CDT.
  assert.deepEqual(week("2026-03-08T12:00:00Z"), { start: "2026-03-02T06:00:00.000Z", end: "2026-03-09T05:00:00.000Z" });
  // Year boundary: Thursday 2026-01-01 is in the week of Monday 2025-12-29.
  assert.deepEqual(week("2026-01-01T12:00:00Z"), { start: "2025-12-29T06:00:00.000Z", end: "2026-01-05T06:00:00.000Z" });
});
