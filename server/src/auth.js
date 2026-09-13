// Bearer device tokens. No accounts, no signup.
// Tokens file: { "<token>": { "person": "anne" | "wes", "device": "Anne iPhone" } }
// The file is read at startup and re-read when its mtime changes, so rotating a token is: edit file, done.
import { readFileSync, statSync } from "node:fs";
import { createHash, timingSafeEqual } from "node:crypto";

const PEOPLE = new Set(["anne", "wes"]);

export function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}

export function parseTokens(json) {
  const raw = JSON.parse(json);
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new Error("tokens file must be an object");
  const byHash = new Map();
  for (const [token, info] of Object.entries(raw)) {
    if (typeof token !== "string" || token.length < 16) throw new Error("token too short (min 16 chars)");
    if (!info || !PEOPLE.has(info.person)) throw new Error(`token for unknown person: ${JSON.stringify(info?.person)}`);
    byHash.set(hashToken(token), { person: info.person, label: String(info.device ?? "unnamed device") });
  }
  return byHash;
}

export function createTokenStore(path) {
  let byHash = new Map();
  let mtimeMs = -1;
  const reload = () => {
    const st = statSync(path);
    if (st.mtimeMs !== mtimeMs) {
      byHash = parseTokens(readFileSync(path, "utf8"));
      mtimeMs = st.mtimeMs;
    }
  };
  reload();
  return {
    /** Returns { tokenHash, person, label } or null. */
    lookup(bearer) {
      try {
        reload();
      } catch {
        // keep the last good set if the file is mid-edit
      }
      if (typeof bearer !== "string" || bearer.length < 16) return null;
      const h = hashToken(bearer);
      for (const [known, info] of byHash) {
        const a = Buffer.from(known, "hex");
        const b = Buffer.from(h, "hex");
        if (a.length === b.length && timingSafeEqual(a, b)) return { tokenHash: known, ...info };
      }
      return null;
    },
    size() {
      return byHash.size;
    },
  };
}

export function bearerFrom(req) {
  const h = req.headers["authorization"];
  if (!h || typeof h !== "string") return null;
  const m = /^Bearer\s+(.+)$/i.exec(h.trim());
  return m ? m[1].trim() : null;
}
