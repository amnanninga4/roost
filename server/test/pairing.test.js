// D-PAIR-S: pairing codes. A phone pairs with a 6-digit code from mkcode instead of a pasted token.
// /pair mints the bearer token behind it into `paired_tokens` (never into the tokens file, which the API
// only reads), /pair/self hands it back, and src/devices.js lists and revokes from the shell.
import { test, before, beforeEach, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";
import { hashToken } from "../src/auth.js";
import { createPairingCode, storePairedToken } from "../src/pairing.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");
const SERVER = resolve(here, "..");

const WES = "wes-token-0123456789abcdef";

let dir, base, app, dbPath, tokensPath;
const logged = [];
// Real time, not a fixed date: mkcode runs in its own process on the real clock, and the codes it mints
// have to still be live for this app.
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

// Both /pair limiters are per-minute, so every test starts in a window of its own.
beforeEach(() => tick(60_000));

after(async () => {
  await new Promise((r) => app.server.close(r));
  app.db.close();
  rmSync(dir, { recursive: true, force: true });
});

/** `ip` sets X-Forwarded-For and `cfIp` CF-Connecting-IP, so a test can pick its own address bucket. */
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

/** The real CLIs, in their own process, against the same DB file the app has open. */
const cli = (script, ...args) =>
  execFileSync(process.execPath, ["--no-warnings=ExperimentalWarning", `src/${script}`, ...args], {
    cwd: SERVER,
    env: { ...process.env, ROOST_DB: dbPath, ROOST_TOKENS: tokensPath },
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"], // captured, so the usage-message cases do not print here
  });
const mkcode = (...args) => cli("mkcode.js", ...args);
const devices = (...args) => cli("devices.js", ...args);
const devicesFail = (...args) => {
  try {
    devices(...args);
    return assert.fail("expected devices.js to exit non-zero");
  } catch (err) {
    return { status: err.status, stderr: String(err.stderr) };
  }
};

const codeFrom = (out) => /^pairing code .*: (\d{6})$/m.exec(out)?.[1];
const codeFor = (...args) => codeFrom(mkcode(...args));
const tokenFile = () => JSON.parse(readFileSync(tokensPath, "utf8"));
const codeRow = (code) => app.db.prepare("SELECT * FROM pairing_codes WHERE code = ?").get(code);
const pairedRow = (token) => app.db.prepare("SELECT * FROM paired_tokens WHERE tokenHash = ?").get(hashToken(token));
const activePaired = () => app.db.prepare("SELECT COUNT(*) AS n FROM paired_tokens WHERE revokedAt IS NULL").get().n;
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

/** Pair a fresh device and return its token. */
async function pairDevice(person, label, deviceName, ip) {
  const paired = await call("POST", "/pair", { body: { code: codeFor(person, label), deviceName }, ip });
  assert.equal(paired.status, 200, "pairing a fresh code");
  return paired.body.token;
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

test("POST /pair needs no bearer, and its token authenticates on the very next request", async () => {
  assert.equal((await call("GET", "/chores")).status, 401);

  const paired = await call("POST", "/pair", { body: { code: anneCode, deviceName: "Anne's iPhone" }, ip: "203.0.113.1" });
  assert.equal(paired.status, 200);
  assert.equal(paired.body.person, "anne");
  assert.match(paired.body.token, /^[A-Za-z0-9_-]{43}$/, "same shape mktoken.js mints");
  assert.deepEqual(Object.keys(paired.body).sort(), ["person", "token"], "the response carries nothing else");

  const chores = await call("GET", "/chores", { token: paired.body.token });
  assert.equal(chores.status, 200, "no restart, no file write, no reload");
  assert.equal(chores.body.chores.length, 41);

  const row = pairedRow(paired.body.token);
  assert.equal(row.person, "anne");
  assert.equal(row.label, "Anne iPhone · Anne's iPhone", "mkcode label · the phone's own name");
  assert.equal(row.revokedAt, null);
  assert.deepEqual(Object.keys(tokenFile()), [WES], "the tokens file is untouched: the API only reads it");

  const code = codeRow(anneCode);
  assert.ok(code.consumedAt, "the code is consumed");
  assert.equal(code.tokenHash, hashToken(paired.body.token), "recorded by hash, never the token");
  assert.equal((await call("GET", "/chores", { token: WES })).status, 200, "the hand-minted device still works");
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
  const before = activePaired();
  const expired = await call("POST", "/pair", { body: { code: stale.code, deviceName: "Phone" }, ip });
  assert.equal(expired.status, 404);
  assert.deepEqual(expired.body, used.body);
  assert.equal(activePaired(), before, "a 404 mints nothing");
  assert.equal(codeRow(stale.code).consumedAt, null, "and consumes nothing");
});

test("the mint is one transaction: a failure after the INSERT leaves the code live", async () => {
  const code = createPairingCode(app.db, { person: "wes", deviceLabel: "Wes iPhone", minutes: 15 }, clock.toISOString()).code;
  const tokenHash = "f".repeat(64);
  // A db that fails exactly on the second statement of the transaction.
  const failing = {
    exec: (sql) => app.db.exec(sql),
    prepare: (sql) => {
      if (sql.startsWith("UPDATE pairing_codes")) throw new Error("disk went away");
      return app.db.prepare(sql);
    },
  };
  assert.throws(
    () => storePairedToken(failing, { tokenHash, person: "wes", label: "Wes iPhone · Phone", code }, clock.toISOString()),
    /disk went away/
  );

  assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM paired_tokens WHERE tokenHash = ?").get(tokenHash).n, 0, "rolled back");
  assert.equal(codeRow(code).consumedAt, null, "the code was not spent");

  const paired = await call("POST", "/pair", { body: { code, deviceName: "Phone" }, ip: "203.0.113.3" });
  assert.equal(paired.status, 200, "so the phone can just try again");
  assert.equal((await call("GET", "/chores", { token: paired.body.token })).status, 200);
});

test("malformed /pair bodies are 400, never 500", async () => {
  const code = unusedCode();
  const bad = (body, ip = "203.0.113.4") => call("POST", "/pair", { body, ip });
  assert.equal((await bad({})).status, 400);
  assert.equal((await bad({ code })).status, 400, "deviceName required");
  assert.equal((await bad({ deviceName: "Phone" })).status, 400, "code required");
  assert.equal((await bad({ code: "12345", deviceName: "Phone" })).status, 400, "five digits is not a code");
  assert.equal((await bad({ code: "abcdef", deviceName: "Phone" })).status, 400);
  assert.equal((await bad({ code, deviceName: "   " })).status, 400);
  assert.equal((await bad({ code, deviceName: "x".repeat(61) })).status, 400);
  const raw = (r) => call("POST", "/pair", { raw: r, ip: "203.0.113.5" });
  assert.equal((await raw("null")).status, 400);
  assert.equal((await raw("[1,2]")).status, 400);
  assert.equal((await raw("{not json")).status, 400);
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("the 11th /pair attempt in a minute from one address is 429; other addresses and the next minute are clear", async () => {
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

test("and 30 answered attempts a minute across every address, however many addresses they come from", async () => {
  const code = unusedCode();
  const attempt = (ip) => call("POST", "/pair", { body: { code, deviceName: "Phone" }, ip });

  for (const ip of ["198.51.100.10", "198.51.100.11", "198.51.100.12"]) {
    for (let i = 1; i <= 10; i++) assert.equal((await attempt(ip)).status, 404, `${ip} attempt ${i}`);
  }
  assert.equal((await attempt("198.51.100.13")).status, 429, "a fresh address is still refused: the global cap is spent");

  tick(60_000);
  assert.equal((await attempt("198.51.100.13")).status, 404, "the global window slides too");
});

test("DELETE /pair/self revokes the calling device only", async () => {
  const token = await pairDevice("wes", "Wes iPhone", "16 Pro", "203.0.113.6");
  assert.equal((await call("GET", "/chores", { token })).status, 200);
  assert.ok(app.db.prepare("SELECT 1 FROM devices WHERE tokenHash = ?").get(hashToken(token)), "device row recorded");

  assert.equal((await call("DELETE", "/pair/self")).status, 401, "unpairing needs the device's own token");
  assert.equal((await call("DELETE", "/pair/self", { token: "wrong-token-0123456789" })).status, 401);

  const gone = await call("DELETE", "/pair/self", { token });
  assert.equal(gone.status, 200);
  assert.deepEqual(gone.body, { unpaired: true, person: "wes", label: "Wes iPhone · 16 Pro" });

  assert.equal((await call("GET", "/chores", { token })).status, 401, "the token stops working immediately");
  assert.ok(pairedRow(token).revokedAt, "kept as a revoked row, not deleted");
  assert.equal(app.db.prepare("SELECT COUNT(*) AS n FROM devices WHERE tokenHash = ?").get(hashToken(token)).n, 0);
  assert.equal((await call("GET", "/chores", { token: WES })).status, 200, "the other device still works");
});

test("DELETE /pair/self will not touch a hand-minted token: 403, and it keeps working", async () => {
  const refused = await call("DELETE", "/pair/self", { token: WES });
  assert.equal(refused.status, 403);
  assert.deepEqual(refused.body, { error: "this device was set up by hand; remove it from the tokens file" });
  assert.deepEqual(Object.keys(tokenFile()), [WES], "the file is untouched");
  assert.equal((await call("GET", "/chores", { token: WES })).status, 200);
});

test("devices.js lists both sources and revokes a paired token from the shell", async () => {
  const token = await pairDevice("anne", "Anne iPad", "iPad mini", "203.0.113.7");
  assert.equal((await call("GET", "/chores", { token })).status, 200, "seen once, so it has a lastSeen");

  const listed = devices("list");
  assert.match(listed, /^paired\s+[0-9a-f]{8}\s+anne\s+Anne iPad · iPad mini\s+\d{4}-/m, "paired row with its lastSeen");
  assert.match(listed, /^file\s+[0-9a-f]{8}\s+wes\s+Wes test/m, "the hand-minted device is listed too");
  assert.match(listed, /^revoked\s+[0-9a-f]{8}\s+wes\s+Wes iPhone · 16 Pro/m, "and the one revoked earlier");

  const prefix = hashToken(token).slice(0, 8);
  assert.match(devices("revoke", prefix), /revoked anne \/ Anne iPad · iPad mini/);
  assert.equal((await call("GET", "/chores", { token })).status, 401, "revoked from the shell, 401 on the next request");
  assert.match(devices("revoke", prefix), /was already revoked/, "idempotent");

  const byHand = devicesFail("revoke", hashToken(WES).slice(0, 8));
  assert.equal(byHand.status, 1);
  assert.match(byHand.stderr, /set up by hand; remove its line from/);
  assert.deepEqual(Object.keys(tokenFile()), [WES], "and the file is still untouched");
  assert.equal((await call("GET", "/chores", { token: WES })).status, 200);

  assert.equal(devicesFail("revoke", "deadbeef").status, 1, "unknown prefix");
  assert.match(devicesFail("revoke", "deadbeef").stderr, /no device whose token hash starts with/);
  assert.equal(devicesFail("revoke", "ab").status, 2, "too short to be a device");
  assert.equal(devicesFail("wat").status, 2);
});

test("/health counts devices and codes still waiting, and needs no auth", async () => {
  const health = await call("GET", "/health");
  assert.equal(health.status, 200);
  assert.equal(health.body.devices, 1 + activePaired(), "one hand-minted device plus the live paired tokens");

  const baseline = liveCount();
  assert.equal(health.body.pendingCodes, baseline);

  const code = codeFor("anne", "Anne iPhone");
  assert.equal((await call("GET", "/health")).body.pendingCodes, baseline + 1, "a new code is pending");

  const paired = await call("POST", "/pair", { body: { code, deviceName: "iPhone" }, ip: "203.0.113.8" });
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

test("first pair sets activeFrom to Chicago today; second pair leaves it unchanged", async () => {
  // Earlier tests in this file may already have paired — clear so we exercise the first-set path.
  app.db.prepare("DELETE FROM meta WHERE key = ?").run("activeFrom");
  assert.equal(app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom"), undefined);

  const t1 = await pairDevice("anne", "Anne phone A", "iPhone", "203.0.113.40");
  assert.ok(t1);
  const first = app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom")?.value;
  assert.match(first, /^\d{4}-\d{2}-\d{2}$/, "stored as YYYY-MM-DD");

  const { chicagoDateString } = await import("../src/rules.js");
  assert.equal(first, chicagoDateString(clock), "matches Chicago calendar day of pair");

  const health = await call("GET", "/health");
  assert.equal(health.body.activeFrom, first, "/health exposes meta activeFrom");

  const t2 = await pairDevice("wes", "Wes phone B", "Pixel", "203.0.113.41");
  assert.ok(t2);
  const second = app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom")?.value;
  assert.equal(second, first, "second pair must not change activeFrom");
});

test("mktoken CLI stamps activeFrom once, then leaves it alone", () => {
  // Clear so mint path can set it (pair tests above may have set meta already — delete then mint)
  app.db.prepare("DELETE FROM meta WHERE key = ?").run("activeFrom");
  assert.equal(app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom"), undefined);

  const out1 = cli("mktoken.js", "anne", "Minted once");
  assert.match(out1, /activeFrom: (\d{4}-\d{2}-\d{2})/);
  const stamped = /^activeFrom: (\d{4}-\d{2}-\d{2})$/m.exec(out1)[1];
  assert.equal(app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom")?.value, stamped);

  const out2 = cli("mktoken.js", "wes", "Minted twice");
  assert.match(out2, new RegExp(`activeFrom: ${stamped}`));
  assert.equal(app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom")?.value, stamped);
});

test("household.js active-from prints and sets the meta date", () => {
  app.db.prepare("DELETE FROM meta WHERE key = ?").run("activeFrom");
  const printed = cli("household.js", "active-from");
  assert.match(printed, /activeFrom: \d{4}-\d{2}-\d{2} \(default\)/);

  const setOut = cli("household.js", "active-from", "2026-09-01");
  assert.match(setOut, /activeFrom set to 2026-09-01/);
  assert.equal(app.db.prepare("SELECT value FROM meta WHERE key = ?").get("activeFrom")?.value, "2026-09-01");

  const again = cli("household.js", "active-from");
  assert.match(again, /activeFrom: 2026-09-01 \(meta\)/);
});
