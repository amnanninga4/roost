# data/

Structured seed data for Roost.

## `chores.json`

Locked household chore list promoted from `chore-master-list.html` (2026-09-13).

Each chore:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Stable slug (unique) |
| `title` | string | Display title from master list |
| `cadence` | string | `daily` \| `weekly` \| `biweekly` \| `monthly` |
| `fixedAssignee` | string \| null | `anne` \| `wes` \| `null` |
| `category` | string | `chore` \| `cat_care` |

Pinned from the master list: **Laundry → anne**, **Garbage can to street, Sunday → wes**.

Do **not** seed from `roost-app-mockup.html` sample rows.

Count note: the HTML meta / NOTES say “32 tasks”, but the list body has **31** items (11+9+5+6). This file matches the body.

## Validate

```bash
python3 scripts/validate-chores.py
```

Stdlib only; exits non-zero on bad JSON, schema, wrong count, duplicate ids, or invalid cadence/assignee/category.
