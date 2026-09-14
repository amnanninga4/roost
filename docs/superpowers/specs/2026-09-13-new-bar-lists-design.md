# The new bar, Lists, Wishlist, and project dates — design

2026-09-13. Source: Wes's decision on the tab bar (chat, 19:58 CDT) and Anne's notes on issue #1 (Wishlist tab; projects with a due date and a person per step). Status: draft for Wes and Anne to review before implementation.

## What this changes

The bottom bar becomes **Tasks · Calendar · Lists · More**. This design ships three of the four: Tasks stays as it is, Lists gathers Shopping, Meals, Projects and a new Wishlist under one tab, and More is a page holding what the gear menu holds today. The Calendar tab is added by the reminders-and-calendar design and slots in second; nothing here reserves a placeholder for it.

Projects gain an optional due day and an optional person per step, which Anne asked for and which the Lists work touches anyway.

## The bar

`RootTab` becomes `tasks, lists, more` (the calendar case arrives with its screen). Titles come from `Strings.Tabs`; symbols: `checklist` (unchanged), `list.bullet.rectangle` for Lists, `ellipsis.circle` for More. The push-to-Tasks hook (`openTasksRequests`) is unchanged. `RootTabsTests` pins the new count, order, titles and symbols.

The gear menu on Tasks goes away. Its four entries move to the More page, so the Tasks header loses the gear and the "Not paired yet · gear menu → Settings" line becomes "Not paired yet · More → Settings". `Strings.Tasks.gear` is deleted; the UI-test helper that opened the gear becomes a helper that opens the More tab and taps a row.

## Lists

One screen, one tab. At the top, under the tab's title, a segmented control with four segments: Shopping, Meals, Projects, Wishlist. Below it the lists page horizontally, `TabView` in page style with the indicator hidden, bound to the same selection, so a swipe and a tap do the same thing and every list keeps its state (a five-second undo bar survives switching away and back). The chosen segment is remembered per phone in `AppStorage` and restored on launch.

Each page is the existing screen body: `ShoppingScreen`, `MealsScreen`, `ProjectsScreen` keep their header line, composer, sections, undo and rejected-row handling. The one visible change inside them is that the header title reads the list name as now, so the UI tests' rule that a page prints its own title still holds. The screen-level chrome (`listTabChrome`) moves up to the Lists container so it is applied once.

At accessibility text sizes the segmented control truncates; the segments then show SF Symbols with the names as accessibility labels (`cart`, `fork.knife`, `hammer`, `gift`), and the audit for this screen checks it.

## Wishlist

A shared list of things to buy eventually, each with an optional price. Either person adds; either person can mark one bought, which moves it to a Bought section exactly like Shopping.

**Row:** title, a price chip when present ("$599"), the adder's avatar, the "Didn't sync" marker on rejection. **Header line:** "4 items · $1,850 total" over the open items (total omitted when no item has a price). **Composer:** the title field with a second field for the price using the number pad; the price is parsed as dollars and cents and stored as integer cents. Empty price is allowed. Sorted newest first; no reorder.

Model, mirroring `ShoppingItemRecord`:

| Field | Type | Notes |
|---|---|---|
| id | String, unique | client-generated |
| title | String | 1 to 200 characters |
| priceCents | Int? | 0 to 99,999,999 or nil |
| addedBy | String | from the token on the server |
| bought, boughtBy, boughtAt | as Shopping | |
| createdAt, updatedAt | Date | |
| sync bookkeeping | as every `ListRecord` | `syncedAt, removed, deleteSynced, rejected, seq, pendingPatch` |

`PatchFields` gains a `price` bit. Server table `wishlist_items` with the same columns and a `CHECK (priceCents IS NULL OR priceCents BETWEEN 0 AND 99999999)`. Routes `POST /wishlist`, `PATCH /wishlist/:id` (title, priceCents, bought), `DELETE /wishlist/:id`, validated like Shopping with one added rule for the price. `/sync` gains a `wishlist` array and the cursor arithmetic includes it; the README's "seven sync tables" becomes eight. Everything generic on both sides (row helpers, `ListRecord`, `outbound`, `patch`, `upsert`, the composer, undo) is reused; the per-list pieces (record, DTO, three endpoints, apply/patchBody, the loops in `replayCreates`/`replayEdits`/`replayRemovals`/`applyListDelta`, `ListActions`, `Strings.Wishlist`, the screen) are added following the Shopping pattern line for line.

The status board and the widget do not show lists and do not change.

## Projects: a due day and a person per step

**Due day.** `ProjectRecord.dueOn: String?`, a calendar day `YYYY-MM-DD` in America/Chicago, the same shape as the household start date. Set or cleared from the project card's menu with a date picker; shown on the card as "Due Sep 20", in the danger role once the day has passed and the project is not finished. On the morning of the due day the phone posts a local notification through the existing planner ("Garage trash is due today"); the server-side digest learns about dated things in the reminders design, not here. Server: `projects.dueOn TEXT NULL` validated as a date, accepted on POST and PATCH, returned in the project shape.

**Step owner.** `SubtaskRecord.assignee: String?` (`anne`, `wes`, or nil). Set from the step row's menu (Anne / Wes / Nobody) and optionally when adding a step. Shown as the person's avatar at the trailing edge of the step, before the check circle. Completing a step still stamps `doneBy` with whoever tapped; the owner is who it was meant for, and the two can differ. Server: `project_subtasks.assignee TEXT NULL CHECK (assignee IN ('anne','wes'))`, accepted on POST and PATCH, returned in the subtask shape. No notification or board behavior is attached to an owner in this change.

## More

A grouped list under the title "More":

- **Household:** Kitchen mode (opens full screen, as today), All chores (pushed).
- **This phone:** Settings (pushed rather than presented as a sheet; its Close button becomes the back button), Sync now with the sync status line beneath it.
- Footer: app name and version, the same line Settings shows today.

Goals will be the first row under Household when that design ships.

## Server schema

`wishlist_items` is a new table, so `CREATE TABLE IF NOT EXISTS` is enough. The two added columns use the `schemaVersion` migration mechanism from the chores-update design; whichever of the two designs lands first introduces it. Both columns are nullable, so `ALTER TABLE … ADD COLUMN` inside the versioned step is sufficient.

On the phone, one new model and two optional properties are lightweight SwiftData migrations; nothing else is needed.

## Tests

Update: `RootTabsTests` (three tabs); the UI-test base (`openTab("Lists")` plus a segment helper; the More helper); the per-screen audits that navigate through the old tabs and the gear; server `lists.test.js` for the eight-array sync and the cursor; the Roost `ListSyncTestCase` JSON builders.

Add: Lists keeps each page's state across segment switches and restores the remembered segment; Wishlist round trip through sync (create with and without price, patch price, mark bought, delete, rejection marker), price parsing ("599", "12.5", "$1,299.99", junk), header total; server wishlist validation and routes; project `dueOn` accepted, patched, cleared, rejected when malformed; subtask `assignee` accepted and rejected; the local notification on a due day; audits for the Lists screen (all four segments) and the More page.

## Docs and screenshots

`Roost/README.md`: the tab description, the screenshot table, the layout listing, the Screens section, the UI-test fixtures table (the `paired` fixture gains two wishlist rows, one project with a due day, one owned step). `NOTES.md` tabs line. `server/README.md`: model bullets, endpoints table, sync row, validation paragraph. Root `README.md` feature sentence. Screenshots: `lists.png` (Shopping segment) and `wishlist.png` with dark variants, `more.png`; the existing shopping, meals and projects PNGs are recaptured inside the Lists tab.

## Not in this change

- The Calendar tab and screen, reminders, events: the next design.
- Goals: its own design; the More row appears with it.
- Wishlist reorder, categories, links to product pages.
- Notifications or pushes tied to a step's owner.
- A price on Shopping items.
