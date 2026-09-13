// HTTP surface. Plain node:http, JSON in/out.
//
//   GET    /health                        no auth
//   GET    /chores                        chores + version
//   GET    /completions?cursor=<n>        completions with seq > cursor, includes deleted rows
//   POST   /completions                   { id, choreId, completedAt } -> 201 new / 200 replay
//   DELETE /completions/:id               soft delete -> 200 (idempotent)
//   GET    /sync?cursor=<n>&choresVersion=<v>
//          one call for the app: cursor, choresVersion, chores (only when version differs), completions delta
import http from "node:http";
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
} from "./db.js";
import { createTokenStore, bearerFrom } from "./auth.js";

const MAX_BODY = 64 * 1024;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;
/** One contract for completion ids: POST validates against it, DELETE routes on it. */
const ID_RE = /^[A-Za-z0-9._~:@+-]{1,64}$/;
const DELETE_RE = /^\/completions\/([A-Za-z0-9._~:@+-]{1,64})$/;
const LAST_SEEN_INTERVAL_MS = 60_000;

export function createApp({ dbPath, choresPath, tokensPath, now = () => new Date(), log = console.error }) {
  const db = openDb(dbPath);
  const seeded = seedChores(db, choresPath);
  const tokens = createTokenStore(tokensPath, { log });
  const lastTouched = new Map(); // tokenHash -> ms; throttles devices-table writes on read-only polls

  const iso = () => now().toISOString();

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
        tokensFileError,
      });
    }

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
      return send(res, created ? 201 : 200, shapeCompletion(row));
    }

    const del = DELETE_RE.exec(path);
    if (req.method === "DELETE" && del) {
      const row = deleteCompletion(db, del[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeCompletion(row));
    }

    if (req.method === "GET" && path === "/sync") {
      const cursor = parseCursor(url.searchParams.get("cursor"));
      const clientVersion = url.searchParams.get("choresVersion");
      const version = Number(getMeta(db, "choresVersion"));
      const rows = completionsAfter(db, cursor);
      const out = {
        serverTime: iso(),
        person: device.person,
        choresVersion: version,
        cursor: rows.length ? rows[rows.length - 1].seq : Math.min(cursor, currentSeq(db)),
        completions: rows.map(shapeCompletion),
      };
      if (clientVersion == null || Number(clientVersion) !== version) out.chores = listChores(db);
      return send(res, 200, out);
    }

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

  return { server, db, tokens, seeded };
}
