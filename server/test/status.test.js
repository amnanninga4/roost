import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createApp } from "../src/app.js";

const here = dirname(fileURLToPath(import.meta.url));
const CHORES = resolve(here, "../../data/chores.json");
const ANNE = "anne-token-0123456789abcdef";

let dir, base, app, tokensPath;
let clock = new Date("2026-09-14T17:00:00.000Z"); // afternoon Chicago on Sep 14

before(async () => {
  dir = mkdtempSync(join(tmpdir(), "roost-status-"));
  tokensPath = join(dir, "tokens.json");
  writeFileSync(
    tokensPath,
    JSON.stringify({ [ANNE]: { person: "anne", device: "Anne test" } })
  );
  app = createApp({
    dbPath: join(dir, "roost.db"),
    choresPath: CHORES,
    tokensPath,
    now: () => clock,
  });
  await new Promise((r) => app.server.listen(0, "127.0.0.1", r));
  base = `http://127.0.0.1:${app.server.address().port}`;
});

after(async () => {
  await new Promise((r) => app.server.close(r));
  app.db.close();
  rmSync(dir, { recursive: true, force: true });
});

test("GET /status returns 200 text/html with a completion title after POST", async () => {
  const post = await fetch(base + "/completions", {
    method: "POST",
    headers: {
      authorization: `Bearer ${ANNE}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      id: "status-c1",
      choreId: "scoop-litter",
      completedAt: "2026-09-14T16:30:00.000Z",
    }),
  });
  assert.equal(post.status, 201);
  const created = await post.json();
  assert.equal(created.choreId, "scoop-litter");

  const res = await fetch(base + "/status");
  assert.equal(res.status, 200);
  const ct = res.headers.get("content-type") || "";
  assert.match(ct, /text\/html/);
  const html = await res.text();
  assert.match(html, /Scoop litter/);
  assert.match(html, /http-equiv="refresh"/i);
});
