// Node port of Packages/RoostCore scheduling / tallies / escalation / rotation.
// All day/week/month arithmetic is America/Chicago; weeks Monday–Sunday.
// Rendering stays in status.js — this module is pure logic only.

export const TZ = "America/Chicago";
export const PEOPLE = Object.freeze(["anne", "wes"]);

/** Every cadence data/chores.json may use, in the order the file groups them. Mirrors RoostCore.Cadence. */
export const CADENCES = Object.freeze(["daily", "weekly", "biweekly", "monthly", "bimonthly", "quarterly"]);

/** Calendar months per period for the month-based cadences. Mirrors Cadence.monthsPerPeriod. */
export const MONTHS_PER_PERIOD = Object.freeze({ monthly: 1, bimonthly: 2, quarterly: 3 });

/** Monday 2026-01-05 00:00 Chicago — period 0 for every cadence. */
export const ANCHOR = chicagoLocal(2026, 1, 5, 0, 0, 0);

/** Default household start: Sep 7 2026 Chicago midnight (= 2026-09-07T05:00:00.000Z CDT). */
export const DEFAULT_ACTIVE_FROM = new Date("2026-09-07T05:00:00.000Z");

/** Calendar YYYY-MM-DD in America/Chicago. */
export function chicagoDateString(date = new Date()) {
  const { year, month, day } = ymd(date);
  return `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

/**
 * Resolve household activeFrom. Meta stores YYYY-MM-DD (Chicago calendar).
 * Date-only strings are Chicago midnight, not UTC midnight.
 * Unset / empty falls back to DEFAULT_ACTIVE_FROM (tests + pre-pair).
 */
export function parseActiveFrom(value) {
  if (value == null || value === "") return DEFAULT_ACTIVE_FROM;
  if (value instanceof Date) return value;
  const s = String(value).trim();
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (m) return chicagoLocal(+m[1], +m[2], +m[3], 0, 0, 0);
  return asDate(s);
}

const STAGE_BY_DAYS = [
  [1, "dueToday"],
  [3, "nudge"],
  [5, "pointed"],
];

// ---------------------------------------------------------------------------
// Chicago calendar helpers
// ---------------------------------------------------------------------------

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

/** Instant for a wall-clock time in America/Chicago. */
export function chicagoLocal(year, month, day, hour = 0, minute = 0, second = 0) {
  // Guess UTC (Chicago is UTC-5 or UTC-6), then correct using formatted parts.
  let guess = Date.UTC(year, month - 1, day, hour + 6, minute, second);
  for (let i = 0; i < 4; i++) {
    const p = chicagoParts(new Date(guess));
    const want = Date.UTC(year, month - 1, day, hour, minute, second);
    const got = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
    const diff = want - got;
    if (diff === 0) return new Date(guess);
    guess += diff;
  }
  return new Date(guess);
}

function ymd(date) {
  const p = chicagoParts(asDate(date));
  return { year: +p.year, month: +p.month, day: +p.day };
}

/** Gregorian → Julian day number (civil date, noon-independent). */
function julianDay(year, month, day) {
  const a = Math.floor((14 - month) / 12);
  const y = year + 4800 - a;
  const m = month + 12 * a - 3;
  return (
    day +
    Math.floor((153 * m + 2) / 5) +
    365 * y +
    Math.floor(y / 4) -
    Math.floor(y / 100) +
    Math.floor(y / 400) -
    32045
  );
}

function fromJulianDay(jd) {
  // Inverse of julianDay for Gregorian calendar.
  let a = jd + 32044;
  let b = Math.floor((4 * a + 3) / 146097);
  let c = a - Math.floor((146097 * b) / 4);
  let d = Math.floor((4 * c + 3) / 1461);
  let e = c - Math.floor((1461 * d) / 4);
  let m = Math.floor((5 * e + 2) / 153);
  const day = e - Math.floor((153 * m + 2) / 5) + 1;
  const month = m + 3 - 12 * Math.floor(m / 10);
  const year = 100 * b + d - 4800 + Math.floor(m / 10);
  return chicagoLocal(year, month, day, 0, 0, 0);
}

function asDate(v) {
  if (v instanceof Date) return v;
  return new Date(v);
}

function floorDiv(a, b) {
  const q = (a / b) | 0; // trunc toward zero (JS |0 / Swift /)
  const r = a % b;
  return r !== 0 && (a < 0) !== (b < 0) ? q - 1 : q;
}

function mod(a, b) {
  const r = a % b;
  return r < 0 ? r + b : r;
}

// ---------------------------------------------------------------------------
// Public calendar API
// ---------------------------------------------------------------------------

export function startOfDay(date) {
  const { year, month, day } = ymd(date);
  return chicagoLocal(year, month, day, 0, 0, 0);
}

/** Whole Chicago days from the anchor Monday to the day containing `date`. */
export function dayIndex(date) {
  const a = ymd(ANCHOR);
  const b = ymd(date);
  return julianDay(b.year, b.month, b.day) - julianDay(a.year, a.month, a.day);
}

/** Start of the Chicago day `index` days after the anchor. */
export function dayAt(index) {
  const a = ymd(ANCHOR);
  return fromJulianDay(julianDay(a.year, a.month, a.day) + index);
}

/** Whole calendar months from January 2026 to the month containing `date`. Negative before it. */
export function monthIndex(date) {
  const { year, month } = ymd(date);
  return (year - 2026) * 12 + (month - 1);
}

export function periodIndex(cadence, date) {
  switch (cadence) {
    case "daily":
      return dayIndex(date);
    case "weekly":
      return floorDiv(dayIndex(date), 7);
    case "biweekly":
      return floorDiv(dayIndex(date), 14);
    case "monthly":
    case "bimonthly":
    case "quarterly":
      return floorDiv(monthIndex(date), MONTHS_PER_PERIOD[cadence]);
    default:
      throw new Error(`unknown cadence: ${cadence}`);
  }
}

/** Start of first day and start of last day of a period. Month-based periods are `MONTHS_PER_PERIOD[cadence]` whole months from month index `index * months`. */
export function periodBounds(cadence, index) {
  switch (cadence) {
    case "daily": {
      const d = dayAt(index);
      return { firstDay: d, lastDay: d };
    }
    case "weekly":
      return { firstDay: dayAt(index * 7), lastDay: dayAt(index * 7 + 6) };
    case "biweekly":
      return { firstDay: dayAt(index * 14), lastDay: dayAt(index * 14 + 13) };
    case "monthly":
    case "bimonthly":
    case "quarterly": {
      const months = MONTHS_PER_PERIOD[cadence];
      const firstMonth = index * months;
      const first = chicagoLocal(2026 + floorDiv(firstMonth, 12), mod(firstMonth, 12) + 1, 1, 0, 0, 0);
      const endMonth = firstMonth + months; // the month after the period, as a month index
      const last = fromJulianDay(julianDay(2026 + floorDiv(endMonth, 12), mod(endMonth, 12) + 1, 1) - 1);
      return { firstDay: first, lastDay: last };
    }
    default:
      throw new Error(`unknown cadence: ${cadence}`);
  }
}

/** Whether the chore narrows its due days inside the period. Mirrors Chore.hasWindow. */
export function hasWindow(chore) {
  return (Array.isArray(chore.weekdays) && chore.weekdays.length > 0) || chore.dueDay != null;
}

/**
 * The days inside period `index` on which `chore` is due: the period itself without a window; the
 * earliest through the latest listed ISO weekday (Mon = 1 … Sun = 7) for a weekly chore with `weekdays`;
 * the seven days ending on `dueDay` of the period's last month for a month-based chore with `dueDay`.
 * Mirrors HouseholdCalendar.dueWindow(for:periodIndex:).
 */
export function dueWindow(chore, index) {
  const bounds = periodBounds(chore.cadence, index);
  if (chore.cadence === "weekly" && Array.isArray(chore.weekdays) && chore.weekdays.length > 0) {
    const first = Math.min(...chore.weekdays);
    const last = Math.max(...chore.weekdays);
    const start = dayIndex(bounds.firstDay);
    return { firstDay: dayAt(start + first - 1), lastDay: dayAt(start + last - 1) };
  }
  const months = MONTHS_PER_PERIOD[chore.cadence];
  if (months && chore.dueDay != null) {
    const lastMonth = index * months + months - 1; // month index of the period's last month
    const due = chicagoLocal(2026 + floorDiv(lastMonth, 12), mod(lastMonth, 12) + 1, chore.dueDay, 0, 0, 0);
    return { firstDay: dayAt(dayIndex(due) - 6), lastDay: due };
  }
  return bounds;
}

/**
 * The period `date` belongs to for `chore`: its calendar period, or the next one once the next period's
 * window has opened (a dueDay early in the month reaches back into the month before). Mirrors
 * Scheduler.effectivePeriod(for:containing:).
 */
export function effectivePeriod(chore, date) {
  const d = asDate(date);
  const index = periodIndex(chore.cadence, d);
  if (chore.dueDay == null) return index;
  const next = dueWindow(chore, index + 1);
  return dayIndex(d) >= dayIndex(next.firstDay) ? index + 1 : index;
}

/** Monday 00:00 of the week containing `date`, and the following Monday 00:00 (exclusive). */
export function weekBounds(date) {
  const index = periodIndex("weekly", date);
  return { start: dayAt(index * 7), end: dayAt(index * 7 + 7) };
}

// ---------------------------------------------------------------------------
// Rotation / escalation
// ---------------------------------------------------------------------------

/** FNV-1a 64-bit. Returns a BigInt. */
export function fnv1a(s) {
  let hash = 0xcbf29ce484222325n;
  const prime = 0x100000001b3n;
  const bytes = typeof Buffer !== "undefined" ? Buffer.from(s, "utf8") : new TextEncoder().encode(s);
  for (const byte of bytes) {
    hash ^= BigInt(byte);
    hash = (hash * prime) & 0xffffffffffffffffn;
  }
  return hash;
}

/** Round-robin assignee for an unpinned chore in a period. Pinned chores never call this. */
export function rotationAssignee(choreId, periodIdx) {
  const start = Number(fnv1a(choreId) & 1n);
  const slot = (start + periodIdx) & 1;
  return slot === 0 ? "anne" : "wes";
}

/** A chore's own rotation, or the hash round-robin. Mirrors ChoreRotation.assignee(periodIndex:). */
export function rotationFor(chore, periodIdx) {
  const r = chore.rotation;
  if (!r) return rotationAssignee(chore.id, periodIdx);
  if (r.kind === "weekdayCycle") {
    const weeks = r.weeks ?? [];
    if (!weeks.length) return "anne";
    const week = weeks[mod(floorDiv(periodIdx, 7), weeks.length)];
    return week?.length === 7 ? week[mod(periodIdx, 7)] : "anne";
  }
  if (r.kind === "alternate") {
    const other = r.start === "anne" ? "wes" : "anne";
    return mod(periodIdx, 2) === 0 ? r.start : other;
  }
  return rotationAssignee(chore.id, periodIdx);
}

/**
 * Days inside [from, through] that `watched` was owed by someone and nobody did.
 * Mirrors MissCounter: floor at activeFrom's period, stop at today − 1, anyone's completion
 * clears the day, ownership via assigneeFor(watched, …) so an accepted handoff moves the miss.
 */
export function missesFor(watched, { from, through, asOf, activeFrom, completions = [], handoffs = [] }) {
  const asOfD = asDate(asOf);
  const floor = periodIndex(watched.cadence, asDate(activeFrom));
  const today = periodIndex(watched.cadence, asOfD);
  const first = Math.max(periodIndex(watched.cadence, asDate(from)), floor);
  const last = Math.min(periodIndex(watched.cadence, asDate(through)), today - 1);
  if (first > last) return {};

  const donePeriods = new Set();
  for (const c of completions) {
    if (c.choreId !== watched.id) continue;
    donePeriods.add(periodIndex(watched.cadence, asDate(c.completedAt)));
  }

  const counts = {};
  for (let period = first; period <= last; period++) {
    if (donePeriods.has(period)) continue;
    const owner = assigneeFor(watched, period, handoffs, asOfD);
    counts[owner] = (counts[owner] ?? 0) + 1;
  }
  return counts;
}

/** The person a penalty moves a chore to, or null. Mirrors MissCounter.penalised. */
export function penalisedPerson(counts, overMisses) {
  // Exactly one person over the line, or nobody. When both are over, the rotation stands: the penalty
  // moves a chore onto whoever let the other carry it, and when both let it slide there is no claim to
  // act on. "Whoever is further over" would flip the owner daily, because the watched chore alternates
  // daily and so does the miss lead. Mirrors MissCounter.penalised.
  const over = PEOPLE.filter((p) => (counts[p] ?? 0) > overMisses);
  return over.length === 1 ? over[0] : null;
}

/**
 * Who owes `chore` for `periodIdx`. An accepted handoff for that exact chore+period
 * wins over fixedAssignee, miss penalty, and rotation. Pending/declined do nothing.
 * R-21: accepted handoffs remain permanent for their periodIndex (no asOf expiry filter).
 *
 * Optional `ctx` (`chores`, `completions`, `activeFrom`) enables the miss penalty between
 * the pin and the rotation. Without it, callers get handoff → pin → rotationFor only.
 *
 * `handoffs` rows may use SQL names (fromPerson/toPerson) or JSON names (from/to).
 */
export function assigneeFor(chore, periodIdx, handoffs = [], asOf = new Date(), ctx = {}) {
  const override = (handoffs ?? [])
    .filter((h) => !h.deletedAt)
    .filter((h) => h.choreId === chore.id && h.periodIndex === periodIdx)
    .filter((h) => h.state === "accepted")
    .sort((a, b) => {
      const at = asDate(a.createdAt).getTime() - asDate(b.createdAt).getTime();
      if (at !== 0) return at;
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    })[0];
  if (override) return override.toPerson ?? override.to;
  if (chore.fixedAssignee) return chore.fixedAssignee;
  if (
    chore.missPenalty &&
    ctx.chores &&
    ctx.completions &&
    ctx.activeFrom != null
  ) {
    const watched = ctx.chores.find((c) => c.id === chore.missPenalty.watch);
    if (watched) {
      const bounds = periodBounds(chore.cadence, periodIdx);
      const counts = missesFor(watched, {
        from: bounds.firstDay,
        through: bounds.lastDay,
        asOf,
        activeFrom: ctx.activeFrom,
        completions: ctx.completions,
        handoffs,
      });
      const moved = penalisedPerson(counts, chore.missPenalty.overMisses);
      if (moved) return moved;
    }
  }
  return rotationFor(chore, periodIdx);
}

export function escalationStage(daysOverdue) {
  if (daysOverdue < 1) return "dueToday";
  if (daysOverdue < 3) return "nudge";
  if (daysOverdue < 5) return "pointed";
  return "alert";
}

// ---------------------------------------------------------------------------
// Scheduler / tallies
// ---------------------------------------------------------------------------

function inSeason(chore, index) {
  const months = chore.season?.months ?? [];
  return months.includes(ymd(periodBounds(chore.cadence, index).firstDay).month);
}

/**
 * First period of the run of in-season periods ending at `current`, never earlier than `floor`; null when
 * `current` itself started out of season. Mirrors Scheduler.firstPeriod(inSeason:endingAt:notBefore:).
 */
export function seasonStart(chore, current, floor) {
  if (!inSeason(chore, current)) return null;
  let start = current;
  while (start - 1 >= floor && inSeason(chore, start - 1)) start -= 1;
  return start;
}

/**
 * Oldest incomplete period for `chore` as of `asOf`, or null if done for the current period.
 * Completing in a later period clears older missed ones (one nag, not a backlog).
 */
export function dueItemFor(chore, { completions, asOf, activeFrom = DEFAULT_ACTIVE_FROM, handoffs = [], chores = [] }) {
  const asOfD = asDate(asOf);
  const active = asDate(activeFrom);
  const current = effectivePeriod(chore, asOfD);
  let floor = effectivePeriod(chore, active);
  // A window that closed before the household started was never owed: start at the next period.
  if (hasWindow(chore) && dayIndex(dueWindow(chore, floor).lastDay) < dayIndex(active)) floor += 1;
  if (chore.season) {
    const start = seasonStart(chore, current, floor);
    if (start === null) return null;
    floor = Math.max(floor, start);
  }
  const mine = completions.filter((c) => c.choreId === chore.id);
  let lastDone = null;
  for (const c of mine) {
    const pi = effectivePeriod(chore, asDate(c.completedAt));
    if (lastDone === null || pi > lastDone) lastDone = pi;
  }
  const oldestIncomplete = Math.max(lastDone === null ? floor : lastDone + 1, floor);
  if (oldestIncomplete > current) return null;

  const bounds = periodBounds(chore.cadence, oldestIncomplete);
  const window = dueWindow(chore, oldestIncomplete);
  // Not yet: this period's window has not opened. A missed window from an older period still shows.
  if (oldestIncomplete === current && dayIndex(asOfD) < dayIndex(window.firstDay)) return null;
  const daysOverdue = Math.max(0, dayIndex(asOfD) - dayIndex(window.lastDay));
  // Both of them owe a together chore; dueItems hands out the second row. Nothing was handed over.
  const ctx = { chores, completions, activeFrom: active };
  const person = chore.together ? "anne" : assigneeFor(chore, oldestIncomplete, handoffs, asOfD, ctx);
  const viaHandoff =
    !chore.together && person !== assigneeFor(chore, oldestIncomplete, [], asOfD, ctx);
  return {
    chore,
    person,
    viaHandoff,
    periodIndex: oldestIncomplete,
    periodStart: bounds.firstDay,
    periodLastDay: bounds.lastDay,
    dueFirstDay: window.firstDay,
    dueLastDay: window.lastDay,
    daysOverdue,
    stage: escalationStage(daysOverdue),
  };
}

/**
 * Everything due on `asOf`, keyed by person. Most overdue first, then by chore list order.
 * Optional `balance` (default false) runs FairnessBalancer over the day's items — off unless asked.
 * Accepted handoffs override assignee for their exact chore+period (via assigneeFor).
 * When balance is on, `handoffs` are also forwarded for reassignability checks.
 */
export function dueItems({
  chores,
  completions,
  asOf,
  activeFrom = DEFAULT_ACTIVE_FROM,
  handoffs = [],
  balance: doBalance = false,
}) {
  const byChore = new Map();
  for (const c of completions) {
    if (!byChore.has(c.choreId)) byChore.set(c.choreId, []);
    byChore.get(c.choreId).push(c);
  }
  let items = [];
  for (const chore of chores) {
    let relevant = byChore.get(chore.id) ?? [];
    if (chore.missPenalty?.watch && chore.missPenalty.watch !== chore.id) {
      relevant = relevant.concat(byChore.get(chore.missPenalty.watch) ?? []);
    }
    const item = dueItemFor(chore, {
      completions: relevant,
      asOf,
      activeFrom,
      handoffs,
      chores,
    });
    if (!item) continue;
    if (chore.together) {
      for (const person of PEOPLE) items.push({ ...item, person });
    } else {
      items.push(item);
    }
  }
  if (doBalance) {
    items = balance(items, { chores, completions, handoffs, asOf });
  }
  const result = Object.fromEntries(PEOPLE.map((p) => [p, []]));
  for (const item of items) {
    result[item.person].push(item);
  }
  for (const person of PEOPLE) {
    result[person].sort((a, b) => {
      if (a.daysOverdue !== b.daysOverdue) return b.daysOverdue - a.daysOverdue;
      const ai = chores.indexOf(a.chore);
      const bi = chores.indexOf(b.chore);
      return (ai < 0 ? 0 : ai) - (bi < 0 ? 0 : bi);
    });
  }
  return result;
}

/** `<choreId>#<periodIndex>`, plus `#<person>` for a together chore's two rows. Mirrors DueItem.id. */
export function dueItemId(item) {
  return item.chore.together
    ? `${item.chore.id}#${item.periodIndex}#${item.person}`
    : `${item.chore.id}#${item.periodIndex}`;
}

/** Completions per person in the Monday–Sunday Chicago week containing `asOf`. A together chore's completion counts for both. */
export function doneThisWeek({ completions, asOf, chores = [] }) {
  const week = weekBounds(asOf);
  const together = new Set(chores.filter((c) => c.together).map((c) => c.id));
  const counts = Object.fromEntries(PEOPLE.map((p) => [p, 0]));
  for (const c of completions) {
    const t = asDate(c.completedAt).getTime();
    if (t < week.start.getTime() || t >= week.end.getTime()) continue;
    if (together.has(c.choreId)) {
      for (const p of PEOPLE) counts[p] += 1;
    } else if (counts[c.person] !== undefined) {
      counts[c.person] += 1;
    }
  }
  return counts;
}

function isDayComplete(person, dayIdx, dailies, completions, handoffs = []) {
  const start = dayAt(dayIdx);
  const end = dayAt(dayIdx + 1);
  const startMs = start.getTime();
  const endMs = end.getTime();
  const mine = dailies.filter((ch) => ch.together || assigneeFor(ch, dayIdx, handoffs, start) === person);
  for (const chore of mine) {
    const done = completions.some((c) => {
      if (c.choreId !== chore.id) return false;
      const t = asDate(c.completedAt).getTime();
      return t >= startMs && t < endMs;
    });
    if (!done) return false;
  }
  return true;
}

/**
 * Consecutive days ending today or yesterday on which `person` finished every daily assigned to them.
 * Unfinished today does not break (count from yesterday). Days before activeFrom never count.
 * A day with no dailies assigned counts as complete.
 */
export function streak({ person, chores, completions, asOf, activeFrom = DEFAULT_ACTIVE_FROM, handoffs = [] }) {
  const dailies = chores.filter((c) => c.cadence === "daily");
  const firstDay = dayIndex(activeFrom);
  const today = dayIndex(asOf);
  let day = today;
  let n = 0;
  if (!isDayComplete(person, today, dailies, completions, handoffs)) {
    day = today - 1;
  }
  while (day >= firstDay) {
    if (!isDayComplete(person, day, dailies, completions, handoffs)) break;
    n += 1;
    day -= 1;
  }
  return n;
}

/**
 * Aggregator for the status board: streak, week tally, overdue (+ optional due-today) per person.
 */
export function boardStats({
  chores,
  completions,
  asOf,
  activeFrom = DEFAULT_ACTIVE_FROM,
  handoffs = [],
  balance: doBalance = false,
}) {
  const due = dueItems({ chores, completions, asOf, activeFrom, handoffs, balance: doBalance });
  const week = doneThisWeek({ completions, asOf, chores });
  const out = {};
  for (const person of PEOPLE) {
    const items = due[person] ?? [];
    out[person] = {
      streak: streak({ person, chores, completions, asOf, activeFrom, handoffs }),
      week: week[person] ?? 0,
      overdue: items.filter((i) => i.daysOverdue >= 1),
      dueToday: items.filter((i) => i.daysOverdue === 0),
      due: items,
    };
  }
  return out;
}

// ---------------------------------------------------------------------------
// FairnessBalancer — mirror of Packages/RoostCore FairnessBalancer.swift
// Off by default: dueItems/boardStats only balance when callers pass balance: true.
// Integer math only. streak / isDayComplete never balance.
// ---------------------------------------------------------------------------

/** Provisional cadence weights — same knob as FairnessWeights.provisional. */
export const FAIRNESS_WEIGHTS = Object.freeze({ daily: 1, weekly: 3, biweekly: 5, monthly: 8, bimonthly: 10, quarterly: 13 });

/** Trailing Chicago days that count toward load (today included). */
export const FAIRNESS_WINDOW_DAYS = 14;

export function weightFor(cadence) {
  const w = FAIRNESS_WEIGHTS[cadence];
  if (w === undefined) throw new Error(`unknown cadence: ${cadence}`);
  return w | 0;
}

/**
 * Accepted handoff still live for chore+period on asOf, or null.
 * Mirrors HandoffRules.acceptedOverride — used only for isReassignable / balance.
 */
function acceptedHandoffOverride(choreId, periodIdx, handoffs, asOf) {
  const matches = (handoffs ?? []).filter((h) => {
    if (h.choreId !== choreId || h.periodIndex !== periodIdx) return false;
    // R-21: accepted is permanent for its period; pending never overrides.
    return h.state === "accepted";
  });
  if (matches.length === 0) return null;
  matches.sort((a, b) => {
    const at = asDate(a.createdAt).getTime() - asDate(b.createdAt).getTime();
    if (at !== 0) return at;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  return matches[0];
}

function loads(chores, completions, asOf, dropCurrentPeriod) {
  const asOfD = asDate(asOf);
  const lastDay = dayIndex(asOfD);
  const windowStart = dayAt(lastDay - (FAIRNESS_WINDOW_DAYS - 1));
  const windowEnd = dayAt(lastDay + 1);
  const startMs = windowStart.getTime();
  const endMs = windowEnd.getTime();
  const cadenceByChore = new Map(chores.map((c) => [c.id, c.cadence]));
  const together = new Set(chores.filter((c) => c.together).map((c) => c.id));

  const out = Object.fromEntries(PEOPLE.map((p) => [p, 0]));
  for (const completion of completions) {
    const t = asDate(completion.completedAt).getTime();
    if (t < startMs || t >= endMs) continue;
    if (together.has(completion.choreId)) continue;
    const cadence = cadenceByChore.get(completion.choreId);
    if (cadence == null) continue;
    if (dropCurrentPeriod) {
      const itsPeriod = periodIndex(cadence, asDate(completion.completedAt));
      const currentPeriod = periodIndex(cadence, asOfD);
      if (itsPeriod === currentPeriod) continue;
    }
    if (out[completion.person] !== undefined) {
      out[completion.person] = (out[completion.person] + weightFor(cadence)) | 0;
    }
  }
  return out;
}

/** Weighted completions per person over the trailing window (today + 13 days back). */
export function windowLoads({ chores, completions, asOf }) {
  return loads(chores, completions, asOf, false);
}

/**
 * Window loads minus completions inside each chore's current period —
 * those are counted at their own slot in the balance walk instead.
 */
export function backgroundLoads({ chores, completions, asOf }) {
  return loads(chores, completions, asOf, true);
}

/** Whoever finished chore in its current period, or null. Latest completedAt, then id. */
export function currentPeriodFinisher(chore, { completions, asOf }) {
  const asOfD = asDate(asOf);
  const current = periodIndex(chore.cadence, asOfD);
  const candidates = (completions ?? []).filter(
    (c) =>
      c.choreId === chore.id &&
      periodIndex(chore.cadence, asDate(c.completedAt)) === current
  );
  if (candidates.length === 0) return null;
  let best = candidates[0];
  for (let i = 1; i < candidates.length; i++) {
    const c = candidates[i];
    const bt = asDate(best.completedAt).getTime();
    const ct = asDate(c.completedAt).getTime();
    if (ct > bt || (ct === bt && c.id > best.id)) best = c;
  }
  return best.person;
}

/**
 * Whether the balancing pass may move this item.
 * Unpinned, daysOverdue === 0, and no accepted handoff covering it.
 */
export function isReassignable(item, { handoffs = [], asOf } = {}) {
  if (item.chore.fixedAssignee || item.chore.together) return false;
  if (item.chore.rotation || item.chore.missPenalty) return false;
  if ((item.daysOverdue | 0) !== 0) return false;
  return (
    acceptedHandoffOverride(item.chore.id, item.periodIndex, handoffs, asOf) == null
  );
}

/**
 * Spread reassignable items across anne/wes by projected load.
 * Walks `chores` in master-list order. Returns same items, some with person flipped.
 * Integer math only. Tie → keep item's current person (rotation's answer).
 */
export function balance(items, { chores, completions, handoffs = [], asOf }) {
  const projected = backgroundLoads({ chores, completions, asOf });
  const itemByChore = new Map();
  for (const item of items) {
    if (!itemByChore.has(item.chore.id)) itemByChore.set(item.chore.id, item);
  }
  const reassigned = new Map();

  for (const chore of chores) {
    if (chore.together) continue; // owed by both, moved by nobody, weighed by nobody
    const weight = weightFor(chore.cadence);
    const finisher = currentPeriodFinisher(chore, { completions, asOf });
    if (finisher != null) {
      if (projected[finisher] !== undefined) {
        projected[finisher] = (projected[finisher] + weight) | 0;
      }
      continue;
    }
    const item = itemByChore.get(chore.id);
    if (!item) continue;
    if (!isReassignable(item, { handoffs, asOf })) {
      if (projected[item.person] !== undefined) {
        projected[item.person] = (projected[item.person] + weight) | 0;
      }
      continue;
    }

    const anne = projected.anne | 0;
    const wes = projected.wes | 0;
    const owner = anne === wes ? item.person : anne < wes ? "anne" : "wes";
    projected[owner] = (projected[owner] + weight) | 0;
    reassigned.set(dueItemId(item), owner);
  }

  return items.map((item) => {
    const owner = reassigned.get(dueItemId(item));
    if (!owner || owner === item.person) return item;
    return { ...item, person: owner };
  });
}

