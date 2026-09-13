import { test } from "node:test";
import assert from "node:assert/strict";
import {
  chicagoLocal,
  dayIndex,
  dayAt,
  weekBounds,
  periodIndex,
  periodBounds,
  fnv1a,
  rotationAssignee,
  assigneeFor,
  escalationStage,
  dueItemFor,
  dueItems,
  doneThisWeek,
  streak,
  boardStats,
  DEFAULT_ACTIVE_FROM,
  ANCHOR,
  FAIRNESS_WEIGHTS,
  FAIRNESS_WINDOW_DAYS,
  weightFor,
  windowLoads,
  backgroundLoads,
  currentPeriodFinisher,
  isReassignable,
  balance,
} from "../src/rules.js";

const litter = { id: "scoop-litter", title: "Scoop litter", cadence: "daily", fixedAssignee: null, category: "cat_care" };
const toilet = { id: "clean-toilet-bowl", title: "Clean toilet bowl", cadence: "weekly", fixedAssignee: null, category: "chore" };
const garbage = {
  id: "garbage-can-to-street-sunday",
  title: "Garbage can to street, Sunday",
  cadence: "weekly",
  fixedAssignee: "wes",
  category: "chore",
};
const oven = { id: "clean-inside-ovens", title: "Clean inside ovens", cadence: "monthly", fixedAssignee: null, category: "chore" };

const activeFrom = chicagoLocal(2026, 9, 7, 0, 0, 0);
const wed = chicagoLocal(2026, 9, 16, 9, 0, 0);

function done(chore, person, date) {
  return {
    id: `${chore.id}-${date.getTime()}`,
    choreId: chore.id,
    person,
    completedAt: date,
  };
}

// --- Escalation ---

test("escalation ladder", () => {
  assert.equal(escalationStage(0), "dueToday");
  assert.equal(escalationStage(1), "nudge");
  assert.equal(escalationStage(2), "nudge");
  assert.equal(escalationStage(3), "pointed");
  assert.equal(escalationStage(4), "pointed");
  assert.equal(escalationStage(5), "alert");
  assert.equal(escalationStage(30), "alert");
});

// --- Calendar ---

test("anchor is Monday period zero", () => {
  assert.equal(periodIndex("daily", ANCHOR), 0);
  assert.equal(periodIndex("weekly", ANCHOR), 0);
  assert.equal(periodIndex("biweekly", ANCHOR), 0);
  assert.equal(periodIndex("monthly", ANCHOR), 0);
  // 2026-01-05 is a Monday
  const p = new Intl.DateTimeFormat("en-US", { timeZone: "America/Chicago", weekday: "short" }).format(ANCHOR);
  assert.equal(p, "Mon");
});

test("week bounds start Monday Chicago", () => {
  const week = weekBounds(wed);
  assert.equal(week.start.getTime(), chicagoLocal(2026, 9, 14, 0).getTime());
  assert.equal(week.end.getTime(), chicagoLocal(2026, 9, 21, 0).getTime());
  const sunLate = chicagoLocal(2026, 9, 20, 23, 59);
  assert.equal(weekBounds(sunLate).start.getTime(), week.start.getTime());
});

test("DEFAULT_ACTIVE_FROM is Sep 7 Chicago midnight", () => {
  assert.equal(DEFAULT_ACTIVE_FROM.toISOString(), "2026-09-07T05:00:00.000Z");
  assert.equal(activeFrom.getTime(), DEFAULT_ACTIVE_FROM.getTime());
});

// --- Rotation ---

test("round-robin alternates every period and is deterministic", () => {
  const unpinned = { id: "wipe-tables", title: "Wipe down tables", cadence: "daily", fixedAssignee: null };
  const a = rotationAssignee(unpinned.id, 10);
  const b = rotationAssignee(unpinned.id, 11);
  const c = rotationAssignee(unpinned.id, 12);
  assert.notEqual(a, b);
  assert.equal(a, c);
  assert.equal(a, rotationAssignee(unpinned.id, 10));
});

test("pinned assignee beats rotation", () => {
  const pinned = { id: "laundry", title: "Laundry", cadence: "weekly", fixedAssignee: "anne" };
  const unpinned = { id: "wipe-tables", title: "Wipe", cadence: "daily", fixedAssignee: null };
  assert.equal(assigneeFor(pinned, 40), "anne");
  // unpinned uses hash rotation (not always wes)
  assert.ok(["anne", "wes"].includes(assigneeFor(unpinned, 40)));
});

test("fnv1a is stable 64-bit and starting person varies by chore id", () => {
  const h = fnv1a("wipe-tables");
  assert.equal(typeof h, "bigint");
  assert.equal(h, fnv1a("wipe-tables"));
  const ids = [
    "load-dishwasher",
    "scoop-litter",
    "wipe-counters-mirrors",
    "wipe-tables",
    "vacuum-first-floor",
    "vacuum-basement",
    "am-wet-cat-food",
    "pm-wet-cat-food",
    "refill-cat-water",
    "water-plants",
    "general-tidy-reset",
  ];
  const starters = new Set(ids.map((id) => rotationAssignee(id, 0)));
  assert.deepEqual(starters, new Set(["anne", "wes"]));
});

// --- Scheduler ---

test("daily done yesterday is due today with no overdue", () => {
  const yesterday = chicagoLocal(2026, 9, 15, 20);
  const item = dueItemFor(litter, {
    completions: [done(litter, "anne", yesterday)],
    asOf: wed,
    activeFrom,
  });
  assert.equal(item?.daysOverdue, 0);
  assert.equal(item?.stage, "dueToday");
  assert.equal(item?.periodStart.getTime(), chicagoLocal(2026, 9, 16, 0).getTime());
});

test("daily done today is not due", () => {
  const item = dueItemFor(litter, {
    completions: [done(litter, "anne", wed)],
    asOf: wed,
    activeFrom,
  });
  assert.equal(item, null);
});

test("daily missed yesterday carries forward as one day late", () => {
  const twoDaysAgo = chicagoLocal(2026, 9, 14, 20);
  const item = dueItemFor(litter, {
    completions: [done(litter, "wes", twoDaysAgo)],
    asOf: wed,
    activeFrom,
  });
  assert.equal(item?.periodStart.getTime(), chicagoLocal(2026, 9, 15, 0).getTime());
  assert.equal(item?.daysOverdue, 1);
  assert.equal(item?.stage, "nudge");
});

test("never done counts from activeFrom not forever", () => {
  const item = dueItemFor(litter, { completions: [], asOf: wed, activeFrom });
  assert.equal(item?.periodStart.getTime(), activeFrom.getTime());
  assert.equal(item?.daysOverdue, 9);
  assert.equal(item?.stage, "alert");
});

test("weekly missed last week is three days late on Wednesday (pointed)", () => {
  const item = dueItemFor(toilet, { completions: [], asOf: wed, activeFrom });
  assert.equal(item?.periodLastDay.getTime(), chicagoLocal(2026, 9, 13, 0).getTime());
  assert.equal(item?.daysOverdue, 3);
  assert.equal(item?.stage, "pointed");
});

test("weekly done last week is due this week not overdue", () => {
  const lastThu = chicagoLocal(2026, 9, 10, 18);
  const item = dueItemFor(toilet, {
    completions: [done(toilet, "anne", lastThu)],
    asOf: wed,
    activeFrom,
  });
  assert.equal(item?.periodStart.getTime(), chicagoLocal(2026, 9, 14, 0).getTime());
  assert.equal(item?.daysOverdue, 0);
});

test("completing now clears older missed periods", () => {
  const doneLate = chicagoLocal(2026, 9, 23, 12);
  const thu = chicagoLocal(2026, 9, 24, 9);
  assert.equal(
    dueItemFor(toilet, {
      completions: [done(toilet, "wes", doneLate)],
      asOf: thu,
      activeFrom,
    }),
    null
  );
});

test("monthly period overdue after month ends", () => {
  const item = dueItemFor(oven, { completions: [], asOf: wed, activeFrom });
  assert.equal(item?.daysOverdue, 0);
  const oct3 = chicagoLocal(2026, 10, 3, 9);
  assert.equal(dueItemFor(oven, { completions: [], asOf: oct3, activeFrom })?.daysOverdue, 3);
});

test("due by person respects pins and sorts most overdue first", () => {
  const chores = [litter, toilet, garbage, oven];
  const byPerson = dueItems({ chores, completions: [], asOf: wed, activeFrom });
  assert.ok(byPerson.wes.some((i) => i.chore.id === garbage.id));
  assert.ok(!byPerson.anne.some((i) => i.chore.id === garbage.id));
  for (const person of ["anne", "wes"]) {
    const overdue = byPerson[person].map((i) => i.daysOverdue);
    assert.deepEqual(overdue, [...overdue].sort((a, b) => b - a));
  }
  assert.equal([...byPerson.anne, ...byPerson.wes].length, 4);
});

// --- Tallies ---

const anneDaily = {
  id: "am-wet-cat-food",
  title: "AM wet cat food",
  cadence: "daily",
  fixedAssignee: "anne",
  category: "cat_care",
};
const wesDaily = {
  id: "pm-wet-cat-food",
  title: "PM wet cat food",
  cadence: "daily",
  fixedAssignee: "wes",
  category: "cat_care",
};
const weekly = { id: "laundry", title: "Laundry", cadence: "weekly", fixedAssignee: "anne", category: "chore" };
const tallyChores = [anneDaily, wesDaily, weekly];

function c(chore, person, month, day, hour = 12) {
  return {
    id: `${chore.id}-${month}-${day}-${hour}`,
    choreId: chore.id,
    person,
    completedAt: chicagoLocal(2026, month, day, hour),
  };
}

test("week tally starts Monday Chicago", () => {
  const completions = [
    c(anneDaily, "anne", 9, 13, 23), // Sunday before → previous week
    c(anneDaily, "anne", 9, 14, 0), // Monday 00:00 → this week
    c(anneDaily, "anne", 9, 16),
    c(weekly, "anne", 9, 15),
    c(wesDaily, "wes", 9, 15),
    c(wesDaily, "wes", 9, 21, 0), // next Monday → next week
  ];
  const asOf = chicagoLocal(2026, 9, 16, 18);
  const counts = doneThisWeek({ completions, asOf });
  assert.equal(counts.anne, 3);
  assert.equal(counts.wes, 1);
});

test("streak counts complete days; unfinished today does not break", () => {
  let completions = [c(anneDaily, "anne", 9, 13), c(anneDaily, "anne", 9, 14), c(anneDaily, "anne", 9, 15)];
  const wedMorning = chicagoLocal(2026, 9, 16, 9);
  assert.equal(
    streak({ person: "anne", chores: tallyChores, completions, asOf: wedMorning, activeFrom }),
    3,
    "unfinished today does not break"
  );

  completions = [...completions, c(anneDaily, "anne", 9, 16, 8)];
  assert.equal(
    streak({ person: "anne", chores: tallyChores, completions, asOf: wedMorning, activeFrom }),
    4,
    "finished today counts"
  );

  const withGap = completions.filter((x) => {
    if (x.choreId !== anneDaily.id) return true;
    const d = chicagoLocal(2026, 9, 14, 12);
    // drop Sep 14 completion
    return x.completedAt.getTime() !== chicagoLocal(2026, 9, 14, 12).getTime();
  });
  // Rebuild withGap more carefully: remove day 14
  const gapped = completions.filter((x) => !(x.choreId === anneDaily.id && x.id.includes("-9-14-")));
  assert.equal(streak({ person: "anne", chores: tallyChores, completions: gapped, asOf: wedMorning, activeFrom }), 2);

  assert.equal(streak({ person: "wes", chores: tallyChores, completions, asOf: wedMorning, activeFrom }), 0);
});

test("streak does not count before activeFrom", () => {
  const completions = [];
  for (let d = 1; d <= 16; d++) completions.push(c(anneDaily, "anne", 9, d));
  const wedNight = chicagoLocal(2026, 9, 16, 22);
  assert.equal(streak({ person: "anne", chores: tallyChores, completions, asOf: wedNight, activeFrom }), 10);
});

test("dayIndex DST fall-back does not shift", () => {
  const before = chicagoLocal(2026, 10, 31);
  const after = chicagoLocal(2026, 11, 2);
  assert.equal(dayIndex(after) - dayIndex(before), 2);
  assert.equal(dayAt(dayIndex(before)).getTime(), chicagoLocal(2026, 10, 31, 0).getTime());
});

test("monthly bounds for September 2026", () => {
  const sep = periodIndex("monthly", chicagoLocal(2026, 9, 13));
  assert.equal(sep, 8);
  const b = periodBounds("monthly", sep);
  assert.equal(b.firstDay.getTime(), chicagoLocal(2026, 9, 1, 0).getTime());
  assert.equal(b.lastDay.getTime(), chicagoLocal(2026, 9, 30, 0).getTime());
});

// --- FairnessBalancer (R-19) — port of FairnessBalancerTests / FairnessLoadTests ---


const tables = { id: "wipe-tables", title: "Wipe down tables", cadence: "daily", fixedAssignee: null, category: "chore" };
const dishes = { id: "wash-dishes", title: "Wash dishes", cadence: "daily", fixedAssignee: null, category: "chore" };
const water = { id: "water-plants", title: "Water plants", cadence: "daily", fixedAssignee: null, category: "chore" };
const laundry = {
  id: "laundry",
  title: "Laundry",
  cadence: "weekly",
  fixedAssignee: "anne",
  category: "chore",
};
const dailies = [litter, tables, dishes, water];

function fdone(chore, person, day, hour = 12) {
  return {
    id: `${chore.id}-${person}-09-${day}-${hour}`,
    choreId: chore.id,
    person,
    completedAt: chicagoLocal(2026, 9, day, hour),
  };
}

const yesterdayEvenly = [
  fdone(litter, "anne", 15),
  fdone(tables, "anne", 15),
  fdone(dishes, "wes", 15),
  fdone(water, "wes", 15),
];
const yesterdayAllAnne = dailies.map((ch) => fdone(ch, "anne", 15));

function idsOf(plan, person) {
  return new Set((plan[person] ?? []).map((i) => i.chore.id));
}

function holderOf(chore, plan) {
  for (const person of ["anne", "wes"]) {
    if (idsOf(plan, person).has(chore.id)) return person;
  }
  return null;
}

function planBalanced(chores, completions, handoffs = []) {
  return dueItems({ chores, completions, asOf: wed, activeFrom, handoffs, balance: true });
}

function planPlain(chores, completions, handoffs = []) {
  return dueItems({ chores, completions, asOf: wed, activeFrom, handoffs, balance: false });
}

test("fairness provisional weights and window days", () => {
  assert.deepEqual(FAIRNESS_WEIGHTS, { daily: 1, weekly: 3, biweekly: 5, monthly: 8 });
  assert.equal(FAIRNESS_WINDOW_DAYS, 14);
  assert.equal(weightFor("daily"), 1);
  assert.equal(weightFor("weekly"), 3);
  assert.equal(weightFor("biweekly"), 5);
  assert.equal(weightFor("monthly"), 8);
});

test("windowLoads: weekly outweighs two dailies", () => {
  const chores = [toilet, litter, tables];
  const completions = [fdone(toilet, "anne", 10), fdone(litter, "wes", 14), fdone(tables, "wes", 15)];
  assert.deepEqual(windowLoads({ chores, completions, asOf: wed }), { anne: 3, wes: 2 });
});

test("windowLoads: fourteen-day window drops older completions", () => {
  assert.equal(
    windowLoads({
      chores: [litter, tables],
      completions: [fdone(litter, "anne", 3, 0)],
      asOf: wed,
    }).anne,
    1,
    "Sep 3 00:00 is the first day counted"
  );
  assert.equal(
    windowLoads({
      chores: [litter, tables],
      completions: [fdone(litter, "anne", 2, 23)],
      asOf: wed,
    }).anne,
    0,
    "Sep 2 is outside the window"
  );
});

test("backgroundLoads leaves out the current period", () => {
  const chores = [litter, tables];
  const completions = [fdone(litter, "anne", 15), fdone(tables, "anne", 16, 8)];
  assert.equal(windowLoads({ chores, completions, asOf: wed }).anne, 2);
  assert.equal(backgroundLoads({ chores, completions, asOf: wed }).anne, 1);
});

test("windowLoads ignores unknown chore ids", () => {
  const ghost = { id: "not-on-the-list", title: "Ghost", cadence: "monthly", fixedAssignee: null, category: "chore" };
  assert.deepEqual(
    windowLoads({
      chores: [litter, tables],
      completions: [fdone(ghost, "anne", 15)],
      asOf: wed,
    }),
    { anne: 0, wes: 0 }
  );
});

test("balance splits the period instead of handing it all to one person", () => {
  const plan = planBalanced(dailies, yesterdayEvenly);
  assert.deepEqual(windowLoads({ chores: dailies, completions: yesterdayEvenly, asOf: wed }), {
    anne: 2,
    wes: 2,
  });
  assert.equal(plan.anne.length, 2);
  assert.equal(plan.wes.length, 2);
  const allIds = new Set([...idsOf(plan, "anne"), ...idsOf(plan, "wes")]);
  assert.deepEqual(allIds, new Set(dailies.map((c) => c.id)));

  const permutations = [
    [3, 2, 1, 0],
    [2, 0, 3, 1],
    [1, 3, 0, 2],
  ];
  for (const order of permutations) {
    const shuffled = order.map((i) => yesterdayEvenly[i]);
    assert.deepEqual(
      planBalanced(dailies, shuffled),
      plan,
      `row order ${order} changed the plan`
    );
  }
});

test("balance: a level tie goes to the rotation's answer", () => {
  const period = periodIndex("daily", wed);
  assert.notEqual(
    rotationAssignee(litter.id, period),
    rotationAssignee(dishes.id, period),
    "fixture must cover a tie breaking both ways"
  );
  const completions = [fdone(litter, "anne", 15), fdone(dishes, "wes", 15)];
  for (const chores of [
    [litter, dishes],
    [dishes, litter],
  ]) {
    const first = chores[0];
    assert.deepEqual(backgroundLoads({ chores, completions, asOf: wed }), { anne: 1, wes: 1 });
    const plan = planBalanced(chores, completions);
    assert.equal(holderOf(first, plan), rotationAssignee(first.id, period));
    const other = rotationAssignee(first.id, period) === "anne" ? "wes" : "anne";
    assert.equal(holderOf(chores[1], plan), other);
  }
});

test("balance: finishing one item leaves every other item where it was", () => {
  const before = planBalanced(dailies, yesterdayEvenly);
  for (const chore of [litter, water]) {
    const owner = holderOf(chore, before);
    assert.ok(owner, `${chore.id} is due before it is done`);
    const after = planBalanced(dailies, [...yesterdayEvenly, fdone(chore, owner, 16, 11)]);
    assert.equal(holderOf(chore, after), null);
    for (const person of ["anne", "wes"]) {
      const expected = new Set(idsOf(before, person));
      expected.delete(chore.id);
      assert.deepEqual(idsOf(after, person), expected);
    }
  }
});

test("balance: overdue items are never moved", () => {
  const chores = [oven, ...dailies];
  const completions = [fdone(oven, "anne", 14)];
  const balanced = planBalanced(chores, completions);
  const plain = planPlain(chores, completions);
  assert.deepEqual(balanced, plain);
  assert.ok([...balanced.anne, ...balanced.wes].every((i) => i.daysOverdue >= 1));
  assert.deepEqual(windowLoads({ chores, completions, asOf: wed }), { anne: 8, wes: 0 });
});

test("balance: pinned and handed-off items are never touched", () => {
  // Items already assigned as FixedRotation(anne) + accepted handoff would produce:
  // laundry→anne (pin), toilet→wes (handoff), litter/tables→anne (rotation fixed).
  const chores = [laundry, toilet, litter, tables];
  const completions = [
    fdone(laundry, "anne", 10),
    fdone(toilet, "anne", 10),
    fdone(litter, "anne", 15),
    fdone(tables, "anne", 15),
  ];
  const week = periodIndex("weekly", wed);
  const accepted = {
    id: "h1",
    choreId: toilet.id,
    from: "anne",
    to: "wes",
    periodIndex: week,
    cadence: "weekly",
    createdAt: wed,
    state: "accepted",
  };
  // Build items with persons as scheduler+handoff would (R-18); balance only.
  const items = [
    {
      chore: laundry,
      person: "anne",
      periodIndex: week,
      periodStart: periodBounds("weekly", week).firstDay,
      periodLastDay: periodBounds("weekly", week).lastDay,
      daysOverdue: 0,
      stage: "dueToday",
    },
    {
      chore: toilet,
      person: "wes",
      periodIndex: week,
      periodStart: periodBounds("weekly", week).firstDay,
      periodLastDay: periodBounds("weekly", week).lastDay,
      daysOverdue: 0,
      stage: "dueToday",
    },
    dueItemFor(litter, { completions, asOf: wed, activeFrom }),
    dueItemFor(tables, { completions, asOf: wed, activeFrom }),
  ].map((item) =>
    item.chore.id === litter.id || item.chore.id === tables.id ? { ...item, person: "anne" } : item
  );

  assert.equal(isReassignable(items[0], { handoffs: [accepted], asOf: wed }), false, "pinned");
  assert.equal(isReassignable(items[1], { handoffs: [accepted], asOf: wed }), false, "handoff");
  assert.equal(isReassignable(items[2], { handoffs: [accepted], asOf: wed }), true);

  const balanced = balance(items, { chores, completions, handoffs: [accepted], asOf: wed });
  const byPerson = { anne: [], wes: [] };
  for (const item of balanced) byPerson[item.person].push(item.chore.id);
  assert.deepEqual(new Set(byPerson.anne), new Set([laundry.id]));
  assert.deepEqual(new Set(byPerson.wes), new Set([toilet.id, litter.id, tables.id]));
});

test("balance: absent person's column stops growing", () => {
  const his = Array.from({ length: 8 }, (_, i) => ({
    id: `wes-chore-${i + 1}`,
    title: `Wes chore ${i + 1}`,
    cadence: "daily",
    fixedAssignee: "wes",
    category: "chore",
  }));
  const chores = [...his, ...dailies];
  const plan = planBalanced(chores, yesterdayAllAnne);
  assert.deepEqual(windowLoads({ chores, completions: yesterdayAllAnne, asOf: wed }), {
    anne: 4,
    wes: 0,
  });
  assert.deepEqual(idsOf(plan, "anne"), new Set(dailies.map((c) => c.id)));
  assert.deepEqual(idsOf(plan, "wes"), new Set(his.map((c) => c.id)));

  const evened = planBalanced([his[0], ...dailies], yesterdayAllAnne);
  const wesIds = idsOf(evened, "wes");
  assert.ok([his[0].id, litter.id, tables.id, dishes.id].every((id) => wesIds.has(id)));
  const anneIds = idsOf(evened, "anne");
  assert.ok([...anneIds].every((id) => id === water.id));
});

test("dueItems/boardStats balance defaults off; streak never balances", () => {
  const plain = planPlain(dailies, yesterdayAllAnne);
  const roundRobinPeople = {};
  for (const chore of dailies) {
    const item = dueItemFor(chore, { completions: yesterdayAllAnne, asOf: wed, activeFrom });
    roundRobinPeople[chore.id] = item.person;
    assert.equal(holderOf(chore, plain), item.person);
  }
  const balanced = planBalanced(dailies, yesterdayAllAnne);
  assert.deepEqual(idsOf(balanced, "wes"), new Set(dailies.map((c) => c.id)));

  const statsOff = boardStats({ chores: dailies, completions: yesterdayAllAnne, asOf: wed, activeFrom });
  assert.equal(statsOff.wes.due.length + statsOff.anne.due.length, 4);
  // default off: same split as plain rotation
  assert.equal(statsOff.anne.due.length, plain.anne.length);
  assert.equal(statsOff.wes.due.length, plain.wes.length);

  const statsOn = boardStats({
    chores: dailies,
    completions: yesterdayAllAnne,
    asOf: wed,
    activeFrom,
    balance: true,
  });
  assert.equal(statsOn.wes.due.length, 4);

  // streak uses plain rotation assignment, not balance
  const sAnne = streak({ person: "anne", chores: dailies, completions: yesterdayAllAnne, asOf: wed, activeFrom });
  const sWes = streak({ person: "wes", chores: dailies, completions: yesterdayAllAnne, asOf: wed, activeFrom });
  assert.equal(typeof sAnne, "number");
  assert.equal(typeof sWes, "number");
});

test("currentPeriodFinisher picks latest completedAt then id", () => {
  const early = fdone(litter, "anne", 16, 8);
  const late = fdone(litter, "wes", 16, 10);
  assert.equal(currentPeriodFinisher(litter, { completions: [early, late], asOf: wed }), "wes");
  const a = { ...early, id: "a-id", person: "anne" };
  const b = { ...early, id: "b-id", person: "wes" };
  assert.equal(currentPeriodFinisher(litter, { completions: [a, b], asOf: wed }), "wes");
  assert.equal(currentPeriodFinisher(litter, { completions: yesterdayEvenly, asOf: wed }), null);
});
