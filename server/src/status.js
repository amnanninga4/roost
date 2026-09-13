// Read-only household status board for a kitchen screen.
// No auth (behind the tunnel). First names + chore titles only.
// Rendering only — streaks / tallies / overdue come from rules.js.
import { readdirSync, readFileSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { PEOPLE, listChores, getMeta } from "./db.js";
import { boardStats, DEFAULT_ACTIVE_FROM, parseActiveFrom, chicagoDateString } from "./rules.js";
import { listHandoffs, expireOpenHandoffs } from "./handoffs.js";
import { readVerifyStatus } from "./verifystatus.js";

const TZ = "America/Chicago";
const here = dirname(fileURLToPath(import.meta.url));
const FONTS_DIR =
  process.env.ROOST_FONTS_DIR || resolve(here, "../../Packages/RoostDesign/Sources/RoostDesign/Resources/Fonts");

/**
 * Basenames of bundled font files only — never path segments. A directory that is missing or unreadable
 * (a deploy that did not copy the package) means no fonts are served and the board falls back to system
 * faces; it must never stop the server from starting. install.sh copies the files to the same relative
 * path under /opt/roost, and ROOST_FONTS_DIR overrides it.
 */
export function loadFontFiles(dir = FONTS_DIR, { log = console.error } = {}) {
  try {
    return new Set(readdirSync(dir).filter((name) => name.endsWith(".ttf") && name === basename(name)));
  } catch (err) {
    log(`fonts dir ${dir} not readable (${err.code ?? err.message}); the status board serves no fonts`);
    return new Set();
  }
}
const FONT_FILES = loadFontFiles();

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function chicagoParts(date) {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  return Object.fromEntries(
    f.formatToParts(date).filter((p) => p.type !== "literal").map((p) => [p.type, p.value])
  );
}

/** Calendar YYYY-MM-DD in America/Chicago. */
export function chicagoDateKey(date) {
  const p = chicagoParts(date);
  return `${p.year}-${p.month}-${p.day}`;
}

function formatChicagoDateHeading(date) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: TZ,
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  }).format(date);
}

function formatChicagoTime(iso) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: TZ,
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(iso));
}

/** HH:MM wall clock in America/Chicago (24h). */
function formatChicagoUpdated(date) {
  const p = chicagoParts(date);
  return `${p.hour}:${p.minute}`;
}

function displayName(person) {
  if (!person) return "";
  return person.charAt(0).toUpperCase() + person.slice(1);
}

function stageLabel(stage) {
  switch (stage) {
    case "dueToday":
      return "due today";
    case "nudge":
      return "1 day late";
    case "pointed":
      return "3 days late";
    case "alert":
      return "5+ days late";
    default:
      return stage;
  }
}

/** Semantic class for escalation stage (warning @ 3 days / pointed, danger @ 5+ / alert). */
function stageClass(stage) {
  switch (stage) {
    case "dueToday":
      return "stage-due";
    case "nudge":
      return "stage-nudge";
    case "pointed":
      return "stage-pointed warning";
    case "alert":
      return "stage-alert danger";
    default:
      return `stage-${String(stage)}`;
  }
}

function loadCompletions(db) {
  return db
    .prepare(
      `SELECT c.id, c.person, c.completedAt, c.choreId, c.seq, ch.title AS title
       FROM completions c
       JOIN chores ch ON ch.id = c.choreId
       WHERE c.deletedAt IS NULL
       ORDER BY c.completedAt DESC, c.seq DESC`
    )
    .all();
}

function loadOpenBonus(db) {
  try {
    return db
      .prepare(
        `SELECT title, points, claimedBy, assignedTo
         FROM bonus_tasks
         WHERE deletedAt IS NULL AND completedAt IS NULL
         ORDER BY claimBy, seq`
      )
      .all();
  } catch {
    return [];
  }
}

function resolveActiveFrom(db, opts) {
  if (opts.activeFrom != null && opts.activeFrom !== "") return parseActiveFrom(opts.activeFrom);
  return parseActiveFrom(getMeta(db, "activeFrom"));
}

/** YYYY-MM-DD string for status.json / board consumers. */
function resolveActiveFromString(db, opts) {
  if (opts.activeFrom != null && opts.activeFrom !== "") {
    return chicagoDateString(parseActiveFrom(opts.activeFrom));
  }
  return getMeta(db, "activeFrom") ?? chicagoDateString(DEFAULT_ACTIVE_FROM);
}

/**
 * Shared board payload for HTML + JSON. Names and titles only.
 * @param {import("node:sqlite").DatabaseSync} db
 * @param {{ now?: () => Date, activeFrom?: Date|string }} [opts]
 */
export function buildStatusBoard(db, opts = {}) {
  const now = (opts.now ?? (() => new Date()))();
  const todayKey = chicagoDateKey(now);
  const rows = loadCompletions(db);
  const chores = listChores(db);
  const activeFrom = resolveActiveFrom(db, opts);

  const completions = rows.map((r) => ({
    id: r.id,
    choreId: r.choreId,
    person: r.person,
    completedAt: r.completedAt,
  }));

  expireOpenHandoffs(db, now);
  const handoffs = listHandoffs(db);
  const stats = boardStats({ chores, completions, asOf: now, activeFrom, handoffs });
  const openBonus = loadOpenBonus(db);

  const byPerson = Object.fromEntries(PEOPLE.map((p) => [p, []]));
  for (const row of rows) {
    if (chicagoDateKey(new Date(row.completedAt)) !== todayKey) continue;
    if (!byPerson[row.person]) byPerson[row.person] = [];
    byPerson[row.person].push({ title: row.title });
  }

  const people = PEOPLE.map((person) => {
    const s = stats[person] ?? { streak: 0, week: 0, overdue: [], dueToday: [] };
    const boardDue = [...s.overdue, ...(s.dueToday ?? []).filter((i) => i.viaHandoff)];
    const due = boardDue.map((i) => ({
      title: i.chore.title,
      stage: i.stage,
      viaHandoff: !!i.viaHandoff,
      person: i.person,
    }));
    const bonus = openBonus
      .filter((b) => (b.claimedBy ?? b.assignedTo) === person)
      .map((b) => ({ title: b.title, points: b.points }));
    return {
      id: person,
      name: displayName(person),
      streak: s.streak,
      week: s.week,
      today: byPerson[person] ?? [],
      due,
      bonus,
    };
  });

  const sharedBonus = openBonus
    .filter((b) => !b.claimedBy && !b.assignedTo)
    .map((b) => ({ title: b.title, points: b.points }));

  const recent = rows.slice(0, 10).map((r) => ({
    person: displayName(r.person),
    title: r.title,
    time: formatChicagoTime(r.completedAt),
  }));

  return {
    date: formatChicagoDateHeading(now),
    updated: formatChicagoUpdated(now),
    activeFrom: resolveActiveFromString(db, opts),
    digestLastSent: getMeta(db, "digestLastSent"),
    people,
    bonus: sharedBonus,
    recent,
  };
}

/**
 * GET /fonts/<file> — basename allowlist only, immutable cache on 200.
 * @param {import("node:http").IncomingMessage} _req
 * @param {import("node:http").ServerResponse} res
 * @param {string} path pathname starting with /fonts/
 */
export function fontsHandler(_req, res, path) {
  if (!path.startsWith("/fonts/")) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
    res.end("not found");
    return;
  }
  const name = path.slice("/fonts/".length);
  // Basename only: reject traversal, nested paths, and anything not in the allowlist.
  if (!name || name !== basename(name) || name.includes("\0") || !FONT_FILES.has(name)) {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
    res.end("not found");
    return;
  }
  const filePath = join(FONTS_DIR, name);
  let buf;
  try {
    buf = readFileSync(filePath);
  } catch {
    res.writeHead(404, { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" });
    res.end("not found");
    return;
  }
  res.writeHead(200, {
    "content-type": "font/ttf",
    "content-length": buf.byteLength,
    "cache-control": "public, max-age=31536000, immutable",
  });
  res.end(buf);
}

/**
 * GET /status.json — same data the page renders; no auth; names and titles only.
 */
/** Plain green-circle SVG favicon; served before auth. */
const FAVICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32"><circle cx="16" cy="16" r="14" fill="#2F8F72"/></svg>`;

export function faviconHandler(_req, res) {
  const buf = Buffer.from(FAVICON_SVG, "utf8");
  res.writeHead(200, {
    "content-type": "image/svg+xml; charset=utf-8",
    "content-length": buf.byteLength,
    "cache-control": "public, max-age=31536000, immutable",
  });
  res.end(buf);
}

export function statusJsonHandler(db, _req, res, opts = {}) {
  const board = buildStatusBoard(db, opts);
  // Ops-only: backup verify status is not rendered on the HTML board.
  const json = JSON.stringify({
    ...board,
    backup: readVerifyStatus({ log: opts.log }),
  });
  res.writeHead(200, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(json),
    "cache-control": "no-store",
  });
  res.end(json);
}

/**
 * GET /status — self-contained HTML status board.
 * @param {import("node:sqlite").DatabaseSync} db
 * @param {import("node:http").IncomingMessage} _req
 * @param {import("node:http").ServerResponse} res
 * @param {{ now?: () => Date, activeFrom?: Date|string }} [opts]
 */
export function statusHandler(db, _req, res, opts = {}) {
  const board = buildStatusBoard(db, opts);

  const personSections = board.people
    .map((p) => {
      const items =
        p.today.length === 0
          ? `<li class="empty">Nothing yet</li>`
          : p.today.map((r) => `<li>${escapeHtml(r.title)}</li>`).join("");

      const overdueBlock =
        p.due.length === 0
          ? `<p class="meta-empty">None</p>`
          : `<ul class="overdue">${p.due
              .map((i) => {
                const arrow = i.viaHandoff
                  ? ` <span class="handoff">→ ${escapeHtml(displayName(i.person))}</span>`
                  : "";
                return `<li class="${escapeHtml(stageClass(i.stage))}"><span class="due-title">${escapeHtml(i.title)}</span>${arrow} <span class="stage-chip">${escapeHtml(stageLabel(i.stage))}</span></li>`;
              })
              .join("")}</ul>`;

      const bonusBlock =
        p.bonus.length === 0
          ? ""
          : `<h3 class="subhead">Bonus</h3><ul class="bonus">${p.bonus
              .map(
                (b) =>
                  `<li><span class="due-title">${escapeHtml(b.title)}</span> <span class="pts">+${escapeHtml(String(b.points))}</span></li>`
              )
              .join("")}</ul>`;

      return `
      <section class="card person person-${escapeHtml(p.id)}">
        <h2>${escapeHtml(p.name)} <span class="count tally">${p.today.length}</span></h2>
        <p class="stats tally">Streak ${p.streak} · Week ${p.week}</p>
        <h3 class="subhead">Overdue</h3>
        ${overdueBlock}
        <h3 class="subhead">Today</h3>
        <ul>${items}</ul>
        ${bonusBlock}
      </section>`;
    })
    .join("");

  const sharedBonus =
    board.bonus.length === 0
      ? ""
      : `<section class="recent bonus-open">
    <h2>Open bonus</h2>
    <ul>${board.bonus
      .map(
        (b) =>
          `<li><span class="what">${escapeHtml(b.title)}</span> <span class="pts">+${escapeHtml(String(b.points))}</span></li>`
      )
      .join("")}</ul>
  </section>`;

  const recentItems =
    board.recent.length === 0
      ? `<li class="empty">No completions yet</li>`
      : board.recent
          .map(
            (r) =>
              `<li><span class="who">${escapeHtml(r.person)}</span>
               <span class="what">${escapeHtml(r.title)}</span>
               <span class="when tally">${escapeHtml(r.time)}</span></li>`
          )
          .join("");

  // App palette tokens from Packages/RoostDesign/README.md — hex only in this block.
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="60">
  <title>Roost status</title>
  <style>
    :root {
      --bg: #F3F6F2;
      --surface: #FFFFFF;
      --surface-2: #FBFDFA;
      --ink: #1F2A22;
      --ink-soft: #5C6C60;
      --line: #DCE6DA;
      --accent: #2F8F72;
      --accent-soft: #CFEEE1;
      --gold: #E08F2E;
      --gold-soft: #FBE3C2;
      --info: #4C7FE0;
      --info-soft: #DEE6FC;
      --tease: #D6487A;
      --tease-soft: #FBDCE8;
      --alert: #E2233F;
      --alert-soft: #FCD9DF;
      --meal: #C2571F;
      --meal-soft: #F5DCC8;
      --assign: #6B4FA0;
      --assign-soft: #E6DFF5;
      --shadow: rgba(31,42,34,0.14);
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #121A15;
        --surface: #1B241D;
        --surface-2: #212C22;
        --ink: #EAF2EC;
        --ink-soft: #9FB3A4;
        --line: #2B3830;
        --accent: #6FC2A6;
        --accent-soft: #1E362E;
        --gold: #D9A754;
        --gold-soft: #3A2D15;
        --info: #7FB3D9;
        --info-soft: #1E2E3A;
        --tease: #E389A8;
        --tease-soft: #3A2129;
        --alert: #FF6478;
        --alert-soft: #3D1620;
        --meal: #E8935A;
        --meal-soft: #3A2415;
        --assign: #B79EE0;
        --assign-soft: #332750;
        --shadow: rgba(0,0,0,0.45);
      }
    }
    @font-face {
      font-family: "Fraunces";
      src: url("/fonts/Fraunces-Variable.ttf") format("truetype");
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: "Nunito Sans";
      src: url("/fonts/NunitoSans-Variable.ttf") format("truetype");
      font-weight: 100 900;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: "IBM Plex Mono";
      src: url("/fonts/IBMPlexMono-Regular.ttf") format("truetype");
      font-weight: 400;
      font-style: normal;
      font-display: swap;
    }
    @font-face {
      font-family: "IBM Plex Mono";
      src: url("/fonts/IBMPlexMono-Medium.ttf") format("truetype");
      font-weight: 500;
      font-style: normal;
      font-display: swap;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Nunito Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
      padding: 1.5rem;
      line-height: 1.4;
    }
    h1 {
      margin: 0 0 0.25rem;
      font-family: "Fraunces", ui-serif, Georgia, serif;
      font-size: 1.75rem;
      font-weight: 700;
      color: var(--accent);
    }
    h2 {
      font-family: "Fraunces", ui-serif, Georgia, serif;
      margin: 0 0 0.35rem;
      font-size: 1.15rem;
      display: flex;
      align-items: baseline;
      gap: 0.5rem;
    }
    .date, .updated {
      color: var(--ink-soft);
      margin: 0;
      font-size: 1.05rem;
    }
    .updated {
      margin-bottom: 1.5rem;
      font-size: 0.9rem;
      font-family: "IBM Plex Mono", ui-monospace, "Cascadia Code", monospace;
      font-weight: 500;
    }
    .grid {
      display: grid;
      gap: 1rem;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      margin-bottom: 1.5rem;
    }
    @media (max-width: 640px) {
      .grid { grid-template-columns: 1fr; }
    }
    .card, .recent {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 1rem 1.15rem;
      box-shadow: 0 1px 2px var(--shadow);
    }
    .stats {
      margin: 0 0 0.75rem;
      color: var(--ink-soft);
      font-size: 0.95rem;
    }
    .tally {
      font-family: "IBM Plex Mono", ui-monospace, "Cascadia Code", monospace;
      font-weight: 500;
      font-variant-numeric: tabular-nums;
    }
    .subhead {
      margin: 0.75rem 0 0.35rem;
      font-size: 0.8rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: var(--ink-soft);
      font-weight: 700;
      font-family: "IBM Plex Mono", ui-monospace, "Cascadia Code", monospace;
    }
    .count {
      background: var(--accent-soft);
      color: var(--accent);
      font-size: 0.85rem;
      font-weight: 700;
      padding: 0.15rem 0.5rem;
      border-radius: 999px;
    }
    ul {
      margin: 0;
      padding: 0;
      list-style: none;
    }
    li {
      padding: 0.4rem 0;
      border-top: 1px solid var(--line);
    }
    li:first-child { border-top: 0; }
    li.empty, .meta-empty { color: var(--ink-soft); font-style: italic; margin: 0; }
    .stage-chip {
      display: inline-block;
      font-size: 0.75rem;
      font-weight: 600;
      line-height: 1.2;
      padding: 0.12rem 0.45rem;
      border-radius: 999px;
      background: var(--surface-2);
      color: var(--ink-soft);
      white-space: nowrap;
      vertical-align: middle;
    }
    .stage-due .stage-chip { color: var(--ink-soft); background: var(--surface-2); }
    .stage-nudge .stage-chip { color: var(--ink-soft); background: var(--line); }
    .stage-pointed .stage-chip, .warning .stage-chip { color: var(--gold); background: var(--gold-soft); }
    .stage-alert .stage-chip, .danger .stage-chip { color: var(--alert); background: var(--alert-soft); }
    .stage-pointed, .warning { background: var(--gold-soft); margin: 0 -0.35rem; padding-left: 0.35rem; padding-right: 0.35rem; border-radius: 6px; }
    .stage-alert, .danger { background: var(--alert-soft); margin: 0 -0.35rem; padding-left: 0.35rem; padding-right: 0.35rem; border-radius: 6px; }
    .handoff { color: var(--accent); font-weight: 600; font-size: 0.95em; }
    .pts { color: var(--gold); font-family: "IBM Plex Mono", ui-monospace, monospace; font-weight: 500; }
    .bonus-open { margin-bottom: 1.5rem; }
    .recent li {
      display: grid;
      grid-template-columns: 4.5rem 1fr auto;
      gap: 0.75rem;
      align-items: baseline;
    }
    .recent li.empty {
      display: block;
      grid-template-columns: none;
    }
    .who { font-weight: 600; color: var(--accent); }
    .what { color: var(--ink); }
    .when { color: var(--ink-soft); white-space: nowrap; }
  </style>
</head>
<body>
  <h1>Roost</h1>
  <p class="date">${escapeHtml(board.date)}</p>
  <p class="updated">updated ${escapeHtml(board.updated)}</p>
  <div class="grid">${personSections}</div>
  ${sharedBonus}
  <section class="recent">
    <h2>Recent</h2>
    <ul>${recentItems}</ul>
  </section>
</body>
</html>`;

  const buf = Buffer.from(html, "utf8");
  res.writeHead(200, {
    "content-type": "text/html; charset=utf-8",
    "content-length": buf.byteLength,
    "cache-control": "no-store",
  });
  res.end(buf);
}
