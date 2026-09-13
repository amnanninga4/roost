// Handoffs: one person offers their turn at a chore to the other for a single period.
// Mirrors Packages/RoostCore Handoff + HandoffRules. SQL columns are fromPerson/toPerson;
// JSON exposes from/to so the app's Codable matches.
//
// Rows share meta.seq with every other table. Create / accept / decline / expire each take
// the next seq so /sync carries every delta. Expiry runs at the start of /sync (and on
// accept/decline), same pattern as bonus auto-assign — no timer required.
import { PEOPLE } from "./db.js";
import { periodIndex as calendarPeriodIndex, assigneeFor } from "./rules.js";

// No people CHECK here: same module-cycle reason as bonus.js. Writers take the person from
// an authenticated token or from PEOPLE, validated at call time.
export const HANDOFFS_SCHEMA = `
CREATE TABLE IF NOT EXISTS handoffs (
  id          TEXT PRIMARY KEY,
  choreId     TEXT NOT NULL REFERENCES chores(id),
  fromPerson  TEXT NOT NULL,
  toPerson    TEXT NOT NULL,
  periodIndex INTEGER NOT NULL,
  cadence     TEXT NOT NULL CHECK (cadence IN ('daily','weekly','biweekly','monthly')),
  state       TEXT NOT NULL CHECK (state IN ('pending','accepted','declined','expired')),
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS handoffs_seq ON handoffs(seq);
CREATE INDEX IF NOT EXISTS handoffs_chore_period ON handoffs(choreId, periodIndex);
`;

const STATES = new Set(["pending", "accepted", "declined", "expired"]);
const OPEN = new Set(["pending", "accepted"]);

function nextSeq(db) {
  db.prepare("UPDATE meta SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) WHERE key = 'seq'").run();
  return Number(db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
}

export function getHandoff(db, id) {
  return db.prepare("SELECT * FROM handoffs WHERE id = ?").get(id) ?? null;
}

/** Live (not soft-deleted) handoffs, any state. Used by assigneeFor / status board. */
export function listHandoffs(db) {
  return db.prepare("SELECT * FROM handoffs WHERE deletedAt IS NULL ORDER BY createdAt, id").all();
}

/** Handoffs with seq > cursor, including soft-deleted ones. cursor 0 = everything. */
export function handoffsAfter(db, cursor) {
  return db.prepare("SELECT * FROM handoffs WHERE seq > ? ORDER BY seq").all(cursor);
}

function update(db, id, fields, now) {
  db.exec("BEGIN");
  try {
    const seq = nextSeq(db);
    const names = Object.keys(fields);
    const sets = names.map((n) => `${n} = ?`).concat("updatedAt = ?", "seq = ?").join(", ");
    db.prepare(`UPDATE handoffs SET ${sets} WHERE id = ?`).run(...names.map((n) => fields[n]), now, seq, id);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return getHandoff(db, id);
}

/** True once `date` is in a later period than the one handed off. */
export function hasExpired(handoff, date) {
  return calendarPeriodIndex(handoff.cadence, date) > handoff.periodIndex;
}

/** Stored state, or expired once the period has ended for a *pending* offer.
 * Accepted handoffs never expire (R-21): they remain a permanent fact about their period. */
export function effectiveState(handoff, date) {
  if (handoff.state === "pending" && hasExpired(handoff, date)) return "expired";
  return handoff.state;
}

/**
 * Accepted handoff that decides who owes choreId for periodIndex, or null.
 * Pending/declined do not override. Accepted rows keep matching after the period ends (R-21).
 */
export function acceptedOverride(choreId, periodIdx, handoffs, date) {
  const matches = handoffs
    .filter((h) => !h.deletedAt)
    .filter((h) => h.choreId === choreId && h.periodIndex === periodIdx)
    .filter((h) => effectiveState(h, date) === "accepted");
  if (matches.length === 0) return null;
  matches.sort((a, b) => {
    const at = Date.parse(a.createdAt) - Date.parse(b.createdAt);
    if (at !== 0) return at;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return matches[0];
}

/** Open (pending or accepted, not past its period) handoff for one chore and period. */
export function openHandoff(choreId, periodIdx, handoffs, date) {
  const matches = handoffs
    .filter((h) => !h.deletedAt)
    .filter((h) => h.choreId === choreId && h.periodIndex === periodIdx)
    .filter((h) => OPEN.has(effectiveState(h, date)));
  if (matches.length === 0) return null;
  matches.sort((a, b) => {
    const at = Date.parse(a.createdAt) - Date.parse(b.createdAt);
    if (at !== 0) return at;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return matches[0];
}

export function shapeHandoff(row) {
  return {
    id: row.id,
    choreId: row.choreId,
    from: row.fromPerson,
    to: row.toPerson,
    periodIndex: row.periodIndex,
    cadence: row.cadence,
    state: row.state,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deleted: !!row.deletedAt,
    seq: row.seq,
  };
}

/**
 * Insert if new. Returns { row, created, error? }.
 * error: unknown_chore | bad_people | self | not_owner | open_exists | future_period | cadence_mismatch
 * Existing rows (any state) are returned untouched (idempotent replay).
 */
export function insertHandoff(db, { id, choreId, fromPerson, toPerson, periodIndex, cadence }, now) {
  const existing = getHandoff(db, id);
  if (existing) return { row: existing, created: false };

  if (!PEOPLE.includes(fromPerson) || !PEOPLE.includes(toPerson)) {
    return { row: null, created: false, error: "bad_people" };
  }
  if (fromPerson === toPerson) return { row: null, created: false, error: "self" };

  const chore = db.prepare("SELECT id, cadence, fixedAssignee FROM chores WHERE id = ? AND retired = 0").get(choreId);
  if (!chore) return { row: null, created: false, error: "unknown_chore" };

  // Client may omit cadence (server uses the chore's) but must not invent a different one.
  if (cadence !== undefined && cadence !== chore.cadence) {
    return { row: null, created: false, error: "cadence_mismatch" };
  }
  const cad = chore.cadence;
  const asOf = new Date(now);
  const current = calendarPeriodIndex(cad, asOf);
  // Optional client periodIndex: past OK (offline sync), future rejected (no next-week offers).
  if (periodIndex !== undefined && periodIndex > current) {
    return { row: null, created: false, error: "future_period" };
  }
  const period = periodIndex ?? current;

  // Owner check uses every live handoff so an accepted one makes `to` the owner (who still
  // cannot stack a second offer — the accepted row is itself open).
  const live = listHandoffs(db);
  const owner = assigneeFor(chore, period, live, asOf);
  if (owner !== fromPerson) return { row: null, created: false, error: "not_owner" };
  if (openHandoff(choreId, period, live, asOf)) return { row: null, created: false, error: "open_exists" };

  db.exec("BEGIN");
  try {
    const seq = nextSeq(db);
    db.prepare(
      `INSERT INTO handoffs (id, choreId, fromPerson, toPerson, periodIndex, cadence, state, createdAt, updatedAt, deletedAt, seq)
       VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, NULL, ?)`
    ).run(id, choreId, fromPerson, toPerson, period, cad, now, now, seq);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return { row: getHandoff(db, id), created: true };
}

/**
 * Accept or decline. Returns { status, row, changed? }:
 *   ok         answered (or already in the requested state — replay)
 *              changed=true only when state actually moved pending→accepted/declined
 *   expired    period ended (row marked expired if it was still open)
 *   forbidden  caller is not the offer's `to`
 *   not_pending already answered differently / not pending
 *   missing    unknown or deleted
 */
export function resolveHandoff(db, id, decision, person, now) {
  const row = getHandoff(db, id);
  if (!row || row.deletedAt) return { status: "missing", row: null };

  const asOf = new Date(now);
  if (hasExpired(row, asOf)) {
    // R-21: accepted is permanent — never flip to expired; report unchanged.
    if (row.state === "accepted") return { status: "ok", row, changed: false };
    if (row.state === "expired") return { status: "expired", row };
    if (row.state === "pending") return { status: "expired", row: update(db, id, { state: "expired" }, now) };
    return { status: "expired", row };
  }

  if (row.toPerson !== person) return { status: "forbidden", row };

  const want = decision === "accept" ? "accepted" : "declined";
  // Replay of an already-answered decision: ok but unchanged (do not re-push).
  if (row.state === want) return { status: "ok", row, changed: false };
  if (row.state !== "pending") return { status: "not_pending", row, changed: false };

  return { status: "ok", row: update(db, id, { state: want }, now), changed: true };
}

/**
 * Mark every *pending* handoff whose period has ended as expired (R-21).
 * Accepted stays accepted forever; declined stays declined.
 * Each expiry takes a new seq. Runs at the start of /sync. Returns the rows it expired.
 */
export function expireOpenHandoffs(db, now) {
  const nowIso = now.toISOString();
  const asOf = now;
  const open = db
    .prepare("SELECT * FROM handoffs WHERE deletedAt IS NULL AND state = 'pending' ORDER BY seq")
    .all();
  const out = [];
  for (const row of open) {
    if (!hasExpired(row, asOf)) continue;
    out.push(update(db, row.id, { state: "expired" }, nowIso));
  }
  return out;
}

/**
 * Fold handoffs into a /sync response: expire pending past-period rows first, add `handoffs`
 * (seq > cursor), and move out.cursor past the newest handoff seq.
 */
export function handoffSync(db, out, cursor, now) {
  expireOpenHandoffs(db, now);
  const rows = handoffsAfter(db, cursor);
  out.handoffs = rows.map(shapeHandoff);
  if (rows.length) out.cursor = Math.max(out.cursor, rows[rows.length - 1].seq);
  return out;
}

// ---- Routes -------------------------------------------------------------------------------------

const ID_RE = /^[A-Za-z0-9._~:@+-]{1,64}$/;
const ID_ERROR = "id required: 1-64 chars of [A-Za-z0-9._~:@+-], client-generated, stable across retries";
const ACTION_RE = /^\/handoffs\/([A-Za-z0-9._~:@+-]{1,64})\/(accept|decline)$/;

/**
 * The /handoffs routes. Returns true when the request was answered.
 *   POST /handoffs              { id, choreId, to } -> 201 pending / 200 replay; from from token
 *   POST /handoffs/:id/accept   to-person only -> 200
 *   POST /handoffs/:id/decline  to-person only -> 200
 */
export async function handoffRoutes({ req, res, path, db, device, send, readJson, now, push, log = console.error }) {
  const iso = () => now().toISOString();

  if (req.method === "POST" && path === "/handoffs") {
    const body = await readJson(req);
    if (typeof body.id !== "string" || !ID_RE.test(body.id)) {
      send(res, 400, { error: ID_ERROR });
      return true;
    }
    if (typeof body.choreId !== "string" || !body.choreId) {
      send(res, 400, { error: "choreId required" });
      return true;
    }
    if (typeof body.to !== "string" || !PEOPLE.includes(body.to)) {
      send(res, 400, { error: "to must be anne or wes" });
      return true;
    }
    // Optional client-supplied periodIndex/cadence; server fills from chore + now when omitted.
    const periodIndex = body.periodIndex !== undefined ? body.periodIndex : undefined;
    if (periodIndex !== undefined && (!Number.isInteger(periodIndex) || periodIndex < 0)) {
      send(res, 400, { error: "periodIndex must be a non-negative integer" });
      return true;
    }
    if (body.cadence !== undefined && !["daily", "weekly", "biweekly", "monthly"].includes(body.cadence)) {
      send(res, 400, { error: "cadence must be daily|weekly|biweekly|monthly" });
      return true;
    }

    expireOpenHandoffs(db, now());

    const { row, created, error } = insertHandoff(
      db,
      {
        id: body.id,
        choreId: body.choreId,
        fromPerson: device.person,
        toPerson: body.to,
        periodIndex,
        cadence: body.cadence,
      },
      iso()
    );
    if (error === "unknown_chore") send(res, 400, { error: "unknown or retired choreId" });
    else if (error === "self") send(res, 400, { error: "cannot hand off to yourself" });
    else if (error === "bad_people") send(res, 400, { error: "from/to must be anne or wes" });
    else if (error === "future_period") send(res, 400, { error: "periodIndex cannot be in the future" });
    else if (error === "cadence_mismatch") send(res, 400, { error: "cadence must match the chore" });
    else if (error === "not_owner") send(res, 403, { error: "only the current owner may offer this chore" });
    else if (error === "open_exists") send(res, 409, { error: "an open handoff already exists for this chore and period" });
    else {
      send(res, created ? 201 : 200, shapeHandoff(row));
      // Offer push only on real create (201), not idempotent replay (200).
      if (created && push) {
        push.notifyHandoff(row, "offer").catch((err) => log(iso(), "push handoff offer", err));
      }
    }
    return true;
  }

  const action = ACTION_RE.exec(path);
  if (req.method === "POST" && action) {
    const [, id, verb] = action;
    expireOpenHandoffs(db, now());
    const { status, row, changed } = resolveHandoff(db, id, verb, device.person, iso());
    if (status === "missing") send(res, 404, { error: "not found" });
    else if (status === "forbidden") send(res, 403, { error: "only the person offered the handoff may answer" });
    else if (status === "expired") send(res, 409, { error: "handoff period has ended", handoff: shapeHandoff(row) });
    else if (status === "not_pending") send(res, 409, { error: "handoff is not pending", handoff: shapeHandoff(row) });
    else {
      send(res, 200, shapeHandoff(row));
      // Accept/decline push only when state newly changed (not replay).
      if (changed && push) {
        const kind = row.state === "accepted" ? "accepted" : "declined";
        push.notifyHandoff(row, kind).catch((err) => log(iso(), `push handoff ${kind}`, err));
      }
    }
    return true;
  }

  return false;
}
