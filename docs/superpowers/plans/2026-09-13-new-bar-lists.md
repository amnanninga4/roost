# New Bar, Lists, Wishlist, and Project Dates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four-tab bar with Tasks · Lists · More, gather Shopping, Meals, Projects and a new Wishlist under Lists, move the gear menu onto a More page, and give projects an optional due day and steps an optional owner, on the server and in the app.

**Architecture:** The Wishlist is Shopping with a price: a new server table and three routes, a new SwiftData record and DTO, and one more loop in each of the sync engine's replay and delta passes, all following the Shopping code line for line. The bar is a three-case `RootTab`; the Lists tab is one container (segmented control over a paged `TabView`) that applies the list chrome once and hosts the four existing page bodies; More is a plain grouped list. The two project fields are nullable columns added through the server's versioned migration and two optional SwiftData properties.

**Tech Stack:** SwiftUI + SwiftData on iOS 26 (`xcodebuild test`), XCUITest audits, Node 22 with `node:sqlite` and `node:test` (`npm test`), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-09-13-new-bar-lists-design.md` (read it first; this plan argues from it and does not restate the reasons).

## Global Constraints

- `main` takes pull requests only. Rebase onto current `main` before opening one. Never merge your own PR.
- User-facing strings live in `Roost/Sources/Strings.swift`. Plain wording, no marketing copy.
- No secrets in the repo: no Team ID, certificates, provisioning profiles, APNs keys, device tokens.
- The Xcode project is generated: a new Swift file under `Roost/Sources`, `Roost/Tests` or `Roost/UITests` needs `cd Roost && xcodegen generate` and the regenerated `Roost/Roost.xcodeproj/project.pbxproj` committed. Never hand-edit the pbxproj.
- Swift is formatted by swiftformat and linted by swiftlint through the committed hook in `.claude/hooks`; commit what the hook leaves.
- Server: Node 22, built-in sqlite, **no dependencies**. `cd server && npm test` must pass with no network.
- Before calling app work done: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` prints `** TEST SUCCEEDED **`, and any screen you changed has been rendered in the simulator and looked at.
- Every colour is a `RoostColor.Role`, every size a `RoostType` rung, every gap a `RoostSpacing` step: no hex, no point sizes, no loose numbers in a screen file.
- The bar: `RootTab { tasks, lists, more }`; symbols `checklist`, `list.bullet.rectangle`, `ellipsis.circle`. Nothing reserves a slot for Calendar.
- Lists pages, in order: Shopping, Meals, Projects, Wishlist; symbols `cart`, `fork.knife`, `hammer`, `gift`; the chosen page is remembered in `AppStorage` under `roost.lists.page`.
- Wishlist price: integer cents, `nil` or `0...99_999_999`, server `CHECK (priceCents IS NULL OR priceCents BETWEEN 0 AND 99999999)`; header "4 items · $1,850 total", total omitted when no open item has a price; sorted newest first.
- `/sync` gains a `wishlist` array; the cursor arithmetic includes it; the README's "seven sync tables" becomes eight.
- `projects.dueOn` is `YYYY-MM-DD` (America/Chicago calendar day) or null; `project_subtasks.assignee` is `anne`, `wes` or null. Both accepted on POST and PATCH, both returned in the row shape.
- The gear menu is gone: `Strings.Tasks.gear` is deleted; the unpaired line reads "Not paired yet · More → Settings".
- Server lane (R-30) runs **after R-29 is merged**: it adds schema version 3 on top of R-29's `migrate`. Deploy the server before the app build goes on a phone.

---

## Lanes and order

| Lane | Tasks | Who | Test command |
|---|---|---|---|
| S — server (ticket R-30) | 1–3 | the server worker, after R-29 merges | `cd server && npm test` |
| A1 — Wishlist, the bar, More | 4–8 | an app-side agent | the `xcodebuild … test` line above |
| A2 — project due day, step owner, the reminder, fixtures and docs | 9–12 | an app-side agent, after A1 merges | the same |

A1 needs nothing from S: its sync tests run against stubs shaped like the server's rows. S must be deployed before an A1 build goes on a phone, or the wishlist POSTs come back 404 and the rows sit rejected. Branches: `server/r30-wishlist-project-fields`, `app/wishlist-and-bar`, `app/project-dates-owners`. Commit after every task.

## File structure

**Server (lane S)**
- Modify `server/src/db.js` — `wishlist_items` table and its four functions; `listsAfter` gains `wishlist`; `projects.dueOn` and `project_subtasks.assignee` in the schema string, `migrateToV3`, `insertProject` / `patchProject` / `insertSubtask` / `patchSubtask` take the new fields.
- Modify `server/src/app.js` — `shapeWishlist`, the three `/wishlist` routes, `wishlist` in `/sync` and its cursor; `validPrice`, `validDay`, `validPerson`; `dueOn` on the project routes, `assignee` on the subtask routes; the header comment.
- Tests: `server/test/lists.test.js`, `server/test/migrate.test.js`. Docs: `server/README.md`.

**App, lane A1**
- Modify `Roost/Sources/Models/ListRecords.swift` — `PatchFields.price`, `WishlistItemRecord`.
- Modify `Roost/Sources/Models/Records.swift` — `RoostSchema.models` gains the record.
- Modify `Roost/Sources/Models/ListActions.swift` — the wishlist actions.
- Modify `Roost/Sources/Models/ListPresentation.swift` — `PriceParser`, `PriceFormat`, `WishlistTotals`.
- Modify `Roost/Sources/Sync/SyncAPI.swift` — `SyncResponse.wishlist`.
- Modify `Roost/Sources/Sync/SyncAPI+Lists.swift` — `WishlistDTO`, `postWishlist` / `patchWishlist` / `deleteWishlist`.
- Modify `Roost/Sources/Sync/ListSync+Records.swift` — the record's `init(dto:)` / `apply` / `patchBody`.
- Modify `Roost/Sources/Sync/ListSync.swift` — the wishlist loops in creates, edits, removals, delta.
- Create `Roost/Sources/Screens/WishlistScreen.swift` — the page.
- Create `Roost/Sources/Screens/ListsScreen.swift` — `ListPage`, the segmented control, the paged `TabView`.
- Create `Roost/Sources/Screens/MoreScreen.swift` — the More page.
- Modify `Roost/Sources/Root/RootTabView.swift`, `Roost/Sources/Screens/ShoppingScreen.swift`, `MealsScreen.swift`, `ProjectsScreen.swift` (drop their own stack and chrome), `TodayScreen.swift` (drop the gear), `SettingsScreen.swift` (pushed, `AppVersion`), `Roost/Sources/Strings.swift`.
- Modify `Roost/Sources/Debug/UITestSeed.swift` — two wishlist rows.
- Tests: `Roost/Tests/RootTabsTests.swift`, `Roost/Tests/ListSyncTestCase.swift`, `Roost/Tests/TodayBoardTests.swift`, new `Roost/Tests/WishlistCraftTests.swift`, new `Roost/Tests/WishlistSyncTests.swift`, `Roost/UITests/RoostUITestCase.swift`, `Roost/UITests/AccessibilityAuditTests.swift`, `Roost/UITests/ScrollPerformanceTests.swift`, new `Roost/UITests/ListsBehaviourTests.swift`.
- Docs: `Roost/README.md`, `NOTES.md`, root `README.md`.

**App, lane A2**
- Modify `ListRecords.swift` (`ProjectRecord.dueOn`, `SubtaskRecord.assignee`, two `PatchFields` bits), `ListActions.swift` (`setDueOn`, `setAssignee`, `addSubtask(assignee:)`, the restore copies), `ListPresentation.swift` (`ProjectDates`), `SyncAPI+Lists.swift` (`ProjectDTO.dueOn`, `SubtaskDTO.assignee`, `postSubtask(assignee:)`), `ListSync+Records.swift`, `ListSync.swift` (the 201 flag sets), `ProjectsScreen.swift` (the due line, the card menu and picker sheet, the owner avatar and menus), `Strings.swift`, `Roost/Sources/Notifications/NotificationPlanner.swift` and `NotificationScheduler.swift`, `UITestSeed.swift`.
- Tests: `Roost/Tests/ListCraftTests.swift`, new `Roost/Tests/ProjectFieldsSyncTests.swift`, `Roost/Tests/NotificationTests.swift`, `Roost/Tests/ListSyncTestCase.swift`.
- Docs: `Roost/README.md`, `NOTES.md`.

---

## Lane S — server (ticket R-30)

Everything here is `server/`. R-29 is merged first, so `db.js` already has `SCHEMA_VERSION`, `migrate(db)`, `columnNames(db, table)` and `migrateToV2(db)`.

### Task 1: The wishlist table, its routes, and its place in `/sync`

**Files:**
- Modify: `server/src/db.js` (the `SCHEMA` string after `project_subtasks`; the lists section; `listsAfter`)
- Modify: `server/src/app.js` (header comment; imports; the constants after `SORT_MAX`; `shapeWishlist` after `shapeShopping`; routes after the shopping block; the `/sync` handler)
- Test: `server/test/lists.test.js`

**Interfaces:**
- Produces (db.js): `getWishlistItem(db, id)`, `insertWishlistItem(db, { id, title, priceCents, addedBy }, now) -> { row, created }`, `patchWishlistItem(db, id, { title, priceCents, bought }, person, now) -> row | null`, `deleteWishlistItem(db, id, now) -> row | null`; `listsAfter(db, cursor)` returns `{ shopping, meals, projects, subtasks, wishlist }`.
- Produces (HTTP): `POST /wishlist { id, title, priceCents? }` → 201/200 with `{ id, title, priceCents, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, deleted, seq }`; `PATCH /wishlist/:id { title?, priceCents?, bought? }` (`priceCents: null` clears); `DELETE /wishlist/:id`; `/sync` carries `wishlist: [...]` and its seqs count toward `cursor`.

- [ ] **Step 1: Write the failing tests**

In `lists.test.js`, change the first test so it knows the fifth table:

```js
test("lists start empty and need auth", async () => {
  for (const t of ["shopping_items", "meals", "projects", "project_subtasks", "wishlist_items"]) assert.equal(count(t), 0, t);
  assert.equal((await call("POST", "/shopping", { body: { id: "s", title: "x" } })).status, 401);
  assert.equal((await call("POST", "/wishlist", { body: { id: "w", title: "x" } })).status, 401);
  assert.equal((await call("PATCH", "/meals/m", { body: { title: "x" } })).status, 401);
  assert.equal((await call("DELETE", "/projects/p")).status, 401);
  const sync = await call("GET", "/sync?choresVersion=1", { token: ANNE });
  assert.equal(sync.status, 200);
  assert.deepEqual([sync.body.shopping, sync.body.meals, sync.body.projects, sync.body.subtasks, sync.body.wishlist], [[], [], [], [], []]);
  assert.equal(sync.body.cursor, 0);
});
```

Add, after the "meals validation" test:

```js
test("wishlist: create with and without a price, replay, price patch and clear, bought stamps, delete, validation", async () => {
  tick();
  const tv = await call("POST", "/wishlist", { token: ANNE, body: { id: "w-1", title: "Bigger TV", priceCents: 59900 } });
  assert.equal(tv.status, 201);
  assert.equal(tv.body.priceCents, 59900);
  assert.equal(tv.body.addedBy, "anne");
  assert.equal(tv.body.bought, false);
  assert.equal(tv.body.boughtBy, null);
  assert.equal(tv.body.deleted, false);
  const trip = await call("POST", "/wishlist", { token: WES, body: { id: "w-2", title: "A weekend away" } });
  assert.equal(trip.status, 201);
  assert.equal(trip.body.priceCents, null, "no price is null, not zero");
  const replay = await call("POST", "/wishlist", { token: WES, body: { id: "w-1", title: "Changed", priceCents: 1 } });
  assert.equal(replay.status, 200);
  assert.deepEqual(replay.body, tv.body, "replay returns the original row unchanged");

  tick();
  const repriced = await call("PATCH", "/wishlist/w-1", { token: WES, body: { priceCents: 54999 } });
  assert.equal(repriced.status, 200);
  assert.equal(repriced.body.priceCents, 54999);
  assert.equal(repriced.body.title, "Bigger TV", "a price patch leaves the title alone");
  const cleared = await call("PATCH", "/wishlist/w-1", { token: WES, body: { priceCents: null } });
  assert.equal(cleared.body.priceCents, null, "a price can be cleared");
  const bought = await call("PATCH", "/wishlist/w-1", { token: WES, body: { bought: true } });
  assert.equal(bought.body.bought, true);
  assert.equal(bought.body.boughtBy, "wes");
  assert.equal(bought.body.boughtAt, clock.toISOString());
  const again = await call("PATCH", "/wishlist/w-1", { token: ANNE, body: { bought: true } });
  assert.equal(again.body.boughtBy, "wes", "re-sending bought=true keeps the first stamp");
  const unbought = await call("PATCH", "/wishlist/w-1", { token: ANNE, body: { bought: false } });
  assert.deepEqual([unbought.body.bought, unbought.body.boughtBy, unbought.body.boughtAt], [false, null, null]);

  const post = (body) => call("POST", "/wishlist", { token: WES, body });
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: -1 })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: 100_000_000 })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: 12.5 })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "x", priceCents: "599" })).status, 400);
  assert.equal((await post({ id: "w-bad", title: "" })).status, 400);
  assert.equal((await post({ title: "no id" })).status, 400);
  assert.equal((await post({ id: "w-max", title: "x", priceCents: 99_999_999 })).status, 201, "the ceiling is allowed");
  assert.equal((await post({ id: "w-zero", title: "free", priceCents: 0 })).status, 201, "zero is a price");
  const patch = (body) => call("PATCH", "/wishlist/w-1", { token: WES, body });
  assert.equal((await patch({})).status, 400, "empty patch");
  assert.equal((await patch({ priceCents: "x" })).status, 400);
  assert.equal((await patch({ bought: "yes" })).status, 400);
  assert.equal((await patch({ title: "" })).status, 400);
  assert.equal((await call("PATCH", "/wishlist/never", { token: WES, body: { title: "x" } })).status, 404);
  assert.equal((await call("DELETE", "/wishlist/never", { token: WES })).status, 404);
  assert.equal(count("wishlist_items"), 4, "nothing created by the rejected requests");

  const del = await call("DELETE", "/wishlist/w-2", { token: WES });
  assert.equal(del.status, 200);
  assert.equal(del.body.deleted, true);
  assert.equal((await call("DELETE", "/wishlist/w-2", { token: WES })).body.seq, del.body.seq, "delete is idempotent");
  assert.equal((await call("PATCH", "/wishlist/w-2", { token: WES, body: { title: "x" } })).status, 404, "deleted row is gone for PATCH");
  assert.equal((await call("POST", "/wishlist", { token: WES, body: { id: "w-2", title: "back?" } })).body.deleted, true, "no resurrection");
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});
```

In the last test ("/sync carries all four arrays…"), rename it "/sync carries all five list arrays…" and make every list of keys five long:

```js
  for (const key of ["completions", "shopping", "meals", "projects", "subtasks", "wishlist"]) assert.ok(Array.isArray(full.body[key]), key);
```
```js
  assert.ok(full.body.wishlist.some((w) => w.deleted));
  const allSeqs = ["shopping", "meals", "projects", "subtasks", "wishlist"].flatMap((k) => full.body[k]).map((r) => r.seq);
```
```js
  assert.deepEqual([idle.body.shopping, idle.body.meals, idle.body.projects, idle.body.subtasks, idle.body.wishlist, idle.body.completions], [[], [], [], [], [], []]);
```
```js
  assert.deepEqual([delta.body.meals, delta.body.projects, delta.body.subtasks, delta.body.wishlist, delta.body.completions], [[], [], [], [], []]);
```

and in the "delta touching every table" block add one wishlist write and one expectation:

```js
  await call("POST", "/wishlist", { token: WES, body: { id: "w-sync", title: "Kayak", priceCents: 89900 } });
```
```js
      wishlist: mixed.body.wishlist.map((r) => r.id),
```
```js
    { shopping: [], meals: ["m-sync"], projects: ["p-sync"], subtasks: ["st-sync"], completions: ["c-sync"], wishlist: ["w-sync"] }
  );
  assert.equal(mixed.body.cursor, c2 + 5);
```

- [ ] **Step 2: Run to see them fail**

Run: `cd server && node --test test/lists.test.js 2>&1 | tail -20`
Expected: `no such table: wishlist_items`, then `404` where `201` was expected.

- [ ] **Step 3: Implement**

`db.js`, in `SCHEMA` after the `project_subtasks_project` index:

```sql
CREATE TABLE IF NOT EXISTS wishlist_items (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  priceCents INTEGER CHECK (priceCents IS NULL OR priceCents BETWEEN 0 AND 99999999),
  addedBy    TEXT NOT NULL CHECK (addedBy IN (${PEOPLE_SQL})),
  bought     INTEGER NOT NULL DEFAULT 0 CHECK (bought IN (0,1)),
  boughtBy   TEXT CHECK (boughtBy IN (${PEOPLE_SQL})),
  boughtAt   TEXT,
  createdAt  TEXT NOT NULL,
  updatedAt  TEXT NOT NULL,
  deletedAt  TEXT,
  seq        INTEGER NOT NULL UNIQUE
);
```

Add `const WISHLIST = "wishlist_items";` next to the other table constants, and after the shopping functions:

```js
// --- wishlist ---

export function getWishlistItem(db, id) {
  return rowById(db, WISHLIST, id);
}

/** `priceCents` is null or 0..99,999,999 (the route validates; the CHECK is the backstop). */
export function insertWishlistItem(db, { id, title, priceCents = null, addedBy }, now) {
  return insertRow(db, WISHLIST, id, { title, priceCents, addedBy, bought: 0, boughtBy: null, boughtAt: null }, now);
}

/**
 * { title?, priceCents?, bought? }. `priceCents: null` clears the price. `bought` stamps and clears
 * exactly as a shopping item does.
 */
export function patchWishlistItem(db, id, { title, priceCents, bought }, person, now) {
  const existing = getWishlistItem(db, id);
  if (!existing || existing.deletedAt) return null;
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (priceCents !== undefined) fields.priceCents = priceCents;
  if (bought === true && !existing.bought) Object.assign(fields, { bought: 1, boughtBy: person, boughtAt: now });
  if (bought === false) Object.assign(fields, { bought: 0, boughtBy: null, boughtAt: null });
  return patchRow(db, WISHLIST, id, fields, now);
}

export function deleteWishlistItem(db, id, now) {
  return deleteRow(db, WISHLIST, id, now);
}
```

`listsAfter`:

```js
export function listsAfter(db, cursor) {
  const after = (table) => db.prepare(`SELECT * FROM ${table} WHERE seq > ? ORDER BY seq`).all(cursor);
  return {
    shopping: after(SHOPPING),
    meals: after(MEALS),
    projects: after(PROJECTS),
    subtasks: after(SUBTASKS),
    wishlist: after(WISHLIST),
  };
}
```

Update the file's top comment: "(completions, shopping items, meals, projects, subtasks, wishlist items, handoffs)".

`app.js`: add the four functions to the `./db.js` import list (`insertWishlistItem, patchWishlistItem, deleteWishlistItem`), add the header lines

```
//   POST   /wishlist                      { id, title, priceCents? } -> 201 new / 200 replay; addedBy from token
//   PATCH  /wishlist/:id                  { title?, priceCents?, bought? }; priceCents=null clears it; bought as /shopping
//   DELETE /wishlist/:id                  soft delete -> 200 (idempotent)
```

and `wishlist` to the `/sync` line's list of deltas. After `SORT_MAX`:

```js
const WISHLIST_RE = new RegExp(`^/wishlist/${ID_PART}$`);
const PRICE_MAX = 99_999_999;
const PRICE_ERROR = `priceCents must be null or an integer 0-${PRICE_MAX}`;
/** Whole cents, or null for "no price". */
const validPrice = (v) => v === null || (Number.isInteger(v) && v >= 0 && v <= PRICE_MAX);
```

After `shapeShopping`:

```js
  function shapeWishlist(row) {
    return {
      id: row.id,
      title: row.title,
      priceCents: row.priceCents ?? null,
      addedBy: row.addedBy,
      bought: !!row.bought,
      boughtBy: row.boughtBy,
      boughtAt: row.boughtAt,
      ...stamp(row),
    };
  }
```

After the shopping routes:

```js
    // --- wishlist ---

    if (req.method === "POST" && path === "/wishlist") {
      const body = await readJson(req);
      if (!validId(body.id)) return send(res, 400, { error: ID_ERROR });
      if (!validTitle(body.title)) return send(res, 400, { error: `title required: 1-${TITLE_MAX} chars` });
      if (has(body, "priceCents") && !validPrice(body.priceCents)) return send(res, 400, { error: PRICE_ERROR });
      const { row, created } = insertWishlistItem(
        db,
        { id: body.id, title: body.title, priceCents: body.priceCents ?? null, addedBy: device.person },
        iso()
      );
      return send(res, created ? 201 : 200, shapeWishlist(row));
    }

    const wishlist = WISHLIST_RE.exec(path);
    if (req.method === "PATCH" && wishlist) {
      const body = await readJson(req);
      const patch = pickPatch(body, { title: validTitle, priceCents: validPrice, bought: isBool });
      const row = patchWishlistItem(db, wishlist[1], patch, device.person, iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeWishlist(row));
    }
    if (req.method === "DELETE" && wishlist) {
      const row = deleteWishlistItem(db, wishlist[1], iso());
      if (!row) return send(res, 404, { error: "not found" });
      return send(res, 200, shapeWishlist(row));
    }
```

In `/sync`: the `maxSeq` array becomes `[rows, lists.shopping, lists.meals, lists.projects, lists.subtasks, lists.wishlist]`, and `out` gains `wishlist: lists.wishlist.map(shapeWishlist),` after `subtasks`.

- [ ] **Step 4: Run the whole suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add server/src/db.js server/src/app.js server/test/lists.test.js
git commit -m "server: wishlist_items table, /wishlist routes, wishlist in /sync"
```

### Task 2: `projects.dueOn` and `project_subtasks.assignee` (schema version 3)

**Files:**
- Modify: `server/src/db.js` (`SCHEMA_VERSION`, `migrate`, the two table definitions, `insertProject`, `patchProject`, `insertSubtask`, `patchSubtask`)
- Modify: `server/src/app.js` (constants; `shapeProject`, `shapeSubtask`; the four project/subtask routes)
- Test: `server/test/migrate.test.js`, `server/test/lists.test.js`

**Interfaces:**
- Produces: `SCHEMA_VERSION = 3`; `migrateToV3(db)` adds the two nullable columns to an existing database; `insertProject(db, { id, title, dueOn = null, subtasks = [] }, now)`; `patchProject(db, id, { title, dueOn }, now)`; `insertSubtask(db, { id, projectId, title, sortOrder, assignee = null }, now)`; `patchSubtask(db, id, { title, done, sortOrder, assignee }, person, now)`; row shapes carry `dueOn: string | null` and `assignee: "anne" | "wes" | null`; `POST /projects { …, dueOn? }`, `PATCH /projects/:id { title?, dueOn? }`, `POST /projects/:id/subtasks { …, assignee? }`, `PATCH /subtasks/:id { …, assignee? }`; malformed values are 400.

- [ ] **Step 1: Write the failing tests**

`migrate.test.js`: change the two literal `"2"` version assertions in the existing tests to `String(SCHEMA_VERSION)`, and add:

```js
test("a version-2 database gains projects.dueOn and project_subtasks.assignee and records version 3", () => {
  const dir = mkdtempSync(join(tmpdir(), "roost-migrate-v3-"));
  try {
    const path = join(dir, "v2.db");
    const raw = new DatabaseSync(path);
    raw.exec(`
      CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      INSERT INTO meta VALUES ('seq', '2'), ('schemaVersion', '2');
      CREATE TABLE projects (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, createdAt TEXT NOT NULL, updatedAt TEXT NOT NULL,
        deletedAt TEXT, seq INTEGER NOT NULL UNIQUE
      );
      CREATE TABLE project_subtasks (
        id TEXT PRIMARY KEY, projectId TEXT NOT NULL REFERENCES projects(id), title TEXT NOT NULL,
        sortOrder INTEGER NOT NULL, done INTEGER NOT NULL DEFAULT 0 CHECK (done IN (0,1)),
        doneBy TEXT CHECK (doneBy IN ('anne','wes')), doneAt TEXT, createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL, deletedAt TEXT, seq INTEGER NOT NULL UNIQUE
      );
      INSERT INTO projects VALUES ('p1', 'Fence', 'x', 'x', NULL, 1);
      INSERT INTO project_subtasks VALUES ('s1', 'p1', 'Posts', 0, 0, NULL, NULL, 'x', 'x', NULL, 2);
    `);
    raw.close();

    const db = openDb(path);
    assert.equal(getMeta(db, "schemaVersion"), "3");
    assert.ok(columns(db, "projects").includes("dueOn"));
    assert.ok(columns(db, "project_subtasks").includes("assignee"));
    assert.equal(db.prepare("SELECT dueOn FROM projects WHERE id = 'p1'").get().dueOn, null);
    assert.equal(db.prepare("SELECT assignee FROM project_subtasks WHERE id = 's1'").get().assignee, null);
    db.prepare("UPDATE project_subtasks SET assignee = 'wes' WHERE id = 's1'").run();
    assert.throws(() => db.prepare("UPDATE project_subtasks SET assignee = 'bob' WHERE id = 's1'").run(), /CHECK/);
    assert.equal(db.prepare("SELECT seq FROM project_subtasks WHERE id = 's1'").get().seq, 2, "rows untouched");
    db.close();

    const again = openDb(path);
    assert.equal(getMeta(again, "schemaVersion"), "3", "opening again is a no-op");
    again.close();
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
```

`lists.test.js`, after the "projects validation" test:

```js
test("projects: dueOn is a calendar day, accepted on create and patch, cleared with null, rejected when malformed", async () => {
  const created = await call("POST", "/projects", { token: ANNE, body: { id: "p-due", title: "Garage trash", dueOn: "2026-09-20" } });
  assert.equal(created.status, 201);
  assert.equal(created.body.dueOn, "2026-09-20");
  const undated = await call("POST", "/projects", { token: ANNE, body: { id: "p-nodue", title: "No date" } });
  assert.equal(undated.body.dueOn, null);
  const moved = await call("PATCH", "/projects/p-due", { token: WES, body: { dueOn: "2026-10-01" } });
  assert.equal(moved.status, 200);
  assert.equal(moved.body.dueOn, "2026-10-01");
  assert.equal(moved.body.title, "Garage trash", "a date patch leaves the title alone");
  const cleared = await call("PATCH", "/projects/p-due", { token: WES, body: { dueOn: null } });
  assert.equal(cleared.body.dueOn, null);
  for (const bad of ["2026-9-20", "20/09/2026", "2026-09-20T00:00:00Z", "2026-02-30", "2026-13-01", 20260920, ""]) {
    assert.equal((await call("PATCH", "/projects/p-due", { token: WES, body: { dueOn: bad } })).status, 400, `patch ${bad}`);
    assert.equal((await call("POST", "/projects", { token: WES, body: { id: "p-bad", title: "x", dueOn: bad } })).status, 400, `post ${bad}`);
  }
  assert.equal((await call("POST", "/projects", { token: WES, body: { id: "p-leap", title: "x", dueOn: "2028-02-29" } })).status, 201, "a real leap day");
  const sync = await call("GET", "/sync?choresVersion=1", { token: ANNE });
  assert.equal(sync.body.projects.find((p) => p.id === "p-leap").dueOn, "2028-02-29", "the /sync shape carries dueOn");
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});

test("subtasks: assignee is anne, wes or null, on create and patch; the owner and the doer are different facts", async () => {
  const owned = await call("POST", "/projects/p-due/subtasks", { token: ANNE, body: { id: "st-owned", title: "Bag it", assignee: "wes" } });
  assert.equal(owned.status, 201);
  assert.equal(owned.body.assignee, "wes");
  const unowned = await call("POST", "/projects/p-due/subtasks", { token: ANNE, body: { id: "st-nobody", title: "Haul it" } });
  assert.equal(unowned.body.assignee, null);
  const handed = await call("PATCH", "/subtasks/st-nobody", { token: WES, body: { assignee: "anne" } });
  assert.equal(handed.status, 200);
  assert.equal(handed.body.assignee, "anne");
  const released = await call("PATCH", "/subtasks/st-nobody", { token: WES, body: { assignee: null } });
  assert.equal(released.body.assignee, null);
  const done = await call("PATCH", "/subtasks/st-owned", { token: ANNE, body: { done: true } });
  assert.equal(done.body.assignee, "wes");
  assert.equal(done.body.doneBy, "anne");
  assert.equal((await call("PATCH", "/subtasks/st-owned", { token: WES, body: { assignee: "bob" } })).status, 400);
  assert.equal((await call("PATCH", "/subtasks/st-owned", { token: WES, body: { assignee: 1 } })).status, 400);
  assert.equal((await call("POST", "/projects/p-due/subtasks", { token: WES, body: { id: "st-bad", title: "x", assignee: "" } })).status, 400);
  const withSteps = await call("POST", "/projects", { token: WES, body: { id: "p-steps", title: "x", subtasks: [{ id: "st-of-p", title: "y" }] } });
  assert.equal(withSteps.body.subtasks[0].assignee, null, "steps created with a project start unowned");
  assert.equal(logged.filter((m) => String(m).includes("unhandled")).length, 0, "no 500s were logged");
});
```

- [ ] **Step 2: Run to see them fail**

Run: `cd server && npm test 2>&1 | grep -E "^not ok|schemaVersion|dueOn|assignee" | head`
Expected: the migrate test reads `"2"`; the routes answer with `dueOn: undefined`.

- [ ] **Step 3: Implement**

`db.js`: `export const SCHEMA_VERSION = 3;`. In `SCHEMA`, `projects` gains `dueOn     TEXT,` after `title`, and `project_subtasks` gains `assignee  TEXT CHECK (assignee IN (${PEOPLE_SQL})),` after `sortOrder`. In `migrate`, after the v2 line:

```js
  if (current < 3) migrateToV3(db);
```

and below `migrateToV2`:

```js
/**
 * v3 (R-30): a due day on projects and an owner on subtasks. Both nullable, so ADD COLUMN is enough;
 * each is guarded on the column list so a database built from the v3 schema string is left alone.
 */
function migrateToV3(db) {
  if (!columnNames(db, "projects").includes("dueOn")) {
    db.exec("ALTER TABLE projects ADD COLUMN dueOn TEXT");
  }
  if (!columnNames(db, "project_subtasks").includes("assignee")) {
    db.exec(`ALTER TABLE project_subtasks ADD COLUMN assignee TEXT CHECK (assignee IN (${PEOPLE_SQL}))`);
  }
}
```

`insertProject`:

```js
/** Creates the project and its `subtasks` [{ id, title }] in order, each row taking its own seq. Steps start unowned. */
export function insertProject(db, { id, title, dueOn = null, subtasks = [] }, now) {
  const existing = getProject(db, id);
  if (existing) return { row: existing, created: false };
  const row = transact(db, () => {
    const project = insertRowIn(db, PROJECTS, id, { title, dueOn }, now);
    subtasks.forEach((s, i) => {
      insertRowIn(
        db,
        SUBTASKS,
        s.id,
        { projectId: id, title: s.title, sortOrder: i, assignee: null, done: 0, doneBy: null, doneAt: null },
        now
      );
    });
    return project;
  });
  return { row, created: true };
}

/** { title?, dueOn? }. `dueOn: null` clears the day. */
export function patchProject(db, id, { title, dueOn }, now) {
  const fields = {};
  if (title !== undefined) fields.title = title;
  if (dueOn !== undefined) fields.dueOn = dueOn;
  return patchRow(db, PROJECTS, id, fields, now);
}
```

`insertSubtask`: signature `{ id, projectId, title, sortOrder, assignee = null }` and the inserted columns `{ projectId, title, sortOrder: order, assignee, done: 0, doneBy: null, doneAt: null }`. `patchSubtask`: signature `{ title, done, sortOrder, assignee }`, and after the `sortOrder` line `if (assignee !== undefined) fields.assignee = assignee;`; its comment becomes `{ title?, done?, sortOrder?, assignee? }`.

`app.js`: import `PEOPLE` from `./db.js`. After `PRICE_ERROR`:

```js
const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const DAY_ERROR = "dueOn must be null or a calendar day, YYYY-MM-DD";
/** A real calendar day: the pattern, and a round trip through Date so 2026-02-30 does not roll into March. */
const validDay = (v) => {
  if (typeof v !== "string" || !DAY_RE.test(v)) return false;
  const t = Date.parse(`${v}T00:00:00Z`);
  return !Number.isNaN(t) && new Date(t).toISOString().slice(0, 10) === v;
};
const ASSIGNEE_ERROR = `assignee must be null or one of ${PEOPLE.join("|")}`;
const validPerson = (v) => v === null || PEOPLE.includes(v);
```

`shapeProject` → `{ id: row.id, title: row.title, dueOn: row.dueOn ?? null, ...stamp(row) }`; `shapeSubtask` gains `assignee: row.assignee ?? null,` after `sortOrder`. Routes:

- `POST /projects`: after the title check, `if (has(body, "dueOn") && body.dueOn !== null && !validDay(body.dueOn)) return send(res, 400, { error: DAY_ERROR });` and pass `dueOn: body.dueOn ?? null` into `insertProject`.
- `PATCH /projects/:id`: `pickPatch(body, { title: validTitle, dueOn: (v) => v === null || validDay(v) })`.
- `POST /projects/:id/subtasks`: after the `sortOrder` check, `if (has(body, "assignee") && !validPerson(body.assignee)) return send(res, 400, { error: ASSIGNEE_ERROR });` and pass `assignee: body.assignee ?? null`.
- `PATCH /subtasks/:id`: `pickPatch(body, { title: validTitle, done: isBool, sortOrder: validSort, assignee: validPerson })`.

Header comment: `POST /projects { id, title, dueOn?, subtasks? }`, `PATCH /projects/:id { title?, dueOn? }`, `POST /projects/:id/subtasks { id, title, sortOrder?, assignee? }`, `PATCH /subtasks/:id { title?, done?, sortOrder?, assignee? }`.

- [ ] **Step 4: Run the whole suite**

Run: `cd server && npm test 2>&1 | tail -8`
Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add server/src/db.js server/src/app.js server/test/migrate.test.js server/test/lists.test.js
git commit -m "server: schema v3 — projects.dueOn and project_subtasks.assignee on the routes and in /sync"
```

### Task 3: `server/README.md` and the lane S PR

**Files:**
- Modify: `server/README.md`

- [ ] **Step 1: Update the text**

- Model: add `- **wishlist** — \`{ id, title, priceCents, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, deleted, seq }\`. Shopping with a price: \`priceCents\` is null or an integer 0–99,999,999 (whole cents), settable on create and PATCH, cleared with null. \`bought\` stamps and clears exactly as shopping does.` The **projects** bullet gains "`dueOn` is a Chicago calendar day (`2026-09-20`) or null, set on create or PATCH and cleared with null." The **subtasks** bullet gains "`assignee` is `anne`, `wes` or null: who the step is meant for. Completing it stamps `doneBy` with whoever did it; the two can differ."
- The "seven sync tables" sentence becomes "All eight sync tables (completions, shopping, meals, projects, subtasks, wishlist, bonus, handoffs) share the ONE `seq` counter…", and "across all seven sync arrays" becomes eight.
- Schema versions paragraph (R-29 added it): "v3 added `projects.dueOn` and `project_subtasks.assignee` with `ALTER TABLE … ADD COLUMN`."
- Endpoints table: three new rows after `DELETE /shopping/:id` (`POST /wishlist` body `{ id, title, priceCents? }`, `addedBy` from the token; `PATCH /wishlist/:id` body `{ title?, priceCents?, bought? }`, `priceCents: null` clears it; `DELETE /wishlist/:id` soft delete, idempotent, 404 if unknown). `POST /projects` body gains `dueOn?`; `PATCH /projects/:id` body `{ title?, dueOn? }`; `POST /projects/:id/subtasks` body gains `assignee?`; `PATCH /subtasks/:id` body gains `assignee?`; the `/sync` row's list gains `wishlist` after `subtasks`.
- Validation paragraph: add "a `priceCents` that is not null or an integer 0–99,999,999, a `dueOn` that is not null or a real `YYYY-MM-DD` day, an `assignee` that is not null, `anne` or `wes`".

- [ ] **Step 2: Commit and open the PR**

```bash
git add server/README.md
git commit -m "server README: wishlist, project due day, step owner, schema v3"
git fetch origin && git rebase origin/main
cd server && npm test 2>&1 | tail -3 && cd ..
gh api -X POST repos/amnanninga4/roost/pulls -f title="R-30: wishlist, project due day, step owner" -f head=server/r30-wishlist-project-fields -f base=main -F body=@/dev/stdin <<'EOF'
Lane S of docs/superpowers/plans/2026-09-13-new-bar-lists.md (tasks 1–3). Server only. Schema version 3 on top of R-29's migration. Deploy before the app build with the Lists tab goes on a phone.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

---

## Lane A1 — Wishlist, the bar, More

### Task 4: The wishlist record, its actions, and the price arithmetic

**Files:**
- Modify: `Roost/Sources/Models/ListRecords.swift:10-22, 90-131`
- Modify: `Roost/Sources/Models/Records.swift:8-17`
- Modify: `Roost/Sources/Models/ListActions.swift` (after the shopping section)
- Modify: `Roost/Sources/Models/ListPresentation.swift` (after `ShoppingSplit`)
- Modify: `Roost/Sources/Strings.swift` (after `enum Shopping`)
- Create: `Roost/Tests/WishlistCraftTests.swift`

**Interfaces:**
- Produces: `PatchFields.price = 1 << 7`; `WishlistItemRecord: ListRecord` with `id, title, priceCents: Int?, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, syncedAt, removed, deleteSynced, rejected, seq, pendingPatch` and `init(id:title:priceCents:addedBy:bought:boughtBy:boughtAt:createdAt:updatedAt:syncedAt:removed:)`; `ListActions.priceLimit = 99_999_999`, `addWishlistItem(_:priceCents:by:in:now:)`, `setWishlistBought(_:_:by:in:now:)`, `setPrice(_:_:in:now:)`, `removeWishlistItem(_:in:now:)`, `clearBoughtWishlist(in:now:)`, `restoreWishlistItem(_:in:now:)`, `clampedPrice(_:)`; `PriceParser.cents(from:) -> Int?`; `PriceFormat.dollars(cents:locale:) -> String`; `WishlistTotals(rows:isBought:priceCents:)` with `openCount` and `totalCents: Int?`; `Strings.Wishlist.*`.

- [ ] **Step 1: Write the failing tests**

Create `Roost/Tests/WishlistCraftTests.swift`:

```swift
// The wishlist's arithmetic and its store actions, without a screen or a server: what a typed price
// becomes, how a price reads back, what the header adds up, and the undo paths a wishlist row shares
// with a shopping row.
@testable import Roost
import SwiftData
import XCTest

final class WishlistCraftTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(
            for: RoostSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
    }

    // MARK: the price field

    func testTypedPricesBecomeWholeCents() {
        XCTAssertEqual(PriceParser.cents(from: "599"), 59900)
        XCTAssertEqual(PriceParser.cents(from: "12.5"), 1250)
        XCTAssertEqual(PriceParser.cents(from: "12.50"), 1250)
        XCTAssertEqual(PriceParser.cents(from: "$1,299.99"), 129_999)
        XCTAssertEqual(PriceParser.cents(from: " 0 "), 0)
        XCTAssertEqual(PriceParser.cents(from: ".5"), 50)
        XCTAssertEqual(PriceParser.cents(from: "12."), 1200)
        XCTAssertEqual(PriceParser.cents(from: "999999.99"), 99_999_999, "the server's ceiling")
    }

    func testJunkAndOutOfRangePricesAreNil() {
        for junk in ["", "   ", "abc", "-5", "1.234", "1.2.3", "$", ".", "1,000,000", "1e3", "12 50"] {
            XCTAssertNil(PriceParser.cents(from: junk), junk)
        }
    }

    func testPricesReadAsDollarsAndOnlyShowCentsWhenThereAreSome() {
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(PriceFormat.dollars(cents: 59900, locale: us), "$599")
        XCTAssertEqual(PriceFormat.dollars(cents: 1250, locale: us), "$12.50")
        XCTAssertEqual(PriceFormat.dollars(cents: 185_000, locale: us), "$1,850")
        XCTAssertEqual(PriceFormat.dollars(cents: 0, locale: us), "$0")
        XCTAssertEqual(PriceFormat.dollars(cents: 99_999_999, locale: us), "$999,999.99")
    }

    // MARK: the header

    private struct Row {
        let bought: Bool
        let price: Int?
    }

    func testHeaderCountsOpenItemsAndTotalsOnlyThePricedOnes() {
        let rows = [Row(bought: false, price: 59900), Row(bought: false, price: nil),
                    Row(bought: false, price: 125_100), Row(bought: true, price: 999_900)]
        let totals = WishlistTotals(rows: rows, isBought: \.bought, priceCents: \.price)
        XCTAssertEqual(totals.openCount, 3)
        XCTAssertEqual(totals.totalCents, 185_000, "bought rows do not count")
        XCTAssertEqual(Strings.Wishlist.header(items: 3, total: "$1,850"), "3 items · $1,850 total")
        XCTAssertEqual(Strings.Wishlist.header(items: 1, total: nil), "1 item")
        let unpriced = WishlistTotals(rows: [Row(bought: false, price: nil)], isBought: \.bought, priceCents: \.price)
        XCTAssertNil(unpriced.totalCents, "no priced item, no total")
    }

    // MARK: the actions

    func testAddingKeepsThePriceInsideTheServersRangeAndBlankTitlesAreNotAdded() throws {
        XCTAssertNil(try ListActions.addWishlistItem("   ", priceCents: 100, by: "anne", in: context, now: clock))
        let item = try XCTUnwrap(try ListActions.addWishlistItem(" Bigger TV ", priceCents: 59900, by: nil, in: context, now: clock))
        XCTAssertEqual(item.title, "Bigger TV")
        XCTAssertEqual(item.priceCents, 59900)
        XCTAssertEqual(item.addedBy, "", "blank until the server stamps it")
        XCTAssertTrue(item.needsPost)
        let free = try XCTUnwrap(try ListActions.addWishlistItem("A weekend away", priceCents: nil, by: "wes", in: context, now: clock))
        XCTAssertNil(free.priceCents)
        XCTAssertEqual(ListActions.clampedPrice(-1), 0)
        XCTAssertEqual(ListActions.clampedPrice(100_000_000), ListActions.priceLimit)
        XCTAssertNil(ListActions.clampedPrice(nil))
    }

    func testPriceAndBoughtEditsFlagOnlyTheirOwnField() throws {
        let item = WishlistItemRecord(id: "w-1", title: "Kayak", priceCents: 89900, addedBy: "anne",
                                      createdAt: clock, syncedAt: clock)
        context.insert(item)
        try context.save()
        try ListActions.setPrice(item, nil, in: context, now: clock)
        XCTAssertNil(item.priceCents)
        XCTAssertEqual(item.pendingFields, [.price])
        try ListActions.setWishlistBought(item, true, by: "wes", in: context, now: clock)
        XCTAssertEqual(item.pendingFields, [.price, .bought])
        XCTAssertEqual(item.boughtBy, "wes")
        XCTAssertEqual(item.boughtAt, clock)
        try ListActions.setWishlistBought(item, false, by: "wes", in: context, now: clock)
        XCTAssertNil(item.boughtBy)
        XCTAssertNil(item.boughtAt)
    }

    func testUndoAfterTheDeleteWentOutCopiesThePriceAndFlagsBought() throws {
        let item = WishlistItemRecord(id: "w-2", title: "Standing desk", priceCents: 45000, addedBy: "wes",
                                      bought: true, boughtBy: "anne", boughtAt: clock, createdAt: clock, syncedAt: clock)
        context.insert(item)
        try context.save()
        try ListActions.removeWishlistItem(item, in: context, now: clock)
        item.deleteSynced = true // the DELETE has been acknowledged
        let copy = try ListActions.restoreWishlistItem(item, in: context, now: clock)
        XCTAssertNotEqual(copy.id, item.id)
        XCTAssertEqual(copy.priceCents, 45000)
        XCTAssertTrue(copy.bought)
        XCTAssertEqual(copy.pendingFields, [.bought], "the create carries the price; bought follows as a PATCH")
        XCTAssertTrue(item.removed, "the tombstone stays")
    }

    func testUndoOfADeleteThatNeverLeftUnremovesTheSameRow() throws {
        let item = try XCTUnwrap(try ListActions.addWishlistItem("Kayak", priceCents: nil, by: "wes", in: context, now: clock))
        try ListActions.removeWishlistItem(item, in: context, now: clock)
        XCTAssertTrue(item.deleteSynced, "never reached the server, so nothing to send")
        let back = try ListActions.restoreWishlistItem(item, in: context, now: clock)
        XCTAssertTrue(back === item)
        XCTAssertFalse(item.removed)
        XCTAssertTrue(item.needsPost)
    }

    func testClearBoughtRemovesEveryTickedRowAndReturnsThem() throws {
        for (index, bought) in [true, false, true].enumerated() {
            context.insert(WishlistItemRecord(id: "w-\(index)", title: "Thing \(index)", addedBy: "anne", bought: bought,
                                              createdAt: clock, syncedAt: clock))
        }
        try context.save()
        let cleared = try ListActions.clearBoughtWishlist(in: context, now: clock)
        XCTAssertEqual(Set(cleared.map(\.id)), ["w-0", "w-2"])
        let live = try context.fetch(FetchDescriptor<WishlistItemRecord>(predicate: #Predicate { !$0.removed }))
        XCTAssertEqual(live.map(\.id), ["w-1"])
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `cd Roost && xcodegen generate && cd .. && xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RoostTests/WishlistCraftTests test 2>&1 | grep -E "error:|Test Suite" | head`
Expected: compile errors — `WishlistItemRecord` not found.

- [ ] **Step 3: Implement**

`ListRecords.swift`: add `static let price = PatchFields(rawValue: 1 << 7)` after `sortOrder`, and after `ShoppingItemRecord`:

```swift
/// One line of the wishlist: a shopping item with a price. `priceCents` is whole cents, nil when the
/// row has no price (nil and 0 are different: "free" is a price). `addedBy` as on a shopping item.
@Model
final class WishlistItemRecord: ListRecord {
    @Attribute(.unique) var id: String
    var title: String
    var priceCents: Int?
    var addedBy: String
    var bought: Bool
    var boughtBy: String?
    var boughtAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var removed: Bool
    var deleteSynced: Bool = false
    var rejected: Bool = false
    var seq: Int?
    var pendingPatch: Int = 0

    init(
        id: String,
        title: String,
        priceCents: Int? = nil,
        addedBy: String,
        bought: Bool = false,
        boughtBy: String? = nil,
        boughtAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        syncedAt: Date? = nil,
        removed: Bool = false
    ) {
        self.id = id
        self.title = title
        self.priceCents = priceCents
        self.addedBy = addedBy
        self.bought = bought
        self.boughtBy = boughtBy
        self.boughtAt = boughtAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.syncedAt = syncedAt
        self.removed = removed
    }
}
```

`Records.swift`: `RoostSchema.models` gains `WishlistItemRecord.self` after `ShoppingItemRecord.self`. Update the file's top comment ("shopping items, wishlist items, meal ideas, …").

`ListActions.swift`, after the shopping section:

```swift
    // MARK: wishlist

    /// The server's ceiling for a price, in cents ($999,999.99).
    static let priceLimit = 99_999_999

    @discardableResult
    static func addWishlistItem(_ title: String, priceCents: Int?, by person: String?, in context: ModelContext,
                                now: Date = Date()) throws -> WishlistItemRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let item = WishlistItemRecord(
            id: newId(), title: title, priceCents: clampedPrice(priceCents), addedBy: person ?? "", createdAt: now
        )
        context.insert(item)
        try context.save()
        return item
    }

    static func setWishlistBought(
        _ item: WishlistItemRecord,
        _ bought: Bool,
        by person: String?,
        in context: ModelContext,
        now: Date = Date()
    ) throws {
        item.bought = bought
        item.boughtBy = bought ? person : nil
        item.boughtAt = bought ? now : nil
        item.markEdited(.bought, at: now)
        try context.save()
    }

    /// nil clears the price.
    static func setPrice(_ item: WishlistItemRecord, _ priceCents: Int?, in context: ModelContext,
                         now: Date = Date()) throws
    {
        item.priceCents = clampedPrice(priceCents)
        item.markEdited(.price, at: now)
        try context.save()
    }

    static func removeWishlistItem(_ item: WishlistItemRecord, in context: ModelContext, now: Date = Date()) throws {
        item.markRemoved(at: now)
        try context.save()
    }

    /// Everything already bought, removed in one go. Returns the rows so the undo bar can put them back.
    @discardableResult
    static func clearBoughtWishlist(in context: ModelContext, now: Date = Date()) throws -> [WishlistItemRecord] {
        let ticked = try context.fetch(FetchDescriptor<WishlistItemRecord>(
            predicate: #Predicate { $0.bought && !$0.removed }
        ))
        for item in ticked {
            item.markRemoved(at: now)
        }
        try context.save()
        return ticked
    }

    /// Undo of `removeWishlistItem`, with the same two outcomes as a shopping row: the same row when
    /// the DELETE never left the phone, a fresh copy when the server has already been told.
    @discardableResult
    static func restoreWishlistItem(
        _ item: WishlistItemRecord, in context: ModelContext, now: Date = Date()
    ) throws -> WishlistItemRecord {
        guard item.deleteReachedServer else {
            item.unremove(at: now)
            try context.save()
            return item
        }
        let copy = WishlistItemRecord(
            id: newId(),
            title: item.title,
            priceCents: item.priceCents,
            addedBy: item.addedBy,
            bought: item.bought,
            boughtBy: item.boughtBy,
            boughtAt: item.boughtAt,
            createdAt: item.createdAt,
            updatedAt: now
        )
        // The create carries id, title and price; a ticked row needs `bought` sent after it.
        if copy.bought {
            copy.pendingFields = .bought
        }
        context.insert(copy)
        try context.save()
        return copy
    }

    /// nil stays nil; anything else lands inside the server's 0...priceLimit.
    static func clampedPrice(_ cents: Int?) -> Int? {
        cents.map { min(max($0, 0), priceLimit) }
    }
```

`ListPresentation.swift`, after `ShoppingSplit` (and add `PriceParser`, `PriceFormat`, `WishlistTotals` to the file's header list):

```swift
/// The wishlist's price field: what a person types, as whole cents.
///
/// "599" is $599, "12.5" is $12.50, "$1,299.99" is $1,299.99. A third decimal, a second point, letters,
/// a sign, a space inside the number, or nothing at all is nil, and so is anything past the server's
/// ceiling. Whole dollars first, because that is how a price is said out loud; the cents are there for
/// the people who type them.
enum PriceParser {
    static func cents(from text: String) -> Int? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.removeAll { $0 == "$" || $0 == "," }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty), fraction.count <= 2 else { return nil }
        guard let dollars = whole.isEmpty ? 0 : Int(whole), dollars <= ListActions.priceLimit / 100 else { return nil }
        let cents = fraction.isEmpty ? 0 : (Int(String(fraction).padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0)
        let total = dollars * 100 + cents
        return total <= ListActions.priceLimit ? total : nil
    }
}

/// How a price reads on a row and in the header: whole dollars when the cents are zero ("$599"),
/// dollars and cents otherwise ("$12.50"), grouped by thousands ("$1,850").
enum PriceFormat {
    static func dollars(cents: Int, locale: Locale = .autoupdatingCurrent) -> String {
        let places = cents % 100 == 0 ? 0 : 2
        return (Decimal(cents) / 100)
            .formatted(.currency(code: "USD").precision(.fractionLength(places)).locale(locale))
    }
}

/// The wishlist header's two numbers: how many open items, and what the priced ones add up to.
struct WishlistTotals: Equatable {
    let openCount: Int
    /// Nil when no open item has a price, so the header leaves the total out rather than saying "$0".
    let totalCents: Int?

    init<Row>(rows: [Row], isBought: (Row) -> Bool, priceCents: (Row) -> Int?) {
        let open = rows.filter { !isBought($0) }
        openCount = open.count
        let priced = open.compactMap(priceCents)
        totalCents = priced.isEmpty ? nil : priced.reduce(0, +)
    }
}
```

`Strings.swift`, after `enum Shopping` (and change the `Lists` comment to "Shared by the four list pages"):

```swift
    enum Wishlist {
        /// "4 items · $1,850 total"; with nothing priced, just "4 items".
        static func header(items: Int, total: String?) -> String {
            let count = "\(items) \(items == 1 ? "item" : "items")"
            guard let total else { return count }
            return "\(count)\(Lists.metaSeparator)\(total) total"
        }

        static let add = "Add something you'd like…"
        /// The second field under the title: dollars, cents optional.
        static let price = "Price, like 599"
        static let empty = "Nothing on the wishlist."
        /// Under the empty line: what to do about it.
        static let emptyHint = "Add the things you'd buy some day."
        static let boughtSection = "Bought"
        static let clearBought = "Clear bought"
        /// VoiceOver: a row's state, and what a tap does to it.
        static let bought = "Bought"
        static let stillWanted = "Still wanted"
        static let markBought = "Marks it bought"
        static let markStillWanted = "Marks it still wanted"
        /// VoiceOver, after the state: "priced $599".
        static func priced(_ price: String) -> String {
            "priced \(price)"
        }
    }
```

- [ ] **Step 4: Run the full app suite**

Run: `xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Models Roost/Sources/Strings.swift Roost/Tests/WishlistCraftTests.swift Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: WishlistItemRecord, its actions, price parsing and formatting, the header totals"
```

### Task 5: Wishlist sync — the DTO, the three calls, the replay loops, the delta

**Files:**
- Modify: `Roost/Sources/Sync/SyncAPI.swift:71-90` (`SyncResponse`)
- Modify: `Roost/Sources/Sync/SyncAPI+Lists.swift` (a DTO after `ShoppingDTO`; three calls after the shopping ones)
- Modify: `Roost/Sources/Sync/ListSync+Records.swift` (after the `ShoppingItemRecord` extension)
- Modify: `Roost/Sources/Sync/ListSync.swift` (`replayCreates`, `replayEdits`, `replayRemovals`, `applyListDelta`)
- Modify: `Roost/Tests/ListSyncTestCase.swift` (a `wishlistJSON` builder; `listsSyncJSON` gains `wishlist:`)
- Create: `Roost/Tests/WishlistSyncTests.swift`

**Interfaces:**
- Consumes: `WishlistItemRecord`, `PatchFields.price`, `ListActions.addWishlistItem` / `setPrice` / `setWishlistBought` / `removeWishlistItem`.
- Produces: `SyncAPI.WishlistDTO { id, title, priceCents: Int?, addedBy, bought, boughtBy, boughtAt, createdAt, updatedAt, deleted, seq }`; `SyncAPI.postWishlist(id:title:priceCents:) -> Posted<WishlistDTO>`, `patchWishlist(id:_:)`, `deleteWishlist(id:)`; `SyncResponse.wishlist: [WishlistDTO]?`; `WishlistItemRecord.init(_ dto:now:)`, `apply(_:now:)`, `patchBody()`; the create POSTs `{ id, title, priceCents }` (null when there is no price) and a 201 clears `.title` and `.price`; a pending `bought` follows as a PATCH; the delta upserts by id.

- [ ] **Step 1: Write the failing tests**

`ListSyncTestCase.swift`: add after `shoppingJSON`:

```swift
func wishlistJSON(
    id: String, title: String, priceCents: Int? = nil, addedBy: String = "anne", bought: Bool = false,
    boughtBy: String? = nil, boughtAt: String? = nil, seq: Int, deleted: Bool = false
) -> [String: Any] {
    [
        "id": id, "title": title, "priceCents": priceCents.map { $0 as Any } ?? NSNull(), "addedBy": addedBy,
        "bought": bought, "boughtBy": orNull(boughtBy), "boughtAt": orNull(boughtAt),
        "createdAt": listStamp, "updatedAt": listStamp, "deleted": deleted, "seq": seq,
    ]
}
```

and give `listsSyncJSON` a `wishlist: [[String: Any]] = []` parameter (after `subtasks`) written into the body as `"wishlist": wishlist`. Add a lookup to the test case:

```swift
    func wishlistRow(_ id: String, in context: ModelContext? = nil) throws -> WishlistItemRecord? {
        try (context ?? fresh()).fetch(FetchDescriptor<WishlistItemRecord>(predicate: #Predicate { $0.id == id })).first
    }
```

Create `Roost/Tests/WishlistSyncTests.swift`:

```swift
// The wishlist through a sync pass: the create with and without a price, the price and bought
// patches, the delete, a refusal, and the delta. Same stub server as the other list suites.
@testable import Roost
import SwiftData
import XCTest

final class WishlistSyncTests: ListSyncTestCase {
    func testAddWithAPriceIsPostedOnceWithThePriceAndMarkedSynced() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = try XCTUnwrap(try ListActions.addWishlistItem("Bigger TV", priceCents: 59900, by: nil, in: ctx, now: listClock))
        let id = item.id
        StubURLProtocol.reset { req in
            let row = wishlistJSON(id: id, title: "Bigger TV", priceCents: 59900, seq: 8)
            if req.httpMethod == "POST" {
                return (201, json(row))
            }
            return (200, listsSyncJSON(cursor: 8, wishlist: [row]))
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 1, deleted: 0, received: 1))
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(post.path, "/wishlist")
        XCTAssertEqual(post.body?["id"] as? String, id)
        XCTAssertEqual(post.body?["title"] as? String, "Bigger TV")
        XCTAssertEqual(post.body?["priceCents"] as? Int, 59900)
        XCTAssertEqual(StubURLProtocol.requests("PATCH").count, 0, "a 201 took the price; nothing follows")
        let synced = try XCTUnwrap(try wishlistRow(id))
        XCTAssertNotNil(synced.syncedAt)
        XCTAssertEqual(synced.seq, 8)
        XCTAssertEqual(synced.addedBy, "anne", "the server's stamp replaces the blank")
        XCTAssertEqual(synced.pendingPatch, 0)

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 8)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "already synced rows are not re-posted")
    }

    func testAddWithoutAPriceSendsNullAndABoughtBeforeTheCreateFollowsAsAPatch() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = try XCTUnwrap(try ListActions.addWishlistItem("A weekend away", priceCents: nil, by: nil, in: ctx, now: listClock))
        try ListActions.setWishlistBought(item, true, by: "anne", in: ctx, now: listClock)
        let id = item.id
        StubURLProtocol.reset { req in
            switch req.httpMethod {
            case "POST": return (201, json(wishlistJSON(id: id, title: "A weekend away", seq: 3)))
            case "PATCH": return (200, json(wishlistJSON(id: id, title: "A weekend away", bought: true, boughtBy: "anne", boughtAt: listStamp, seq: 4)))
            default: return (200, listsSyncJSON(cursor: 4))
            }
        }
        _ = await client.syncNow()
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertTrue(post.body?["priceCents"] is NSNull, "no price is sent as null, not left out")
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/wishlist/\(id)")
        XCTAssertEqual(patch.body?["bought"] as? Bool, true)
        XCTAssertNil(patch.body?["priceCents"], "the create carried the price; only bought is left")
        XCTAssertEqual(try wishlistRow(id)?.seq, 4)
    }

    func testPricePatchSendsOnlyThePriceAndClearingSendsNull() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let item = WishlistItemRecord(id: "w-1", title: "Kayak", priceCents: 89900, addedBy: "wes", createdAt: listClock, syncedAt: listClock)
        item.seq = 5
        ctx.insert(item)
        try ctx.save()
        try ListActions.setPrice(item, 79900, in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            let row = wishlistJSON(id: "w-1", title: "Kayak", priceCents: 79900, addedBy: "wes", seq: 9)
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 9, wishlist: [row]))
        }
        _ = await client.syncNow()
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.body?["priceCents"] as? Int, 79900)
        XCTAssertNil(patch.body?["title"])
        XCTAssertNil(patch.body?["bought"])
        XCTAssertEqual(try wishlistRow("w-1")?.pendingPatch, 0)

        let again = fresh()
        try ListActions.setPrice(XCTUnwrap(try wishlistRow("w-1", in: again)), nil, in: again, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (200, json(wishlistJSON(id: "w-1", title: "Kayak", addedBy: "wes", seq: 10)))
            }
            return (200, listsSyncJSON(cursor: 10))
        }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("PATCH").first?.body?["priceCents"] is NSNull, "clearing sends null")
        XCTAssertNil(try wishlistRow("w-1")?.priceCents)
    }

    func testDeleteReplaysAsDELETEAndARefusedCreateIsKeptAndNeverRetried() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let synced = WishlistItemRecord(id: "w-2", title: "Standing desk", priceCents: 45000, addedBy: "anne", createdAt: listClock, syncedAt: listClock)
        synced.seq = 6
        ctx.insert(synced)
        try ctx.save()
        try ListActions.removeWishlistItem(synced, in: ctx, now: listClock)
        let refused = try XCTUnwrap(try ListActions.addWishlistItem("x", priceCents: nil, by: nil, in: ctx, now: listClock))
        StubURLProtocol.reset { req in
            switch req.httpMethod {
            case "DELETE": return (200, json(wishlistJSON(id: "w-2", title: "Standing desk", priceCents: 45000, seq: 11, deleted: true)))
            case "POST": return (400, json(["error": "title required: 1-200 chars"]))
            default: return (200, listsSyncJSON(cursor: 11))
            }
        }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 1, received: 0))
        XCTAssertEqual(StubURLProtocol.requests("DELETE").map(\.path), ["/wishlist/w-2"])
        XCTAssertEqual(try wishlistRow("w-2")?.deleteSynced, true)
        let kept = try XCTUnwrap(try wishlistRow(refused.id))
        XCTAssertTrue(kept.rejected)
        XCTAssertFalse(kept.removed, "kept locally with the marker")

        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 11)) }
        _ = await client.syncNow()
        XCTAssertEqual(StubURLProtocol.requests("POST").count, 0, "a rejected row is never retried")
    }

    func testDeltaUpsertsByIdAndADeletedRowGoesAway() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 20, wishlist: [
                wishlistJSON(id: "w-a", title: "Bigger TV", priceCents: 59900, seq: 19),
                wishlistJSON(id: "w-b", title: "Gone", addedBy: "wes", seq: 20, deleted: true),
            ]))
        }
        let first = await client.syncNow()
        XCTAssertEqual(first, .synced(posted: 0, deleted: 0, received: 2))
        let a = try XCTUnwrap(try wishlistRow("w-a"))
        XCTAssertEqual(a.priceCents, 59900)
        XCTAssertEqual(a.addedBy, "anne")
        XCTAssertNotNil(a.syncedAt)
        let b = try XCTUnwrap(try wishlistRow("w-b"))
        XCTAssertTrue(b.removed)
        XCTAssertTrue(b.deleteSynced)
        XCTAssertEqual(try state().cursor, 20)

        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 21, wishlist: [
                wishlistJSON(id: "w-a", title: "Bigger TV", priceCents: 54999, bought: true, boughtBy: "wes", boughtAt: listStamp, seq: 21),
            ]))
        }
        _ = await client.syncNow()
        let updated = try XCTUnwrap(try wishlistRow("w-a"))
        XCTAssertEqual(updated.priceCents, 54999)
        XCTAssertTrue(updated.bought)
        XCTAssertEqual(updated.boughtBy, "wes")
        XCTAssertEqual(StubURLProtocol.requests("DELETE").count, 0, "a delta never echoes a DELETE")
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd Roost && xcodegen generate && cd .. && xcodebuild … -only-testing:RoostTests/WishlistSyncTests test 2>&1 | grep -E "error:|failed" | head`
Expected: compile errors — `wishlistJSON` and `wishlistRow` undefined until Step 1's edits build; then the tests fail because no `/wishlist` request is ever made.

- [ ] **Step 3: Implement**

`SyncAPI.swift`, `SyncResponse`: after `subtasks` add `let wishlist: [WishlistDTO]?` with the comment "Optional so a server older than R-30, or a test stub, still decodes."

`SyncAPI+Lists.swift`: after `ShoppingDTO`:

```swift
    struct WishlistDTO: Codable, Sendable, Equatable {
        let id: String
        let title: String
        let priceCents: Int?
        let addedBy: String
        let bought: Bool
        let boughtBy: String?
        let boughtAt: String?
        let createdAt: String
        let updatedAt: String
        let deleted: Bool
        let seq: Int
    }
```

after the shopping calls:

```swift
    // MARK: wishlist

    /// 201 new, 200 replay. The create carries the price too (null for none), so a 201 leaves only a
    /// pending `bought` to follow. `addedBy` comes back stamped from the token.
    func postWishlist(id: String, title: String, priceCents: Int?) async throws -> Posted<WishlistDTO> {
        let body: Fields = [
            "id": .string(id), "title": .string(title),
            "priceCents": priceCents.map { .int($0) } ?? .null,
        ]
        return try await post("wishlist", body: body)
    }

    func patchWishlist(id: String, _ fields: Fields) async throws -> WishlistDTO {
        try await call("PATCH", "wishlist/\(id)", body: fields)
    }

    func deleteWishlist(id: String) async throws -> WishlistDTO {
        try await call("DELETE", "wishlist/\(id)")
    }
```

`ListSync+Records.swift`, after the `ShoppingItemRecord` extension:

```swift
extension WishlistItemRecord {
    convenience init(_ dto: SyncAPI.WishlistDTO, now: Date) {
        self.init(
            id: dto.id,
            title: dto.title,
            priceCents: dto.priceCents,
            addedBy: dto.addedBy,
            bought: dto.bought,
            boughtBy: dto.boughtBy,
            boughtAt: dto.boughtAt.flatMap(SyncAPI.parseDate),
            createdAt: SyncAPI.parseDate(dto.createdAt) ?? now,
            updatedAt: SyncAPI.parseDate(dto.updatedAt) ?? now,
            syncedAt: now,
            removed: dto.deleted
        )
        deleteSynced = dto.deleted
        seq = dto.seq
    }

    func apply(_ dto: SyncAPI.WishlistDTO, now: Date) {
        let dirty = pendingFields
        if !dirty.contains(.title) {
            title = dto.title
        }
        if !dirty.contains(.price) {
            priceCents = dto.priceCents
        }
        if !dirty.contains(.bought) {
            bought = dto.bought
            boughtBy = dto.boughtBy
            boughtAt = dto.boughtAt.flatMap(SyncAPI.parseDate)
        }
        addedBy = dto.addedBy
        markSynced(seq: dto.seq, deleted: dto.deleted, updatedAt: dto.updatedAt, now: now)
    }

    func patchBody() -> SyncAPI.Fields {
        var body: SyncAPI.Fields = [:]
        if pendingFields.contains(.title) {
            body["title"] = .string(title)
        }
        if pendingFields.contains(.price) {
            body["priceCents"] = priceCents.map { .int($0) } ?? .null
        }
        if pendingFields.contains(.bought) {
            body["bought"] = .bool(bought)
        }
        return body
    }
}
```

`ListSync.swift`:

- `replayCreates`: after `postShoppingItems` add `posted += try await postWishlistItems(api: api, now: now)`, and the function after `postShoppingItems`:

```swift
    private func postWishlistItems(api: SyncAPI, now: Date) async throws -> Int {
        let items = try fetch(
            #Predicate<WishlistItemRecord> { $0.syncedAt == nil && !$0.rejected && !$0.removed },
            sort: [SortDescriptor(\.createdAt)]
        )
        var posted = 0
        for item in items {
            let sent = try await outbound(item) {
                let reply = try await api.postWishlist(id: item.id, title: item.title, priceCents: item.priceCents)
                if reply.isNew {
                    item.pendingFields.subtract([.title, .price]) // the create carried both; `bought` waits for the edits
                }
                item.apply(reply.row, now: now)
            }
            if sent == .taken {
                posted += 1
            }
        }
        return posted
    }
```

- `replayEdits`: fetch `wishlist` with the same predicate shape as `items` (`#Predicate<WishlistItemRecord> { $0.syncedAt != nil && $0.pendingPatch != 0 && !$0.rejected && !$0.removed }`, sorted by `updatedAt`) and add `posted += try await patch(wishlist) { try await api.patchWishlist(id: $0.id, $0.patchBody()) } apply: { $0.apply($1, now: now) }` after the shopping line.
- `replayRemovals`: fetch `wishlist` (`$0.removed && !$0.deleteSynced`, sorted by `updatedAt`) and add `deleted += try await remove(wishlist) { _ = try await api.deleteWishlist(id: $0.id) }` after the shopping line.
- `applyListDelta`: after the shopping loop,

```swift
        for dto in response.wishlist ?? [] {
            let id = dto.id
            try upsert(fetchOne(#Predicate<WishlistItemRecord> { $0.id == id }), seq: dto.seq, now: now) {
                WishlistItemRecord(dto, now: now)
            } apply: { $0.apply(dto, now: now) }
        }
```

and `response.wishlist?.count` in the `counts` array. Update the file's header comment ("shopping, wishlist, meals, projects, subtasks").

- [ ] **Step 4: Run the full app suite**

Run the `xcodebuild … test` line. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Sync Roost/Tests/ListSyncTestCase.swift Roost/Tests/WishlistSyncTests.swift Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: wishlist through the sync pass — DTO, three calls, replay loops, delta"
```

### Task 6: The Wishlist page

**Files:**
- Create: `Roost/Sources/Screens/WishlistScreen.swift`

**Interfaces:**
- Consumes: `WishlistItemRecord`, `ListActions` wishlist calls, `PriceParser`, `PriceFormat`, `WishlistTotals`, `Strings.Wishlist`, `ShoppingSplit`, `ListScreenHeader`, `ListComposer`, `ListEmptyState`, `CheckCircle`, `PersonAvatar`, `MetaChip`, `NotSyncedMarker`, `ListUndo`, `swipeToDelete`, `undoBar`, `refocus`.
- Produces: `struct WishlistScreen: View` — a `List` body with no `NavigationStack` and no `listTabChrome()` of its own (the Lists container applies them, Task 7). The header title is `Strings.Tabs.wishlist`, so the page prints its own name.

- [ ] **Step 1: Write the screen**

```swift
// The Wishlist page: things to buy some day, with a price when there is one. Shopping's shape — type at
// the top, tick what was bought and it sinks into the Bought section, clear that section, swipe a row
// away with five seconds to take it back — plus a second field for the price. Every write goes to the
// store first, then kicks a sync.
import RoostCore
import RoostDesign
import SwiftData
import SwiftUI

struct WishlistScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync

    @Query(filter: #Predicate<WishlistItemRecord> { !$0.removed }, sort: \WishlistItemRecord.createdAt, order: .reverse)
    private var items: [WishlistItemRecord]
    @Query private var syncStates: [SyncState]

    @State private var draft = ""
    @State private var priceDraft = ""
    @FocusState private var draftFocused: Bool
    @State private var undo = ListUndo()
    /// Counters the taps bump, so the haptics fire on what the reader did and never on a delta.
    @State private var added = 0
    @State private var checkedOff = 0
    @State private var uncheckedOff = 0

    private var person: String? {
        syncStates.first?.person
    }

    private var split: ShoppingSplit<WishlistItemRecord> {
        ShoppingSplit(rows: items, isBought: \.bought, boughtAt: \.boughtAt)
    }

    private var headerLine: String {
        let totals = WishlistTotals(rows: items, isBought: \.bought, priceCents: \.priceCents)
        return Strings.Wishlist.header(items: totals.openCount, total: totals.totalCents.map { PriceFormat.dollars(cents: $0) })
    }

    var body: some View {
        let rows = split
        List {
            Section {
                ListScreenHeader(title: Strings.Tabs.wishlist, line: headerLine, status: sync.statusLine)
                    .listHeaderRow()
            }
            Section {
                ListComposer(placeholder: Strings.Wishlist.add, text: $draft, focused: $draftFocused, onSubmit: add) {
                    if !draft.isEmpty {
                        TextField(Strings.Wishlist.price, text: $priceDraft)
                            .roostType(.subheadline)
                            .foregroundStyle(RoostColor.Role.textSecondary.color)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onSubmit(add)
                            .padding(.leading, RoostSpacing.xl + RoostSpacing.md)
                            .accessibilityLabel(Strings.Wishlist.price)
                    }
                }
            }
            Section {
                if items.isEmpty {
                    ListEmptyState(symbol: "gift", line: Strings.Wishlist.empty, hint: Strings.Wishlist.emptyHint)
                }
                ForEach(rows.toBuy) { item in
                    row(item)
                }
            }
            if !rows.bought.isEmpty {
                Section {
                    ForEach(rows.bought) { item in
                        row(item)
                    }
                } header: {
                    boughtHeader
                }
            }
        }
        .accessibilityIdentifier("wishlistList")
        .roostAnimation(.standard, value: items.map(\.bought))
        .roostHaptic(.selection, trigger: added)
        .roostHaptic(.checkOff, trigger: checkedOff)
        .roostHaptic(.undo, trigger: uncheckedOff)
        .undoBar(undo)
    }

    private var boughtHeader: some View {
        HStack {
            Text(Strings.Wishlist.boughtSection.uppercased())
                .roostType(.monoLabel)
                .foregroundStyle(RoostColor.Role.textSecondary.color)
            Spacer(minLength: RoostSpacing.sm)
            Button(Strings.Wishlist.clearBought, action: clearBought)
                .roostType(.footnote)
                .foregroundStyle(RoostColor.Role.accent.color)
                .buttonStyle(.roostTrailingTextAction)
        }
        .textCase(nil)
    }

    private func row(_ item: WishlistItemRecord) -> some View {
        WishlistRow(item: item) { toggle(item) }
            .listRowBackground(RoostColor.Role.surface.color)
            .roostTransition(.checkOff)
            .swipeToDelete(rejected: item.rejected) { remove(item) }
    }

    // MARK: actions

    private func add() {
        // A price that does not parse is not a reason to lose the title: the row goes in without one.
        let price = PriceParser.cents(from: priceDraft)
        do {
            guard try ListActions.addWishlistItem(draft, priceCents: price, by: person, in: context) != nil else {
                draft = "" // blank: let Return put the keyboard away
                priceDraft = ""
                return
            }
        } catch {
            return // the store refused; the fields keep what was typed
        }
        draft = ""
        priceDraft = ""
        added += 1
        sync.syncSoon()
        refocus($draftFocused)
    }

    private func toggle(_ item: WishlistItemRecord) {
        let bought = !item.bought
        try? ListActions.setWishlistBought(item, bought, by: person, in: context)
        if bought {
            checkedOff += 1
        } else {
            uncheckedOff += 1
        }
        sync.syncSoon()
    }

    /// The removal is in the store at once; its sync waits for the undo window (see `ListUndo`).
    private func remove(_ item: WishlistItemRecord) {
        let title = item.title
        try? ListActions.removeWishlistItem(item, in: context)
        undo.offer(Strings.Lists.removed(title), restore: { [context] in
            _ = try? ListActions.restoreWishlistItem(item, in: context)
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }

    private func clearBought() {
        guard let cleared = try? ListActions.clearBoughtWishlist(in: context), !cleared.isEmpty else { return }
        undo.offer(Strings.Lists.removedCount(cleared.count), restore: { [context] in
            for item in cleared {
                _ = try? ListActions.restoreWishlistItem(item, in: context)
            }
            sync.syncSoon()
        }, commit: {
            sync.syncSoon()
        })
    }
}

private struct WishlistRow: View {
    let item: WishlistItemRecord
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var price: String? {
        item.priceCents.map { PriceFormat.dollars(cents: $0) }
    }

    /// Bought reads as done; the price and a refusal join the value so they are spoken, not just drawn.
    private var value: String {
        var parts = [item.bought ? Strings.Wishlist.bought : Strings.Wishlist.stillWanted]
        if let price {
            parts.append(Strings.Wishlist.priced(price))
        }
        if item.rejected {
            parts.append(Strings.Lists.didNotSyncValue)
        }
        return parts.joined(separator: Strings.Lists.metaSeparator)
    }

    private var title: some View {
        Text(item.title)
            .roostType(.rowTitle)
            .foregroundStyle(item.bought ? RoostColor.Role.textSecondary.color : RoostColor.Role.textPrimary.color)
            .strikethrough(item.bought, color: RoostColor.Role.textSecondary.color)
            .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var chips: some View {
        if let price {
            MetaChip(text: price, role: .accent)
        }
        if item.rejected {
            NotSyncedMarker()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let person = Person(rawValue: item.addedBy) {
            PersonAvatar(person: person)
        }
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: RoostSpacing.md) {
                CheckCircle(isOn: item.bought)
                // At an accessibility size the chips drop under the title rather than squeezing it.
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: RoostSpacing.sm) {
                        HStack(spacing: RoostSpacing.sm) {
                            title
                            Spacer(minLength: RoostSpacing.sm)
                            avatar
                        }
                        HStack(spacing: RoostSpacing.sm) {
                            chips
                        }
                    }
                } else {
                    title
                    Spacer(minLength: RoostSpacing.sm)
                    chips
                    avatar
                }
            }
            .padding(.vertical, RoostSpacing.xs)
            .frame(minHeight: RoostSpacing.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityValue(value)
        .accessibilityHint(item.bought ? Strings.Wishlist.markStillWanted : Strings.Wishlist.markBought)
    }
}

#Preview {
    NavigationStack {
        WishlistScreen()
            .listTabChrome()
    }
    .modelContainer(UITestSeed.paired.makeContainer())
    .environment(SyncCoordinator.preview)
}
```

If `SyncCoordinator.preview` does not exist, look at how `ShoppingScreen`'s neighbours preview (`grep -rn "#Preview" Roost/Sources/Screens`) and use the same environment they do; if none of them has a preview, drop the `#Preview` block and verify in Task 7 on the simulator instead. `MetaChip(text:role:)` with `.accent` uses `RoostColor.Role.accent` and its soft partner, which exist (`PlusBadge` uses both).

- [ ] **Step 2: Build**

Run: `cd Roost && xcodegen generate && cd .. && xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`. (The page is reachable from Task 7 on; the tests for its logic are Tasks 4 and 5.)

- [ ] **Step 3: Commit**

```bash
git add Roost/Sources/Screens/WishlistScreen.swift Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: the Wishlist page"
```

### Task 7: The bar and the Lists container

**Files:**
- Modify: `Roost/Sources/Root/RootTabView.swift`
- Create: `Roost/Sources/Screens/ListsScreen.swift`
- Modify: `Roost/Sources/Screens/ShoppingScreen.swift:33-84`, `MealsScreen.swift:81-123`, `ProjectsScreen.swift:740-787` (each drops its `NavigationStack`, `.listTabChrome()` and `.tint`)
- Modify: `Roost/Sources/Strings.swift` (`enum Tabs`)
- Modify: `Roost/Sources/Debug/UITestSeed.swift` (two wishlist rows)
- Modify: `Roost/Tests/RootTabsTests.swift`
- Modify: `Roost/UITests/RoostUITestCase.swift`, `Roost/UITests/AccessibilityAuditTests.swift`, `Roost/UITests/ScrollPerformanceTests.swift`
- Create: `Roost/UITests/ListsBehaviourTests.swift`

**Interfaces:**
- Produces: `RootTab { tasks, lists, more }` with the titles and symbols in Global Constraints; `ListPage { shopping, meals, projects, wishlist }` (`String` raw values, `CaseIterable`, `title`, `symbol`, `storageKey = "roost.lists.page"`); `ListsScreen` — the one `NavigationStack` and `listTabChrome()` over a segmented `Picker` (accessibility identifier `listsPicker`) and a paged `TabView` bound to the same `@AppStorage` selection; `MoreScreen` is referenced from `RootTabView` and is created in Task 8 — until then `screen(for: .more)` returns `EmptyView()`; UI-test helper `openList(_:in:)`; the Shopping and Projects lists carry accessibility identifiers `shoppingList` and `projectsList`.

- [ ] **Step 1: Write the failing tests**

`RootTabsTests.swift`, replace `testRootHasFourTabsInOrder`:

```swift
    func testRootHasThreeTabsInOrder() {
        XCTAssertEqual(RootTab.allCases, [.tasks, .lists, .more])
        XCTAssertEqual(RootTab.allCases.map(\.title), ["Tasks", "Lists", "More"])
        XCTAssertEqual(RootTab.allCases.map(\.symbol), ["checklist", "list.bullet.rectangle", "ellipsis.circle"])
    }

    func testListsPagesInOrderWithTheirSymbolsAndAStableStorageKey() {
        XCTAssertEqual(ListPage.allCases, [.shopping, .meals, .projects, .wishlist])
        XCTAssertEqual(ListPage.allCases.map(\.title), ["Shopping", "Meals", "Projects", "Wishlist"])
        XCTAssertEqual(ListPage.allCases.map(\.symbol), ["cart", "fork.knife", "hammer", "gift"])
        XCTAssertEqual(ListPage.storageKey, "roost.lists.page")
        XCTAssertEqual(ListPage(rawValue: "wishlist"), .wishlist, "AppStorage writes the raw value; it must not change")
    }
```

Create `Roost/UITests/ListsBehaviourTests.swift`:

```swift
// Two promises the Lists container makes: a page keeps its state while another page is showing, and
// the page you left on is the page you come back to after a relaunch.
import XCTest

final class ListsBehaviourTests: RoostUITestCase {
    func testADraftSurvivesSwitchingPagesAndBack() {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Shopping", in: app)
        let field = app.textFields["Add an item…"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout))
        field.tap()
        field.typeText("Paper towels")
        openList("Meals", in: app)
        openList("Shopping", in: app)
        XCTAssertEqual(app.textFields["Add an item…"].value as? String, "Paper towels", "the draft is still there")
    }

    func testTheChosenPageIsRememberedAcrossALaunch() {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Wishlist", in: app)
        app.terminate()
        let again = launch(.paired)
        waitForTasks(in: again)
        again.tabBars.buttons["Lists"].tap()
        XCTAssertTrue(again.staticTexts["Nothing on the wishlist."].waitForExistence(timeout: Self.timeout)
            || again.staticTexts["Wishlist"].waitForExistence(timeout: Self.timeout), "Wishlist came back")
        XCTAssertTrue(again.segmentedControls["listsPicker"].buttons["Wishlist"].isSelected)
        openList("Shopping", in: again) // leave the default for the next test
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd Roost && xcodegen generate && cd .. && xcodebuild … -only-testing:RoostTests/RootTabsTests test 2>&1 | grep -E "error:|failed" | head`
Expected: compile errors — `RootTab` has no member `lists`; `ListPage` not found.

- [ ] **Step 3: Implement**

`Strings.swift`, `enum Tabs`:

```swift
    enum Tabs {
        static let tasks = "Tasks"
        static let lists = "Lists"
        static let more = "More"
        /// The four pages under Lists; each page's header prints its own name.
        static let shopping = "Shopping"
        static let meals = "Meals"
        static let projects = "Projects"
        static let wishlist = "Wishlist"
    }
```

`RootTabView.swift`, replace the file:

```swift
import RoostDesign

// The root of the app: three tabs. Tasks is the Today screen; Lists holds Shopping, Meals, Projects and
// Wishlist behind a segmented control; More holds what the gear menu used to. Calendar arrives with the
// reminders design and slots in second; nothing here reserves it a place.
import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case tasks, lists, more

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .tasks: Strings.Tabs.tasks
        case .lists: Strings.Tabs.lists
        case .more: Strings.Tabs.more
        }
    }

    var symbol: String {
        switch self {
        case .tasks: "checklist"
        case .lists: "list.bullet.rectangle"
        case .more: "ellipsis.circle"
        }
    }
}

struct RootTabView: View {
    @State private var selected: RootTab = .tasks
    @Environment(SyncCoordinator.self) private var sync

    var body: some View {
        TabView(selection: $selected) {
            ForEach(RootTab.allCases) { tab in
                Tab(tab.title, systemImage: tab.symbol, value: tab) {
                    screen(for: tab)
                }
            }
        }
        .tint(RoostColor.accent)
        // A tapped push lands on Tasks: everything the server pushes is about a chore. A counter rather
        // than a flag, so a second tap works even if the reader has moved to another tab since the first.
        .onChange(of: sync.push.openTasksRequests) {
            selected = .tasks
        }
    }

    @ViewBuilder
    private func screen(for tab: RootTab) -> some View {
        switch tab {
        case .tasks: TodayScreen()
        case .lists: ListsScreen()
        case .more: EmptyView() // MoreScreen lands in the next task
        }
    }
}
```

Create `Roost/Sources/Screens/ListsScreen.swift`:

```swift
// The Lists tab: Shopping, Meals, Projects and Wishlist under one roof. A segmented control picks the
// page and a paged TabView under it scrolls to the same page, so a tap and a swipe do the same thing and
// every page keeps its own state — its draft, its open cards, its five-second undo — while another one is
// showing. The chosen page is remembered per phone. The list chrome is applied here, once, so the pages
// are plain `List` bodies.
import RoostDesign
import SwiftUI

/// The four pages, in bar order. The raw values are what `AppStorage` writes, so they must not change.
enum ListPage: String, CaseIterable, Identifiable {
    case shopping, meals, projects, wishlist

    static let storageKey = "roost.lists.page"

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .shopping: Strings.Tabs.shopping
        case .meals: Strings.Tabs.meals
        case .projects: Strings.Tabs.projects
        case .wishlist: Strings.Tabs.wishlist
        }
    }

    /// What the segments show at accessibility text sizes, where four words no longer fit.
    var symbol: String {
        switch self {
        case .shopping: "cart"
        case .meals: "fork.knife"
        case .projects: "hammer"
        case .wishlist: "gift"
        }
    }
}

struct ListsScreen: View {
    @AppStorage(ListPage.storageKey) private var page: ListPage = .shopping
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                    .padding(.horizontal, RoostSpacing.screenMargin)
                    .padding(.vertical, RoostSpacing.sm)
                TabView(selection: $page) {
                    ForEach(ListPage.allCases) { page in
                        pageBody(page)
                            .tag(page)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .listTabChrome()
        }
        .tint(RoostColor.Role.accent.color)
    }

    private var picker: some View {
        Picker(Strings.Tabs.lists, selection: $page) {
            ForEach(ListPage.allCases) { page in
                if typeSize.isAccessibilitySize {
                    Image(systemName: page.symbol)
                        .accessibilityLabel(page.title)
                        .tag(page)
                } else {
                    Text(page.title)
                        .tag(page)
                }
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("listsPicker")
    }

    @ViewBuilder
    private func pageBody(_ page: ListPage) -> some View {
        switch page {
        case .shopping: ShoppingScreen()
        case .meals: MealsScreen()
        case .projects: ProjectsScreen()
        case .wishlist: WishlistScreen()
        }
    }
}
```

The three pages: in `ShoppingScreen`, `MealsScreen` and `ProjectsScreen`, delete the `NavigationStack {` line and its closing brace, the `.listTabChrome()` line, and the trailing `.tint(RoostColor.Role.accent.color)`; the `List { … }` with its remaining modifiers is the whole body. In `ShoppingScreen` the body then starts `let rows = split` followed by `List {`, which is legal in a `ViewBuilder` body only as the first statement — keep it that way. Add `.accessibilityIdentifier("shoppingList")` to Shopping's `List` and `.accessibilityIdentifier("projectsList")` to Projects', right after the closing brace of each `List`. Update each file's header comment ("Shopping page" rather than "Shopping tab"; the chrome comes from `ListsScreen`).

`UITestSeed.swift`: add `seedWishlist(into: context, day: day)` after `seedShopping`, the function

```swift
        @MainActor
        private func seedWishlist(into context: ModelContext, day: (Int) -> Date) {
            for (index, item) in Self.wishlist.enumerated() {
                let record = WishlistItemRecord(
                    id: "uitest-wishlist-\(index)",
                    title: item.title,
                    priceCents: item.priceCents,
                    addedBy: item.addedBy.rawValue,
                    createdAt: day(-1).addingTimeInterval(Double(Self.wishlist.count - index)),
                    syncedAt: day(-1)
                )
                context.insert(record)
            }
        }
```

and, in the rows extension after `bulkTitle`:

```swift
        struct SeededWishlistItem {
            let title: String
            let addedBy: Person
            var priceCents: Int?
        }

        /// Two rows: one with a price, so the chip and the header total are on screen, and one without.
        static var wishlist: [SeededWishlistItem] {
            [
                SeededWishlistItem(title: "Bigger TV", addedBy: .anne, priceCents: 59900),
                SeededWishlistItem(title: "A weekend away", addedBy: .wes),
            ]
        }
```

`RoostUITestCase.swift`: add after `openTab`:

```swift
    /// Opens the Lists tab and picks one of its pages by the segment's name, then waits for the page's
    /// own header. The remembered page persists between launches, so this always taps the segment.
    func openList(_ title: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons["Lists"]
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "the Lists tab never appeared")
        tab.tap()
        let segment = app.segmentedControls["listsPicker"].buttons[title]
        XCTAssertTrue(segment.waitForExistence(timeout: Self.timeout), "the \(title) segment never appeared")
        segment.tap()
        XCTAssertTrue(
            app.staticTexts[title].waitForExistence(timeout: Self.timeout),
            "the \(title) page never appeared"
        )
    }
```

`AccessibilityAuditTests.swift`: `testShoppingAudit`, `testMealsAudit`, `testProjectsAudit` call `openList(…)` instead of `openTab(…)`. In `testProjectsAudit`, replace `app.collectionViews.firstMatch.swipeUp()` with `app.collectionViews["projectsList"].swipeUp()` (the paged container is a scroll view of its own now, so "first collection view" is no longer a safe name for the list). Add:

```swift
    func testWishlistAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openList("Wishlist", in: app)
        XCTAssertTrue(app.buttons["Bigger TV"].waitForExistence(timeout: Self.timeout), "the wishlist rows never appeared")
        try audit(app, allowing: [
            customFontScales("$599"),
            textFieldScrolls("Add something you'd like…"),
        ])
    }
```

`ScrollPerformanceTests.swift`: `openTab("Shopping", in: app)` → `openList("Shopping", in: app)`, and `shoppingList(in:)` returns `app.collectionViews["shoppingList"]`.

- [ ] **Step 4: Run the full suite and look at the screen**

Run the `xcodebuild … test` line (unit and UI tests). Expected: `** TEST SUCCEEDED **`. Then `xcrun simctl launch booted xyz.hinescreative.roost -roostUITestState paired`, tap Lists, and check: four segments; a swipe moves the page and the segment follows; the Wishlist page shows "2 items · $599 total", a `$599` chip on Bigger TV, an avatar per row; the header title of each page is its name; the app title stays "Roost" in the bar. Relaunch with `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` and confirm the segments are symbols. Screenshot both for the PR.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources Roost/Tests/RootTabsTests.swift Roost/UITests Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: Tasks · Lists · More — the Lists container with four pages, the bar, the UI-test helpers"
```

### Task 8: The More page, the gear's retirement, Settings pushed

**Files:**
- Create: `Roost/Sources/Screens/MoreScreen.swift`
- Modify: `Roost/Sources/Root/RootTabView.swift` (`.more: MoreScreen()`)
- Modify: `Roost/Sources/Screens/TodayScreen.swift:33-34, 68-76, 152-168`
- Modify: `Roost/Sources/Screens/SettingsScreen.swift:23-88, 296-303`
- Modify: `Roost/Sources/Strings.swift` (`Tasks.gear`, `Tasks.notPaired`, `Sync.notPaired`, `Settings.close`, new `enum More`)
- Modify: `Roost/Tests/TodayBoardTests.swift:216-218`
- Modify: `Roost/UITests/RoostUITestCase.swift`, `Roost/UITests/AccessibilityAuditTests.swift`

**Interfaces:**
- Produces: `MoreScreen` — Household: Kitchen mode (full-screen cover), All chores (pushed); This phone: Settings (pushed), Sync now with `sync.statusLine` beneath; footer `AppVersion.line`; `enum AppVersion { static var line: String }` (moved out of `SettingsScreen`); `Strings.More.household = "HOUSEHOLD"`, `Strings.More.thisPhone = "THIS PHONE"`; `Strings.Tasks.notPaired = "Not paired yet · More → Settings"`, `Strings.Sync.notPaired = "Not paired · More → Settings"`; `Strings.Tasks.gear` and `Strings.Settings.close` deleted; UI-test helper `openFromMore(_:in:)` replaces `openFromGearMenu`.

- [ ] **Step 1: Write the failing tests**

`TodayBoardTests.swift`, the unpaired test (around line 216): keep the two existing assertions and add

```swift
        XCTAssertTrue(Strings.Tasks.notPaired.contains(Strings.Tabs.more), "the line points at the More tab now")
        XCTAssertEqual(Strings.Tasks.notPaired, "Not paired yet · More → Settings")
        XCTAssertEqual(Strings.Sync.notPaired, "Not paired · More → Settings")
```

`AccessibilityAuditTests.swift`: replace the "behind the gear" section:

```swift
    // MARK: - the More tab

    func testMoreAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openTab("More", in: app)
        XCTAssertTrue(app.buttons["All chores"].waitForExistence(timeout: Self.timeout), "the More page never appeared")
        try audit(app, allowing: [
            customFontScales("HOUSEHOLD"),
            customFontScales("THIS PHONE"),
            customFontScales("Roost 0.1.0 (1)"),
        ])
    }

    func testSettingsAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromMore("Settings", in: app)
        XCTAssertTrue(
            app.staticTexts["Paired as"].waitForExistence(timeout: Self.timeout),
            "Settings never appeared"
        )
        try audit(app, allowing: [
            customFontScales("SYNC"),
            customFontScales("Roost 0.1.0 (1)"),
            customFontScales("Roost forgets the token on this phone. You'll need a new code to pair again."),
            customFontScales("Settings"),
            // The navigation bar's back button. Bar items keep a fixed size on iOS whatever the reader's
            // text setting says, and there is no modifier that changes that.
            KnownIssue(
                compact: "Dynamic Type font sizes are partially unsupported",
                element: "More",
                reason: "a navigation bar button; iOS does not scale bar items with Dynamic Type"
            ),
            textFieldScrolls("Address"),
        ])
    }

    func testAllChoresAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromMore("All chores", in: app)
        XCTAssertTrue(
            app.staticTexts["HOUSEHOLD LIST"].waitForExistence(timeout: Self.timeout),
            "All chores never appeared"
        )
        try audit(app)
    }

    func testKitchenModeAudit() throws {
        let app = launch(.paired)
        waitForTasks(in: app)
        openFromMore("Kitchen mode", in: app)
        XCTAssertTrue(
            app.staticTexts["DUE TODAY"].waitForExistence(timeout: Self.timeout),
            "Kitchen mode never appeared"
        )
        try audit(app, allowing: [dateLineWraps])
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `xcodebuild … -only-testing:RoostTests/TodayBoardTests test 2>&1 | grep -E "error:|failed" | head`
Expected: the two string assertions fail (the old wording).

- [ ] **Step 3: Implement**

`Strings.swift`:
- `Tabs` is done (Task 7). In `Tasks`: delete `static let gear = "More"` and its comment; change the comment above `allChores` to "The More page's rows. Settings is `Strings.Settings.title`, which the screen itself owns."; `notPaired = "Not paired yet · More → Settings"` with the comment "Not paired: one line under the header pointing at the More tab's Settings row, where "Paired as" lives."
- `Sync.notPaired = "Not paired · More → Settings"`.
- `Settings`: delete `close`; the enum comment becomes "More → Settings."
- `Chores` comment: "More → All chores"; `Kitchen` comment: "Kitchen mode (More → Kitchen mode)".
- Add after `enum Tabs`:

```swift
    /// The More tab: what the gear menu held, as a page.
    enum More {
        /// Section headers, in the mono eyebrow like Settings', so written in caps here.
        static let household = "HOUSEHOLD"
        static let thisPhone = "THIS PHONE"
    }
```

`SettingsScreen.swift`: remove the `NavigationStack { … }` wrapper (the `Form` and its modifiers are the body; keep `.tint(RoostColor.Role.accent.color)` on the `Form`), delete the `ToolbarItem(placement: .cancellationAction)` block and `@Environment(\.dismiss)`, and replace `private static var versionLine` with a call to `AppVersion.line`. Add at the bottom of the file:

```swift
/// "Roost 0.1.0 (1)" — from the bundle, so it is whatever this build actually is. Settings and More both show it.
enum AppVersion {
    static var line: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return Strings.Settings.version(short, build: build)
    }
}
```

Update the file's header comment: "More → Settings", and the paragraph about Close ("pushed from More; the back button is the way out").

`TodayScreen.swift`: delete `@State private var showSettings`, `@State private var showKitchen`, the `.toolbar { gear }`, `.sheet(isPresented: $showSettings)`, `.fullScreenCover(isPresented: $showKitchen)` lines, and the whole `private var gear` property. Update the README-style comment at the top (no gear).

Create `Roost/Sources/Screens/MoreScreen.swift`:

```swift
// The More tab: what the gear menu used to hold, as a page. Household things first, then this phone's,
// then the version line Settings also shows. Kitchen mode opens full screen as before; the other rows push.
import RoostDesign
import SwiftUI

struct MoreScreen: View {
    @Environment(SyncCoordinator.self) private var sync
    @State private var showKitchen = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { showKitchen = true } label: {
                        MoreRow(title: Strings.Kitchen.menuEntry, symbol: "rectangle.on.rectangle")
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(RoostColor.Role.surface.color)
                    NavigationLink {
                        ChoreListScreen()
                    } label: {
                        MoreRow(title: Strings.Tasks.allChores, symbol: "list.bullet")
                    }
                    .listRowBackground(RoostColor.Role.surface.color)
                } header: {
                    MoreHeader(Strings.More.household)
                }
                Section {
                    NavigationLink {
                        SettingsScreen()
                    } label: {
                        MoreRow(title: Strings.Settings.title, symbol: "iphone.and.arrow.forward")
                    }
                    .listRowBackground(RoostColor.Role.surface.color)
                    Button { sync.syncSoon() } label: {
                        MoreRow(title: Strings.Tasks.syncNow, symbol: "arrow.triangle.2.circlepath", detail: sync.statusLine)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(RoostColor.Role.surface.color)
                } header: {
                    MoreHeader(Strings.More.thisPhone)
                } footer: {
                    Text(AppVersion.line)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                        .frame(maxWidth: .infinity)
                        .padding(.top, RoostSpacing.sm)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(RoostSpacing.md)
            .scrollContentBackground(.hidden)
            .background(RoostColor.Role.background.color)
            .navigationTitle(Strings.Tabs.more)
            .toolbarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showKitchen) { KitchenScreen() }
        }
        .tint(RoostColor.Role.accent.color)
    }
}

/// One row: a symbol in the accent, the title, and an optional second line (the sync status under Sync now).
/// One element to VoiceOver, named by the title, with the second line as its value.
private struct MoreRow: View {
    let title: String
    let symbol: String
    var detail: String?

    var body: some View {
        HStack(spacing: RoostSpacing.md) {
            Image(systemName: symbol)
                .roostType(.body)
                .foregroundStyle(RoostColor.Role.accent.color)
                .frame(width: RoostSpacing.xl)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RoostSpacing.xxs) {
                Text(title)
                    .roostType(.body)
                    .foregroundStyle(RoostColor.Role.textPrimary.color)
                if let detail {
                    Text(detail)
                        .roostType(.caption)
                        .foregroundStyle(RoostColor.Role.textSecondary.color)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, RoostSpacing.xxs)
        .frame(minHeight: RoostSpacing.minTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(detail ?? "")
    }
}

/// A section header in the app's mono eyebrow, the same as Settings'.
private struct MoreHeader: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .roostType(.monoLabel)
            .foregroundStyle(RoostColor.Role.textSecondary.color)
            .textCase(nil)
    }
}
```

`RootTabView.swift`: `case .more: MoreScreen()` (drop the `EmptyView()` and its comment).

`RoostUITestCase.swift`: replace `openFromGearMenu` with

```swift
    /// Opens the More tab and taps one of its rows.
    func openFromMore(_ item: String, in app: XCUIApplication) {
        let tab = app.tabBars.buttons["More"]
        XCTAssertTrue(tab.waitForExistence(timeout: Self.timeout), "the More tab never appeared")
        tab.tap()
        let row = app.buttons[item]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "'\(item)' is not on the More page")
        row.tap()
    }
```

and change the file's header ("the taps that reach each screen") to mention the Lists segments and the More rows.

- [ ] **Step 4: Run the full suite and look at the screens**

Run the `xcodebuild … test` line. Expected: `** TEST SUCCEEDED **`. Then in the simulator (`paired` fixture): More shows two groups and the version footer; Kitchen mode opens full screen and closes; All chores pushes with a back button; Settings pushes, has no Close, and its back button returns to More; Sync now's second line reads the status. Tasks has no gear, and the unpaired fixture's line (launch with `-roostUITestState onboarding` is not paired; instead check `Strings.Tasks.notPaired` on a paired store by reading the `TodayBoardTests` assertion) — the screenshot of More goes on the PR.

- [ ] **Step 5: Commit, then the A1 docs and the PR**

```bash
git add Roost/Sources Roost/Tests/TodayBoardTests.swift Roost/UITests Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: the More page; the gear is gone; Settings is pushed"
```

Docs for A1, in the same branch:

- `Roost/README.md`: line 3's history sentence gains "The 2026-09-13 bar change replaced the four tabs with Tasks · Lists · More, put Shopping, Meals, Projects and a new Wishlist under Lists, and moved the gear menu to the More page." The screenshot table: the Shopping/Meals/Projects cells keep their files (recaptured inside Lists in this PR: `xcrun simctl io booted screenshot Roost/docs/shopping.png` and so on, light and dark), and gain `lists.png` (the Lists tab on Shopping) / `wishlist.png` (+ `-dark`) and `more.png`. Layout listing: `Root/RootTabView.swift    the tab bar (RootTab: Tasks, Lists, More) and the screen behind each`; add `Screens/ListsScreen.swift  the Lists tab: ListPage, the segmented control, the paged TabView that hosts the four pages and applies the list chrome once`, `Screens/WishlistScreen.swift  Wishlist page: composer with a price field, price chips, header total, Bought section, undo`, `Screens/MoreScreen.swift  the More tab: Kitchen mode, All chores, Settings (pushed), Sync now + status, version`; the Shopping/Meals/Projects lines say "page" not "tab"; `Screens/SettingsScreen.swift More → Settings …`; `Screens/ChoreListScreen.swift … reachable from More as "All chores"`; `Strings.swift` line mentions the Wishlist and More strings. Screens section: "The root is `RootTabView`, a `TabView` over the `RootTab` enum: Tasks (`checklist`), Lists (`list.bullet.rectangle`), More (`ellipsis.circle`)… The Lists tab is `ListsScreen`: a segmented control (symbols at accessibility sizes) over a paged `TabView` bound to the same `AppStorage` selection, so a swipe and a tap do the same thing and every page keeps its state; the list chrome is applied once there." Replace "the gear menu (…) stays on Tasks" with a More paragraph (Household / This phone / footer). The three-list paragraph becomes four pages and describes the Wishlist row and header. States: "Not paired yet · More → Settings". Sync: "from More → Sync now"; the status line's "Not paired · More → Settings". "All chores (More → All chores)". Fixtures table: `paired` gains "two wishlist rows". The "Adding an audit" example uses `openFromMore` and mentions `openList(_:in:)`. The test-count sentence adds the new suites in the file's style (root tabs: three tabs and the four pages with a stable storage key; wishlist craft: price parsing, formatting, totals, the actions and their undo paths; wishlist sync: create with and without a price, price patch and clear, bought, delete, refusal, delta; UI: the draft survives a page switch, the chosen page survives a relaunch; the audits for Wishlist and More).
- `NOTES.md` line 40: "**Tabs:** Tasks / Lists (Shopping · Meals · Projects · Wishlist) / More. Calendar slots in second when the reminders design ships. (Decided 2026-09-13; spec in docs/superpowers/specs/2026-09-13-new-bar-lists-design.md.)"
- Root `README.md` line 5: add "a wishlist" after "meal ideas"; line 51: "syncs chores, shopping, wishlist, meals, projects, bonus, and handoffs".

```bash
git add Roost/README.md Roost/docs NOTES.md README.md
git commit -m "docs: the new bar, the Lists tab, the Wishlist, the More page"
git fetch origin && git rebase origin/main
cd Roost && xcodegen generate && cd .. && git status --short   # must be clean
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"
gh api -X POST repos/amnanninga4/roost/pulls -f title="App: Tasks · Lists · More, the Wishlist, the More page" -f head=app/wishlist-and-bar -f base=main -F body=@/dev/stdin <<'EOF'
Lane A1 of docs/superpowers/plans/2026-09-13-new-bar-lists.md (tasks 4–8). Needs R-30 deployed before this build goes on a phone (the wishlist POSTs 404 against an older server and the rows sit rejected until then).

Screenshots: (attach lists, wishlist, more; the accessibility-size segments.)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

---

## Lane A2 — project due day, step owner, the reminder, fixtures and docs (after A1 merges)

### Task 9: A due day on a project

**Files:**
- Modify: `Roost/Sources/Models/ListRecords.swift` (`PatchFields.dueOn`, `ProjectRecord`)
- Modify: `Roost/Sources/Models/ListActions.swift` (`setDueOn`; `restoreProject` copies the day)
- Modify: `Roost/Sources/Models/ListPresentation.swift` (`ProjectDates`)
- Modify: `Roost/Sources/Sync/SyncAPI+Lists.swift` (`ProjectDTO.dueOn`)
- Modify: `Roost/Sources/Sync/ListSync+Records.swift` (the `ProjectRecord` extension)
- Modify: `Roost/Sources/Screens/ProjectsScreen.swift` (the card's due line and menu, the picker sheet)
- Modify: `Roost/Sources/Strings.swift` (`enum Projects`)
- Modify: `Roost/Tests/ListSyncTestCase.swift` (`projectJSON(dueOn:)`)
- Modify: `Roost/Tests/ListCraftTests.swift`
- Create: `Roost/Tests/ProjectFieldsSyncTests.swift`

**Interfaces:**
- Produces: `PatchFields.dueOn = 1 << 8`; `ProjectRecord.dueOn: String?` (a Chicago calendar day, `YYYY-MM-DD`) and `init(id:title:dueOn:createdAt:updatedAt:syncedAt:removed:)`; `ListActions.setDueOn(_:_:in:now:)`; `ProjectDates.dayString(_:calendar:) -> String`, `day(from:calendar:) -> Date?`, `label(_:now:locale:calendar:) -> String?` ("Due Sep 20"), `isPast(_:now:calendar:) -> Bool`; `SyncAPI.ProjectDTO.dueOn: String?` (absent from an older server decodes as nil); `apply` takes `dueOn` unless `.dueOn` is pending; `patchBody` sends `dueOn` (null to clear); `Strings.Projects.due(_:)`, `setDueDay`, `changeDueDay`, `clearDueDay`, `dueDayPicker`, `dueDayDone`, `pastDue`.

- [ ] **Step 1: Write the failing tests**

`ListSyncTestCase.swift`: `projectJSON` gains `dueOn: String? = nil` (after `title`) written as `"dueOn": orNull(dueOn)`.

`ListCraftTests.swift`, add a section:

```swift
    // MARK: project due days

    func testDueDayReadsAsDueMonthDayAndKnowsWhenItHasPassed() throws {
        let cal = HouseholdCalendar()
        let us = Locale(identifier: "en_US")
        let sep10 = cal.date(year: 2026, month: 9, day: 10, hour: 9)
        XCTAssertEqual(ProjectDates.label("2026-09-20", now: sep10, locale: us, calendar: cal), "Due Sep 20")
        XCTAssertEqual(ProjectDates.label("2027-01-05", now: sep10, locale: us, calendar: cal), "Due Jan 5, 2027", "another year says so")
        XCTAssertNil(ProjectDates.label("next tuesday", now: sep10, locale: us, calendar: cal))
        XCTAssertFalse(ProjectDates.isPast("2026-09-20", now: sep10, calendar: cal))
        XCTAssertFalse(ProjectDates.isPast("2026-09-20", now: cal.date(year: 2026, month: 9, day: 20, hour: 23), calendar: cal), "the day itself is not past")
        XCTAssertTrue(ProjectDates.isPast("2026-09-20", now: cal.date(year: 2026, month: 9, day: 21, hour: 0), calendar: cal))
        XCTAssertFalse(ProjectDates.isPast("garbage", now: sep10, calendar: cal))
        XCTAssertEqual(ProjectDates.dayString(cal.date(year: 2026, month: 9, day: 20, hour: 23), calendar: cal), "2026-09-20")
        XCTAssertEqual(ProjectDates.day(from: "2026-09-20", calendar: cal), cal.startOfDay(cal.date(year: 2026, month: 9, day: 20)))
    }

    func testSettingAndClearingTheDueDayFlagsOnlyThatField() throws {
        let project = ProjectRecord(id: "p-1", title: "Garage trash", createdAt: clock, syncedAt: clock)
        context.insert(project)
        try context.save()
        try ListActions.setDueOn(project, "2026-09-20", in: context, now: clock)
        XCTAssertEqual(project.dueOn, "2026-09-20")
        XCTAssertEqual(project.pendingFields, [.dueOn])
        try ListActions.setDueOn(project, nil, in: context, now: clock)
        XCTAssertNil(project.dueOn)
        XCTAssertEqual(project.pendingFields, [.dueOn])
    }
```

(`ListCraftTests` already has a `context` and a `clock`; if its names differ, use the file's own.) Create `Roost/Tests/ProjectFieldsSyncTests.swift`:

```swift
// The two project fields through a sync pass: the due day and the step owner, each patched alone,
// cleared with null, taken from a delta, and tolerated when an older server leaves the key out.
@testable import Roost
import SwiftData
import XCTest

final class ProjectFieldsSyncTests: ListSyncTestCase {
    func testDueDayPatchSendsOnlyTheDayAndClearingSendsNull() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-1", title: "Garage trash", createdAt: listClock, syncedAt: listClock)
        project.seq = 4
        ctx.insert(project)
        try ctx.save()
        try ListActions.setDueOn(project, "2026-09-20", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            let row = projectJSON(id: "p-1", title: "Garage trash", dueOn: "2026-09-20", seq: 9, subtasks: [])
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 9, projects: [projectJSON(id: "p-1", title: "Garage trash", dueOn: "2026-09-20", seq: 9)]))
        }
        _ = await client.syncNow()
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/projects/p-1")
        XCTAssertEqual(patch.body?["dueOn"] as? String, "2026-09-20")
        XCTAssertNil(patch.body?["title"], "only the changed field is sent")
        XCTAssertEqual(try projectRow("p-1")?.pendingPatch, 0)

        let again = fresh()
        try ListActions.setDueOn(XCTUnwrap(try projectRow("p-1", in: again)), nil, in: again, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (200, json(projectJSON(id: "p-1", title: "Garage trash", seq: 10, subtasks: [])))
            }
            return (200, listsSyncJSON(cursor: 10))
        }
        _ = await client.syncNow()
        XCTAssertTrue(StubURLProtocol.requests("PATCH").first?.body?["dueOn"] is NSNull, "clearing sends null")
        XCTAssertNil(try projectRow("p-1")?.dueOn)
    }

    func testDeltaCarriesTheDueDayAndAnOlderServerLeavesItNil() async throws {
        try await pairAsAnne()
        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 12, projects: [projectJSON(id: "p-2", title: "Fence", dueOn: "2026-10-01", seq: 12)]))
        }
        _ = await client.syncNow()
        XCTAssertEqual(try projectRow("p-2")?.dueOn, "2026-10-01")

        var older = projectJSON(id: "p-3", title: "Old server", seq: 13)
        older.removeValue(forKey: "dueOn")
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 13, projects: [older])) }
        let outcome = await client.syncNow()
        XCTAssertEqual(outcome, .synced(posted: 0, deleted: 0, received: 1), "a missing key is not a decoding failure")
        XCTAssertNil(try projectRow("p-3")?.dueOn)
    }

    func testAPendingDueDayOutlivesADeltaWithTheServersOlderCopy() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-4", title: "Shed", dueOn: "2026-09-01", createdAt: listClock, syncedAt: listClock)
        project.seq = 5
        ctx.insert(project)
        try ctx.save()
        try ListActions.setDueOn(project, "2026-09-30", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            if req.httpMethod == "PATCH" {
                return (503, json(["error": "later"])) // the edit stays queued
            }
            return (200, listsSyncJSON(cursor: 6, projects: [projectJSON(id: "p-4", title: "Shed", dueOn: "2026-09-01", seq: 6)]))
        }
        _ = await client.syncNow()
        XCTAssertEqual(try projectRow("p-4")?.dueOn, "2026-09-30", "the local edit wins until it is sent")
        XCTAssertEqual(try projectRow("p-4")?.pendingFields, [.dueOn])
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `cd Roost && xcodegen generate && cd .. && xcodebuild … -only-testing:RoostTests/ListCraftTests -only-testing:RoostTests/ProjectFieldsSyncTests test 2>&1 | grep -E "error:|failed" | head`
Expected: compile errors — `ProjectDates` and `ProjectRecord.dueOn` do not exist.

- [ ] **Step 3: Implement**

`ListRecords.swift`: `static let dueOn = PatchFields(rawValue: 1 << 8)`; `ProjectRecord` gains `var dueOn: String?` after `title`, an `init` parameter `dueOn: String? = nil` after `title`, and `self.dueOn = dueOn`; the doc comment: "`dueOn` is a Chicago calendar day, `2026-09-20`, or nil: the same shape as the household start date."

`ListActions.swift`, in the projects section:

```swift
    /// `dueOn` is a Chicago calendar day ("2026-09-20"), or nil to clear the day.
    static func setDueOn(_ project: ProjectRecord, _ dueOn: String?, in context: ModelContext, now: Date = Date()) throws {
        project.dueOn = dueOn
        project.markEdited(.dueOn, at: now)
        try context.save()
    }
```

In `restoreProject`, the copy is `ProjectRecord(id: newId(), title: project.title, dueOn: project.dueOn, createdAt: project.createdAt, updatedAt: now)` and, since a create does not carry the day, add after it: `if copy.dueOn != nil { copy.pendingFields = .dueOn }`.

`ListPresentation.swift`, after `MealDates` (and add `ProjectDates` to the header list):

```swift
/// A project's due day: the `YYYY-MM-DD` the server stores, read and written through the household
/// calendar so the phone's own time zone never moves the day.
enum ProjectDates {
    /// "2026-09-20" for the Chicago day containing `date`.
    static func dayString(_ date: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> String {
        NotificationPlanner.dayKey(date, calendar: calendar)
    }

    /// The start of that day in Chicago, or nil for anything that is not a day.
    static func day(from text: String, calendar: HouseholdCalendar = HouseholdCalendar()) -> Date? {
        SyncAPI.parseActiveFrom(text, calendar: calendar)
    }

    /// "Due Sep 20", or "Due Jan 5, 2027" when the day is in another year. Nil for a day that does not parse.
    static func label(
        _ text: String, now: Date = Date(), locale: Locale = .autoupdatingCurrent,
        calendar: HouseholdCalendar = HouseholdCalendar()
    ) -> String? {
        guard let day = day(from: text, calendar: calendar) else { return nil }
        let sameYear = calendar.calendar.component(.year, from: day) == calendar.calendar.component(.year, from: now)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMM d" : "MMM d y")
        return Strings.Projects.due(formatter.string(from: day))
    }

    /// True once the day has ended: the morning after is the first moment it reads as past.
    static func isPast(_ text: String, now: Date, calendar: HouseholdCalendar = HouseholdCalendar()) -> Bool {
        guard let day = day(from: text, calendar: calendar) else { return false }
        return calendar.startOfDay(now) > day
    }
}
```

`SyncAPI+Lists.swift`, `ProjectDTO`: add `let dueOn: String?` after `title` with the comment "Absent from a server older than R-30, which decodes as nil."

`ListSync+Records.swift`, `ProjectRecord` extension: the `init` passes `dueOn: dto.dueOn`; `apply` gains

```swift
        if !pendingFields.contains(.dueOn) {
            dueOn = dto.dueOn
        }
```

and `patchBody` gains

```swift
        if pendingFields.contains(.dueOn) {
            body["dueOn"] = dueOn.map { .string($0) } ?? .null
        }
```

`Strings.swift`, `enum Projects`:

```swift
        /// On a card with a due day: "Due Sep 20".
        static func due(_ day: String) -> String {
            "Due \(day)"
        }

        /// The card's menu.
        static let setDueDay = "Set a due day"
        static let changeDueDay = "Change the due day"
        static let clearDueDay = "Clear the due day"
        /// The picker sheet's title and its confirming button.
        static let dueDayPicker = "Due day"
        static let dueDayDone = "Done"
        /// VoiceOver, on a card whose day has passed.
        static let pastDue = "Past due"
```

`ProjectsScreen.swift`:

- `@State private var editingDue: ProjectRecord?` next to `open`.
- In `card(_:)`, compute `let now = Date()`, `let dueLabel = project.dueOn.flatMap { ProjectDates.label($0, now: now) }`, `let pastDue = !progress.isFinished && (project.dueOn.map { ProjectDates.isPast($0, now: now) } ?? false)`, and pass `dueLabel: dueLabel, pastDue: pastDue` into `ProjectRow`.
- The card's `.contextMenu` gains, before the destructive button:

```swift
                    Button(project.dueOn == nil ? Strings.Projects.setDueDay : Strings.Projects.changeDueDay,
                           systemImage: "calendar") { editingDue = project }
                    if project.dueOn != nil {
                        Button(Strings.Projects.clearDueDay, systemImage: "calendar.badge.minus") { setDueOn(project, nil) }
                    }
```

- On the `List` (after `.undoBar(undo)`):

```swift
            .sheet(item: $editingDue) { project in
                DueDaySheet(initial: project.dueOn.flatMap { ProjectDates.day(from: $0) } ?? Date()) { picked in
                    setDueOn(project, ProjectDates.dayString(picked))
                }
            }
```

- An action: `private func setDueOn(_ project: ProjectRecord, _ day: String?) { try? ListActions.setDueOn(project, day, in: context); sync.syncSoon() }`.
- `ProjectRow` gains `let dueLabel: String?` and `let pastDue: Bool`; its `value` appends `Strings.Projects.pastDue` when `pastDue` and the label when present; the progress `HStack` gains, after the count:

```swift
                    if let dueLabel {
                        Text(dueLabel)
                            .roostType(.caption)
                            .foregroundStyle(pastDue ? RoostColor.Role.danger.color : RoostColor.Role.textSecondary.color)
                            .fixedSize()
                    }
```

- The sheet, at the bottom of the file:

```swift
/// The date picker behind "Set a due day". Graphical, in the household's time zone, so the day picked is
/// the day stored whatever zone the phone is in.
private struct DueDaySheet: View {
    let onPick: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date

    init(initial: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        _day = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            DatePicker(Strings.Projects.dueDayPicker, selection: $day, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.timeZone, HouseholdCalendar().calendar.timeZone)
                .tint(RoostColor.Role.accent.color)
                .padding(RoostSpacing.lg)
                .navigationTitle(Strings.Projects.dueDayPicker)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.Settings.cancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Strings.Projects.dueDayDone) {
                            onPick(day)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
```

`ProjectsScreen.swift` needs `import RoostCore` (it has it) for `HouseholdCalendar`.

- [ ] **Step 4: Run the full suite and look at the card**

Run the `xcodebuild … test` line. Expected: `** TEST SUCCEEDED **`. In the simulator: long-press a card → Set a due day → pick a day → "Due <day>" on the card; pick yesterday → the label goes red; Clear the due day removes it.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources Roost/Tests Roost/Roost.xcodeproj/project.pbxproj
git commit -m "app: a due day on a project — record, sync, ProjectDates, the card menu and picker"
```

### Task 10: An owner on a step

**Files:**
- Modify: `Roost/Sources/Models/ListRecords.swift` (`PatchFields.assignee`, `SubtaskRecord`)
- Modify: `Roost/Sources/Models/ListActions.swift` (`addSubtask(assignee:)`, `setAssignee`, the restore copies)
- Modify: `Roost/Sources/Sync/SyncAPI+Lists.swift` (`SubtaskDTO.assignee`, `postSubtask(assignee:)`)
- Modify: `Roost/Sources/Sync/ListSync+Records.swift` (the `SubtaskRecord` extension)
- Modify: `Roost/Sources/Sync/ListSync.swift:150-176` (`postSubtasks` sends and clears the owner)
- Modify: `Roost/Sources/Screens/ProjectsScreen.swift` (`SubtaskRow`, `SubtaskComposer`)
- Modify: `Roost/Sources/Strings.swift` (`enum Projects`)
- Modify: `Roost/Tests/ListSyncTestCase.swift` (`subtaskJSON(assignee:)`), `Roost/Tests/ListCraftTests.swift`, `Roost/Tests/ProjectFieldsSyncTests.swift`

**Interfaces:**
- Produces: `PatchFields.assignee = 1 << 9`; `SubtaskRecord.assignee: String?` and an `init` parameter `assignee: String? = nil` after `sortOrder`; `ListActions.addSubtask(_:to:assignee:in:now:)` (the owner is flagged so it reaches the server whichever route the create takes) and `setAssignee(_:_:in:now:)`; `SyncAPI.SubtaskDTO.assignee: String?`; `postSubtask(projectId:id:title:sortOrder:assignee:)` sends `assignee` (null for none) and a 201 clears `.assignee` too; `Strings.Projects.owner = "Owner"`, `nobody = "Nobody"`, `ownedBy(_:)` = "For Wes".
- The avatar: the check circle stays at the leading edge where it is; the owner's avatar goes at the trailing edge of the step, after the title and the "Didn't sync" marker. (The spec's "before the check circle" is read as "the last thing before the row ends"; the circle has been leading since D-3 and the tap target is the whole row.)

- [ ] **Step 1: Write the failing tests**

`ListSyncTestCase.swift`: `subtaskJSON` gains `assignee: String? = nil` (after `sortOrder`) written as `"assignee": orNull(assignee)`.

`ListCraftTests.swift`:

```swift
    // MARK: step owners

    func testAddingAStepWithAnOwnerFlagsTheOwnerAndSettingItLaterFlagsOnlyThat() throws {
        let project = try XCTUnwrap(try ListActions.startProject("Garage", in: context, now: clock))
        let owned = try XCTUnwrap(try ListActions.addSubtask("Bag it", to: project, assignee: "wes", in: context, now: clock))
        XCTAssertEqual(owned.assignee, "wes")
        XCTAssertEqual(owned.pendingFields, [.assignee], "flagged, so it reaches the server whichever create carries the step")
        let plain = try XCTUnwrap(try ListActions.addSubtask("Haul it", to: project, in: context, now: clock))
        XCTAssertNil(plain.assignee)
        XCTAssertEqual(plain.pendingFields, [])
        plain.syncedAt = clock
        try ListActions.setAssignee(plain, "anne", in: context, now: clock)
        XCTAssertEqual(plain.pendingFields, [.assignee])
        try ListActions.setAssignee(plain, nil, in: context, now: clock)
        XCTAssertNil(plain.assignee)
    }

    func testUndoOfAnOwnedStepAfterTheDeleteWentOutKeepsTheOwnerAndFlagsIt() throws {
        let step = SubtaskRecord(id: "st-1", projectId: "p", title: "Bag it", sortOrder: 0, assignee: "wes",
                                 done: true, doneBy: "anne", doneAt: clock, createdAt: clock, syncedAt: clock)
        context.insert(step)
        try context.save()
        try ListActions.removeSubtask(step, in: context, now: clock)
        step.deleteSynced = true
        let copy = try ListActions.restoreSubtask(step, in: context, now: clock)
        XCTAssertEqual(copy.assignee, "wes")
        XCTAssertEqual(copy.pendingFields, [.done, .assignee])
    }
```

`ProjectFieldsSyncTests.swift`:

```swift
    func testAStepAddedWithAnOwnerPostsTheOwnerAndA201ClearsIt() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let project = ProjectRecord(id: "p-5", title: "Garage", createdAt: listClock, syncedAt: listClock)
        project.seq = 3
        ctx.insert(project)
        try ctx.save()
        let step = try XCTUnwrap(try ListActions.addSubtask("Bag it", to: project, assignee: "wes", in: ctx, now: listClock))
        let id = step.id
        StubURLProtocol.reset { req in
            let row = subtaskJSON(id: id, projectId: "p-5", title: "Bag it", assignee: "wes", seq: 7)
            if req.httpMethod == "POST" {
                return (201, json(row))
            }
            return (200, listsSyncJSON(cursor: 7, subtasks: [row]))
        }
        _ = await client.syncNow()
        let post = try XCTUnwrap(StubURLProtocol.requests("POST").first)
        XCTAssertEqual(post.path, "/projects/p-5/subtasks")
        XCTAssertEqual(post.body?["assignee"] as? String, "wes")
        XCTAssertEqual(StubURLProtocol.requests("PATCH").count, 0, "the create carried the owner")
        XCTAssertEqual(try subtaskRow(id)?.pendingPatch, 0)
    }

    func testOwnerPatchSendsOnlyTheOwnerAndTheDoerStaysWhoeverTapped() async throws {
        try await pairAsAnne()
        let ctx = fresh()
        let step = SubtaskRecord(id: "st-9", projectId: "p-5", title: "Haul it", sortOrder: 1, createdAt: listClock, syncedAt: listClock)
        step.seq = 8
        ctx.insert(step)
        try ctx.save()
        try ListActions.setAssignee(step, "wes", in: ctx, now: listClock)
        StubURLProtocol.reset { req in
            let row = subtaskJSON(id: "st-9", projectId: "p-5", title: "Haul it", sortOrder: 1, assignee: "wes", seq: 9)
            if req.httpMethod == "PATCH" {
                return (200, json(row))
            }
            return (200, listsSyncJSON(cursor: 9, subtasks: [row]))
        }
        _ = await client.syncNow()
        let patch = try XCTUnwrap(StubURLProtocol.requests("PATCH").first)
        XCTAssertEqual(patch.path, "/subtasks/st-9")
        XCTAssertEqual(patch.body?["assignee"] as? String, "wes")
        XCTAssertNil(patch.body?["done"])
        XCTAssertNil(patch.body?["title"])

        StubURLProtocol.reset { _ in
            (200, listsSyncJSON(cursor: 10, subtasks: [
                subtaskJSON(id: "st-9", projectId: "p-5", title: "Haul it", sortOrder: 1, done: true, doneBy: "anne", doneAt: listStamp, assignee: "wes", seq: 10),
            ]))
        }
        _ = await client.syncNow()
        let row = try XCTUnwrap(try subtaskRow("st-9"))
        XCTAssertEqual(row.assignee, "wes")
        XCTAssertEqual(row.doneBy, "anne", "the owner and the doer are two facts")

        var older = subtaskJSON(id: "st-old", projectId: "p-5", title: "Old server", seq: 11)
        older.removeValue(forKey: "assignee")
        StubURLProtocol.reset { _ in (200, listsSyncJSON(cursor: 11, subtasks: [older])) }
        XCTAssertEqual(await client.syncNow(), .synced(posted: 0, deleted: 0, received: 1))
        XCTAssertNil(try subtaskRow("st-old")?.assignee)
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `xcodebuild … -only-testing:RoostTests/ListCraftTests -only-testing:RoostTests/ProjectFieldsSyncTests test 2>&1 | grep -E "error:|failed" | head`
Expected: compile errors — `SubtaskRecord` has no `assignee`.

- [ ] **Step 3: Implement**

`ListRecords.swift`: `static let assignee = PatchFields(rawValue: 1 << 9)`; `SubtaskRecord` gains `var assignee: String?` after `sortOrder`, the `init` parameter `assignee: String? = nil` after `sortOrder`, and `self.assignee = assignee`; doc comment: "`assignee` is who the step is meant for (`anne`, `wes`, nil); `doneBy` is who ticked it, and the two can differ."

`ListActions.swift`:

```swift
    /// Appends after the project's highest live step, the same default the server uses. An owner given
    /// here is flagged as an edit as well: a step that rides its project's create goes out without it,
    /// and the flag is what sends it after.
    @discardableResult
    static func addSubtask(_ title: String, to project: ProjectRecord, assignee: String? = nil,
                           in context: ModelContext, now: Date = Date()) throws -> SubtaskRecord?
    {
        guard let title = cleaned(title) else { return nil }
        let siblings = try liveSubtasks(of: project.id, in: context)
        let next = (siblings.map(\.sortOrder).max() ?? -1) + 1
        let subtask = SubtaskRecord(
            id: newId(), projectId: project.id, title: title, sortOrder: next, assignee: assignee, createdAt: now
        )
        if assignee != nil {
            subtask.pendingFields = .assignee
        }
        context.insert(subtask)
        try context.save()
        return subtask
    }

    /// `anne`, `wes`, or nil for nobody.
    static func setAssignee(_ subtask: SubtaskRecord, _ person: String?, in context: ModelContext,
                            now: Date = Date()) throws
    {
        subtask.assignee = person
        subtask.markEdited(.assignee, at: now)
        try context.save()
    }
```

In `restoreSubtask` and in `restoreProject`'s step loop, the copies pass `assignee: subtask.assignee` / `assignee: step.assignee` (after `sortOrder`) and the flag block becomes:

```swift
        var pending: PatchFields = []
        if copy.done {
            pending.insert(.done)
        }
        if copy.assignee != nil {
            pending.insert(.assignee)
        }
        copy.pendingFields = pending
```

(in `restoreProject` the variable is `stepCopy`.)

`SyncAPI+Lists.swift`: `SubtaskDTO` gains `let assignee: String?` after `sortOrder`; `postSubtask` becomes

```swift
    /// 400 when the project is unknown or deleted. `assignee` rides the create (null for nobody).
    func postSubtask(
        projectId: String, id: String, title: String, sortOrder: Int, assignee: String?
    ) async throws -> Posted<SubtaskDTO> {
        let body: Fields = [
            "id": .string(id), "title": .string(title), "sortOrder": .int(sortOrder),
            "assignee": assignee.map { .string($0) } ?? .null,
        ]
        return try await post("projects/\(projectId)/subtasks", body: body)
    }
```

`ListSync+Records.swift`, `SubtaskRecord` extension: `init` passes `assignee: dto.assignee`; `apply` gains `if !dirty.contains(.assignee) { assignee = dto.assignee }`; `patchBody` gains `if pendingFields.contains(.assignee) { body["assignee"] = assignee.map { .string($0) } ?? .null }`.

`ListSync.swift`, `postSubtasks`: the call passes `assignee: step.assignee`, and the 201 line becomes `step.pendingFields.subtract([.title, .sortOrder, .assignee])`. (`postProjects` keeps `subtract([.title, .sortOrder])`: the project create carries no owner, so the flag stays and a PATCH follows.)

`Strings.swift`, `enum Projects`:

```swift
        /// The owner picker on a step and in the step composer.
        static let owner = "Owner"
        static let nobody = "Nobody"
        /// VoiceOver, on an owned step: "For Wes".
        static func ownedBy(_ name: String) -> String {
            "For \(name)"
        }
```

`ProjectsScreen.swift`:

- `SubtaskRow` gains `let onAssign: (String?) -> Void`. Its `value` gains `Strings.Projects.ownedBy(person.displayName)` when `Person(rawValue: step.assignee ?? "")` exists. In the non-accessibility branch, after the `NotSyncedMarker`, and in the accessibility branch's title `HStack`, add:

```swift
                    if let owner = Person(rawValue: step.assignee ?? "") {
                        PersonAvatar(person: owner)
                    }
```

(`PersonAvatar`'s own accessibility label reads "Added by Wes"; give it `.accessibilityLabel(Strings.Projects.ownedBy(owner.displayName))` here so a step says "For Wes".) Add a `.contextMenu` on the row's `Button`:

```swift
        .contextMenu {
            Picker(Strings.Projects.owner, selection: Binding(get: { step.assignee }, set: onAssign)) {
                Text(Strings.Projects.nobody).tag(String?.none)
                ForEach(Person.allCases, id: \.self) { person in
                    Text(person.displayName).tag(Optional(person.rawValue))
                }
            }
        }
```

and the accessibility actions gain one per person and one for nobody (`Button(Strings.Projects.nobody) { onAssign(nil) }`, `Button(person.displayName) { onAssign(person.rawValue) }`), because a context menu is a gesture VoiceOver users do not make.

- `card(_:)` passes `onAssign: { setAssignee(step, $0) }` and the screen gains `private func setAssignee(_ step: SubtaskRecord, _ person: String?) { try? ListActions.setAssignee(step, person, in: context); sync.syncSoon() }`.
- `SubtaskComposer`: `onAdd` becomes `(String, String?) -> Bool`; it gains `@State private var owner: String?` and, after the `TextField`, a `Menu` whose label is the chosen person's avatar or `Image(systemName: "person.crop.circle")` in the secondary ink, containing the same `Picker` bound to `$owner`, with `.accessibilityLabel(Strings.Projects.owner)`; `submit` calls `onAdd(draft, owner)` and clears `owner` on success. The screen's `add(_:to:)` becomes `add(_ text: String, owner: String?, to project:)` and passes `assignee: owner`.

- [ ] **Step 4: Run the full suite and look at the row**

Run the `xcodebuild … test` line. Expected: `** TEST SUCCEEDED **`. In the simulator: long-press a step → Owner → Wes → a "W" avatar at the row's trailing edge; Nobody clears it; the composer's person button picks an owner for the next step.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources Roost/Tests
git commit -m "app: an owner on a step — record, sync, the row menu and the composer's picker"
```

### Task 11: The morning-of reminder for a due project

**Files:**
- Modify: `Roost/Sources/Notifications/NotificationPlanner.swift`
- Modify: `Roost/Sources/Notifications/NotificationScheduler.swift:100-135` (`currentPlan`)
- Modify: `Roost/Sources/Strings.swift` (`enum Projects`)
- Modify: `Roost/Tests/NotificationTests.swift`

**Interfaces:**
- Consumes: `ProjectRecord.dueOn`, `SubtaskRecord`, `ProjectProgress`, `NotificationPlanner.dayKey` / `time` / `identifierPrefix`.
- Produces: `struct DueProject: Hashable, Sendable { let id: String; let title: String; let dueOn: String }`; `NotificationPlanner.projectHour = 9`; `NotificationPlanner.planProjects(_:on:now:calendar:) -> [PlannedNotification]` — one per project whose `dueOn` is the day, id `roost.project.<id>.<day>`, title "Due today", body `Strings.Projects.dueToday(title)` ("Garage trash is due today"), fire time 09:00 Chicago, dropped when already past `now`; the scheduler feeds it every live, unfinished project with a day, for each day of its horizon.

- [ ] **Step 1: Write the failing tests**

In `NotificationPlannerTests`:

```swift
    func testAProjectDueTodayIsOneMorningNotificationAndTomorrowsIsNot() {
        let projects = [
            DueProject(id: "p-garage", title: "Garage trash", dueOn: "2026-09-06"),
            DueProject(id: "p-fence", title: "Fence", dueOn: "2026-09-07"),
        ]
        let planned = NotificationPlanner.planProjects(projects, on: Fixture.morning, now: Fixture.morning, calendar: Fixture.cal)
        XCTAssertEqual(planned.map(\.id), ["roost.project.p-garage.2026-09-06"])
        XCTAssertEqual(planned.first?.title, "Due today")
        XCTAssertEqual(planned.first?.body, "Garage trash is due today")
        XCTAssertEqual(planned.first?.fireAt, Fixture.nineAM)

        let tomorrow = Fixture.cal.adding(days: 1, to: Fixture.morning)
        let next = NotificationPlanner.planProjects(projects, on: tomorrow, now: Fixture.morning, calendar: Fixture.cal)
        XCTAssertEqual(next.map(\.id), ["roost.project.p-fence.2026-09-07"])

        let late = NotificationPlanner.planProjects(projects, on: Fixture.morning, now: Fixture.evening, calendar: Fixture.cal)
        XCTAssertEqual(late, [], "09:00 has passed by 19:00")
    }
```

In `NotificationSchedulerTests` (its `setUpWithError` seeds chores and completions; the paired person is set the way the existing scheduler tests do it — copy that line):

```swift
    func testADueProjectIsScheduledAndAFinishedOneIsNot() async throws {
        let ctx = ModelContext(container)
        let state = try ChoreSeeder.syncState(in: ctx)
        state.person = Person.anne.rawValue
        let garage = ProjectRecord(id: "p-garage", title: "Garage trash", dueOn: "2026-09-06", createdAt: now, syncedAt: now)
        let fence = ProjectRecord(id: "p-fence", title: "Fence", dueOn: "2026-09-06", createdAt: now, syncedAt: now)
        ctx.insert(garage)
        ctx.insert(fence)
        ctx.insert(SubtaskRecord(id: "st-1", projectId: "p-fence", title: "Done already", sortOrder: 0, done: true, createdAt: now, syncedAt: now))
        try ctx.save()

        await scheduler().replan()
        let ids = Set(center.pending.map(\.identifier))
        XCTAssertTrue(ids.contains("roost.project.p-garage.2026-09-06"), "\(ids)")
        XCTAssertFalse(ids.contains("roost.project.p-fence.2026-09-06"), "a finished project is not reminded")
        XCTAssertTrue(ids.contains("roost.digest.2026-09-06"), "the chore plan is still there")

        try ListActions.setDueOn(garage, nil, in: ctx, now: now)
        await scheduler().replan()
        XCTAssertFalse(Set(center.pending.map(\.identifier)).contains("roost.project.p-garage.2026-09-06"))
    }
```

- [ ] **Step 2: Run to see them fail**

Run: `xcodebuild … -only-testing:RoostTests/NotificationPlannerTests -only-testing:RoostTests/NotificationSchedulerTests test 2>&1 | grep -E "error:|failed" | head`
Expected: compile errors — `DueProject` and `planProjects` do not exist.

- [ ] **Step 3: Implement**

`Strings.swift`, `enum Projects`: `static func dueToday(_ title: String) -> String { "\(title) is due today" }` with the comment "The morning-of reminder's body."

`NotificationPlanner.swift`: the header comment gains "09:00 Chicago  one notification per project due that day ("Garage trash is due today")". After `PlannedNotification`:

```swift
/// A live, unfinished project with a due day, as the scheduler hands it to the planner.
struct DueProject: Hashable, Sendable {
    let id: String
    let title: String
    /// `YYYY-MM-DD`, Chicago.
    let dueOn: String
}
```

In the enum, `static let projectHour = 9` after `overdueHour`, and after `badgeCount`:

```swift
    /// One notification per project due on the day containing `date`, at 9 in the morning, dropped when
    /// that moment has already passed. Both people get it: a project is the household's, not a person's.
    static func planProjects(_ projects: [DueProject], on date: Date, now: Date,
                             calendar: HouseholdCalendar = HouseholdCalendar()) -> [PlannedNotification]
    {
        let day = dayKey(date, calendar: calendar)
        let fireAt = time(projectHour, on: date, calendar: calendar)
        return projects
            .filter { $0.dueOn == day }
            .map { project in
                PlannedNotification(
                    id: "\(identifierPrefix)project.\(project.id).\(day)",
                    title: "Due today",
                    body: Strings.Projects.dueToday(project.title),
                    fireAt: fireAt
                )
            }
            .filter { $0.fireAt > now }
    }
```

`NotificationScheduler.swift`, in `currentPlan` after the handoffs fetch:

```swift
        // Projects with a due day, minus the finished ones: one reminder on the morning of the day.
        let dated = try context.fetch(FetchDescriptor<ProjectRecord>(
            predicate: #Predicate { !$0.removed && $0.dueOn != nil }
        ))
        let steps = Dictionary(grouping: try context.fetch(FetchDescriptor<SubtaskRecord>(
            predicate: #Predicate { !$0.removed }
        )), by: \.projectId)
        let dueProjects = dated.compactMap { project -> DueProject? in
            guard let dueOn = project.dueOn,
                  !ProjectProgress(steps: steps[project.id] ?? [], isDone: \.done).isFinished
            else { return nil }
            return DueProject(id: project.id, title: project.title, dueOn: dueOn)
        }
```

and inside the horizon loop, after the chore plan line: `planned += NotificationPlanner.planProjects(dueProjects, on: day, now: now, calendar: calendar)`. The header comment gains a line for the project reminder.

- [ ] **Step 4: Run the full suite**

Run the `xcodebuild … test` line. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Roost/Sources/Notifications Roost/Sources/Strings.swift Roost/Tests/NotificationTests.swift
git commit -m "app: a local reminder on the morning a project is due"
```

### Task 12: Fixtures, audits, docs, screenshots, and the A2 PR

**Files:**
- Modify: `Roost/Sources/Debug/UITestSeed.swift` (the project fixture gains a due day and an owned step)
- Modify: `Roost/UITests/AccessibilityAuditTests.swift` (`testProjectsAudit` waits for the owned step)
- Modify: `Roost/README.md`, `NOTES.md`

- [ ] **Step 1: The fixture**

`UITestSeed.swift`: `SeededStep` gains `var assignee: Person?`; `SeededProject` gains `var dueInDays: Int?`. "Clear out the garage" gets `dueInDays: 3` and its "Shelve what stays" step `assignee: .wes`. In `seedProjects`, the record is built with `dueOn: project.dueInDays.map { ProjectDates.dayString(day($0)) }` and each subtask with `assignee: step.assignee?.rawValue`. Update the comment above `projects` ("…the other card is one tap away at 2 of 4, due in three days, with one step that is Wes's").

- [ ] **Step 2: The audit**

`testProjectsAudit`: after waiting for "Shelve what stays", also assert `app.buttons["Shelve what stays"].value as? String` contains "For Wes" (the owner is spoken), and add `customFontScales("Due …")` is unnecessary — the due label is a `RoostType` rung, so if the audit reports it, add `KnownIssue(compact: "Dynamic Type font sizes are partially unsupported", element: nil, reason: "the due-day caption is a RoostType rung")` only if the run reports it; do not add it blind.

Run the UI tests: `xcodebuild … -only-testing:RoostUITests test 2>&1 | grep -E "Test Case.*(passed|failed)|TEST"`. Expected: every audit passes.

- [ ] **Step 3: Docs and screenshots**

- `Roost/README.md`: the history sentence gains "and gave projects an optional due day and steps an optional owner, with a reminder on the morning a project is due". Screens → Projects paragraph: "A card can carry a due day (long-press → Set a due day; `ProjectRecord.dueOn`, a Chicago calendar day) shown as "Due Sep 20", in the danger role once the day has passed and the project is not finished; on the morning of the day the phone posts "Garage trash is due today" through `NotificationPlanner.planProjects`. A step can carry an owner (long-press → Owner, or the person button in the step composer; `SubtaskRecord.assignee`), shown as the person's avatar at the trailing edge; completing a step still stamps whoever tapped." Layout: `Models/ListPresentation.swift` line mentions `ProjectDates`; `Notifications/NotificationPlanner.swift` mentions the project reminder. Fixtures table: `paired` gains "one project due in three days with a step that is Wes's". The test-count sentence gains the new suites (project due days: the label, past-due, the day round trip, set and clear; step owners: flagged on add, set later, kept through undo; the two fields through sync: patch alone, clear with null, the delta, an older server's missing key; the reminder: one per due project at 09:00, none for tomorrow's or a finished one, dropped once 09:00 has passed, and the scheduler feeds live unfinished dated projects).
- Recapture `projects.png` and `projects-dark.png` with the open card showing the due label and the owned step (`xcrun simctl io booted screenshot Roost/docs/projects.png`, then with the simulator in dark appearance).
- `NOTES.md`: under the tabs line add "**Projects (2026-09-13):** a due day per project and an owner per step, from Anne's issue #1 notes; the morning-of reminder is local to the phone until the reminders design moves it to the server."

- [ ] **Step 4: Commit and open the A2 PR**

```bash
git add Roost/Sources/Debug/UITestSeed.swift Roost/UITests Roost/README.md Roost/docs NOTES.md
git commit -m "app: fixtures, audits and docs for project due days and step owners"
git fetch origin && git rebase origin/main
cd Roost && xcodegen generate && cd .. && git status --short   # must be clean
xcodebuild -project Roost/Roost.xcodeproj -scheme Roost -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test 2>&1 | grep -E "TEST (SUCCEEDED|FAILED)"
gh api -X POST repos/amnanninga4/roost/pulls -f title="App: project due days, step owners, the morning-of reminder" -f head=app/project-dates-owners -f base=main -F body=@/dev/stdin <<'EOF'
Lane A2 of docs/superpowers/plans/2026-09-13-new-bar-lists.md (tasks 9–12). Needs the A1 PR merged first and R-30 deployed (the two fields 400 against an older server and the rows sit rejected until then).

Screenshots: (attach the Projects page with a due label and an owned step, light and dark.)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```

---

## Self-review against the spec

- **The bar** — Task 7 (`RootTab`, titles, symbols, `openTasksRequests` untouched, `RootTabsTests`); the gear's retirement, `Strings.Tasks.gear` deleted, the unpaired line, the UI helper — Task 8.
- **Lists** — Task 7: one screen, the segmented control, the paged `TabView` on the same selection, `AppStorage`, each page keeps its state (`ListsBehaviourTests`), pages keep their header title, chrome applied once by the container, symbols with accessibility labels at accessibility sizes.
- **Wishlist** — Tasks 4 (record with the spec's field table, `PatchFields.price`, the actions, `PriceParser`, `PriceFormat`, `WishlistTotals`, strings), 5 (DTO, three calls, `SyncResponse.wishlist`, the loops, the delta), 6 (row: title, price chip, avatar, "Didn't sync"; header "4 items · $1,850 total"; composer with a number-pad price field; newest first; Bought section and clear), 1 (server table with the CHECK, routes, `/sync`, cursor), 3 (README "eight").
- **Projects: due day** — Tasks 9 (record, sync, `ProjectDates`, the card's "Due Sep 20", danger when past and unfinished, menu with a date picker, set and clear), 11 (the morning-of local notification through the existing planner), 2 (server column, validated as a real day, POST and PATCH, returned in the shape).
- **Projects: step owner** — Tasks 10 (record, sync, the row menu Anne / Wes / Nobody, the composer's picker, avatar at the trailing edge, `doneBy` unchanged), 2 (server column with the CHECK, POST and PATCH, returned in the shape). No notification or board behaviour is attached to an owner.
- **More** — Task 8: Household (Kitchen mode full screen, All chores pushed), This phone (Settings pushed with the back button, Sync now with the status line), footer version.
- **Server schema** — Task 1 (`CREATE TABLE IF NOT EXISTS`), Task 2 (schema version 3 with `ALTER TABLE … ADD COLUMN`, on R-29's mechanism). The app side is two optional properties and one new model (Tasks 4, 9, 10).
- **Tests** listed in the spec — `RootTabsTests` (7), the UI-test base helpers (7, 8), the per-screen audits (7, 8, 12), `lists.test.js` for the five arrays and the cursor (1), the `ListSyncTestCase` builders (5, 9, 10); added: Lists state and the remembered page (7), the wishlist round trip and price parsing and the header total (4, 5), server wishlist validation and routes (1), `dueOn` accepted / patched / cleared / rejected (2, 9), `assignee` accepted and rejected (2, 10), the local notification (11), audits for Lists and More (7, 8).
- **Docs and screenshots** — Tasks 3, 8, 12: `Roost/README.md` (tabs, screenshot table, layout, Screens, fixtures), `NOTES.md`, `server/README.md`, root `README.md`; `lists.png`, `wishlist.png` (+ dark), `more.png`, the recaptured Shopping / Meals / Projects.
- **Not in this change** — nothing here touches Calendar, reminders on the server, Goals, wishlist reorder or categories, pushes about an owner, or a price on Shopping.
- **Type consistency** — `WishlistItemRecord.priceCents` / `WishlistDTO.priceCents` / `PatchFields.price` / body key `priceCents` (4, 5); `ProjectRecord.dueOn` / `ProjectDTO.dueOn` / `PatchFields.dueOn` / body key `dueOn` (9); `SubtaskRecord.assignee` / `SubtaskDTO.assignee` / `PatchFields.assignee` / body key `assignee` (10); `postSubtask(projectId:id:title:sortOrder:assignee:)` used in 10's `ListSync.swift` edit; `openList(_:in:)` / `openFromMore(_:in:)` used in 7, 8, 12; `ListPage.storageKey` in 7's test and screen; `AppVersion.line` in 8's two screens.
- **The one spec wording resolved here** — the owner's avatar sits at the trailing edge (Task 10 says why); if Anne wanted it beside the leading circle, that is a one-line move in `SubtaskRow`.
