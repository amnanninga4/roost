# data/

Structured seed data for Roost.

## `chores.json`

Locked household chore list promoted from `chore-master-list.html` (2026-09-13).

Each chore:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Stable slug (unique) |
| `title` | string | Display title from master list |
| `cadence` | string | `daily` \| `weekly` \| `biweekly` \| `monthly` \| `bimonthly` \| `quarterly` |
| `fixedAssignee` | string \| null | `anne` \| `wes` \| `null` |
| `category` | string | `chore` \| `cat_care` |
| `season` | object \| absent | Optional `{"months":[1..12]}`; not on a together chore; cadence at most monthly |
| `together` | bool \| absent | Optional; both people owe it; `fixedAssignee` must be null |

Pinned: **Laundry → anne**, **Wash all rugs → anne**, **Mow lawn → anne**, **Trim Wes's hair → anne**, **Garbage can to street, Sunday → wes**, **Change bed sheets → anne**, **AM wet cat food → wes**, **PM wet cat food → anne**, **Charge the cat play device → wes**, **Put the toy out for the cats → anne**.

Do **not** seed from `roost-app-mockup.html` sample rows.

Count: **41** items (13+12+5+7+1+3), version 3 since 2026-09-14; the previous lists were 39 (11+12+5+7+1+3, version 2, 2026-09-13) and 31 (11+9+5+6).

## Validate

```bash
python3 scripts/validate-chores.py
```

Stdlib only; exits non-zero on bad JSON, schema, wrong count, duplicate ids, invalid cadence/assignee/category, broken grouping order, season/together rules, or a mismatched pinned set.
