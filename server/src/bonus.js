// Bonus "first to claim" tasks. A bonus task is a one-off with a point value and a claim deadline:
// the first person to claim it gets the points. Left unclaimed past claimBy, it is auto-assigned so it
// cannot disappear, and shows in that person's list.
//
// Everything bonus lives here so it sits cleanly next to the other list tables: db.js only runs
// BONUS_SCHEMA, app.js only dispatches to bonusRoutes and folds bonusSync into /sync.
//
// Rows share the meta.seq cursor with every other table. Every insert, claim, auto-assign, complete and
// soft delete takes the next value, so the one /sync cursor covers bonus tasks too.
//
// The auto-assign tally needs the current week in America/Chicago (Monday 00:00 to the next Monday
// 00:00), the same bounds as RoostCore.HouseholdCalendar.weekBounds. That is the one Chicago-time rule
// the server owns; due-today, streaks and escalation stay in the app.
import { PEOPLE } from "./db.js";

// No people CHECK in this schema: db.js imports this file for BONUS_SCHEMA, so PEOPLE is not initialised
// while this module evaluates (module cycle). Every writer takes the person from an authenticated token
// or from PEOPLE, and the functions below only read PEOPLE at call time.
export const BONUS_SCHEMA = `
CREATE TABLE IF NOT EXISTS bonus_tasks (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  points      INTEGER NOT NULL CHECK (points BETWEEN 1 AND 10),
  claimBy     TEXT NOT NULL,
  claimedBy   TEXT,
  claimedAt   TEXT,
  assignedTo  TEXT,
  completedAt TEXT,
  createdBy   TEXT NOT NULL,
  createdAt   TEXT NOT NULL,
  updatedAt   TEXT NOT NULL,
  deletedAt   TEXT,
  seq         INTEGER NOT NULL UNIQUE
);
CREATE INDEX IF NOT EXISTS bonus_tasks_seq ON bonus_tasks(seq);
`;

/** Same counter as db.js (meta.seq); kept here so this file adds nothing to db.js's exports. */
function nextSeq(db) {
  db.prepare("UPDATE meta SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT) WHERE key = 'seq'").run();
  return Number(db.prepare("SELECT value FROM meta WHERE key = 'seq'").get().value);
}

// ---- Chicago week -------------------------------------------------------------------------------

const chicagoFmt = new Intl.DateTimeFormat("en-US", {
  timeZone: "America/Chicago",
  hourCycle: "h23",
  weekday: "short",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
});
const DAY_MS = 86_400_000;
const DAYS_SINCE_MONDAY = { Mon: 0, Tue: 1, Wed: 2, Thu: 3, Fri: 4, Sat: 5, Sun: 6 };

/** Chicago wall-clock reading of `date`: calendar day, weekday, and the wall time as a Date.UTC number. */
function chicagoParts(date) {
  const p = {};
  for (const { type, value } of chicagoFmt.formatToParts(date)) p[type] = value;
  return {
    y: +p.year,
    m: +p.month,
    d: +p.day,
    weekday: p.weekday,
    wall: Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour % 24, +p.minute, +p.second),
  };
}

/** UTC ms of 00:00 America/Chicago on the calendar day given as a Date.UTC(y, m, d) number. */
function chicagoMidnight(dayUtc) {
  // Read the day as if it were UTC, then correct by the zone offset in force at that instant. Two passes
  // settle it on either side of a DST change (Chicago switches at 02:00, never at midnight).
  let utc = dayUtc;
  for (let i = 0; i < 2; i++) utc += dayUtc - chicagoParts(new Date(utc)).wall;
  return utc;
}

/**
 * Monday 00:00 America/Chicago of the week containing `now` (a Date), and the next Monday 00:00
 * (exclusive), both as ISO-8601 UTC strings. Matches RoostCore.HouseholdCalendar.weekBounds.
 */
export function chicagoWeek(now) {
  const p = chicagoParts(now);
  const monday = Date.UTC(p.y, p.m - 1, p.d - DAYS_SINCE_MONDAY[p.weekday]);
  return {
    start: new Date(chicagoMidnight(monday)).toISOString(),
    end: new Date(chicagoMidnight(monday + 7 * DAY_MS)).toISOString(),
  };
}

// ---- Queries ------------------------------------------------------------------------------------
// `now` is an ISO UTC string here, as in db.js; the week functions take a Date.

export function getBonus(db, id) {
  return db.prepare("SELECT * FROM bonus_tasks WHERE id = ?").get(id) ?? null;
}

/** Bonus rows with seq > cursor, including soft-deleted ones. cursor 0 = everything. */
export function bonusAfter(db, cursor) {
  return db.prepare("SELECT * FROM bonus_tasks WHERE seq > ? ORDER BY seq").all(cursor);
}

/** Insert if new. Returns { row, created }. Existing rows are returned untouched (idempotent replay). */
export function insertBonus(db, { id, title, points, claimBy, createdBy }, now) {
  const existing = getBonus(db, id);
  if (existing) return { row: existing, created: false };
  db.exec("BEGIN");
  try {
    const seq = nextSeq(db);
    db.prepare(
      "INSERT INTO bonus_tasks (id, title, points, claimBy, createdBy, createdAt, updatedAt, seq) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    ).run(id, title, points, claimBy, createdBy, now, now, seq);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return { row: getBonus(db, id), created: true };
}

/** Apply `fields` to a row with a new seq and updatedAt, in one transaction. Column names are code, never input. */
function update(db, id, fields, now) {
  db.exec("BEGIN");
  try {
    const seq = nextSeq(db);
    const names = Object.keys(fields);
    const sets = names.map((n) => `${n} = ?`).concat("updatedAt = ?", "seq = ?").join(", ");
    db.prepare(`UPDATE bonus_tasks SET ${sets} WHERE id = ?`).run(...names.map((n) => fields[n]), now, seq, id);
    db.exec("COMMIT");
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
  return getBonus(db, id);
}

/**
 * First claim wins. Returns { status, row }:
 *   claimed  the caller holds it (a repeat claim by the same person is a replay, row unchanged)
 *   taken    the other person claimed it first
 *   expired  claimBy has passed, or it was already auto-assigned
 *   missing  unknown or deleted
 */
export function claimBonus(db, id, person, now) {
  const row = getBonus(db, id);
  if (!row || row.deletedAt) return { status: "missing", row: null };
  if (row.claimedBy === person) return { status: "claimed", row };
  if (row.claimedBy) return { status: "taken", row };
  if (row.assignedTo || row.claimBy < now) return { status: "expired", row };
  return { status: "claimed", row: update(db, id, { claimedBy: person, claimedAt: now }, now) };
}

/**
 * Only the claimer or the auto-assignee may complete. Returns { status, row }:
 *   completed  done now, or already done by the caller (replay, row unchanged)
 *   forbidden  the caller is neither claimer nor assignee (an unclaimed task has neither)
 *   missing    unknown or deleted
 */
export function completeBonus(db, id, person, now) {
  const row = getBonus(db, id);
  if (!row || row.deletedAt) return { status: "missing", row: null };
  if ((row.claimedBy ?? row.assignedTo) !== person) return { status: "forbidden", row };
  if (row.completedAt) return { status: "completed", row };
  return { status: "completed", row: update(db, id, { completedAt: now }, now) };
}

/** Soft delete so the deletion propagates through /sync deltas. Idempotent. Null when unknown. */
export function deleteBonus(db, id, now) {
  const row = getBonus(db, id);
  if (!row) return null;
  if (row.deletedAt) return row;
  return update(db, id, { deletedAt: now }, now);
}

/** Points each person has earned (completed, not deleted) in the Chicago week containing `now` (a Date). */
export function weekPoints(db, now) {
  const week = chicagoWeek(now);
  const points = Object.fromEntries(PEOPLE.map((p) => [p, 0]));
  const rows = db
    .prepare(
      `SELECT COALESCE(claimedBy, assignedTo) AS person, SUM(points) AS total FROM bonus_tasks
       WHERE deletedAt IS NULL AND completedAt IS NOT NULL AND completedAt >= ? AND completedAt < ?
       GROUP BY person`
    )
    .all(week.start, week.end);
  for (const r of rows) if (r.person in points) points[r.person] = r.total;
  return points;
}

/** Fewer points this week wins; a tie goes to the person who did not create the task. */
function pickAssignee(points, createdBy) {
  return [...PEOPLE].sort((a, b) => points[a] - points[b] || (a === createdBy) - (b === createdBy))[0];
}

/**
 * Assign every unclaimed, unassigned, undeleted task whose claimBy has passed (`now` is a Date). Each
 * assignment takes a new seq so it reaches both phones on their next sync. Runs at the start of every
 * /sync, so it needs no timer. Returns the rows it assigned, oldest deadline first.
 */
export function autoAssignExpired(db, now) {
  const nowIso = now.toISOString();
  const expired = db
    .prepare(
      "SELECT id, createdBy FROM bonus_tasks WHERE deletedAt IS NULL AND claimedBy IS NULL AND assignedTo IS NULL AND claimBy < ? ORDER BY claimBy, seq"
    )
    .all(nowIso);
  if (expired.length === 0) return [];
  const points = weekPoints(db, now);
  return expired.map((t) => update(db, t.id, { assignedTo: pickAssignee(points, t.createdBy) }, nowIso));
}

export function shapeBonus(row) {
  return {
    id: row.id,
    title: row.title,
    points: row.points,
    claimBy: row.claimBy,
    claimedBy: row.claimedBy,
    claimedAt: row.claimedAt,
    assignedTo: row.assignedTo,
    completedAt: row.completedAt,
    createdBy: row.createdBy,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deleted: !!row.deletedAt,
    seq: row.seq,
  };
}

/**
 * Fold the bonus delta into a /sync response object: auto-assigns expired tasks first, adds `bonus`
 * (rows with seq > cursor, deleted flagged) and moves `out.cursor` past the newest bonus seq.
 */
export function bonusSync(db, out, cursor, now) {
  autoAssignExpired(db, now);
  const rows = bonusAfter(db, cursor);
  out.bonus = rows.map(shapeBonus);
  if (rows.length) out.cursor = Math.max(out.cursor, rows[rows.length - 1].seq);
  return out;
}

// ---- Routes -------------------------------------------------------------------------------------

/** Same id contract as every other client-generated id (app.js ID_RE). */
const ID_RE = /^[A-Za-z0-9._~:@+-]{1,64}$/;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
const ITEM_RE = /^\/bonus\/([A-Za-z0-9._~:@+-]{1,64})$/;
const ACTION_RE = /^\/bonus\/([A-Za-z0-9._~:@+-]{1,64})\/(claim|complete)$/;
const TITLE_MAX = 200;
const POINTS_MAX = 10;

/**
 * The /bonus routes. Returns true when the request was answered, false to fall through to the 404.
 *   GET    /bonus?cursor=<n>       rows with seq > cursor, deleted rows included (auto-assigns first)
 *   POST   /bonus                  { id, title, points, claimBy } -> 201 new / 200 replay; createdBy from token
 *   POST   /bonus/:id/claim        first claim wins -> 200 (repeat by the same person 200), 409 taken or expired
 *   POST   /bonus/:id/complete     claimer or assignee only -> 200 (repeat 200), 403 anyone else
 *   DELETE /bonus/:id              soft delete -> 200 (idempotent), 404 unknown
 */
export async function bonusRoutes({ req, res, path, url, db, device, send, readJson, parseCursor, now }) {
  const iso = () => now().toISOString();

  if (req.method === "GET" && path === "/bonus") {
    const cursor = parseCursor(url.searchParams.get("cursor"));
    autoAssignExpired(db, now());
    const rows = bonusAfter(db, cursor);
    send(res, 200, {
      serverTime: iso(),
      cursor: rows.length ? rows[rows.length - 1].seq : cursor,
      bonus: rows.map(shapeBonus),
    });
    return true;
  }

  if (req.method === "POST" && path === "/bonus") {
    const body = await readJson(req);
    const { id, points, claimBy } = body;
    const title = typeof body.title === "string" ? body.title.trim() : "";
    if (typeof id !== "string" || !ID_RE.test(id)) {
      send(res, 400, { error: "id required: 1-64 chars of [A-Za-z0-9._~:@+-], client-generated, stable across retries" });
    } else if (title.length < 1 || title.length > TITLE_MAX) {
      send(res, 400, { error: `title required: 1-${TITLE_MAX} chars` });
    } else if (!Number.isInteger(points) || points < 1 || points > POINTS_MAX) {
      send(res, 400, { error: `points must be an integer 1-${POINTS_MAX}` });
    } else if (typeof claimBy !== "string" || !ISO_RE.test(claimBy) || Number.isNaN(Date.parse(claimBy))) {
      send(res, 400, { error: "claimBy must be ISO-8601 UTC (…Z)" });
    } else {
      // claimBy is stored normalised to milliseconds so deadline comparisons are plain string compares.
      const task = { id, title, points, claimBy: new Date(claimBy).toISOString(), createdBy: device.person };
      const { row, created } = insertBonus(db, task, iso());
      send(res, created ? 201 : 200, shapeBonus(row));
    }
    return true;
  }

  const action = ACTION_RE.exec(path);
  if (req.method === "POST" && action) {
    const [, id, verb] = action;
    if (verb === "claim") {
      const { status, row } = claimBonus(db, id, device.person, iso());
      if (status === "missing") send(res, 404, { error: "not found" });
      else if (status === "taken") send(res, 409, { error: "already claimed", claimedBy: row.claimedBy });
      else if (status === "expired") send(res, 409, { error: "claim deadline passed" });
      else send(res, 200, shapeBonus(row));
    } else {
      const { status, row } = completeBonus(db, id, device.person, iso());
      if (status === "missing") send(res, 404, { error: "not found" });
      else if (status === "forbidden") send(res, 403, { error: "only the person who claimed or was assigned this task can complete it" });
      else send(res, 200, shapeBonus(row));
    }
    return true;
  }

  const item = ITEM_RE.exec(path);
  if (req.method === "DELETE" && item) {
    const row = deleteBonus(db, item[1], iso());
    if (!row) send(res, 404, { error: "not found" });
    else send(res, 200, shapeBonus(row));
    return true;
  }

  return false;
}
