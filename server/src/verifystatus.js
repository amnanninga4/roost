/** Read nightly verify-backup status for /health and /status.json.
 *
 * Path: ROOST_VERIFY_STATUS, default /var/lib/roost/verify-status.json.
 * Never touches the filesystem at module load. Reads on each call.
 * Absent or unparseable → null (log once per bad mtime / read error; never throw).
 * Exposed shape is { at, ok, seq } only — integrity/backup stay on disk for ops.
 */
import { readFileSync, statSync } from "node:fs";

export const DEFAULT_VERIFY_STATUS_PATH = "/var/lib/roost/verify-status.json";

export function verifyStatusPath() {
  const fromEnv = process.env.ROOST_VERIFY_STATUS;
  if (fromEnv != null && fromEnv !== "") return fromEnv;
  return DEFAULT_VERIFY_STATUS_PATH;
}

/** @type {string|null} */
let loggedKey = null;

/**
 * @param {{ path?: string, log?: (msg: string) => void }} [opts]
 * @returns {{ at: string, ok: boolean, seq: number|null } | null}
 */
export function readVerifyStatus({ path, log = console.error } = {}) {
  const statusPath = path ?? verifyStatusPath();
  let st;
  try {
    st = statSync(statusPath);
  } catch (err) {
    if (err && err.code === "ENOENT") return null;
    const key = `stat:${statusPath}:${err?.code ?? err?.message}`;
    if (loggedKey !== key) {
      loggedKey = key;
      log(`verify-status ${statusPath} unreadable: ${err?.message ?? err}`);
    }
    return null;
  }

  let raw;
  try {
    raw = readFileSync(statusPath, "utf8");
  } catch (err) {
    const key = `read:${statusPath}:${st.mtimeMs}`;
    if (loggedKey !== key) {
      loggedKey = key;
      log(`verify-status ${statusPath} unreadable: ${err?.message ?? err}`);
    }
    return null;
  }

  try {
    const j = JSON.parse(raw);
    if (!j || typeof j !== "object" || Array.isArray(j)) throw new Error("must be an object");
    if (typeof j.at !== "string" || !j.at) throw new Error("at must be a non-empty string");
    if (typeof j.ok !== "boolean") throw new Error("ok must be boolean");
    let seq = null;
    if (j.seq != null) {
      const n = Number(j.seq);
      if (!Number.isFinite(n)) throw new Error("seq must be a number or null");
      seq = n;
    }
    return { at: j.at, ok: j.ok, seq };
  } catch (err) {
    const key = `parse:${statusPath}:${st.mtimeMs}`;
    if (loggedKey !== key) {
      loggedKey = key;
      log(`verify-status ${statusPath} not applied: ${err?.message ?? err}`);
    }
    return null;
  }
}
