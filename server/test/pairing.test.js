// D-PAIR-S: pairing codes. A phone pairs with a 6-digit code from mkcode instead of a pasted token;
// /pair mints the bearer token behind it, /pair/self hands it back.
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import { hashToken } from "../src/auth.js";
import { createPairingCode } from "../src/pairing.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");
const SERVER = resolve(here, "..");

const WES = "wes-token-0123456789abcdef";

let dir, base, app, dbPath, tokensPath;
const logged = [];
// Real time, not a fixed date: mkcode runs in its own process on the real clock, and the codes it mints
// have to still be live for this app. tick() moves the app's clock on from there.
let clock = new Date();
const tick = (ms = 1000) => (clock = new Date(clock.getTime() + ms));

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-pair-test-"));
  dbPath = join(dir, "roost.db");
  tokensPath = join(dir, "tokens.json");
  writeFileSync(tokensPath, JSON.stringify({ [WES]: { person: "wes", device: "Wes test" } }));
  app = createApp({ dbPath, choresPath: CHORES, tokensPath, now: () => clock, log: (m) => logged.push(m) });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});

after(async () => {
  await new Promise((r) => app.server.close(r));
  app.db.close();
  rmSync(dir, { recursive: true, force: true });
});

/** `ip` sets X-Forwarded-For and `cfIp` CF-Connecting-IP, so each test gets its own rate-limit bucket. */
const call = async (method, path, { token, body, raw, ip, cfIp } = {}) => {
  const res = await fetch(base + path, {
    method,
    headers: {
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(ip ? { "x-forwarded-for": ip } : {}),
      ...(cfIp ? { "cf-connecting-ip": cfIp } : {}),
      ...(body !== undefined || raw !== undefined ? { "content-type": "application/json" } : {}),
    },
    body: raw !== undefined ? raw : body !== undefined ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
};

/** The real CLI, in its own process, against the same DB file the app has open. */
const mkcode = (...args) =>
  execFileSync(process.execPath, ["--no-warnings=ExperimentalWarning", "src/mkcode.js", ...args], {
    cwd: SERVER,
    env: { ...process.env, ROOST_DB: dbPath },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"], // captured, so the usage-message cases do not print here
  });

const codeFrom = (out) => /^pairing code .*: (\d{6})$/m.exec(out)?.[1];
const codeFor = (...args) => codeFrom(mkcode(...args));
const tokenFile = () => JSON.parse(readFileSync(tokensPath, "utf8"));
const codeRow = (code) => app.db.prepare("SELECT * FROM pairing_codes WHERE code = ?").get(code);
const liveCount = () =>
  app.db
    .prepare("SELECT COUNT(*) AS n FROM pairing_codes WHERE consumedAt IS NULL AND expiresAt > ?")
    .get(clock.toISOString()).n;

/** A code the table has never held, so the 404 tests cannot collide with a real one. */
function unusedCode() {
  let n = 0;
  while (codeRow(String(n).padStart(6, "0"))) n++;
  return String(n).padStart(6, "0");
}

let anneCode;

test("mkcode prints a fresh 6-digit code per device, unconsumed, with --minutes honoured", () => {
  const out = mkcode("anne", "Anne iPhone");
  anneCode = codeFrom(out);
  assert.match(anneCode, /^\d{6}$/);
  assert.match(out, /^expires \d{4}-\d\d-\d\dT.*it works once$/m);

  const second = codeFor("anne", "Anne iPad", "--minutes", "5");
  assert.notEqual(second, anneCode, "two live codes never share a number");

  const rows = app.db.prepare("SELECT person, deviceLabel, consumedAt, tokenHash FROM pairing_codes ORDER BY deviceLabel").all();
  assert.deepEqual(
    rows.map((r) => [r.person, r.deviceLabel, r.consumedAt, r.tokenHash]),
    [
      ["anne", "Anne iPad", null, null],
      ["anne", "Anne iPhone", null, null],
    ]
  );
  const five = codeRow(second);
  assert.equal(Date.parse(five.expiresAt) - Date.parse(five.createdAt), 5 * 60_000);
  assert.equal(Date.parse(codeRow(anneCode).expiresAt) - Date.parse(codeRow(anneCode).createdAt), 15 * 60_000, "default 15");

  assert.throws(() => mkcode("nobody", "Phone"), /Command failed/, "unknown person exits non-zero");
  assert.throws(() => mkcode("anne"), /Command failed/, "a device label is required");
  assert.throws(() => mkcode("anne", "Phone", "--minutes", "soon"), /Command failed/);
});

test("POST /pair needs no bearer and its token authenticates on the very next request", async () => {
  assert.equal((await call("GET", "/chores")).status, 401);

  const paired = await call("POST", "/pair", { body: { code: anneCode, deviceName: "Anne's iPhone" }, ip: "203.0.113.1" });
  assert.equal(paired.status, 200);
  assert.equal(paired.body.person, "anne");
  assert.match(paired.body.token, /^[A-Za-z0-9_-]{43}$/, "same shape mktoken.js mints");
  assert.deepEqual(Object.keys(paired.body).sort(), ["person", "token"], "the response carries nothing else");

  const chores = await call("GET", "/chores", { token: paired.body.token });
  assert.equal(chores.status, 200, "no restart, no mtime wait");
  assert.equal(chores.body.chores.length, 31);

  const entry = tokenFile()[paired.body.token];
  assert.deepEqual(entry, { person: "anne", device: "Anne iPhone · Anne's iPhone" }, "mkcode label · the phone's own name");
  assert.equal(Object.keys(tokenFile()).length, 2, "appended, the existing device untouched");
  assert.equal((await call("GET", "/chores", { token: WES })).status, 200);

  const row = codeRow(anneCode);
  assert.ok(row.consumedAt, "the code is consumed");
  assert.equal(row.tokenHash, hashToken(paired.body.token), "consumed with the token's hash, never the token");
});

test("a code works once: a replay, an unknown code and an expired one all answer the same 404", async () => {
  const ip = "203.0.113.2";
  const used = await call("POST", "/pair", { body: { code: anneCode, deviceName: "Second phone" }, ip });
  assert.equal(used.status, 404);
  assert.deepEqual(used.body, { error: "invalid or expired code" });

  const unknown = await call("POST", "/pair", { body: { code: unusedCode(), deviceName: "Phone" }, ip });
  assert.equal(unknown.status, 404);
  assert.deepEqual(unknown.body, used.body, "an unknown code is indistinguishable from a used one");

  // Minted with a `now` from January, so it expired months before this app's clock.
  const stale = createPairingCode(app.db, { person: "wes", deviceLabel: "Wes iPhone", minutes: 15 }, "2026-01-02T03:04:05.000Z");
  assert.equal(stale.expiresAt, "2026-01-02T03:19:05.000Z");
  const before = Object.keys(tokenFile()).length;
  const expired = await call("POST", "/pair", { body: { code: stale.code, deviceName: "Phone" }, ip });
  assert.equal(expired.status, 404);
  assert.deepEqual(expired.body, used.body);
  assert.equal(Object.keys(tokenFile()).length, before, "a 404 mints nothing");
  assert.equal(codeRow(stale.code).consumedAt, null, "and consumes nothing");
});

test("malformed /pair bodies are 400, never 500", async () => {
  const code = unusedCode();
  const bad = (body, ip = "203.0.113.3") => call("POST", "/pair", { body, ip });
  assert.equal((await bad({})).status, 400);
  assert.equal((await bad({ code })).status, 400, "deviceName required");
  assert.equal((await bad({ deviceName: "Phone" })).status, 400, "code required");
  assert.equal((await bad({ code: "12345", deviceName: "Phone" })).status, 400, "five digits is not a code");
  assert.equal((await bad({ code: "abcdef", deviceName: "Phone" })).status, 400);
  assert.equal((await bad({ code, deviceName: "   " })).status, 400);
  assert.equal((await bad({ code, deviceName: "x".repeat(61) })).status, 400);
  const raw = (r) => call("POST", "/pair", { raw: r, ip: "203.0.113.4" });
  assert.equal((await raw("null")).status, 400);
  assert.equal((await raw("[1,2]")).status, 400);
  assert.equal((await raw("{not json")).status, 400);
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("the 11th /pair attempt in a minute is 429; other addresses and the next minute are clear", async () => {
  const ip = "198.51.100.5";
  const code = unusedCode();
  const attempt = (extra = {}) => call("POST", "/pair", { body: { code, deviceName: "Phone" }, ip, ...extra });

  for (let i = 1; i <= 10; i++) assert.equal((await attempt()).status, 404, `attempt ${i} is answered`);
  assert.equal((await attempt()).status, 429, "the 11th is refused");
  assert.equal((await attempt()).status, 429);

  const cf = await attempt({ cfIp: "198.51.100.6" });
  assert.equal(cf.status, 404, "CF-Connecting-IP is the bucket when present, and has its own budget");

  tick(60_000);
  assert.equal((await attempt()).status, 404, "the window slides");
});

test("DELETE /pair/self revokes the calling device only", async () => {
  const paired = await call("POST", "/pair", {
    body: { code: codeFor("wes", "Wes iPhone"), deviceName: "16 Pro" },
    ip: "203.0.113.5",
  });
  const token = paired.body.token;
  assert.equal((await call("GET", "/chores", { token })).status, 200);
  assert.ok(app.db.prepare("SELECT 1 FROM devices WHERE tokenHash = ?").get(hashToken(token)), "device row recorded");

  assert.equal((await call("DELETE", "/pair/self")).status, 401, "unpairing needs the device's own token");
  assert.equal((await call("DELETE", "/pair/self", { token: "wrong-token-0123456789" })).status, 401);

  const gone = await call("DELETE", "/pair/self", { token });
  assert.equal(gone.status, 200);
  assert.deepEqual(gone.body, { unpaired: true, person: "wes", label: "Wes iPhone · 16 Pro" });

  assert.equal((await call("GET", "/chores", { token })).status, 401, "the token stops working immediately");
  assert.equal(token in tokenFile(), false, "gone from the tokens file");
  assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM devices WHERE tokenHash = ?").get(hashToken(token)).n, 0);
  assert.equal((await call("GET", "/chores", { token: WES })).status, 200, "the other device still works");
});

test("/health counts codes still waiting, and needs no auth", async () => {
  const baseline = liveCount();
  const health = await call("GET", "/health");
  assert.equal(health.status, 200);
  assert.equal(health.body.pendingCodes, baseline);
  assert.ok(baseline >= 1, "Anne's iPad code is still waiting");

  const code = codeFor("anne", "Anne iPad");
  assert.equal((await call("GET", "/health")).body.pendingCodes, baseline + 1, "a new code is pending");

  const paired = await call("POST", "/pair", { body: { code, deviceName: "iPad" }, ip: "203.0.113.6" });
  assert.equal(paired.status, 200);
  assert.equal((await call("GET", "/health")).body.pendingCodes, baseline, "a consumed code is not pending");

  createPairingCode(app.db, { person: "wes", deviceLabel: "Old laptop", minutes: 1 }, "2026-01-01T00:00:00.000Z");
  assert.equal((await call("GET", "/health")).body.pendingCodes, baseline, "an expired code is not pending");
});

// Last: with no proxy header the bucket is the socket address, which every other request here shares.
test("no proxy header: the socket address is the rate-limit bucket", async () => {
  const code = unusedCode();
  const attempt = () => call("POST", "/pair", { body: { code, deviceName: "Phone" } });
  for (let i = 1; i <= 10; i++) assert.equal((await attempt()).status, 404, `attempt ${i} is answered`);
  assert.equal((await attempt()).status, 429);
});
