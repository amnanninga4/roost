// R-9: shopping items, meals, projects + subtasks share the completions seq counter and ride /sync.
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
const WES = "wes-token-0123456789abcdef";

let dir, base, app;
const logged = [];
let clock = new Date("2026-09-14T12:00:00.000Z");
const tick = (ms = 1000) => (clock = new Date(clock.getTime() + ms));

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-lists-test-"));
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

const count = (table) => app.db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get().n;
const seqOf = () => Number(app.db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);

test("lists start empty and need auth", async () => {
  for (const t of ["shopping_items", "meals", "projects", "project_subtasks", "wishlist_items"]) assert.equal(count(t), 0, t);
  assert.equal((await call("POST", "/shopping", { body: { id: "s", title: "x" } })).status, 401);
  assert.equal((await call("POST", "/wishlist", { body: { id: "w", title: "x" } })).status, 401);
  assert.equal((await call("PATCH", "/meals/m", { body: { title: "x" } })).status, 401);
  assert.equal((await call("DELETE", "/projects/p")).status, 401);
  const sync = await call("GET", "/sync?choresVersion=1", { token: ANNE });
  assert.equal(sync.status, 200);
  assert.deepEqual([sync.body.shopping, sync.body.meals, sync.body.projects, sync.body.subtasks, sync.body.wishlist], [[], [], [], [], []]);
  assert.equal(sync.body.cursor, 0);
});

test("shopping: create (addedBy from token), replay, bought stamps and clears, soft delete", async () => {
  tick();
  const body = { id: "sh-1", title: "Oat milk" };
  const first = await call("POST", "/shopping", { token: ANNE, body });
  assert.equal(first.status, 201);
  assert.equal(first.body.addedBy, "anne");
  assert.equal(first.body.bought, false);
  assert.equal(first.body.boughtBy, null);
  assert.equal(first.body.boughtAt, null);
  assert.equal(first.body.deleted, false);
  assert.equal(first.body.seq, 1);

  tick();
  const replay = await call("POST", "/shopping", { token: WES, body: { ...body, title: "Changed on replay" } });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, first.body, "replay returns the original row unchanged");
  assert.equal(count("shopping_items"), 1);

  tick();
  const bought = await call("PATCH", "/shopping/sh-1", { token: WES, body: { bought: true } });
  assert.equal(bought.status, 200);
  assert.equal(bought.body.bought, true);
  assert.equal(bought.body.boughtBy, "wes");
  assert.equal(bought.body.boughtAt, clock.toISOString());
  assert.equal(bought.body.seq, 2, "patch bumps seq");

  tick();
  const again = await call("PATCH", "/shopping/sh-1", { token: ANNE, body: { bought: true } });
  assert.equal(again.body.boughtBy, "wes", "re-sending bought=true keeps the first stamp");
  assert.equal(again.body.boughtAt, bought.body.boughtAt);

  tick();
  const renamed = await call("PATCH", "/shopping/sh-1", { token: ANNE, body: { title: "Oat milk (barista)" } });
  assert.equal(renamed.body.title, "Oat milk (barista)");
  assert.equal(renamed.body.bought, true, "title patch leaves bought alone");

  const unbought = await call("PATCH", "/shopping/sh-1", { token: ANNE, body: { bought: false } });
  assert.equal(unbought.body.bought, false);
  assert.equal(unbought.body.boughtBy, null);
  assert.equal(unbought.body.boughtAt, null);

  const del = await call("DELETE", "/shopping/sh-1", { token: ANNE });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  const delSeq = del.body.seq;
  const delAgain = await call("DELETE", "/shopping/sh-1", { token: ANNE });
  assert.equal(delAgain.status, 200, "delete is idempotent");
  assert.equal(delAgain.body.seq, delSeq, "second delete does not bump seq");
  assert.equal((await call("PATCH", "/shopping/sh-1", { token: ANNE, body: { title: "x" } })).status, 404, "deleted row is gone for PATCH");
  assert.equal(count("shopping_items"), 1, "soft delete keeps the row");

  const replayDeleted = await call("POST", "/shopping", { token: ANNE, body });
  assert.equal(replayDeleted.status, 200);
  assert.equal(replayDeleted.body.deleted, true, "replaying a POST for a deleted id returns the deleted row, no resurrection");
});

test("shopping validation: bad id, bad title, empty/unknown patch, bad bool, unknown row", async () => {
  const post = (body) => call("POST", "/shopping", { token: WES, body });
  assert.equal((await post({ title: "no id" })).status, 400);
  assert.equal((await post({ id: "has space", title: "x" })).status, 400);
  assert.equal((await post({ id: "x".repeat(65), title: "x" })).status, 400);
  assert.equal((await post({ id: "sh-bad", title: "" })).status, 400);
  assert.equal((await post({ id: "sh-bad", title: "   " })).status, 400);
  assert.equal((await post({ id: "sh-bad", title: "x".repeat(201) })).status, 400);
  assert.equal((await post({ id: "sh-bad", title: 42 })).status, 400);
  assert.equal((await call("POST", "/shopping", { token: WES, raw: "null" })).status, 400);
  assert.equal((await call("POST", "/shopping", { token: WES, raw: "[1]" })).status, 400);
  assert.equal((await call("POST", "/shopping", { token: WES, raw: "{nope" })).status, 400);

  assert.equal((await post({ id: "sh-ok", title: "ok" })).status, 201);
  const patch = (body) => call("PATCH", "/shopping/sh-ok", { token: WES, body });
  assert.equal((await patch({})).status, 400, "empty patch");
  assert.equal((await patch({ nothing: 1 })).status, 400, "no recognised field");
  assert.equal((await patch({ bought: "yes" })).status, 400);
  assert.equal((await patch({ title: null })).status, 400);
  assert.equal((await patch({ title: "" })).status, 400);
  assert.equal((await call("PATCH", "/shopping/never", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("DELETE", "/shopping/never", { token: WES })).status, 404);
  assert.equal((await call("PATCH", "/shopping/bad%20id", { token: WES, body: { title: "x" } })).status, 404, "id outside ID_RE does not route");
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("meals: create, patch fields, nextUp is exclusive with a seq per cleared row, delete", async () => {
  tick();
  const a = await call("POST", "/meals", { token: ANNE, body: { id: "m-a", title: "Tacos", tag: "Weeknight" } });
  assert.equal(a.status, 201);
  assert.deepEqual(
    { tag: a.body.tag, lastMadeAt: a.body.lastMadeAt, nextUp: a.body.nextUp, deleted: a.body.deleted },
    { tag: "Weeknight", lastMadeAt: null, nextUp: false, deleted: false }
  );
  const b = await call("POST", "/meals", { token: ANNE, body: { id: "m-b", title: "Chili" } });
  assert.equal(b.body.tag, "", "tag defaults to empty");
  const c = await call("POST", "/meals", { token: WES, body: { id: "m-c", title: "Ramen", nextUp: true } });
  assert.equal(c.body.nextUp, true, "nextUp can be set on create");

  const replay = await call("POST", "/meals", { token: WES, body: { id: "m-a", title: "Other" } });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, a.body);

  tick();
  const made = await call("PATCH", "/meals/m-a", { token: ANNE, body: { lastMadeAt: "2026-09-13T23:30:00.000Z", tag: "Sunday" } });
  assert.equal(made.status, 200);
  assert.equal(made.body.lastMadeAt, "2026-09-13T23:30:00.000Z");
  assert.equal(made.body.tag, "Sunday");
  const cleared = await call("PATCH", "/meals/m-a", { token: ANNE, body: { lastMadeAt: null } });
  assert.equal(cleared.body.lastMadeAt, null, "lastMadeAt can be cleared with null");

  // nextUp exclusivity: m-c holds it; setting m-a clears m-c with its own seq.
  const seqBefore = seqOf();
  const next = await call("PATCH", "/meals/m-a", { token: WES, body: { nextUp: true } });
  assert.equal(next.body.nextUp, true);
  assert.equal(seqOf(), seqBefore + 2, "one seq for the cleared meal, one for the target");
  const rows = app.db.prepare("SELECT id, nextUp, seq FROM meals ORDER BY id").all().map((r) => ({ ...r }));
  assert.deepEqual(
    rows.map((r) => [r.id, r.nextUp]),
    [["m-a", 1], ["m-b", 0], ["m-c", 0]]
  );
  const mc = rows.find((r) => r.id === "m-c");
  assert.equal(mc.seq, seqBefore + 1, "cleared row took the first new seq");
  assert.equal(next.body.seq, seqBefore + 2, "target took the last");

  const delta = await call("GET", `/sync?cursor=${seqBefore}&choresVersion=1`, { token: ANNE });
  assert.deepEqual(delta.body.meals.map((m) => [m.id, m.nextUp]), [["m-c", false], ["m-a", true]], "both rows ride the delta");

  const same = await call("PATCH", "/meals/m-a", { token: WES, body: { nextUp: true } });
  assert.equal(seqOf(), seqBefore + 3, "re-asserting nextUp only bumps the target");
  assert.equal(same.body.nextUp, true);

  const off = await call("PATCH", "/meals/m-a", { token: WES, body: { nextUp: false } });
  assert.equal(off.body.nextUp, false);
  assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM meals WHERE nextUp = 1").get().n, 0, "nextUp=false clears without touching others");

  const del = await call("DELETE", "/meals/m-b", { token: ANNE });
  assert.equal(del.body.deleted, true);
  assert.equal((await call("DELETE", "/meals/m-b", { token: ANNE })).body.seq, del.body.seq);
  assert.equal((await call("PATCH", "/meals/m-b", { token: ANNE, body: { title: "x" } })).status, 404);
});

test("meals validation", async () => {
  const post = (body) => call("POST", "/meals", { token: WES, body });
  assert.equal((await post({ id: "m-bad", title: "x", tag: "t".repeat(41) })).status, 400);
  assert.equal((await post({ id: "m-bad", title: "x", tag: 7 })).status, 400);
  assert.equal((await post({ id: "m-bad", title: "x", lastMadeAt: "yesterday" })).status, 400);
  assert.equal((await post({ id: "m-bad", title: "x", nextUp: "yes" })).status, 400);
  assert.equal((await post({ id: "m-bad" })).status, 400);
  assert.equal((await post({ id: "bad id", title: "x" })).status, 400);
  assert.equal((await post({ id: "m-tag40", title: "x", tag: "t".repeat(40) })).status, 201, "tag may be exactly 40");
  const patch = (body) => call("PATCH", "/meals/m-tag40", { token: WES, body });
  assert.equal((await patch({})).status, 400);
  assert.equal((await patch({ tag: null })).status, 400, "tag is not nullable");
  assert.equal((await patch({ lastMadeAt: "2026-09-13" })).status, 400);
  assert.equal((await patch({ nextUp: 1 })).status, 400);
  assert.equal((await call("PATCH", "/meals/never", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("DELETE", "/meals/never", { token: WES })).status, 404);
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});


test("wishlist: create with and without a price, replay, price patch and clear, bought stamps, delete, validation", async () => {
  tick();
  const tv = await call("POST", "/wishlist", { token: ANNE, body: { id: "w-1", title: "Bigger TV", priceCents: 59900 } });
  assert.equal(tv.status, 201);
  assert.equal(tv.body.priceCents, 59900);
  assert.equal(tv.body.addedBy, "anne");
  assert.equal(tv.body.bought, false);
  assert.equal(tv.body.boughtBy, null);
  assert.equal(tv.body.deleted, false);
  const trip = await call("POST", "/wishlist", { token: WES, body: { id: "w-2", title: "A weekend away" } });
  assert.equal(trip.status, 201);
  assert.equal(trip.body.priceCents, null, "no price is null, not zero");
  const replay = await call("POST", "/wishlist", { token: WES, body: { id: "w-1", title: "Changed", priceCents: 1 } });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, tv.body, "replay returns the original row unchanged");

  tick();
  const repriced = await call("PATCH", "/wishlist/w-1", { token: WES, body: { priceCents: 54999 } });
  assert.equal(repriced.status, 200);
  assert.equal(repriced.body.priceCents, 54999);
  assert.equal(repriced.body.title, "Bigger TV", "a price patch leaves the title alone");
  const cleared = await call("PATCH", "/wishlist/w-1", { token: WES, body: { priceCents: null } });
  assert.equal(cleared.body.priceCents, null, "a price can be cleared");
  const bought = await call("PATCH", "/wishlist/w-1", { token: WES, body: { bought: true } });
  assert.equal(bought.body.bought, true);
  assert.equal(bought.body.boughtBy, "wes");
  assert.equal(bought.body.boughtAt, clock.toISOString());
  const again = await call("PATCH", "/wishlist/w-1", { token: ANNE, body: { bought: true } });
  assert.equal(again.body.boughtBy, "wes", "re-sending bought=true keeps the first stamp");
  const unbought = await call("PATCH", "/wishlist/w-1", { token: ANNE, body: { bought: false } });
  assert.deepEqual([unbought.body.bought, unbought.body.boughtBy, unbought.body.boughtAt], [false, null, null]);

  const post = (body) => call("POST", "/wishlist", { token: WES, body });
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: -1 })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: 100_000_000 })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: 12.5 })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: "599" })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "" })).status, 400);
  assert.equal((await post({ title: "no id" })).status, 400);
  assert.equal((await post({ id: "w-max", title: "x", priceCents: 99_999_999 })).status, 201, "the ceiling is allowed");
  assert.equal((await post({ id: "w-zero", title: "free", priceCents: 0 })).status, 201, "zero is a price");
  const patch = (body) => call("PATCH", "/wishlist/w-1", { token: WES, body });
  assert.equal((await patch({})).status, 400, "empty patch");
  assert.equal((await patch({ priceCents: "x" })).status, 400);
  assert.equal((await patch({ bought: "yes" })).status, 400);
  assert.equal((await patch({ title: "" })).status, 400);
  assert.equal((await call("PATCH", "/wishlist/never", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("DELETE", "/wishlist/never", { token: WES })).status, 404);
  assert.equal(count("wishlist_items"), 4, "nothing created by the rejected requests");

  const del = await call("DELETE", "/wishlist/w-2", { token: WES });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  assert.equal((await call("DELETE", "/wishlist/w-2", { token: WES })).body.seq, del.body.seq, "delete is idempotent");
  assert.equal((await call("PATCH", "/wishlist/w-2", { token: WES, body: { title: "x" } })).status, 404, "deleted row is gone for PATCH");
  assert.equal((await call("POST", "/wishlist", { token: WES, body: { id: "w-2", title: "back?" } })).body.deleted, true, "no resurrection");
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("projects: create with subtasks in order, replay, patch, add/patch/delete subtasks, cascade delete with distinct seqs", async () => {
  tick();
  const seq0 = seqOf();
  const created = await call("POST", "/projects", {
    token: WES,
    body: { id: "p-1", title: "Fix the fence", subtasks: [{ id: "st-1", title: "Buy posts" }, { id: "st-2", title: "Dig holes" }, { id: "st-3", title: "Set posts" }] },
  });
  assert.equal(created.status, 201);
  assert.equal(created.body.seq, seq0 + 1, "project takes the first seq");
  assert.deepEqual(
    created.body.subtasks.map((s) => [s.id, s.sortOrder, s.seq, s.done, s.doneBy, s.doneAt, s.deleted]),
    [["st-1", 0, seq0 + 2, false, null, null, false], ["st-2", 1, seq0 + 3, false, null, null, false], ["st-3", 2, seq0 + 4, false, null, null, false]],
    "subtasks created in order, each with its own seq"
  );
  assert.equal(created.body.subtasks[0].projectId, "p-1");

  const replay = await call("POST", "/projects", { token: ANNE, body: { id: "p-1", title: "Other", subtasks: [{ id: "st-9", title: "extra" }] } });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, created.body, "replay returns the original project and subtasks; extra subtasks ignored");
  assert.equal(count("project_subtasks"), 3);

  const noSubs = await call("POST", "/projects", { token: ANNE, body: { id: "p-2", title: "Plan trip" } });
  assert.equal(noSubs.status, 201);
  assert.deepEqual(noSubs.body.subtasks, []);

  tick();
  const renamed = await call("PATCH", "/projects/p-1", { token: ANNE, body: { title: "Fix the back fence" } });
  assert.equal(renamed.status, 200);
  assert.equal(renamed.body.title, "Fix the back fence");
  assert.equal(renamed.body.subtasks.length, 3);

  const added = await call("POST", "/projects/p-1/subtasks", { token: ANNE, body: { id: "st-4", title: "Hang panels" } });
  assert.equal(added.status, 201);
  assert.equal(added.body.sortOrder, 3, "sortOrder defaults to one past the highest");
  assert.equal(added.body.projectId, "p-1");
  const addedReplay = await call("POST", "/projects/p-1/subtasks", { token: ANNE, body: { id: "st-4", title: "Different" } });
  assert.equal(addedReplay.status, 200);
  assert.deepEqual(addedReplay.body, added.body);
  const explicit = await call("POST", "/projects/p-1/subtasks", { token: ANNE, body: { id: "st-5", title: "Paint", sortOrder: 10 } });
  assert.equal(explicit.body.sortOrder, 10);

  tick();
  const done = await call("PATCH", "/subtasks/st-1", { token: WES, body: { done: true } });
  assert.equal(done.status, 200);
  assert.equal(done.body.done, true);
  assert.equal(done.body.doneBy, "wes");
  assert.equal(done.body.doneAt, clock.toISOString());
  tick();
  const doneAgain = await call("PATCH", "/subtasks/st-1", { token: ANNE, body: { done: true } });
  assert.equal(doneAgain.body.doneBy, "wes", "re-sending done=true keeps the first stamp");
  const moved = await call("PATCH", "/subtasks/st-1", { token: ANNE, body: { sortOrder: 5, title: "Buy 6 posts" } });
  assert.equal(moved.body.sortOrder, 5);
  assert.equal(moved.body.title, "Buy 6 posts");
  assert.equal(moved.body.done, true);
  const undone = await call("PATCH", "/subtasks/st-1", { token: ANNE, body: { done: false } });
  assert.deepEqual([undone.body.done, undone.body.doneBy, undone.body.doneAt], [false, null, null]);

  const delSub = await call("DELETE", "/subtasks/st-5", { token: ANNE });
  assert.equal(delSub.body.deleted, true);
  assert.equal((await call("DELETE", "/subtasks/st-5", { token: ANNE })).body.seq, delSub.body.seq, "idempotent");
  assert.equal((await call("PATCH", "/subtasks/st-5", { token: ANNE, body: { title: "x" } })).status, 404);

  // Cascade: p-1 has live st-1..st-4 and deleted st-5. Delete takes 4 subtask seqs + 1 project seq, all distinct.
  const before = seqOf();
  const delProject = await call("DELETE", "/projects/p-1", { token: WES });
  assert.equal(delProject.status, 200);
  assert.equal(delProject.body.deleted, true);
  assert.equal(seqOf(), before + 5, "4 live subtasks + the project each took a seq; the already-deleted one did not");
  const seqs = delProject.body.subtasks.map((s) => s.seq).concat(delProject.body.seq);
  assert.equal(new Set(seqs).size, seqs.length, "every cascaded row has a distinct seq");
  assert.ok(delProject.body.subtasks.every((s) => s.deleted), "every subtask reports deleted");
  assert.equal(delProject.body.seq, before + 5, "project takes the last seq so a cursor at it covers the whole cascade");
  assert.equal(delProject.body.subtasks.find((s) => s.id === "st-5").seq, delSub.body.seq, "already-deleted subtask keeps its seq");

  const delAgain = await call("DELETE", "/projects/p-1", { token: WES });
  assert.equal(delAgain.status, 200);
  assert.equal(seqOf(), before + 5, "second cascade delete bumps nothing");
  assert.equal((await call("PATCH", "/projects/p-1", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("POST", "/projects/p-1/subtasks", { token: WES, body: { id: "st-late", title: "x" } })).status, 400, "deleted project rejects new subtasks");
  assert.equal(count("projects"), 2);
  assert.equal(count("project_subtasks"), 5, "soft delete keeps every row");
});

test("projects validation: bad ids, bad bodies, unknown projectId, duplicate or taken subtask ids", async () => {
  const post = (body) => call("POST", "/projects", { token: WES, body });
  assert.equal((await post({ title: "no id" })).status, 400);
  assert.equal((await post({ id: "p-bad", title: "" })).status, 400);
  assert.equal((await post({ id: "p-bad", title: "x", subtasks: "nope" })).status, 400);
  assert.equal((await post({ id: "p-bad", title: "x", subtasks: [null] })).status, 400);
  assert.equal((await post({ id: "p-bad", title: "x", subtasks: [{ id: "bad id", title: "x" }] })).status, 400);
  assert.equal((await post({ id: "p-bad", title: "x", subtasks: [{ id: "st-x", title: "" }] })).status, 400);
  assert.equal((await post({ id: "p-bad", title: "x", subtasks: [{ id: "st-dup", title: "a" }, { id: "st-dup", title: "b" }] })).status, 400, "duplicate ids in one request");
  assert.equal((await post({ id: "p-bad", title: "x", subtasks: [{ id: "st-1", title: "taken" }] })).status, 400, "subtask id already belongs to another project");
  assert.equal(count("projects"), 2, "nothing created by the rejected requests");

  const sub = (body) => call("POST", "/projects/p-2/subtasks", { token: WES, body });
  assert.equal((await call("POST", "/projects/never/subtasks", { token: WES, body: { id: "st-n", title: "x" } })).status, 400, "unknown projectId");
  assert.equal((await sub({ title: "no id" })).status, 400);
  assert.equal((await sub({ id: "st-n", title: "x", sortOrder: -1 })).status, 400);
  assert.equal((await sub({ id: "st-n", title: "x", sortOrder: 1.5 })).status, 400);
  assert.equal((await sub({ id: "st-n", title: "x", sortOrder: "2" })).status, 400);
  assert.equal((await sub({ id: "st-n", title: "x" })).status, 201);

  assert.equal((await call("PATCH", "/projects/p-2", { token: WES, body: {} })).status, 400);
  assert.equal((await call("PATCH", "/projects/p-2", { token: WES, body: { title: "x".repeat(201) } })).status, 400);
  assert.equal((await call("PATCH", "/projects/never", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("DELETE", "/projects/never", { token: WES })).status, 404);
  assert.equal((await call("PATCH", "/subtasks/st-n", { token: WES, body: { done: "yes" } })).status, 400);
  assert.equal((await call("PATCH", "/subtasks/st-n", { token: WES, body: {} })).status, 400);
  assert.equal((await call("PATCH", "/subtasks/never", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("DELETE", "/subtasks/never", { token: WES })).status, 404);
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("/sync carries all five list arrays, cursor is the max seq across tables, same-tick write after a sync is delivered", async () => {
  const full = await call("GET", "/sync?choresVersion=1", { token: ANNE });
  assert.equal(full.status, 200);
  for (const key of ["completions", "shopping", "meals", "projects", "subtasks", "wishlist"]) assert.ok(Array.isArray(full.body[key]), key);
  assert.equal(full.body.cursor, seqOf(), "cursor equals the max seq across every table");
  assert.equal(full.body.shopping.length, count("shopping_items"), "deleted shopping rows included");
  assert.ok(full.body.shopping.some((s) => s.deleted));
  assert.ok(full.body.projects.some((p) => p.deleted));
  assert.ok(full.body.subtasks.some((s) => s.deleted));
  assert.ok(full.body.meals.some((m) => m.deleted));
  assert.ok(full.body.wishlist.some((w) => w.deleted));
  assert.deepEqual(full.body.completions, [], "no completions were made in this suite");
  const allSeqs = ["shopping", "meals", "projects", "subtasks", "wishlist"].flatMap((k) => full.body[k]).map((r) => r.seq);
  assert.equal(Math.max(...allSeqs), full.body.cursor);
  assert.equal(new Set(allSeqs).size, allSeqs.length, "no seq is shared between tables");

  const idle = await call("GET", `/sync?cursor=${full.body.cursor}&choresVersion=1`, { token: ANNE });
  assert.deepEqual([idle.body.shopping, idle.body.meals, idle.body.projects, idle.body.subtasks, idle.body.wishlist, idle.body.completions], [[], [], [], [], [], []]);
  assert.equal(idle.body.cursor, full.body.cursor, "cursor holds when nothing changed");

  // Client syncs, then a write lands in the SAME clock tick (no tick()). A time cursor would drop it.
  const cursor = idle.body.cursor;
  const write = await call("POST", "/shopping", { token: WES, body: { id: "sh-same-tick", title: "Eggs" } });
  assert.equal(write.status, 201);
  assert.equal(write.body.seq, cursor + 1);
  const delta = await call("GET", `/sync?cursor=${cursor}&choresVersion=1`, { token: ANNE });
  assert.deepEqual(delta.body.shopping.map((s) => s.id), ["sh-same-tick"], "same-tick write is not lost");
  assert.deepEqual([delta.body.meals, delta.body.projects, delta.body.subtasks, delta.body.wishlist, delta.body.completions], [[], [], [], [], []]);
  assert.equal(delta.body.cursor, cursor + 1);

  // A delta touching every table at once, from one cursor, with the cursor advancing to the newest row.
  const c2 = delta.body.cursor;
  await call("POST", "/meals", { token: WES, body: { id: "m-sync", title: "Soup" } });
  await call("POST", "/projects", { token: WES, body: { id: "p-sync", title: "Garage", subtasks: [{ id: "st-sync", title: "Sort boxes" }] } });
  await call("POST", "/completions", { token: WES, body: { id: "c-sync", choreId: "laundry", completedAt: "2026-09-14T13:00:00.000Z" } });
  await call("POST", "/wishlist", { token: WES, body: { id: "w-sync", title: "Kayak", priceCents: 89900 } });
  const mixed = await call("GET", `/sync?cursor=${c2}&choresVersion=1`, { token: ANNE });
  assert.deepEqual(
    {
      shopping: mixed.body.shopping.map((r) => r.id),
      meals: mixed.body.meals.map((r) => r.id),
      projects: mixed.body.projects.map((r) => r.id),
      subtasks: mixed.body.subtasks.map((r) => r.id),
      completions: mixed.body.completions.map((r) => r.id),
      wishlist: mixed.body.wishlist.map((r) => r.id),
    },
    { shopping: [], meals: ["m-sync"], projects: ["p-sync"], subtasks: ["st-sync"], completions: ["c-sync"], wishlist: ["w-sync"] }
  );
  assert.equal(mixed.body.cursor, c2 + 5);
  assert.equal(mixed.body.cursor, seqOf());
  assert.equal(mixed.body.chores, undefined, "matching choresVersion → chores omitted");
  assert.equal((await call("GET", "/health")).body.cursor, seqOf(), "health cursor tracks the shared counter");
});
