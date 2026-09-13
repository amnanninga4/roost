import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { generateKeyPairSync } from "node:crypto";
import { createApp } from "../src/app.js";
import {
  makeApnsJwt,
  loadApnsConfig,
  createDisabledSender,
  buildSender,
  createPush,
  STAGE_RANK,
  partnerOf,
  upsertPushToken,
  shouldPruneToken,
  hasPushAlert,
  COMPLETION_EXPIRATION_SEC,
} from "../src/push.js";
import { escalationStage } from "../src/rules.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");

const ANNE = "anne-token-0123456789abcdef";
const WES = "wes-token-0123456789abcdef";
const ANNE_PUSH = "a".repeat(64);
const WES_PUSH = "b".repeat(64);
const DEAD_PUSH = "d".repeat(64);

let dir, base, app, tokensPath, sent, clock;
const logged = [];

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-push-"));
  tokensPath = join(dir, "tokens.json");
  writeFileSync(
    tokensPath,
    JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" }, [WES]: { person: "wes", device: "Wes test" } })
  );
  clock = new Date("2026-09-14T12:00:00.000Z");
  sent = [];
  const mockSender = async (req) => {
    sent.push(req);
    return { status: 200 };
  };
  app = createApp({
    dbPath: join(dir, "roost.db"),
    choresPath: CHORES,
    tokensPath,
    apnsPath: join(dir, "missing-apns.json"),
    pushSender: mockSender,
    now: () => clock,
    log: (...m) => logged.push(m.map(String).join(" ")),
    sweepIntervalMs: 0,
  });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});

after(async () => {
  app.push.stopSweep();
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

test("partnerOf and stage ranks: alert is stage 3", () => {
  assert.equal(partnerOf("anne"), "wes");
  assert.equal(partnerOf("wes"), "anne");
  assert.equal(STAGE_RANK.alert, 3);
  assert.equal(STAGE_RANK[escalationStage(5)], 3);
  assert.ok(STAGE_RANK[escalationStage(4)] < 3);
});

test("health reports push status; missing key is no key when no injected sender health", async () => {
  // With an injected sender, createApp reports "ready" (or env if config present).
  const h = await call("GET", "/health");
  assert.equal(h.status, 200);
  assert.equal(h.body.push, "ready");

  // Disabled path with no sender: buildSender → "no key"
  const built = buildSender(join(dir, "definitely-missing.json"), { log: () => {} });
  assert.equal(built.health, "no key");
  await built.sender({ deviceToken: "x", headers: {}, body: {} }); // no throw
  await built.sender({ deviceToken: "x", headers: {}, body: {} });
});

test("POST /push/token upserts; DELETE unregisters; auth required", async () => {
  assert.equal((await call("POST", "/push/token", { body: { token: ANNE_PUSH, platform: "ios" } })).status, 401);

  const reg = await call("POST", "/push/token", {
    token: ANNE,
    body: { token: ANNE_PUSH, platform: "ios" },
  });
  assert.equal(reg.status, 200);
  assert.equal(reg.body.person, "anne");
  assert.equal(reg.body.platform, "ios");
  assert.equal(reg.body.token, ANNE_PUSH);

  const again = await call("POST", "/push/token", {
    token: ANNE,
    body: { token: ANNE_PUSH, platform: "ios" },
  });
  assert.equal(again.status, 200, "upsert is idempotent");

  assert.equal(
    (await call("POST", "/push/token", { token: ANNE, body: { token: "short", platform: "ios" } })).status,
    400
  );
  assert.equal(
    (await call("POST", "/push/token", { token: ANNE, body: { token: ANNE_PUSH, platform: "android" } })).status,
    400
  );

  const wesReg = await call("POST", "/push/token", {
    token: WES,
    body: { token: WES_PUSH, platform: "ios" },
  });
  assert.equal(wesReg.status, 200);

  // Anne cannot delete Wes's token
  assert.equal(
    (await call("DELETE", "/push/token", { token: ANNE, body: { token: WES_PUSH } })).status,
    404
  );

  const del = await call("DELETE", "/push/token", { token: ANNE, body: { token: ANNE_PUSH } });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  assert.equal((await call("DELETE", "/push/token", { token: ANNE, body: { token: ANNE_PUSH } })).status, 404);
});

test("POST /completions notifies the other person with payload + apns-topic + expiration; no network", async () => {
  sent.length = 0;
  // Re-register both so delivery has somewhere to go
  await call("POST", "/push/token", { token: ANNE, body: { token: ANNE_PUSH, platform: "ios" } });
  await call("POST", "/push/token", { token: WES, body: { token: WES_PUSH, platform: "ios" } });

  const post = await call("POST", "/completions", {
    token: ANNE,
    body: { id: "push-c1", choreId: "scoop-litter", completedAt: "2026-09-14T11:30:00.000Z" },
  });
  assert.equal(post.status, 201);

  // Allow the fire-and-forget notify to land
  await new Promise((r) => setTimeout(r, 30));

  assert.equal(sent.length, 1, "one device for the other person");
  const req = sent[0];
  assert.equal(req.deviceToken, WES_PUSH, "Anne's completion notifies Wes");
  assert.equal(req.headers["apns-topic"], "xyz.hinescreative.roost");
  assert.equal(req.headers["apns-push-type"], "alert");
  const expectedExp = String(Math.floor(clock.getTime() / 1000) + COMPLETION_EXPIRATION_SEC);
  assert.equal(req.headers["apns-expiration"], expectedExp, "completion apns-expiration = now+3600");
  assert.equal(req.body.aps.alert.title, "Roost");
  assert.equal(req.body.aps.alert.body, "Anne did Scoop litter");

  // Replay must not re-notify
  sent.length = 0;
  const replay = await call("POST", "/completions", {
    token: ANNE,
    body: { id: "push-c1", choreId: "scoop-litter", completedAt: "2026-09-14T11:30:00.000Z" },
  });
  assert.equal(replay.status, 200);
  await new Promise((r) => setTimeout(r, 30));
  assert.equal(sent.length, 0, "idempotent replay does not push again");
});

test("red-alert sweep notifies partner for stage>=3; collapse-id; persists across restart", async () => {
  sent.length = 0;
  // Far past activeFrom (2026-09-07) so a daily chore with no completions is deeply overdue.
  const asOf = new Date("2026-09-20T17:00:00.000Z"); // Chicago afternoon Sep 20
  await app.push.runRedAlertSweep(asOf);
  assert.ok(sent.length >= 1, "at least one red-alert delivered");
  for (const req of sent) {
    assert.equal(req.headers["apns-topic"], "xyz.hinescreative.roost");
    assert.match(req.body.aps.alert.title, /red alert/i);
    assert.ok(req.body.aps.alert.body.includes("overdue"));
    assert.match(req.headers["apns-collapse-id"], /^red-.+/, "red alerts set apns-collapse-id");
  }
  const firstCount = sent.length;
  const alertRows = app.db.prepare("SELECT choreId, periodIndex, sentAt FROM push_alerts").all();
  assert.equal(alertRows.length, firstCount, "each send recorded in push_alerts");
  for (const row of alertRows) {
    assert.ok(hasPushAlert(app.db, row.choreId, row.periodIndex));
  }

  sent.length = 0;
  await app.push.runRedAlertSweep(asOf);
  assert.equal(sent.length, 0, "same period is not re-alerted in-process");

  // Simulate restart: new createPush on the same db must not re-send.
  const restartSent = [];
  const push2 = createPush({
    db: app.db,
    apnsPath: join(dir, "missing-apns.json"),
    sender: async (req) => {
      restartSent.push(req);
      return { status: 200 };
    },
    now: () => clock,
    log: () => {},
    sweepIntervalMs: 0,
  });
  await push2.runRedAlertSweep(asOf);
  assert.equal(restartSent.length, 0, "restart must not re-send every stage>=3 alert");
  push2.stopSweep();
  assert.ok(firstCount > 0);
});

test("deliver prunes dead tokens on 410 and 400 BadDeviceToken / DeviceTokenNotForTopic", async () => {
  assert.equal(shouldPruneToken(410, undefined), true);
  assert.equal(shouldPruneToken(400, "BadDeviceToken"), true);
  assert.equal(shouldPruneToken(400, "DeviceTokenNotForTopic"), true);
  assert.equal(shouldPruneToken(400, "BadTopic"), false);
  assert.equal(shouldPruneToken(200, undefined), false);
  assert.equal(shouldPruneToken(500, "InternalServerError"), false);

  const pruneToken = DEAD_PUSH;
  upsertPushToken(app.db, { token: pruneToken, person: "wes", platform: "ios" }, clock.toISOString());
  assert.ok(app.db.prepare("SELECT 1 FROM push_tokens WHERE token = ?").get(pruneToken));

  const statuses = [
    { status: 410, reason: "Unregistered" },
    { status: 400, reason: "BadDeviceToken" },
    { status: 400, reason: "DeviceTokenNotForTopic" },
  ];
  for (const { status, reason } of statuses) {
    const tok = (status === 410 ? "e" : status === 400 && reason === "BadDeviceToken" ? "f" : "g").repeat(64);
    upsertPushToken(app.db, { token: tok, person: "anne", platform: "ios" }, clock.toISOString());
    const prunePush = createPush({
      db: app.db,
      apnsPath: join(dir, "missing-apns.json"),
      sender: async () => ({ status, reason }),
      now: () => clock,
      log: () => {},
      sweepIntervalMs: 0,
    });
    await prunePush.deliver("anne", { title: "t", body: "b" });
    assert.equal(
      app.db.prepare("SELECT 1 FROM push_tokens WHERE token = ?").get(tok),
      undefined,
      `token pruned on ${status} ${reason ?? ""}`
    );
    // Good token for same person must survive if sender returns 200 for it — deliver walks all rows;
    // here only anne tokens that match our inject. Re-check ANNE_PUSH still present if registered.
    prunePush.stopSweep();
  }

  // 400 with a non-dead reason must NOT prune
  const keep = "h".repeat(64);
  upsertPushToken(app.db, { token: keep, person: "wes", platform: "ios" }, clock.toISOString());
  const keepPush = createPush({
    db: app.db,
    apnsPath: join(dir, "missing-apns.json"),
    sender: async () => ({ status: 400, reason: "PayloadTooLarge" }),
    now: () => clock,
    log: () => {},
    sweepIntervalMs: 0,
  });
  await keepPush.deliver("wes", { title: "t", body: "b" });
  assert.ok(app.db.prepare("SELECT 1 FROM push_tokens WHERE token = ?").get(keep), "non-dead 400 keeps token");
  keepPush.stopSweep();
});

test("red-alert sweep is not re-entrant while awaiting sends", async () => {
  let release;
  const gate = new Promise((r) => {
    release = r;
  });
  let entered = 0;
  const slowPush = createPush({
    db: app.db,
    apnsPath: join(dir, "missing-apns.json"),
    sender: async () => {
      entered += 1;
      await gate;
      return { status: 200 };
    },
    now: () => clock,
    log: () => {},
    sweepIntervalMs: 0,
  });
  // Clear prior alerts for a fresh overdue sweep would be hard; instead call deliver path via
  // overlapping runRedAlertSweep: first call holds sweeping=true while sender awaits.
  // Seed one overdue path by wiping push_alerts so sweep has work (or use deliver directly).
  // Simpler: monkey-patch via overlapping runRedAlertSweep when alerts already recorded —
  // sweeping guard still trips even when there is no work if we inject a slow first iteration.
  // Force work: delete push_alerts so stage>=3 items fire again.
  app.db.prepare("DELETE FROM push_alerts").run();
  upsertPushToken(app.db, { token: WES_PUSH, person: "wes", platform: "ios" }, clock.toISOString());
  upsertPushToken(app.db, { token: ANNE_PUSH, person: "anne", platform: "ios" }, clock.toISOString());

  const asOf = new Date("2026-09-20T17:00:00.000Z");
  const first = slowPush.runRedAlertSweep(asOf);
  // Give the first sweep a chance to set sweeping=true and hit the first await deliver
  await new Promise((r) => setTimeout(r, 20));
  const second = slowPush.runRedAlertSweep(asOf);
  await second; // must resolve immediately as no-op
  release();
  await first;
  assert.ok(entered >= 1, "first sweep sent at least once");
  // Second tick did nothing while first was awaiting — entered equals only first sweep's sends
  const enteredAfterFirst = entered;
  await slowPush.runRedAlertSweep(asOf);
  assert.equal(entered, enteredAfterFirst, "after completion, same period not re-sent; re-entrancy held");
  slowPush.stopSweep();
});

test("makeApnsJwt is ES256 and loadApnsConfig disables cleanly", () => {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const pem = privateKey.export({ type: "pkcs8", format: "pem" });
  const jwt = makeApnsJwt({ keyPem: pem, keyId: "KEYID123", teamId: "TEAMID123", nowSec: 1_700_000_000 });
  const [h, c, s] = jwt.split(".");
  assert.ok(h && c && s);
  const header = JSON.parse(Buffer.from(h, "base64url").toString());
  assert.equal(header.alg, "ES256");
  assert.equal(header.kid, "KEYID123");
  const claims = JSON.parse(Buffer.from(c, "base64url").toString());
  assert.equal(claims.iss, "TEAMID123");

  assert.equal(loadApnsConfig(join(dir, "nope.json"), { log: () => {} }), null);

  const keyPath = join(dir, "fake.p8");
  writeFileSync(keyPath, pem);
  const cfgPath = join(dir, "apns.json");
  writeFileSync(
    cfgPath,
    JSON.stringify({
      keyPath,
      keyId: "KEYID123",
      teamId: "TEAMID123",
      bundleId: "xyz.hinescreative.roost",
      env: "sandbox",
    })
  );
  const cfg = loadApnsConfig(cfgPath, { log: () => {} });
  assert.equal(cfg.env, "sandbox");
  assert.equal(cfg.bundleId, "xyz.hinescreative.roost");
  assert.ok(existsSync(cfg.keyPath));

  const disabled = createDisabledSender({ log: (...m) => logged.push(m.join(" ")) });
  // two calls, one log
  const before = logged.filter((l) => String(l).includes("push disabled")).length;
  return Promise.all([disabled(), disabled()]).then(() => {
    const after = logged.filter((l) => String(l).includes("push disabled")).length;
    assert.equal(after - before, 1);
  });
});

test("upsertPushToken stores person/platform/updatedAt", () => {
  const now = "2026-09-14T12:00:00.000Z";
  const row = upsertPushToken(app.db, { token: "c".repeat(64), person: "wes", platform: "ios" }, now);
  assert.equal(row.person, "wes");
  assert.equal(row.platform, "ios");
  assert.equal(row.updatedAt, now);
});
