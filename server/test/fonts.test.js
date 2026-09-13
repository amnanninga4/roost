import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { loadFontFiles } from "../src/status.js";

const here = dirname(fileURLToPath(import.meta.url));
const statusUrl = pathToFileURL(resolve(here, "../src/status.js")).href;

test("fonts: the bundled directory lists the faces the board's CSS asks for", () => {
  const files = loadFontFiles();
  for (const name of ["Fraunces-Variable.ttf", "NunitoSans-Variable.ttf", "IBMPlexMono-Regular.ttf", "IBMPlexMono-Medium.ttf"]) {
    assert.ok(files.has(name), `${name} missing`);
  }
});

test("fonts: a missing directory serves no fonts and never stops the server", () => {
  const logged = [];
  assert.deepEqual([...loadFontFiles("/nonexistent/roost-fonts", { log: (m) => logged.push(m) })], []);
  assert.equal(logged.length, 1);
  assert.match(logged[0], /serves no fonts/);

  // The real failure mode: the module is imported at startup on a host without the package directory.
  const script = `import(${JSON.stringify(statusUrl)}).then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });`;
  const run = spawnSync(process.execPath, ["--no-warnings=ExperimentalWarning", "--input-type=module", "-e", script], {
    env: { ...process.env, ROOST_FONTS_DIR: "/nonexistent/roost-fonts" },
    encoding: "utf8",
  });
  assert.equal(run.status, 0, run.stderr);
  assert.match(run.stderr, /serves no fonts/);
});
