// Read-only household status board for a kitchen screen.
// No auth (behind the tunnel). First names + chore titles only.
import { PEOPLE } from "./db.js";

const TZ = "America/Chicago";

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

function displayName(person) {
  if (!person) return "";
  return person.charAt(0).toUpperCase() + person.slice(1);
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

/**
 * GET /status — self-contained HTML status board.
 * @param {import("node:sqlite").DatabaseSync} db
 * @param {import("node:http").IncomingMessage} _req
 * @param {import("node:http").ServerResponse} res
 * @param {{ now?: () => Date }} [opts]
 */
export function statusHandler(db, _req, res, opts = {}) {
  const now = (opts.now ?? (() => new Date()))();
  const todayKey = chicagoDateKey(now);
  const rows = loadCompletions(db);

  const byPerson = Object.fromEntries(PEOPLE.map((p) => [p, []]));
  for (const row of rows) {
    if (chicagoDateKey(new Date(row.completedAt)) !== todayKey) continue;
    if (!byPerson[row.person]) byPerson[row.person] = [];
    byPerson[row.person].push(row);
  }

  const recent = rows.slice(0, 10);

  const personSections = PEOPLE.map((person) => {
    const list = byPerson[person] ?? [];
    const items =
      list.length === 0
        ? `<li class="empty">Nothing yet</li>`
        : list.map((r) => `<li>${escapeHtml(r.title)}</li>`).join("");
    return `
      <section class="card">
        <h2>${escapeHtml(displayName(person))} <span class="count">${list.length}</span></h2>
        <ul>${items}</ul>
      </section>`;
  }).join("");

  const recentItems =
    recent.length === 0
      ? `<li class="empty">No completions yet</li>`
      : recent
          .map(
            (r) =>
              `<li><span class="who">${escapeHtml(displayName(r.person))}</span>
               <span class="what">${escapeHtml(r.title)}</span>
               <span class="when">${escapeHtml(formatChicagoTime(r.completedAt))}</span></li>`
          )
          .join("");

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
      --accent: #2F6F5E;
      --accent-soft: #DCEBE3;
      --gold: #B9812E;
      --gold-soft: #F3E4C9;
      --shadow: rgba(31, 42, 34, 0.14);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
      background: var(--bg);
      color: var(--ink);
      padding: 1.5rem;
      line-height: 1.4;
    }
    h1 {
      margin: 0 0 0.25rem;
      font-size: 1.75rem;
      font-weight: 700;
      color: var(--accent);
    }
    .date {
      color: var(--ink-soft);
      margin-bottom: 1.5rem;
      font-size: 1.05rem;
    }
    .grid {
      display: grid;
      gap: 1rem;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      margin-bottom: 1.5rem;
    }
    .card, .recent {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 1rem 1.15rem;
      box-shadow: 0 1px 2px var(--shadow);
    }
    h2 {
      margin: 0 0 0.75rem;
      font-size: 1.15rem;
      display: flex;
      align-items: baseline;
      gap: 0.5rem;
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
    li.empty { color: var(--ink-soft); font-style: italic; }
    .recent li {
      display: grid;
      grid-template-columns: 4.5rem 1fr auto;
      gap: 0.75rem;
      align-items: baseline;
    }
    .who { font-weight: 600; color: var(--accent); }
    .what { color: var(--ink); }
    .when { color: var(--ink-soft); font-variant-numeric: tabular-nums; white-space: nowrap; }
  </style>
</head>
<body>
  <h1>Roost</h1>
  <p class="date">${escapeHtml(formatChicagoDateHeading(now))}</p>
  <div class="grid">${personSections}</div>
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
