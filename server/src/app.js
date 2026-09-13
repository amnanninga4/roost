// HTTP surface. Plain node:http, JSON in/out.
//
//   GET    /health                        no auth
//   GET    /chores                        chores + version
//   GET    /completions?since=<iso>       changed since (exclusive), includes deleted rows
//   POST   /completions                   { id, choreId, completedAt } -> 201 new / 200 replay
//   DELETE /completions/:id               soft delete -> 200 (idempotent)
//   GET    /sync?since=<iso>&choresVersion=<n>
//          one call for the app: serverTime, choresVersion, chores (only when version differs), completions delta
import http from "node:http";
import {
  openDb,
  seedChores,
  getMeta,
  listChores,
  choreExists,
  insertCompletion,
  deleteCompletion,
  completionsSince,
  touchDevice,
} from "./db.js";
import { createTokenStore, bearerFrom } from "./auth.js";

const MAX_BODY = 64 * 1024;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?Z$/;

export function createApp({ dbPath, choresPath, tokensPath, now = () => new Date() }) {
  const db = openDb(dbPath);
  const seeded = seedChores(db, choresPath);
  const tokens = createTokenStore(tokensPath);

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
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
        } catch {
          reject(Object.assign(new Error("invalid JSON"), { status: 400 }));
        }
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
    };
  }

  function validSince(v) {
    if (v == null || v === "") return null;
    if (!ISO_RE.test(v)) throw Object.assign(new Error("since must be ISO-8601 UTC (…Z)"), { status: 400 });
    return v;
  }

  async function handle(req, res) {
    const url = new URL(req.url, "http://localhost");
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (req.method === "GET" && path === "/health") {
      return send(res, 200, {
        ok: true,
        serverTime: iso(),
        choresVersion: Number(getMeta(db, "choresVersion")),
        choresSeeded: seeded,
      });
    }

    const device = tokens.lookup(bearerFrom(req));
    if (!device) return send(res, 401, { error: "unauthorized" });
    touchDevice(db, device, iso());

    if (req.method === "GET" && path === "/chores") {
      return send(res, 200, {
        version: Number(getMeta(db, "choresVersion")),
        source: getMeta(db, "choresSource"),
        locked: getMeta(db, "choresLocked"),
        chores: listChores(db),
      });
    }

    if (req.method === "GET" && path === "/completions") {
      const since = validSince(url.searchParams.get("since"));
      return send(res, 200, {
        serverTime: iso(),
        completions: completionsSince(db, since).map(shapeCompletion),
      });
    }

    if (req.method === "POST" && path === "/completions") {
      const body = await readJson(req);
      const { id, choreId, completedAt } = body;
      if (typeof id !== "string" || id.length < 1 || id.length > 64) {
        return send(res, 400, { error: "id required (1-64 chars, client-generated, stable across retries)" });
      }
      if (typeof choreId !== "string" || !choreExists(db, choreId)) {
        return send(res, 400, { error: "unknown choreId" });
      }
      if (typeof completedAt !== "string" || !ISO_RE.test(completedAt) || Number.isNaN(Date.parse(completedAt))) {
        return send(res, 400, { error: "completedAt must be ISO-8601 UTC (…Z)" });
      }
      const { row, created } = insertCompletion(db, { id, choreId, person: device.person, completedAt }, iso());
      return send(res, created ? 201 : 200, shapeCompletion(row));
    }

    const del = /^\/completions\/([A-Za-z0-9._~:@+-]{1,64})$/.exec(path);
    if (req.method === "DELETE" && del) {
      const row = deleteCompletion(db, del[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeCompletion(row));
    }

    if (req.method === "GET" && path === "/sync") {
      const since = validSince(url.searchParams.get("since"));
      const clientVersion = url.searchParams.get("choresVersion");
      const version = Number(getMeta(db, "choresVersion"));
      const out = {
        serverTime: iso(),
        person: device.person,
        choresVersion: version,
        completions: completionsSince(db, since).map(shapeCompletion),
      };
      if (clientVersion == null || Number(clientVersion) !== version) out.chores = listChores(db);
      return send(res, 200, out);
    }

    return send(res, 404, { error: "not found" });
  }

  const server = http.createServer((req, res) => {
    handle(req, res).catch((err) => {
      const status = err.status ?? 500;
      if (status === 500) console.error(iso(), "unhandled", err);
      if (!res.headersSent) send(res, status, { error: status === 500 ? "internal error" : err.message });
      else res.destroy();
    });
  });

  return { server, db, tokens, seeded };
}
