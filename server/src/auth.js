// Bearer device tokens. No accounts, no signup. Two sources, checked in this order:
//   1. the tokens file, hand-minted by mktoken.js and never written by the API:
//      { "<token>": { "person": "anne" | "wes", "device": "Anne iPhone" } }
//   2. the `paired_tokens` table, written by POST /pair (pairing.js) when a phone redeems a code.
// The file is read at startup and re-read when its mtime changes, so rotating a token is: edit file, done.
// A file that fails to parse after an edit is logged (once per mtime) and reported in /health; the last
// good set stays active until the file is fixed, so a broken edit cannot lock every device out. The table
// is read live on every lookup, so pairing and revoking take effect on the very next request.
import { readFileSync, statSync } from "node:fs";
import { createHash, timingSafeEqual } from "node:crypto";
import { PEOPLE } from "./db.js";

const PEOPLE_SET = new Set(PEOPLE);

export function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}

export function parseTokens(json) {
  const raw = JSON.parse(json);
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("tokens file must be an object");
  const byHash = new Map();
  for (const [token, info] of Object.entries(raw)) {
    if (typeof token !== "string" || token.length < 16) throw new Error("token too short (min 16 chars)");
    if (!info || !PEOPLE_SET.has(info.person)) throw new Error(`token for unknown person: ${JSON.stringify(info?.person)}`);
    byHash.set(hashToken(token), { person: info.person, label: String(info.device ?? "unnamed device") });
  }
  return byHash;
}

export function createTokenStore(path, { db, log = console.error } = {}) {
  let byHash = new Map();
  let mtimeMs = -1;
  let lastError = null;
  let erroredMtime = -1;

  const reload = () => {
    const st = statSync(path);
    if (st.mtimeMs === mtimeMs) return;
    try {
      byHash = parseTokens(readFileSync(path, "utf8"));
      mtimeMs = st.mtimeMs;
      lastError = null;
    } catch (err) {
      if (erroredMtime !== st.mtimeMs) {
        erroredMtime = st.mtimeMs;
        lastError = `${new Date().toISOString()} tokens file ${path} not applied: ${err.message}`;
        log(lastError);
      }
    }
  };

  // First load must succeed: a bad file at startup is a deploy error, not something to limp past.
  byHash = parseTokens(readFileSync(path, "utf8"));
  mtimeMs = statSync(path).mtimeMs;

  return {
    /** Returns { tokenHash, person, label, source: "file" | "paired" } or null. */
    lookup(bearer) {
      reload();
      if (typeof bearer !== "string" || bearer.length < 16) return null;
      const h = hashToken(bearer);
      for (const [known, info] of byHash) {
        const a = Buffer.from(known, "hex");
        const b = Buffer.from(h, "hex");
        if (a.length === b.length && timingSafeEqual(a, b)) return { tokenHash: known, ...info, source: "file" };
      }
      // pairing.js owns this table. The primary-key lookup compares SHA-256 of the presented token, not
      // the token, so an index probe leaks nothing a timing-safe walk would hide.
      const paired = db
        ?.prepare("SELECT person, label FROM paired_tokens WHERE tokenHash = ? AND revokedAt IS NULL")
        .get(h);
      return paired ? { tokenHash: h, person: paired.person, label: paired.label, source: "paired" } : null;
    },
    /** Devices that can authenticate right now: file entries plus unrevoked paired tokens. */
    size() {
      reload();
      const active = db?.prepare("SELECT COUNT(*) AS n FROM paired_tokens WHERE revokedAt IS NULL").get().n ?? 0;
      return byHash.size + active;
    },
    /** Null when the current file parsed cleanly; otherwise the logged message. */
    error() {
      reload();
      return lastError;
    },
  };
}

export function bearerFrom(req) {
  const h = req.headers["authorization"];
  if (!h || typeof h !== "string") return null;
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1].trim() : null;
}
