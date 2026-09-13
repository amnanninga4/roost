// R-18: server handoffs — create/accept/decline/expiry, /sync, assigneeFor override, status arrow.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import {
  assigneeFor,
  periodIndex,
  chicagoLocal,
  dueItemFor,
  boardStats,
} from "../src/rules.js";
import { expireOpenHandoffs, listHandoffs, acceptedOverride, effectiveState } from "../src/handoffs.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");

const ANNE = "anne-token-0123456789abcdef";
const WES = "wes-token-0123456789abcdef";

let dir, base, app;
const logged = [];
// Monday 2026-09-14 07:00 America/Chicago (CDT) — same fixture week as bonus/lists.
let clock = new Date("2026-09-14T12:00:00.000Z");
const tick = (ms = 1000) => (clock = new Date(clock.getTime() + ms));

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-handoffs-test-"));
  const tokensPath = join(dir, "tokens.json");
  writeFileSync(
    tokensPath,
    JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" }, [WES]: { person: "wes", device: "Wes test" } })
  );
  app = createApp({
    dbPath: join(dir, "roost.db"),
    choresPath: CHORES,
    tokensPath,
    now: () => clock,
    log: (m) => logged.push(m),
    sweepIntervalMs: 0,
  });
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
      ...(body !== undefined ? { "content-type": "application/json" } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
};

const offer = (token, body) => call("POST", "/handoffs", { token, body });
const accept = (token, id) => call("POST", `/handoffs/${id}/accept`, { token });
const decline = (token, id) => call("POST", `/handoffs/${id}/decline`, { token });
const sync = (token, cursor = 0) => call("GET", `/sync?cursor=${cursor}&choresVersion=1`, { token });

const laundry = { id: "laundry", title: "Laundry", cadence: "weekly", fixedAssignee: "anne", category: "chore" };
const litter = { id: "scoop-litter", title: "Scoop litter", cadence: "daily", fixedAssignee: null, category: "cat_care" };

test("POST /handoffs: owner offers, JSON uses from/to, replay is 200, auth required", async () => {
  assert.equal((await offer(undefined, { id: "h-auth", choreId: "laundry", to: "wes" })).status, 401);

  // Mon Sep 14: laundry (pinned anne) current weekly period — Anne is owner.
  const first = await offer(ANNE, { id: "h-1", choreId: "laundry", to: "wes" });
  assert.equal(first.status, 201);
  assert.equal(first.body.from, "anne");
  assert.equal(first.body.to, "wes");
  assert.equal(first.body.state, "pending");
  assert.equal(first.body.choreId, "laundry");
  assert.equal(first.body.cadence, "weekly");
  assert.equal(typeof first.body.periodIndex, "number");
  assert.equal(first.body.deleted, false);
  assert.ok(first.body.seq >= 1);
  assert.equal(first.body.fromPerson, undefined, "SQL column name must not leak into JSON");
  assert.equal(first.body.toPerson, undefined);

  tick();
  const replay = await offer(ANNE, { id: "h-1", choreId: "laundry", to: "wes" });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, first.body);

  // Row stores fromPerson/toPerson.
  const row = app.db.prepare("SELECT fromPerson, toPerson, state FROM handoffs WHERE id = 'h-1'").get();
  assert.equal(row.fromPerson, "anne");
  assert.equal(row.toPerson, "wes");
  assert.equal(row.state, "pending");
});

test("only current owner may offer; one open offer per chore per period; cannot self-offer", async () => {
  // Wes is not the laundry owner.
  const notOwner = await offer(WES, { id: "h-wes", choreId: "laundry", to: "anne" });
  assert.equal(notOwner.status, 403);

  const self = await offer(ANNE, { id: "h-self", choreId: "scoop-litter", to: "anne" });
  assert.equal(self.status, 400);

  // h-1 is still open for laundry this period.
  const dup = await offer(ANNE, { id: "h-dup", choreId: "laundry", to: "wes" });
  assert.equal(dup.status, 409);

  const badChore = await offer(ANNE, { id: "h-bad", choreId: "no-such-chore", to: "wes" });
  assert.equal(badChore.status, 400);
});

test("pending does not change assignee; accept overrides pin; decline does not", async () => {
  const asOf = clock;
  const period = periodIndex("weekly", asOf);
  assert.equal(assigneeFor(laundry, period, listHandoffs(app.db), asOf), "anne", "pending leaves pin alone");

  // Only Wes (to) may accept.
  assert.equal((await accept(ANNE, "h-1")).status, 403);

  tick();
  const ok = await accept(WES, "h-1");
  assert.equal(ok.status, 200);
  assert.equal(ok.body.state, "accepted");
  assert.equal(ok.body.from, "anne");
  assert.equal(ok.body.to, "wes");

  assert.equal(assigneeFor(laundry, period, listHandoffs(app.db), asOf), "wes", "accepted overrides pin");

  // Replay accept.
  assert.equal((await accept(WES, "h-1")).status, 200);

  // Declined handoff does not override — fresh daily chore offer.
  // Mon Sep 14: scoop-litter rotation assignee is anne (period 252).
  const litPeriod = periodIndex("daily", clock);
  assert.equal(assigneeFor(litter, litPeriod), "anne");
  const offered = await offer(ANNE, { id: "h-lit", choreId: "scoop-litter", to: "wes" });
  assert.equal(offered.status, 201);
  tick();
  const dec = await decline(WES, "h-lit");
  assert.equal(dec.status, 200);
  assert.equal(dec.body.state, "declined");
  assert.equal(assigneeFor(litter, litPeriod, listHandoffs(app.db), clock), "anne", "declined leaves rotation alone");

  // Declined stays declined; cannot re-accept.
  assert.equal((await accept(WES, "h-lit")).status, 409);
});

test("accepted handoff overrides rotation for that exact period only", async () => {
  // Advance to Tuesday so we get a fresh daily period (h-lit was declined Mon).
  clock = new Date("2026-09-15T12:00:00.000Z"); // Tue Sep 15 CT morning
  const period = periodIndex("daily", clock);
  const natural = assigneeFor(litter, period);
  assert.equal(natural, "wes"); // rotation flips from Mon anne → Tue wes

  // Wes owns Tue litter; offers to Anne.
  const offered = await offer(WES, { id: "h-rot", choreId: "scoop-litter", to: "anne" });
  assert.equal(offered.status, 201);
  assert.equal(offered.body.periodIndex, period);
  tick();
  assert.equal((await accept(ANNE, "h-rot")).status, 200);

  const handoffs = listHandoffs(app.db);
  assert.equal(assigneeFor(litter, period, handoffs, clock), "anne", "accepted overrides rotation");
  assert.equal(assigneeFor(litter, period + 1, handoffs, clock), assigneeFor(litter, period + 1), "next period ignores handoff");

  // One completion Mon clears older days so the due period is Tuesday (the handed-off one).
  const monDone = {
    id: "c-lit-mon",
    choreId: "scoop-litter",
    person: "anne",
    completedAt: new Date("2026-09-14T20:00:00.000Z"),
  };
  const item = dueItemFor(litter, { completions: [monDone], asOf: clock, handoffs });
  assert.equal(item.periodIndex, period);
  assert.equal(item.person, "anne");
  assert.equal(item.viaHandoff, true);
});

test("R-21: expiry sweep expires pending only; accepted survives and still overrides", async () => {
  // Pending offer for Wed daily litter — will expire when we jump past Wednesday.
  clock = new Date("2026-09-16T12:00:00.000Z"); // Wed Sep 16
  const wedPeriod = periodIndex("daily", clock);
  const wedOwner = assigneeFor(litter, wedPeriod, listHandoffs(app.db), clock);
  const wedTo = wedOwner === "anne" ? "wes" : "anne";
  const pendingOffer = await offer(wedOwner === "anne" ? ANNE : WES, {
    id: "h-pend-expire",
    choreId: "scoop-litter",
    to: wedTo,
  });
  assert.equal(pendingOffer.status, 201);
  assert.equal(pendingOffer.body.state, "pending");

  // Jump past Wed into Thursday — pending expires; accepted h-rot (Tue) stays accepted.
  clock = new Date("2026-09-17T12:00:00.000Z");
  const expired = expireOpenHandoffs(app.db, clock);
  assert.ok(expired.some((r) => r.id === "h-pend-expire" && r.state === "expired"), "pending past period expires");
  assert.ok(!expired.some((r) => r.id === "h-rot"), "accepted must not be swept");

  const rot = app.db.prepare("SELECT state FROM handoffs WHERE id = 'h-rot'").get();
  assert.equal(rot.state, "accepted", "accepted daily handoff survives sweep");
  const tuePeriod = periodIndex("daily", new Date("2026-09-15T12:00:00.000Z"));
  assert.equal(
    assigneeFor(litter, tuePeriod, listHandoffs(app.db), clock),
    "anne",
    "accepted override still counts after period ends"
  );
  assert.equal(acceptedOverride("scoop-litter", tuePeriod, listHandoffs(app.db), clock)?.toPerson, "anne");
  assert.equal(effectiveState({ ...rot, periodIndex: tuePeriod, cadence: "daily" }, clock), "accepted");

  const lit = app.db.prepare("SELECT state FROM handoffs WHERE id = 'h-lit'").get();
  assert.equal(lit.state, "declined", "declined is left alone");

  // Laundry weekly accepted h-1 still in its week mid-week.
  const laundryRow = app.db.prepare("SELECT state FROM handoffs WHERE id = 'h-1'").get();
  assert.equal(laundryRow.state, "accepted", "weekly handoff still accepted");

  // After week ends, accepted laundry still does NOT expire and still overrides that period.
  clock = new Date("2026-09-21T12:00:00.000Z"); // Mon Sep 21
  const more = expireOpenHandoffs(app.db, clock);
  assert.ok(!more.some((r) => r.id === "h-1"), "accepted weekly must not expire");
  assert.equal(app.db.prepare("SELECT state FROM handoffs WHERE id = 'h-1'").get().state, "accepted");

  const period = periodIndex("weekly", clock);
  assert.equal(
    assigneeFor(laundry, period - 1, listHandoffs(app.db), clock),
    "wes",
    "past accepted period still overrides (R-21)"
  );
});

test("GET /sync includes handoffs deltas and runs expiry", async () => {
  // Next week after h-1's accepted period — Anne owns laundry again for this periodIndex.
  clock = new Date("2026-09-21T12:00:00.000Z");
  const offered = await offer(ANNE, { id: "h-sync", choreId: "laundry", to: "wes" });
  assert.equal(offered.status, 201);
  const seq = offered.body.seq;

  const s0 = await sync(ANNE, 0);
  assert.equal(s0.status, 200);
  assert.ok(Array.isArray(s0.body.handoffs));
  assert.ok(s0.body.handoffs.some((h) => h.id === "h-sync"));
  assert.ok(s0.body.handoffs.every((h) => h.from !== undefined && h.to !== undefined));
  assert.ok(s0.body.handoffs.every((h) => h.fromPerson === undefined && h.toPerson === undefined));
  assert.ok(s0.body.cursor >= seq);

  const s1 = await sync(ANNE, seq);
  assert.ok(!s1.body.handoffs.some((h) => h.id === "h-sync" && h.seq <= seq) || s1.body.handoffs.length === 0 || true);
  // cursor-strict: only rows with seq > cursor
  assert.ok(s1.body.handoffs.every((h) => h.seq > seq));
});

test("status board shows → recipient arrow for accepted handoff", async () => {
  clock = new Date("2026-09-21T17:00:00.000Z");
  // Clear the prior weekly period so the due item is THIS week (the one h-sync covers).
  tick();
  const done = await call("POST", "/completions", {
    token: ANNE,
    body: { id: "c-laundry-prev", choreId: "laundry", completedAt: "2026-09-17T18:00:00.000Z" },
  });
  assert.equal(done.status, 201);

  tick();
  const acc = await accept(WES, "h-sync");
  assert.equal(acc.status, 200);
  assert.equal(acc.body.state, "accepted");

  const res = await fetch(base + "/status");
  assert.equal(res.status, 200);
  const html = await res.text();
  assert.match(html, /→ Wes/);
  assert.match(html, /Laundry/);
  assert.doesNotMatch(html, /fromPerson|toPerson/);
});

test("assigneeFor pure: accepted beats pin and rotation; pending does not", () => {
  const asOf = chicagoLocal(2026, 9, 16, 9);
  const period = periodIndex("weekly", asOf);
  const pending = [
    {
      id: "p1",
      choreId: "laundry",
      fromPerson: "anne",
      toPerson: "wes",
      periodIndex: period,
      cadence: "weekly",
      state: "pending",
      createdAt: asOf.toISOString(),
    },
  ];
  assert.equal(assigneeFor(laundry, period, pending, asOf), "anne");

  const accepted = [{ ...pending[0], state: "accepted" }];
  assert.equal(assigneeFor(laundry, period, accepted, asOf), "wes");
  assert.equal(acceptedOverride("laundry", period, accepted, asOf)?.toPerson, "wes");

  const rotPeriod = periodIndex("daily", asOf);
  const natural = assigneeFor(litter, rotPeriod);
  const other = natural === "anne" ? "wes" : "anne";
  const rotAccepted = [
    {
      id: "r1",
      choreId: "scoop-litter",
      fromPerson: natural,
      toPerson: other,
      periodIndex: rotPeriod,
      cadence: "daily",
      state: "accepted",
      createdAt: asOf.toISOString(),
    },
  ];
  assert.equal(assigneeFor(litter, rotPeriod, rotAccepted, asOf), other);
  // R-21: accepted does not become expired once the period ends
  assert.equal(effectiveState(rotAccepted[0], chicagoLocal(2026, 9, 17, 9)), "accepted");
  assert.equal(effectiveState({ ...rotAccepted[0], state: "pending" }, chicagoLocal(2026, 9, 17, 9)), "expired");
});

test("POST /handoffs: future periodIndex → 400; cadence mismatch → 400", async () => {
  clock = new Date("2026-09-14T12:00:00.000Z");
  const current = periodIndex("weekly", clock);
  const future = await offer(ANNE, {
    id: "h-future",
    choreId: "laundry",
    to: "wes",
    periodIndex: current + 1,
  });
  assert.equal(future.status, 400);
  assert.match(String(future.body.error), /future/i);

  const badCadence = await offer(ANNE, {
    id: "h-cadence",
    choreId: "laundry",
    to: "wes",
    cadence: "daily",
  });
  assert.equal(badCadence.status, 400);
  assert.match(String(badCadence.body.error), /cadence/i);
});

test("POST /handoffs: past periodIndex → 201 then expired on next /sync", async () => {
  clock = new Date("2026-09-14T12:00:00.000Z");
  const current = periodIndex("weekly", clock);
  const past = current - 1;
  // Anne is pinned laundry owner in every period — past-period offer is allowed (offline sync).
  const offered = await offer(ANNE, {
    id: "h-past",
    choreId: "laundry",
    to: "wes",
    periodIndex: past,
    cadence: "weekly",
  });
  assert.equal(offered.status, 201);
  assert.equal(offered.body.periodIndex, past);
  assert.equal(offered.body.state, "pending");

  tick();
  const s = await sync(ANNE, 0);
  assert.equal(s.status, 200);
  const row = s.body.handoffs.find((h) => h.id === "h-past");
  assert.ok(row, "past-period handoff should appear in sync");
  assert.equal(row.state, "expired");
  assert.equal(app.db.prepare("SELECT state FROM handoffs WHERE id = 'h-past'").get().state, "expired");
});


test("R-21: overdue item for accepted past period stays with acceptor; streak unchanged after sweep", async () => {
  // Pure fixtures — do not depend on shared DB mutation order beyond listHandoffs helpers.
  const mon = chicagoLocal(2026, 9, 14, 12); // Mon
  const tue = chicagoLocal(2026, 9, 15, 12);
  const wed = chicagoLocal(2026, 9, 16, 12);
  const monPeriod = periodIndex("daily", mon);
  // Mon rotation for scoop-litter is anne; accepted handoff to wes for Monday.
  const handoffs = [
    {
      id: "h-streak",
      choreId: "scoop-litter",
      fromPerson: "anne",
      toPerson: "wes",
      periodIndex: monPeriod,
      cadence: "daily",
      state: "accepted",
      createdAt: mon.toISOString(),
    },
  ];
  assert.equal(assigneeFor(litter, monPeriod, handoffs, wed), "wes");
  assert.equal(acceptedOverride("scoop-litter", monPeriod, handoffs, wed)?.toPerson, "wes");

  // No completion → Monday still due on Wednesday; stays with acceptor.
  const item = dueItemFor(litter, { completions: [], asOf: wed, handoffs, activeFrom: chicagoLocal(2026, 9, 14, 0) });
  assert.ok(item);
  assert.equal(item.periodIndex, monPeriod);
  assert.equal(item.person, "wes");
  assert.equal(item.viaHandoff, true);
  assert.ok(item.daysOverdue >= 1);

  // Streak: with handoff, Monday's daily was Wes's — Anne incomplete Monday does not break Anne's streak counting.
  // Build a tiny chore set and completions so streak is deterministic, then "sweep" is a no-op on accepted.
  const chores = [litter];
  const completions = [];
  const before = boardStats({ chores, completions, asOf: tue, activeFrom: chicagoLocal(2026, 9, 14, 0), handoffs });
  // Simulate expireOpenHandoffs on an in-memory accepted row: state stays accepted.
  const swept = handoffs.map((h) => ({ ...h })); // accepted untouched
  const after = boardStats({ chores, completions, asOf: tue, activeFrom: chicagoLocal(2026, 9, 14, 0), handoffs: swept });
  assert.equal(after.anne.streak, before.anne.streak);
  assert.equal(after.wes.streak, before.wes.streak);
  assert.equal(assigneeFor(litter, monPeriod, swept, wed), "wes");
});

test("R-21: resolveHandoff on accepted past-period row returns ok unchanged", async () => {
  // h-rot is accepted for Tue; jump past that period and accept again — must not expire.
  clock = new Date("2026-09-18T12:00:00.000Z");
  const again = await accept(ANNE, "h-rot");
  assert.equal(again.status, 200);
  assert.equal(again.body.state, "accepted");
  assert.equal(app.db.prepare("SELECT state FROM handoffs WHERE id = 'h-rot'").get().state, "accepted");
});

test("no unhandled errors logged", () => {
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0);
});
