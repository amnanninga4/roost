// Pairing codes. A phone pairs by typing a short code, not by pasting a 43-character bearer token.
//
// `src/mkcode.js` mints a 6-digit code that names the person and the device it is for and lives for 15
// minutes. The phone POSTs it to /pair with its own device name; the server mints a real bearer token
// exactly as mktoken.js does, appends it to the tokens file, marks the code consumed with that token's
// hash, and hands the token back. Bearer tokens are still the only long-lived credential — the code is a
// one-shot way to hand one over, and DELETE /pair/self gives it back.
//
// Everything pairing lives here so it sits next to the other tables: db.js only runs PAIRING_SCHEMA,
// app.js only builds the routes and dispatches to them, /health only reads pendingCodes().
//
// No `seq` column: codes never reach the phones through /sync, so they stay outside the sync cursor.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { randomBytes, randomInt } from "node:crypto";
import { PEOPLE } from "./db.js";

// No people CHECK in this schema, for the reason bonus.js gives: db.js imports this file for
// PAIRING_SCHEMA, so PEOPLE is not initialised while this module evaluates (module cycle).
// createPairingCode reads PEOPLE at call time and is the only writer of `person`.
export const PAIRING_SCHEMA = `
CREATE TABLE IF NOT EXISTS pairing_codes (
  code        TEXT PRIMARY KEY,
  person      TEXT NOT NULL,
  deviceLabel TEXT NOT NULL,
  createdAt   TEXT NOT NULL,
  expiresAt   TEXT NOT NULL,
  consumedAt  TEXT,
  tokenHash   TEXT
);
CREATE INDEX IF NOT EXISTS pairing_codes_expires ON pairing_codes(expiresAt);
`;

const CODE_LEN = 6;
const CODE_SPACE = 10 ** CODE_LEN; // 000000-999999, zero-padded, so a leading zero is a real code
const CODE_DRAWS = 40; // only a live code blocks a number, so this is never close to exhausted
const CODE_RE = /^\d{6}$/;
/** Default life of a code. Long enough to walk to the other phone, short enough to be worth guessing. */
export const DEFAULT_MINUTES = 15;
const MINUTES_MAX = 24 * 60;
const TOKEN_BYTES = 32; // as mktoken.js: 32 random bytes -> 43 base64url chars
const TOKEN_MODE = 0o640; // as mktoken.js; only applies when the file is created
const DEVICE_NAME_MAX = 60;
const RATE_LIMIT = 10; // /pair attempts per window, per source address
const RATE_WINDOW_MS = 60_000;
const RATE_KEYS_MAX = 512; // swept when exceeded, so a spoofed-header flood cannot grow the map

/** Uniform 6-digit draw. `randomInt` is crypto-backed; String().padStart keeps 000123 usable. */
function randomCode() {
  return String(randomInt(CODE_SPACE)).padStart(CODE_LEN, "0");
}

/**
 * The row for `code` if it is still usable: known, unconsumed, unexpired. One query for all three
 * failures, so an unknown code, a used one and an expired one take the same path out.
 * Times are compared as strings, which holds because every one of them is a `toISOString()`.
 */
export function liveCode(db, code, nowIso) {
  const row = db
    .prepare("SELECT * FROM pairing_codes WHERE code = ? AND consumedAt IS NULL AND expiresAt > ?")
    .get(code, nowIso);
  return row ?? null;
}

/** Codes still waiting to be used. Reported by /health so a forgotten code is visible. */
export function pendingCodes(db, nowIso) {
  return db
    .prepare("SELECT COUNT(*) AS n FROM pairing_codes WHERE consumedAt IS NULL AND expiresAt > ?")
    .get(nowIso).n;
}

/**
 * Mint a code for `person` / `deviceLabel`, live for `minutes`. Returns the stored row.
 * Codes are unique among the live ones: a live code owns its number, a consumed or expired row's
 * number is free to draw again.
 */
export function createPairingCode(db, { person, deviceLabel, minutes = DEFAULT_MINUTES }, nowIso) {
  if (!PEOPLE.includes(person)) throw new Error(`unknown person: ${JSON.stringify(person)}`);
  const label = String(deviceLabel ?? "").trim();
  if (!label) throw new Error("device label required");
  if (!Number.isInteger(minutes) || minutes < 1 || minutes > MINUTES_MAX) {
    throw new Error(`minutes must be an integer 1-${MINUTES_MAX}`);
  }
  const expiresAt = new Date(Date.parse(nowIso) + minutes * 60_000).toISOString();
  const read = db.prepare("SELECT * FROM pairing_codes WHERE code = ?");
  for (let i = 0; i < CODE_DRAWS; i++) {
    const code = randomCode();
    const clash = read.get(code);
    if (clash && !clash.consumedAt && clash.expiresAt > nowIso) continue;
    if (clash) db.prepare("DELETE FROM pairing_codes WHERE code = ?").run(code);
    db.prepare(
      "INSERT INTO pairing_codes (code, person, deviceLabel, createdAt, expiresAt) VALUES (?, ?, ?, ?, ?)"
    ).run(code, person, label, nowIso, expiresAt);
    return read.get(code);
  }
  throw new Error(`no free pairing code after ${CODE_DRAWS} draws`);
}

/**
 * Mint a bearer token and append it to the tokens file, the same way src/mktoken.js does: 32 random
 * bytes as base64url, the whole file rewritten, 0640 when it has to be created. Returns the token.
 * The server never stores it — only its SHA-256 lands in the DB.
 */
export function mintToken(tokensPath, { person, device }) {
  const current = existsSync(tokensPath) ? JSON.parse(readFileSync(tokensPath, "utf8")) : {};
  const token = randomBytes(TOKEN_BYTES).toString("base64url");
  current[token] = { person, device };
  writeFileSync(tokensPath, JSON.stringify(current, null, 2) + "\n", { mode: TOKEN_MODE });
  return token;
}

/** Drop `token` from the tokens file. True when it was there. */
export function revokeToken(tokensPath, token) {
  if (!existsSync(tokensPath)) return false;
  const current = JSON.parse(readFileSync(tokensPath, "utf8"));
  if (!(token in current)) return false;
  delete current[token];
  writeFileSync(tokensPath, JSON.stringify(current, null, 2) + "\n", { mode: TOKEN_MODE });
  return true;
}

/**
 * Sliding-window attempt counter for the one public endpoint. In memory: a restart forgets it, which is
 * fine — it exists so a 6-digit code cannot be ground through, and codes expire in minutes anyway.
 * Rejected attempts are not recorded, so the window is `limit` answered attempts per `windowMs`.
 */
export function createRateLimiter({ limit = RATE_LIMIT, windowMs = RATE_WINDOW_MS, keysMax = RATE_KEYS_MAX } = {}) {
  const hits = new Map(); // key -> ms timestamps still inside the window
  const fresh = (list, tMs) => list.filter((t) => tMs - t < windowMs);
  return {
    /** Records an attempt by `key` at `tMs`. False when that key is over the limit for this window. */
    allow(key, tMs) {
      if (hits.size > keysMax) for (const [k, list] of hits) if (fresh(list, tMs).length === 0) hits.delete(k);
      const list = fresh(hits.get(key) ?? [], tMs);
      hits.set(key, list);
      if (list.length >= limit) return false;
      list.push(tMs);
      return true;
    },
  };
}

/**
 * The caller's address. The server sits behind a Cloudflare Tunnel, so the socket address is the tunnel
 * itself: CF-Connecting-IP is the header cloudflared sets and a client cannot forge through it.
 * X-Forwarded-For (first hop) covers any other proxy in front; the socket is the fallback.
 */
export function clientIp(req) {
  const cf = req.headers["cf-connecting-ip"];
  if (typeof cf === "string" && cf.trim()) return cf.trim();
  const xff = req.headers["x-forwarded-for"];
  const hop = typeof xff === "string" ? xff.split(",")[0].trim() : "";
  return hop || req.socket?.remoteAddress || "unknown";
}

/**
 * The /pair routes, built once per app because the rate limiter is per-process state.
 *   POST   /pair        NO AUTH  { code, deviceName } -> 200 { token, person }
 *                                404 for any unusable code, 429 over the attempt limit
 *   DELETE /pair/self   bearer   drops the calling device's token and its devices row
 * `routes(req, res, path)` returns true when it answered the request, false to fall through.
 */
export function createPairing({
  db,
  tokens,
  tokensPath,
  hashToken,
  bearerFrom,
  send,
  readJson,
  now,
  limiter = createRateLimiter(),
}) {
  const iso = () => now().toISOString();

  async function routes(req, res, path) {
    if (req.method === "POST" && path === "/pair") {
      // Counted before the body is read: a flood of junk bodies costs a guesser the same as a flood of codes.
      if (!limiter.allow(clientIp(req), now().getTime())) {
        send(res, 429, { error: "too many pairing attempts, wait a minute" });
        return true;
      }
      const body = await readJson(req);
      const code = typeof body.code === "string" ? body.code.trim() : "";
      const deviceName = typeof body.deviceName === "string" ? body.deviceName.trim() : "";
      if (!CODE_RE.test(code) || !deviceName || deviceName.length > DEVICE_NAME_MAX) {
        send(res, 400, { error: `code must be ${CODE_LEN} digits and deviceName 1-${DEVICE_NAME_MAX} chars` });
        return true;
      }
      const nowIso = iso();
      const row = liveCode(db, code, nowIso);
      // One answer for unknown / already used / expired: a guesser learns nothing from which it was.
      if (!row) {
        send(res, 404, { error: "invalid or expired code" });
        return true;
      }
      // Synchronous from here, so no other request can land between minting and consuming. The token is
      // written first: if that throws, the code is still live and the phone can try again.
      const token = mintToken(tokensPath, { person: row.person, device: `${row.deviceLabel} · ${deviceName}` });
      db.prepare("UPDATE pairing_codes SET consumedAt = ?, tokenHash = ? WHERE code = ?").run(
        nowIso,
        hashToken(token),
        code
      );
      tokens.refresh(); // the store keys off mtime; force it so the token works on the very next request
      send(res, 200, { token, person: row.person });
      return true;
    }

    if (req.method === "DELETE" && path === "/pair/self") {
      const bearer = bearerFrom(req);
      const device = tokens.lookup(bearer);
      if (!device) {
        send(res, 401, { error: "unauthorized" });
        return true;
      }
      revokeToken(tokensPath, bearer);
      // `devices` is db.js's table, keyed by the same hash the store just handed back.
      db.prepare("DELETE FROM devices WHERE tokenHash = ?").run(device.tokenHash);
      tokens.refresh(); // the next request with this token is a 401
      send(res, 200, { unpaired: true, person: device.person, label: device.label });
      return true;
    }

    return false;
  }

  return { routes };
}
