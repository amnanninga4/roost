// APNs push: device token registry, HTTP/2 sender, completion + red-alert + morning digest.
//
// Everything push lives here so app.js only imports, creates the service, dispatches
// pushRoutes, and adds one /health field (same shape as pairing/bonus).
//
// Config (host file, never in the repo): /etc/roost/apns.json
//   { "keyPath", "keyId", "teamId", "bundleId": "xyz.hinescreative.roost", "env": "sandbox"|"production" }
// When the file or .p8 is missing, push is DISABLED cleanly: /health reports push:"no key",
// sends are no-ops that log once, nothing throws.
import { readFileSync, existsSync } from "node:fs";
import { createPrivateKey, sign } from "node:crypto";
import http2 from "node:http2";
import { PEOPLE, getMeta, setMeta } from "./db.js";
import { listHandoffs } from "./handoffs.js";
import { dueItems, parseActiveFrom, chicagoDateString, chicagoLocal } from "./rules.js";

export const DEFAULT_APNS_PATH = "/etc/roost/apns.json";
export const DEFAULT_BUNDLE_ID = "xyz.hinescreative.roost";
export const RED_ALERT_MS = 15 * 60 * 1000;
export const APNS_REQUEST_TIMEOUT_MS = 10_000;
export const COMPLETION_EXPIRATION_SEC = 3600;

/** meta key: Chicago YYYY-MM-DD of the last morning-digest pass (R-25). */
export const DIGEST_LAST_SENT_META = "digestLastSent";

/** dueToday=0, nudge=1, pointed=2, alert=3 — red-alert is stage >= 3. */
export const STAGE_RANK = Object.freeze({ dueToday: 0, nudge: 1, pointed: 2, alert: 3 });

export const PUSH_SCHEMA = `
CREATE TABLE IF NOT EXISTS push_tokens (
  token     TEXT PRIMARY KEY,
  person    TEXT NOT NULL CHECK (person IN ('anne','wes')),
  platform  TEXT NOT NULL,
  updatedAt TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS push_tokens_person ON push_tokens(person);
CREATE TABLE IF NOT EXISTS push_alerts (
  choreId     TEXT NOT NULL,
  periodIndex INTEGER NOT NULL,
  sentAt      TEXT NOT NULL,
  PRIMARY KEY (choreId, periodIndex)
);
`;

const PLATFORMS = new Set(["ios"]);
const TOKEN_RE = /^[0-9a-fA-F]{64}$/;
const NAME = { anne: "Anne", wes: "Wes" };
const DEAD_TOKEN_REASONS = new Set(["BadDeviceToken", "DeviceTokenNotForTopic"]);

export function partnerOf(person) {
  return person === "anne" ? "wes" : "anne";
}

export function upsertPushToken(db, { token, person, platform }, now) {
  db.prepare(
    `INSERT INTO push_tokens (token, person, platform, updatedAt) VALUES (?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET person = excluded.person, platform = excluded.platform, updatedAt = excluded.updatedAt`
  ).run(token, person, platform, now);
  return db.prepare("SELECT token, person, platform, updatedAt FROM push_tokens WHERE token = ?").get(token);
}

export function deletePushToken(db, { token, person }) {
  const row = db.prepare("SELECT token, person, platform, updatedAt FROM push_tokens WHERE token = ?").get(token);
  if (!row) return null;
  if (row.person !== person) return null;
  db.prepare("DELETE FROM push_tokens WHERE token = ?").run(token);
  return row;
}

export function tokensForPerson(db, person) {
  return db.prepare("SELECT token, person, platform, updatedAt FROM push_tokens WHERE person = ?").all(person);
}

/** True when APNs says the device token is permanently dead and should be pruned. */
export function shouldPruneToken(status, reason) {
  if (status === 410) return true;
  if (status === 400 && DEAD_TOKEN_REASONS.has(reason)) return true;
  return false;
}

export function hasPushAlert(db, choreId, periodIndex) {
  return !!db.prepare("SELECT 1 FROM push_alerts WHERE choreId = ? AND periodIndex = ?").get(choreId, periodIndex);
}

export function recordPushAlert(db, choreId, periodIndex, sentAt) {
  db.prepare(
    `INSERT INTO push_alerts (choreId, periodIndex, sentAt) VALUES (?, ?, ?)
     ON CONFLICT(choreId, periodIndex) DO NOTHING`
  ).run(choreId, periodIndex, sentAt);
}

function b64url(data) {
  return Buffer.from(data).toString("base64url");
}

/** ES256 JWT for APNs (iss=teamId, iat=now, kid=keyId). Built-in crypto only. */
export function makeApnsJwt({ keyPem, keyId, teamId, nowSec }) {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = b64url(JSON.stringify({ iss: teamId, iat: nowSec }));
  const key = createPrivateKey(keyPem);
  const sig = sign("SHA256", Buffer.from(`${header}.${claims}`), { key, dsaEncoding: "ieee-p1363" });
  return `${header}.${claims}.${sig.toString("base64url")}`;
}

/**
 * Read apns.json. Returns null when missing/invalid so callers disable cleanly.
 * Does not throw for a missing file.
 */
export function loadApnsConfig(apnsPath, { log = console.error } = {}) {
  if (!apnsPath || !existsSync(apnsPath)) return null;
  let raw;
  try {
    raw = JSON.parse(readFileSync(apnsPath, "utf8"));
  } catch (err) {
    log(`apns config ${apnsPath} not applied: ${err.message}`);
    return null;
  }
  const { keyPath, keyId, teamId, bundleId, env } = raw ?? {};
  if (!keyPath || !keyId || !teamId || !bundleId || (env !== "sandbox" && env !== "production")) {
    log(`apns config ${apnsPath} incomplete (need keyPath, keyId, teamId, bundleId, env)`);
    return null;
  }
  if (!existsSync(keyPath)) {
    log(`apns key file missing: ${keyPath}`);
    return null;
  }
  let keyPem;
  try {
    keyPem = readFileSync(keyPath, "utf8");
  } catch (err) {
    log(`apns key unreadable: ${err.message}`);
    return null;
  }
  return { keyPath, keyId, teamId, bundleId, env, keyPem };
}

function apnsHost(env) {
  return env === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
}

function parseApnsReason(resp) {
  if (!resp) return undefined;
  try {
    const parsed = JSON.parse(resp);
    return typeof parsed?.reason === "string" ? parsed.reason : undefined;
  } catch {
    return undefined;
  }
}

/**
 * Real HTTP/2 APNs sender. Injectable `connect` for tests that still want the request shape
 * without talking to Apple; production uses node:http2.connect.
 * Resolves { status, reason } where reason is the APNs JSON body `reason` field (if any).
 */
export function createHttp2Sender(config, { connect = http2.connect, now = () => new Date(), log = console.error } = {}) {
  let jwt = null;
  let jwtExp = 0;

  function bearer() {
    const sec = Math.floor(now().getTime() / 1000);
    // APNs JWTs are valid up to 1h; refresh a minute early.
    if (!jwt || sec >= jwtExp - 60) {
      jwt = makeApnsJwt({ keyPem: config.keyPem, keyId: config.keyId, teamId: config.teamId, nowSec: sec });
      jwtExp = sec + 3500;
    }
    return jwt;
  }

  return async function sendApns({ deviceToken, headers, body }) {
    const host = apnsHost(config.env);
    const client = connect(`https://${host}`);
    return await new Promise((resolve, reject) => {
      let settled = false;
      const fail = (err) => {
        if (settled) return;
        settled = true;
        try {
          client.close();
        } catch {
          /* ignore */
        }
        reject(err);
      };
      const succeed = (value) => {
        if (settled) return;
        settled = true;
        try {
          client.close();
        } catch {
          /* ignore */
        }
        resolve(value);
      };

      client.on("error", fail);
      if (typeof client.setTimeout === "function") {
        client.setTimeout(APNS_REQUEST_TIMEOUT_MS, () => fail(new Error("apns client timeout")));
      }

      const reqHeaders = {
        ":method": "POST",
        ":path": `/3/device/${deviceToken}`,
        authorization: `bearer ${bearer()}`,
        "apns-topic": headers["apns-topic"] ?? config.bundleId,
        "apns-push-type": headers["apns-push-type"] ?? "alert",
        "apns-priority": headers["apns-priority"] ?? "10",
        "content-type": "application/json",
      };
      if (headers["apns-collapse-id"]) reqHeaders["apns-collapse-id"] = headers["apns-collapse-id"];
      if (headers["apns-expiration"]) reqHeaders["apns-expiration"] = headers["apns-expiration"];

      const req = client.request(reqHeaders);
      let status = 0;
      let resp = "";
      req.on("response", (h) => {
        status = Number(h[":status"] ?? 0);
      });
      req.setEncoding("utf8");
      req.on("data", (c) => (resp += c));
      req.on("end", () => {
        const reason = parseApnsReason(resp);
        if (status >= 400) log(`apns ${status} for …${deviceToken.slice(-8)}: ${resp || "(empty)"}`);
        succeed({ status, reason });
      });
      req.on("error", fail);
      if (typeof req.setTimeout === "function") {
        req.setTimeout(APNS_REQUEST_TIMEOUT_MS, () => fail(new Error("apns request timeout")));
      }
      req.end(JSON.stringify(body));
    });
  };
}

/** No-op sender when the key is absent. Logs once, never throws. Resolves { status: 0 }. */
export function createDisabledSender({ log = console.error } = {}) {
  let logged = false;
  return async function sendDisabled() {
    if (!logged) {
      logged = true;
      log("push disabled: no apns key (sends are no-ops)");
    }
    return { status: 0 };
  };
}

/**
 * Build the low-level sender from config. Prefer injecting `sender` in tests.
 * Returns { sender, health } where health is "no key" | "sandbox" | "production".
 */
export function buildSender(apnsPath, { sender, connect, now, log } = {}) {
  if (sender) {
    const cfg = loadApnsConfig(apnsPath, { log });
    return { sender, health: cfg ? cfg.env : "ready", config: cfg };
  }
  const config = loadApnsConfig(apnsPath, { log });
  if (!config) return { sender: createDisabledSender({ log }), health: "no key", config: null };
  return { sender: createHttp2Sender(config, { connect, now, log }), health: config.env, config };
}

function alertBody(title, body) {
  return {
    aps: {
      alert: { title, body },
      sound: "default",
    },
  };
}

/**
 * Push service: token routes helpers, notify helpers, red-alert sweep.
 * `sender` is injectable so tests assert payload + apns-topic with no network.
 */
export function createPush({
  db,
  apnsPath = DEFAULT_APNS_PATH,
  sender: injectedSender,
  now = () => new Date(),
  log = console.error,
  sweepIntervalMs = RED_ALERT_MS,
  connect,
} = {}) {
  const built = buildSender(apnsPath, { sender: injectedSender, connect, now, log });
  let health = built.health;
  let sender = built.sender;
  let config = built.config;
  const bundleId = () => config?.bundleId ?? DEFAULT_BUNDLE_ID;

  async function deliver(person, { title, body, headers: extraHeaders = {} }) {
    const rows = tokensForPerson(db, person);
    if (rows.length === 0) return;
    const payload = alertBody(title, body);
    const headers = {
      "apns-topic": bundleId(),
      "apns-push-type": "alert",
      "apns-priority": "10",
      ...extraHeaders,
    };
    for (const row of rows) {
      try {
        const result = await sender({ deviceToken: row.token, headers, body: payload });
        const status = result?.status;
        const reason = result?.reason;
        if (shouldPruneToken(status, reason)) {
          db.prepare("DELETE FROM push_tokens WHERE token = ?").run(row.token);
        }
      } catch (err) {
        log(`push send failed for ${person}: ${err.message}`);
      }
    }
  }

  async function notifyCompletion(row) {
    if (!row || row.deletedAt) return;
    const chore = db.prepare("SELECT title FROM chores WHERE id = ?").get(row.choreId);
    const title = chore?.title ?? row.choreId;
    const who = NAME[row.person] ?? row.person;
    const other = partnerOf(row.person);
    const expiration = String(Math.floor(now().getTime() / 1000) + COMPLETION_EXPIRATION_SEC);
    await deliver(other, {
      title: "Roost",
      body: `${who} did ${title}`,
      headers: { "apns-expiration": expiration },
    });
  }

  /** daily→today, weekly|biweekly→this week, monthly→this month. */
  function periodPhrase(cadence) {
    if (cadence === "daily") return "today";
    if (cadence === "weekly" || cadence === "biweekly") return "this week";
    if (cadence === "monthly") return "this month";
    return "this period";
  }

  /**
   * Handoff push. kind: "offer" | "accepted" | "declined".
   * Offer → toPerson; accept/decline → fromPerson. Collapse id handoff-<id>.
   * Callers fire only on real transitions (created offer; newly accepted/declined).
   */
  async function notifyHandoff(row, kind) {
    if (!row) return;
    const chore = db.prepare("SELECT title FROM chores WHERE id = ?").get(row.choreId);
    const title = chore?.title ?? row.choreId;
    const phrase = periodPhrase(row.cadence);
    const headers = { "apns-collapse-id": `handoff-${row.id}` };
    if (kind === "offer") {
      const who = NAME[row.fromPerson] ?? row.fromPerson;
      await deliver(row.toPerson, {
        title: "Roost",
        body: `${who} asked you to take ${title} ${phrase}`,
        headers,
      });
      return;
    }
    if (kind === "accepted" || kind === "declined") {
      const who = NAME[row.toPerson] ?? row.toPerson;
      const verb = kind === "accepted" ? "accepted" : "declined";
      await deliver(row.fromPerson, {
        title: "Roost",
        body: `${who} ${verb} ${title} ${phrase}`,
        headers,
      });
    }
  }

  /**
   * Red-alert: stage >= 3 ("alert", daysOverdue >= 5). Notify the assignee's partner.
   * Idempotent across restarts via push_alerts (choreId, periodIndex).
   * Re-entrancy guarded: a second tick while a sweep is awaiting sends is a no-op.
   */
  let sweeping = false;
  async function runRedAlertSweep(asOf = now()) {
    if (sweeping) return;
    sweeping = true;
    try {
      const chores = db
        .prepare("SELECT id, title, cadence, fixedAssignee, category FROM chores WHERE retired = 0 ORDER BY sortOrder")
        .all();
      const completions = db
        .prepare("SELECT choreId, person, completedAt FROM completions WHERE deletedAt IS NULL")
        .all();
      const activeFrom = parseActiveFrom(getMeta(db, "activeFrom"));
      const due = dueItems({ chores, completions, asOf, activeFrom });
      const sentAt = asOf.toISOString();
      for (const person of PEOPLE) {
        for (const item of due[person] ?? []) {
          if ((STAGE_RANK[item.stage] ?? -1) < 3) continue;
          if (hasPushAlert(db, item.chore.id, item.periodIndex)) continue;
          recordPushAlert(db, item.chore.id, item.periodIndex, sentAt);
          const other = partnerOf(item.person);
          const who = NAME[item.person] ?? item.person;
          await deliver(other, {
            title: "Roost red alert",
            body: `${who}'s chore is overdue: ${item.chore.title}`,
            headers: { "apns-collapse-id": `red-${item.chore.id}` },
          });
        }
      }
    } finally {
      sweeping = false;
    }
  }

  /**
   * Morning digest (R-25): at/after 08:00 America/Chicago, one push per person who has
   * due-today or overdue items. Title Roost; body "N for you today: <most urgent>"
   * (+ " and N-1 more" when N > 1). Most urgent = highest STAGE_RANK, ties keep list order.
   * apns-collapse-id digest-<person>; apns-expiration = next Chicago midnight.
   * Persists digestLastSent (Chicago date) so a restart never double-sends.
   * dueItems with activeFrom + handoffs, balancer off. Same interval as red-alert.
   */
  let digestSweeping = false;
  async function runMorningDigestSweep(asOf = now()) {
    if (digestSweeping) return;
    digestSweeping = true;
    try {
      const today = chicagoDateString(asOf);
      if (getMeta(db, DIGEST_LAST_SENT_META) === today) return;

      const [y, m, d] = today.split("-").map(Number);
      const eight = chicagoLocal(y, m, d, 8, 0, 0);
      if (asOf.getTime() < eight.getTime()) return;

      const chores = db
        .prepare("SELECT id, title, cadence, fixedAssignee, category FROM chores WHERE retired = 0 ORDER BY sortOrder")
        .all();
      const completions = db
        .prepare("SELECT choreId, person, completedAt FROM completions WHERE deletedAt IS NULL")
        .all();
      const handoffs = listHandoffs(db);
      const activeFrom = parseActiveFrom(getMeta(db, "activeFrom"));
      const due = dueItems({ chores, completions, asOf, activeFrom, handoffs, balance: false });
      const endOfDay = chicagoLocal(y, m, d + 1, 0, 0, 0);
      const expiration = String(Math.floor(endOfDay.getTime() / 1000));

      for (const person of PEOPLE) {
        const items = due[person] ?? [];
        if (items.length === 0) continue;
        const n = items.length;
        const mostUrgent = items.reduce((best, item) =>
          (STAGE_RANK[item.stage] ?? -1) > (STAGE_RANK[best.stage] ?? -1) ? item : best
        );
        const first = mostUrgent.chore?.title ?? mostUrgent.chore?.id ?? "chore";
        const body =
          n > 1 ? `${n} for you today: ${first} and ${n - 1} more` : `${n} for you today: ${first}`;
        await deliver(person, {
          title: "Roost",
          body,
          headers: {
            "apns-collapse-id": `digest-${person}`,
            "apns-expiration": expiration,
          },
        });
      }

      setMeta(db, DIGEST_LAST_SENT_META, today);
    } finally {
      digestSweeping = false;
    }
  }

  let timer = null;
  function startSweep() {
    if (timer || sweepIntervalMs <= 0) return;
    timer = setInterval(() => {
      runRedAlertSweep().catch((err) => log(`red-alert sweep: ${err.message}`));
      runMorningDigestSweep().catch((err) => log(`morning digest: ${err.message}`));
    }, sweepIntervalMs);
    timer.unref?.();
  }

  function stopSweep() {
    if (timer) {
      clearInterval(timer);
      timer = null;
    }
  }

  startSweep();

  return {
    health: () => health,
    notifyCompletion,
    notifyHandoff,
    runRedAlertSweep,
    runMorningDigestSweep,
    deliver,
    startSweep,
    stopSweep,
    /** Test helper: swap sender without rebuilding the app. */
    _setSender(s, h = "ready", cfg = null) {
      sender = s;
      health = h;
      config = cfg;
    },
  };
}

// ---- Routes -------------------------------------------------------------------------------------

/**
 *   POST   /push/token   { token, platform } -> 200 upsert; person from bearer
 *   DELETE /push/token   { token }           -> 200 unregister (own tokens only), 404 unknown
 * Returns true when answered.
 */
export async function pushRoutes({ req, res, path, db, device, send, readJson, iso }) {
  if (path !== "/push/token") return false;

  if (req.method === "POST") {
    const body = await readJson(req);
    const token = typeof body.token === "string" ? body.token.trim() : "";
    const platform = typeof body.platform === "string" ? body.platform.trim().toLowerCase() : "";
    if (!TOKEN_RE.test(token)) {
      send(res, 400, { error: "token must be a 64-char hex APNs device token" });
      return true;
    }
    if (!PLATFORMS.has(platform)) {
      send(res, 400, { error: "platform must be ios" });
      return true;
    }
    const row = upsertPushToken(db, { token, person: device.person, platform }, iso());
    send(res, 200, { token: row.token, person: row.person, platform: row.platform, updatedAt: row.updatedAt });
    return true;
  }

  if (req.method === "DELETE") {
    const body = await readJson(req);
    const token = typeof body.token === "string" ? body.token.trim() : "";
    if (!TOKEN_RE.test(token)) {
      send(res, 400, { error: "token must be a 64-char hex APNs device token" });
      return true;
    }
    const row = deletePushToken(db, { token, person: device.person });
    if (!row) {
      send(res, 404, { error: "not found" });
      return true;
    }
    send(res, 200, { token: row.token, person: row.person, platform: row.platform, updatedAt: row.updatedAt, deleted: true });
    return true;
  }

  return false;
}