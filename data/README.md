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
| `weekdays` | `[int]` \| absent | Optional; weekly only; Mon = 1 … Sun = 7, ascending unique; window = earliest…latest day of the period's week |
| `dueDay` | int \| absent | 1–28; required on monthly / bimonthly / quarterly; window = the 7 days ending on it in the period's last month |
| `rotation` | object \| absent | Optional; never with a pin. `weekdayCycle` (daily only): 1–4 Monday-first week tables of `anne`/`wes`. `alternate`: `start` owns every even period index, the other person the odd ones (not keyed off `activeFrom`) |
| `missPenalty` | object \| absent | Optional `{watch, overMisses}`; counted over the chore's **calendar** period; beats the rotation and loses to a pin or an accepted handoff |

Pinned: **Laundry → anne**, **Wash all rugs → anne**, **Mow lawn → anne**, **Trim Wes's hair → anne**, **Garbage can to street, Sunday → wes**, **Change bed sheets → anne**, **AM wet cat food → wes**, **PM wet cat food → anne**, **Charge the cat play device → wes**, **Put the toy out for the cats → anne**.

Due windows (v4):

| Chore | Window |
|---|---|
| take-out-garbage-basement, -bathroom, -kitchen | weekdays [5, 6] |
| garbage-can-to-street-sunday | weekdays [7] |
| clean-under-cushions | dueDay 5 |
| wash-all-rugs | dueDay 8 |
| trim-wes-hair (bimonthly) | dueDay 10 |
| clean-inside-ovens | dueDay 12 |
| clean-garbage-cans (quarterly) | dueDay 14 |
| wipe-dust-bar-cart | dueDay 15 |
| clean-under-couches | dueDay 19 |
| wipe-down-doors (quarterly) | dueDay 21 |
| clean-medicine-cabinet | dueDay 22 |
| change-litter | dueDay 25 |
| clean-out-fridge-pantry (quarterly, together) | dueDay 28 |

### Litter

Two separate rotations (Anne's feedback on issue #1). Scooping is daily with a two-week `weekdayCycle`: week A Anne Mon/Wed/Fri/Sun and Wes Tue/Thu/Sat, week B swapped, so whoever had four days last week has three this week. Changing is monthly, alternates from Wes (`start: wes` owns even monthly indexes), and carries a `missPenalty` on scooping — more than two missed scoop days in the month moves that month's change to the misser.

Do **not** seed from `roost-app-mockup.html` sample rows.

Count: **41** items (13+12+5+7+1+3), version 5 since 2026-09-15; the previous lists were 41 (version 4, 2026-09-14), 41 (version 3, 2026-09-14), 39 (11+12+5+7+1+3, version 2, 2026-09-13) and 31 (11+9+5+6).

## Validate

```bash
python3 scripts/validate-chores.py
```

Stdlib only; exits non-zero on bad JSON, schema, wrong count, duplicate ids, invalid cadence/assignee/category, broken grouping order, season/together rules, window rules (weekdays / dueDay), rotation/missPenalty rules, a mismatched pinned set, a mismatched window map, or a mismatched rotation/penalty map.
