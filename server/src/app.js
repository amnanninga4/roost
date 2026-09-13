// HTTP surface. Plain node:http, JSON in/out.
//
//   GET    /health                        no auth
//   GET    /status                        no auth — kitchen status board (HTML)
//   GET    /chores                        chores + version
//   GET    /me                            { person, label, source, createdAt, lastSeen }
//   GET    /completions?cursor=<n>        completions with seq > cursor, includes deleted rows
//   POST   /completions                   { id, choreId, completedAt } -> 201 new / 200 replay
//   DELETE /completions/:id               soft delete -> 200 (idempotent)
//   POST   /shopping                      { id, title } -> 201 new / 200 replay; addedBy from token
//   PATCH  /shopping/:id                  { title?, bought? }; bought=true stamps boughtBy/boughtAt, false clears
//   DELETE /shopping/:id                  soft delete -> 200 (idempotent)
//   POST   /meals                         { id, title, tag?, lastMadeAt?, nextUp? }
//   PATCH  /meals/:id                     { title?, tag?, lastMadeAt?, nextUp? }; nextUp=true clears every other meal
//   DELETE /meals/:id                     soft delete
//   POST   /projects                      { id, title, subtasks?: [{ id, title }] } created in order
//   PATCH  /projects/:id                  { title? }
//   DELETE /projects/:id                  soft delete, cascades to its subtasks
//   POST   /projects/:id/subtasks         { id, title, sortOrder? }
//   PATCH  /subtasks/:id                  { title?, done?, sortOrder? }; done=true stamps doneBy/doneAt, false clears
//   DELETE /subtasks/:id                  soft delete
//   /bonus, /bonus/:id/{claim,complete}   first-to-claim bonus tasks; routes and rules live in bonus.js
//   POST   /handoffs                     { id, choreId, to } -> 201 pending / 200 replay; handoffs.js
//   POST   /handoffs/:id/{accept,decline} answer an offer; to-person only
//   POST   /pair                          no auth — { code, deviceName } -> { token, person }; pairing.js
//   DELETE /pair/self                     unpair the calling device (paired tokens only); pairing.js
//   POST|DELETE /push/token               APNs device token register/unregister; sender in push.js
//   GET    /sync?cursor=<n>&choresVersion=<v>
//          one call for the app: cursor, choresVersion, chores (only when version differs), and the
//          completions / shopping / meals / projects / subtasks / bonus / handoffs deltas (every row with seq > cursor)
import http from "node:http";
import { readFileSync } from "node:fs";
import {
  openDb,
  seedChores,
  getMeta,
  listChores,
  choreExists,
  insertCompletion,
  deleteCompletion,
  completionsAfter,
  currentSeq,
  touchDevice,
  insertShoppingItem,
  patchShoppingItem,
  deleteShoppingItem,
  insertMeal,
  patchMeal,
  deleteMeal,
  insertProject,
  patchProject,
  deleteProject,
  projectExists,
  getSubtask,
  subtasksOf,
  insertSubtask,
  patchSubtask,
  deleteSubtask,
  listsAfter,
} from "./db.js";
import { createTokenStore, bearerFrom, hashToken } from "./auth.js";
import { statusHandler } from "./status.js";
import { bonusRoutes, bonusSync } from "./bonus.js";
import { createPairing, pendingCodes } from "./pairing.js";
import { createPush, pushRoutes } from "./push.js";
import { handoffRoutes, handoffSync } from "./handoffs.js";

const MAX_BODY = 64 * 1024;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
/** One contract for every client-generated id: POST validates against it, the :id routes below match on it. */
const ID_RE = /^[A-Za-z0-9._~:@+-]{1,64}$/;
const ID_PART = "([A-Za-z0-9._~:@+-]{1,64})";
const DELETE_RE = new RegExp(`^/completions/${ID_PART}$`);
const SHOPPING_RE = new RegExp(`^/shopping/${ID_PART}$`);
const MEAL_RE = new RegExp(`^/meals/${ID_PART}$`);
const PROJECT_RE = new RegExp(`^/projects/${ID_PART}$`);
const PROJECT_SUBTASKS_RE = new RegExp(`^/projects/${ID_PART}/subtasks$`);
const SUBTASK_RE = new RegExp(`^/subtasks/${ID_PART}$`);
const LAST_SEEN_INTERVAL_MS = 60_000;
const TITLE_MAX = 200;
const TAG_MAX = 40;
const SUBTASKS_MAX = 100;
const SORT_MAX = 1_000_000;

const ID_ERROR = "id required: 1-64 chars of [A-Za-z0-9._~:@+-], client-generated, stable across retries";
const validId = (v) => typeof v === "string" && ID_RE.test(v);
const validTitle = (v) => typeof v === "string" && v.trim().length > 0 && v.length <= TITLE_MAX;
const validTag = (v) => typeof v === "string" && v.length <= TAG_MAX;
const validIso = (v) => typeof v === "string" && ISO_RE.test(v) && !Number.isNaN(Date.parse(v));
const validSort = (v) => Number.isInteger(v) && v >= 0 && v <= SORT_MAX;
/** Key present in the body (null counts as present; undefined does not). */
const has = (body, key) => body[key] !== undefined;

class BadRequest extends Error {
  constructor(message) {
    super(message);
    this.status = 400;
  }
}


/** Deployed git SHA for /health. ROOST_REV env wins; else /opt/roost/.deployed-rev from install.sh. */
function readDeployedRev() {
  if (process.env.ROOST_REV != null && process.env.ROOST_REV !== "") {
    return String(process.env.ROOST_REV).trim();
  }
  try {
    return readFileSync("/opt/roost/.deployed-rev", "utf8").trim() || "unknown";
  } catch {
    return "unknown";
  }
}

export function createApp({ dbPath, choresPath, tokensPath, apnsPath, pushSender, now = () => new Date(), log = console.error, sweepIntervalMs } = {}) {
  const db = openDb(dbPath);
  const seeded = seedChores(db, choresPath);
  const tokens = createTokenStore(tokensPath, { db, log });
  const push = createPush({ db, apnsPath, sender: pushSender, now, log, sweepIntervalMs });
  const lastTouched = new Map(); // tokenHash -> ms; throttles devices-table writes on read-only polls

  const iso = () => now().toISOString();
  const pairing = createPairing({ db, tokens, hashToken, bearerFrom, send, readJson, now });

  function send(res, status, body) {
    const json = JSON.stringify(body);
    res.writeHead(status, {
      "content-type": "application/json; charset=utf-8",
      "content-length": Buffer.byteLength(json),
      "cache-control": "no-store",
    });
    res.end(json);
  }

  function readJson(req) {
    return new Promise((resolve, reject) => {
      let size = 0;
      const chunks = [];
      req.on("data", (c) => {
        size += c.length;
        if (size > MAX_BODY) {
          reject(Object.assign(new Error("body too large"), { status: 413 }));
          req.destroy();
          return;
        }
        chunks.push(c);
      });
      req.on("end", () => {
        if (chunks.length === 0) return resolve({});
        let parsed;
        try {
          parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        } catch {
          return reject(Object.assign(new Error("invalid JSON"), { status: 400 }));
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
          return reject(Object.assign(new Error("body must be a JSON object"), { status: 400 }));
        }
        resolve(parsed);
      });
      req.on("error", reject);
    });
  }

  function shapeCompletion(row) {
    return {
      id: row.id,
      choreId: row.choreId,
      person: row.person,
      completedAt: row.completedAt,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      deleted: !!row.deletedAt,
      seq: row.seq,
    };
  }

  const stamp = (row) => ({ createdAt: row.createdAt, updatedAt: row.updatedAt, deleted: !!row.deletedAt, seq: row.seq });

  function shapeShopping(row) {
    return { id: row.id, title: row.title, addedBy: row.addedBy, bought: !!row.bought, boughtBy: row.boughtBy, boughtAt: row.boughtAt, ...stamp(row) };
  }

  function shapeMeal(row) {
    return { id: row.id, title: row.title, tag: row.tag, lastMadeAt: row.lastMadeAt, nextUp: !!row.nextUp, ...stamp(row) };
  }

  function shapeProject(row) {
    return { id: row.id, title: row.title, ...stamp(row) };
  }

  /** Project plus its subtasks, so a cascade delete or a POST with subtasks shows every row that took a seq. */
  function shapeProjectWithSubtasks(row) {
    return { ...shapeProject(row), subtasks: subtasksOf(db, row.id).map(shapeSubtask) };
  }

  function shapeSubtask(row) {
    return {
      id: row.id,
      projectId: row.projectId,
      title: row.title,
      sortOrder: row.sortOrder,
      done: !!row.done,
      doneBy: row.doneBy,
      doneAt: row.doneAt,
      ...stamp(row),
    };
  }

  /**
   * Pull the allowed optional fields out of a PATCH body. Rejects unknown-typed values and an empty
   * patch. `rules` is { field: (value) => ok }; a rule may accept null where the column is nullable.
   */
  function pickPatch(body, rules) {
    const out = {};
    for (const [key, ok] of Object.entries(rules)) {
      if (!has(body, key)) continue;
      if (!ok(body[key])) throw new BadRequest(`invalid ${key}`);
      out[key] = body[key];
    }
    if (Object.keys(out).length === 0) throw new BadRequest(`nothing to update; expected one of ${Object.keys(rules).join(", ")}`);
    return out;
  }

  const isBool = (v) => typeof v === "boolean";

  function parseCursor(v) {
    if (v == null || v === "") return 0;
    if (!/^\d{1,15}$/.test(v)) throw Object.assign(new Error("cursor must be a non-negative integer"), { status: 400 });
    return Number(v);
  }

  function noteDevice(device) {
    const t = now().getTime();
    const prev = lastTouched.get(device.tokenHash) ?? -Infinity;
    if (t - prev >= LAST_SEEN_INTERVAL_MS) {
      touchDevice(db, device, new Date(t).toISOString());
      lastTouched.set(device.tokenHash, t);
    }
  }

  async function handle(req, res) {
    const url = new URL(req.url, "http://localhost");
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (req.method === "GET" && path === "/health") {
      const tokensFileError = tokens.error(); // reloads the file first, so `devices` below is current
      return send(res, 200, {
        ok: true,
        serverTime: iso(),
        choresVersion: Number(getMeta(db, "choresVersion")),
        choresSeeded: seeded,
        cursor: currentSeq(db),
        devices: tokens.size(),
        pendingCodes: pendingCodes(db, iso()),
        tokensFileError,
        push: push.health(),
        rev: readDeployedRev(),
      });
    }

    if (req.method === "GET" && path === "/status") return statusHandler(db, req, res, { now });

    if (await pairing.routes(req, res, path)) return; // POST /pair has no bearer yet; /pair/self checks its own

    const device = tokens.lookup(bearerFrom(req));
    if (!device) return send(res, 401, { error: "unauthorized" });
    noteDevice(device);

    if (req.method === "GET" && path === "/chores") {
      return send(res, 200, {
        version: Number(getMeta(db, "choresVersion")),
        source: getMeta(db, "choresSource"),
        locked: getMeta(db, "choresLocked"),
        chores: listChores(db),
      });
    }

    if (req.method === "GET" && path === "/me") {
      const lastSeen =
        db.prepare("SELECT lastSeen FROM devices WHERE tokenHash = ?").get(device.tokenHash)?.lastSeen ?? null;
      let createdAt = null;
      if (device.source === "paired") {
        createdAt =
          db.prepare("SELECT createdAt FROM paired_tokens WHERE tokenHash = ?").get(device.tokenHash)?.createdAt ??
          null;
      }
      return send(res, 200, {
        person: device.person,
        label: device.label,
        source: device.source,
        createdAt,
        lastSeen,
      });
    }

    if (req.method === "GET" && path === "/completions") {
      const cursor = parseCursor(url.searchParams.get("cursor"));
      const rows = completionsAfter(db, cursor);
      return send(res, 200, {
        serverTime: iso(),
        cursor: rows.length ? rows[rows.length - 1].seq : cursor,
        completions: rows.map(shapeCompletion),
      });
    }

    if (req.method === "POST" && path === "/completions") {
      const body = await readJson(req);
      const { id, choreId, completedAt } = body;
      if (typeof id !== "string" || !ID_RE.test(id)) {
        return send(res, 400, { error: "id required: 1-64 chars of [A-Za-z0-9._~:@+-], client-generated, stable across retries" });
      }
      if (typeof choreId !== "string" || !choreExists(db, choreId)) {
        return send(res, 400, { error: "unknown or retired choreId" });
      }
      if (typeof completedAt !== "string" || !ISO_RE.test(completedAt) || Number.isNaN(Date.parse(completedAt))) {
        return send(res, 400, { error: "completedAt must be ISO-8601 UTC (…Z)" });
      }
      const { row, created } = insertCompletion(db, { id, choreId, person: device.person, completedAt }, iso());
      if (created) push.notifyCompletion(row).catch((err) => log(iso(), "push completion", err));
      return send(res, created ? 201 : 200, shapeCompletion(row));
    }

    const del = DELETE_RE.exec(path);
    if (req.method === "DELETE" && del) {
      const row = deleteCompletion(db, del[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeCompletion(row));
    }

    // --- shopping ---

    if (req.method === "POST" && path === "/shopping") {
      const body = await readJson(req);
      if (!validId(body.id)) return send(res, 400, { error: ID_ERROR });
      if (!validTitle(body.title)) return send(res, 400, { error: `title required: 1-${TITLE_MAX} chars` });
      const { row, created } = insertShoppingItem(db, { id: body.id, title: body.title, addedBy: device.person }, iso());
      return send(res, created ? 201 : 200, shapeShopping(row));
    }

    const shopping = SHOPPING_RE.exec(path);
    if (req.method === "PATCH" && shopping) {
      const body = await readJson(req);
      const patch = pickPatch(body, { title: validTitle, bought: isBool });
      const row = patchShoppingItem(db, shopping[1], patch, device.person, iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeShopping(row));
    }
    if (req.method === "DELETE" && shopping) {
      const row = deleteShoppingItem(db, shopping[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeShopping(row));
    }

    // --- meals ---

    if (req.method === "POST" && path === "/meals") {
      const body = await readJson(req);
      if (!validId(body.id)) return send(res, 400, { error: ID_ERROR });
      if (!validTitle(body.title)) return send(res, 400, { error: `title required: 1-${TITLE_MAX} chars` });
      if (has(body, "tag") && !validTag(body.tag)) return send(res, 400, { error: `tag must be a string of 0-${TAG_MAX} chars` });
      if (has(body, "lastMadeAt") && body.lastMadeAt !== null && !validIso(body.lastMadeAt)) {
        return send(res, 400, { error: "lastMadeAt must be null or ISO-8601 UTC (…Z)" });
      }
      if (has(body, "nextUp") && !isBool(body.nextUp)) return send(res, 400, { error: "nextUp must be a boolean" });
      const { row, created } = insertMeal(
        db,
        { id: body.id, title: body.title, tag: body.tag ?? "", lastMadeAt: body.lastMadeAt ?? null, nextUp: body.nextUp ?? false },
        iso()
      );
      return send(res, created ? 201 : 200, shapeMeal(row));
    }

    const meal = MEAL_RE.exec(path);
    if (req.method === "PATCH" && meal) {
      const body = await readJson(req);
      const patch = pickPatch(body, {
        title: validTitle,
        tag: validTag,
        lastMadeAt: (v) => v === null || validIso(v),
        nextUp: isBool,
      });
      const row = patchMeal(db, meal[1], patch, iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeMeal(row));
    }
    if (req.method === "DELETE" && meal) {
      const row = deleteMeal(db, meal[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeMeal(row));
    }

    // --- projects + subtasks ---

    if (req.method === "POST" && path === "/projects") {
      const body = await readJson(req);
      if (!validId(body.id)) return send(res, 400, { error: ID_ERROR });
      if (!validTitle(body.title)) return send(res, 400, { error: `title required: 1-${TITLE_MAX} chars` });
      const subtasks = body.subtasks ?? [];
      if (!Array.isArray(subtasks) || subtasks.length > SUBTASKS_MAX) {
        return send(res, 400, { error: `subtasks must be an array of at most ${SUBTASKS_MAX} { id, title }` });
      }
      const seen = new Set();
      for (const s of subtasks) {
        if (!s || typeof s !== "object" || Array.isArray(s)) return send(res, 400, { error: "each subtask must be an object" });
        if (!validId(s.id) || seen.has(s.id)) return send(res, 400, { error: `subtask ${ID_ERROR}` });
        if (!validTitle(s.title)) return send(res, 400, { error: `subtask title required: 1-${TITLE_MAX} chars` });
        seen.add(s.id);
      }
      if (!projectExists(db, body.id) && subtasks.some((s) => getSubtask(db, s.id))) {
        return send(res, 400, { error: "a subtask id already exists" });
      }
      const { row, created } = insertProject(
        db,
        { id: body.id, title: body.title, subtasks: subtasks.map((s) => ({ id: s.id, title: s.title })) },
        iso()
      );
      return send(res, created ? 201 : 200, shapeProjectWithSubtasks(row));
    }

    const project = PROJECT_RE.exec(path);
    if (req.method === "PATCH" && project) {
      const body = await readJson(req);
      const patch = pickPatch(body, { title: validTitle });
      const row = patchProject(db, project[1], patch, iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeProjectWithSubtasks(row));
    }
    if (req.method === "DELETE" && project) {
      const row = deleteProject(db, project[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeProjectWithSubtasks(row));
    }

    const projectSubtasks = PROJECT_SUBTASKS_RE.exec(path);
    if (req.method === "POST" && projectSubtasks) {
      const body = await readJson(req);
      if (!projectExists(db, projectSubtasks[1])) return send(res, 400, { error: "unknown or deleted projectId" });
      if (!validId(body.id)) return send(res, 400, { error: ID_ERROR });
      if (!validTitle(body.title)) return send(res, 400, { error: `title required: 1-${TITLE_MAX} chars` });
      if (has(body, "sortOrder") && !validSort(body.sortOrder)) return send(res, 400, { error: "sortOrder must be a non-negative integer" });
      const { row, created } = insertSubtask(
        db,
        { id: body.id, projectId: projectSubtasks[1], title: body.title, sortOrder: body.sortOrder },
        iso()
      );
      return send(res, created ? 201 : 200, shapeSubtask(row));
    }

    const subtask = SUBTASK_RE.exec(path);
    if (req.method === "PATCH" && subtask) {
      const body = await readJson(req);
      const patch = pickPatch(body, { title: validTitle, done: isBool, sortOrder: validSort });
      const row = patchSubtask(db, subtask[1], patch, device.person, iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeSubtask(row));
    }
    if (req.method === "DELETE" && subtask) {
      const row = deleteSubtask(db, subtask[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeSubtask(row));
    }

    if (req.method === "GET" && path === "/sync") {
      const cursor = parseCursor(url.searchParams.get("cursor"));
      const clientVersion = url.searchParams.get("choresVersion");
      const version = Number(getMeta(db, "choresVersion"));
      const rows = completionsAfter(db, cursor);
      const lists = listsAfter(db, cursor);
      // Cursor = the highest seq handed out in this response, across every table; unchanged when nothing changed.
      const maxSeq = [rows, lists.shopping, lists.meals, lists.projects, lists.subtasks]
        .filter((r) => r.length)
        .reduce((m, r) => Math.max(m, r[r.length - 1].seq), 0);
      const out = {
        serverTime: iso(),
        person: device.person,
        choresVersion: version,
        cursor: maxSeq || Math.min(cursor, currentSeq(db)),
        completions: rows.map(shapeCompletion),
        shopping: lists.shopping.map(shapeShopping),
        meals: lists.meals.map(shapeMeal),
        projects: lists.projects.map(shapeProject),
        subtasks: lists.subtasks.map(shapeSubtask),
      };
      if (clientVersion == null || Number(clientVersion) !== version) out.chores = listChores(db);
      bonusSync(db, out, cursor, now()); // auto-assigns expired bonus tasks, adds out.bonus, folds its seqs into out.cursor
      handoffSync(db, out, cursor, now()); // expires past-period open handoffs, adds out.handoffs, folds seqs into out.cursor
      return send(res, 200, out);
    }

    if (await pushRoutes({ req, res, path, db, device, send, readJson, iso })) return;
    if (await bonusRoutes({ req, res, path, url, db, device, send, readJson, parseCursor, now })) return;
    if (await handoffRoutes({ req, res, path, db, device, send, readJson, now, push, log })) return;

    return send(res, 404, { error: "not found" });
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      const status = err.status ?? 500;
      if (status === 500) log(iso(), "unhandled", err);
      if (!res.headersSent) send(res, status, { error: status === 500 ? "internal error" : err.message });
      else res.destroy();
    });
  });

  return { server, db, tokens, seeded, push };
}
