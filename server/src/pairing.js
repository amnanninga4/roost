// Pairing codes. A phone pairs by typing a short code, not by pasting a 43-character bearer token.
//
// `src/mkcode.js` mints a 6-digit code that names the person and the device it is for and lives for 15
// minutes. The phone POSTs it to /pair with its own device name; the server mints a real bearer token,
// records its SHA-256 in `paired_tokens`, marks the code consumed, and hands the token back. Bearer
// tokens are still the only long-lived credential — the code is a one-shot way to hand one over.
//
// Paired tokens live in SQLite, never in the tokens file. The API only ever reads `/etc/roost/tokens.json`
// (root:roost 0640, hand-minted by mktoken.js): rewriting it from a request is not atomic, so a crash or
// a full disk mid-write would truncate it and lock every device out, and the unit keeps /etc read-only on
// purpose. A row here is also revocable from the shell (`src/devices.js`) with no file edit and no restart.
//
// Everything pairing lives here so it sits next to the other tables: db.js only runs PAIRING_SCHEMA,
// app.js only builds the routes and dispatches to them, /health only reads pendingCodes().
//
// No `seq` on either table: neither codes nor tokens reach the phones through /sync.
import { randomBytes, randomInt } from "node:crypto";
import { PEOPLE } from "./db.js";

// No people CHECK in either table, for the reason bonus.js gives: db.js imports this file for
// PAIRING_SCHEMA, so PEOPLE is not initialised while this module evaluates (module cycle).
// createPairingCode reads PEOPLE at call time, and it is the only writer of `person` in both.
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
CREATE TABLE IF NOT EXISTS paired_tokens (
  tokenHash TEXT PRIMARY KEY,
  person    TEXT NOT NULL,
  label     TEXT NOT NULL,
  createdAt TEXT NOT NULL,
  revokedAt TEXT
);
`;

const CODE_LEN = 6;
const CODE_SPACE = 10 ** CODE_LEN; // 000000-999999, zero-padded, so a leading zero is a real code
const CODE_DRAWS = 40; // only a live code blocks a number, so this is never close to exhausted
const CODE_RE = /^\d{6}$/;
/** Default life of a code. Long enough to walk to the other phone, short enough to be worth guessing. */
export const DEFAULT_MINUTES = 15;
const MINUTES_MAX = 24 * 60;
const TOKEN_BYTES = 32; // as mktoken.js: 32 random bytes -> 43 base64url chars
const DEVICE_NAME_MAX = 60;
const RATE_LIMIT = 10; // answered /pair attempts per window, per source address
/**
 * And a cap across every source. A 6-digit code has 1,000,000 values and lives 15 minutes, so the
 * per-address limit alone does not bound a guess: every new address brings its own budget. 30 answered
 * attempts a minute bounds one code's whole lifetime to about 450 guesses — roughly 1 in 2,200 of
 * landing on a live code before it expires — no matter how many addresses the guesses come from.
 */
const RATE_GLOBAL_LIMIT = 30;
const RATE_GLOBAL_KEY = "*";
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

/** A bearer token of the shape mktoken.js mints. The token itself is never stored, only its hash. */
export function mintTokenValue() {
  return randomBytes(TOKEN_BYTES).toString("base64url");
}

/**
 * Record a minted token and spend the code it came from, in ONE transaction: the code stays live unless
 * the token is really stored, and no token is stored without its code being spent.
 */
export function storePairedToken(db, { tokenHash, person, label, code }, nowIso) {
  db.exec("BEGIN");
  try {
    db.prepare("INSERT INTO paired_tokens (tokenHash, person, label, createdAt) VALUES (?, ?, ?, ?)").run(
      tokenHash,
      person,
      label,
      nowIso
    );
    db.prepare("UPDATE pairing_codes SET consumedAt = ?, tokenHash = ? WHERE code = ?").run(nowIso, tokenHash, code);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
}

/**
 * Revoke a paired token: the store stops accepting it on the very next request (it reads this table
 * live), and its `devices` row goes with it. One code path for DELETE /pair/self and src/devices.js.
 * False when the hash is not a live paired token; nothing here can touch a hand-minted file token.
 */
export function revokePairedToken(db, tokenHash, nowIso) {
  const row = db.prepare("SELECT revokedAt FROM paired_tokens WHERE tokenHash = ?").get(tokenHash);
  if (!row || row.revokedAt) return false;
  db.exec("BEGIN");
  try {
    db.prepare("UPDATE paired_tokens SET revokedAt = ? WHERE tokenHash = ?").run(nowIso, tokenHash);
    db.prepare("DELETE FROM devices WHERE tokenHash = ?").run(tokenHash);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return true;
}

/** Every paired token with the `devices` lastSeen, newest first. Revoked rows included, flagged. */
export function listPairedTokens(db) {
  return db
    .prepare(
      `SELECT p.tokenHash, p.person, p.label, p.createdAt, p.revokedAt, d.lastSeen
       FROM paired_tokens p LEFT JOIN devices d ON d.tokenHash = p.tokenHash
       ORDER BY p.createdAt DESC`
    )
    .all();
}

/**
 * Sliding-window attempt counter. In memory: a restart forgets it, which is fine — it exists so a
 * 6-digit code cannot be ground through, and codes expire in minutes anyway. Rejected attempts are not
 * recorded, so a window holds `limit` answered attempts.
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
 * The /pair routes, built once per app because the rate limiters are per-process state.
 *   POST   /pair        NO AUTH  { code, deviceName } -> 200 { token, person }
 *                                404 for any unusable code, 429 over either attempt limit
 *   DELETE /pair/self   bearer   revokes the calling device's paired token and its devices row;
 *                                403 for a hand-minted token, which only the tokens file can revoke
 * `routes(req, res, path)` returns true when it answered the request, false to fall through.
 */
export function createPairing({
  db,
  tokens,
  hashToken,
  bearerFrom,
  send,
  readJson,
  now,
  limiter = createRateLimiter(),
  globalLimiter = createRateLimiter({ limit: RATE_GLOBAL_LIMIT }),
}) {
  const iso = () => now().toISOString();

  async function routes(req, res, path) {
    if (req.method === "POST" && path === "/pair") {
      // Counted before the body is read: a flood of junk bodies costs a guesser the same as a flood of
      // codes. Short-circuited, so an attempt refused by one limiter is not charged to the other.
      const tMs = now().getTime();
      if (!limiter.allow(clientIp(req), tMs) || !globalLimiter.allow(RATE_GLOBAL_KEY, tMs)) {
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
      const token = mintTokenValue();
      // One transaction, so a failure leaves the code live rather than spent on a token nobody has.
      storePairedToken(
        db,
        { tokenHash: hashToken(token), person: row.person, label: `${row.deviceLabel} · ${deviceName}`, code },
        nowIso
      );
      // No store reload: the token store reads paired_tokens live, so this works on the next request.
      send(res, 200, { token, person: row.person });
      return true;
    }

    if (req.method === "DELETE" && path === "/pair/self") {
      const device = tokens.lookup(bearerFrom(req));
      if (!device) {
        send(res, 401, { error: "unauthorized" });
        return true;
      }
      if (device.source !== "paired") {
        send(res, 403, { error: "this device was set up by hand; remove it from the tokens file" });
        return true;
      }
      revokePairedToken(db, device.tokenHash, iso());
      send(res, 200, { unpaired: true, person: device.person, label: device.label });
      return true;
    }

    return false;
  }

  return { routes };
}
