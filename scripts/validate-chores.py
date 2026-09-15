#!/usr/bin/env python3
"""Validate data/chores.json against the Roost chore seed schema.

Schema (simple, Swift/SwiftData-friendly):
  Root object:
    version: int          # 4 since the 2026-09-14 due-windows update
    source: str           # e.g. "chore-master-list.html"
    locked: str           # ISO date the list was settled
    notes: str            # optional human note
    chores: list[Chore]

  Chore object:
    id: str                    # stable slug, unique
    title: str                 # display title
    cadence: str               # daily | weekly | biweekly | monthly | bimonthly | quarterly
    fixedAssignee: str|null    # anne | wes | null
    category: str              # chore | cat_care
    season: {"months": [int]}  # optional: 1..12, non-empty, unique; not on a together chore; not on a
                               # cadence longer than monthly
    together: bool             # optional: both people owe it; fixedAssignee must be null
    weekdays: [int]            # optional: weekly only, Mon=1…Sun=7, ascending unique; window = min…max
    dueDay: int                # optional/required on monthly|bimonthly|quarterly: 1..28; window = 7 days ending on it

The file is grouped by cadence in CADENCE_ORDER and the order is meaning: it becomes `sortOrder` on
both stores. Counts and pins below are the list Anne and Wes settled on 2026-09-14 (41 chores).

Exit codes:
  0  valid
  1  invalid JSON, schema, count, order, duplicate ids, bad enums, or a broken rule
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHORES_PATH = REPO_ROOT / "data" / "chores.json"

CADENCE_ORDER = ("daily", "weekly", "biweekly", "monthly", "bimonthly", "quarterly")
VALID_CADENCES = frozenset(CADENCE_ORDER)
SEASON_CADENCES = frozenset({"daily", "weekly", "biweekly", "monthly"})
VALID_ASSIGNEES = frozenset({"anne", "wes"})
VALID_CATEGORIES = frozenset({"chore", "cat_care"})
REQUIRED_CHORE_KEYS = ("id", "title", "cadence", "fixedAssignee", "category")
OPTIONAL_CHORE_KEYS = ("season", "together", "weekdays", "dueDay")
WINDOW_MONTH_CADENCES = frozenset({"monthly", "bimonthly", "quarterly"})

EXPECTED_VERSION = 4
# EXPECTED_COUNTS / EXPECTED_COUNT / EXPECTED_PINNED unchanged (41, ten pins)
EXPECTED_WEEKDAYS = {
    "take-out-garbage-basement": [5, 6],
    "take-out-garbage-bathroom": [5, 6],
    "take-out-garbage-kitchen": [5, 6],
    "garbage-can-to-street-sunday": [7],
}
EXPECTED_DUE_DAYS = {
    "clean-under-cushions": 5,
    "wash-all-rugs": 8,
    "trim-wes-hair": 10,
    "clean-inside-ovens": 12,
    "clean-garbage-cans": 14,
    "wipe-dust-bar-cart": 15,
    "clean-under-couches": 19,
    "wipe-down-doors": 21,
    "clean-medicine-cabinet": 22,
    "change-litter": 25,
    "clean-out-fridge-pantry": 28,
}
EXPECTED_COUNTS = {"daily": 13, "weekly": 12, "biweekly": 5, "monthly": 7, "bimonthly": 1, "quarterly": 3}
EXPECTED_COUNT = sum(EXPECTED_COUNTS.values())  # 41
EXPECTED_PINNED = {
    "laundry": "anne",
    "wash-all-rugs": "anne",
    "mow-lawn": "anne",
    "trim-wes-hair": "anne",
    "garbage-can-to-street-sunday": "wes",
    "change-bed-sheets": "anne",
    "am-wet-cat-food": "wes",
    "pm-wet-cat-food": "anne",
    "charge-cat-play-device": "wes",
    "put-toy-out-for-cats": "anne",
}


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def check_season(loc: str, season: object, chore: dict) -> None:
    if not isinstance(season, dict) or set(season) != {"months"}:
        fail(f"{loc}.season must be an object with exactly one key, months")
    months = season["months"]
    if not isinstance(months, list) or not months:
        fail(f"{loc}.season.months must be a non-empty list")
    for m in months:
        if not isinstance(m, int) or isinstance(m, bool) or not 1 <= m <= 12:
            fail(f"{loc}.season.months has a value outside 1..12: {m!r}")
    if len(set(months)) != len(months):
        fail(f"{loc}.season.months repeats a month")
    if chore["cadence"] not in SEASON_CADENCES:
        fail(f"{loc}: a season needs a cadence of at most monthly, got {chore['cadence']!r}")
    if chore.get("together"):
        fail(f"{loc}: a together chore cannot have a season")


def check_weekdays(loc: str, days: object, chore: dict) -> None:
    if not isinstance(days, list) or not days:
        fail(f"{loc}.weekdays must be a non-empty list")
    for d in days:
        if not isinstance(d, int) or isinstance(d, bool) or not 1 <= d <= 7:
            fail(f"{loc}.weekdays has a value outside 1..7 (Monday = 1 … Sunday = 7): {d!r}")
    if days != sorted(set(days)):
        fail(f"{loc}.weekdays must be ascending and unique")
    if chore["cadence"] != "weekly":
        fail(f"{loc}: weekdays only belong on a weekly chore, got {chore['cadence']!r}")


def check_due_day(loc: str, day: object, chore: dict) -> None:
    if not isinstance(day, int) or isinstance(day, bool) or not 1 <= day <= 28:
        fail(f"{loc}.dueDay must be an integer 1..28, got {day!r}")
    if chore["cadence"] not in WINDOW_MONTH_CADENCES:
        fail(f"{loc}: dueDay only belongs on a monthly, bimonthly or quarterly chore, got {chore['cadence']!r}")


def main() -> None:
    if not CHORES_PATH.is_file():
        fail(f"missing file: {CHORES_PATH}")

    try:
        data = json.loads(CHORES_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    if not isinstance(data, dict):
        fail("root must be an object")
    for key in ("version", "source", "locked", "chores"):
        if key not in data:
            fail(f"root missing required key: {key}")
    if data["version"] != EXPECTED_VERSION:
        fail(f"version must be {EXPECTED_VERSION}, got {data['version']!r}")
    if not isinstance(data["source"], str) or not data["source"].strip():
        fail("source must be a non-empty string")
    if not isinstance(data["locked"], str) or not data["locked"].strip():
        fail("locked must be a non-empty string")

    chores = data["chores"]
    if not isinstance(chores, list):
        fail("chores must be a list")
    if len(chores) != EXPECTED_COUNT:
        fail(f"expected {EXPECTED_COUNT} chores, got {len(chores)}")

    seen_ids: set[str] = set()
    by_cadence = {c: 0 for c in CADENCE_ORDER}
    pinned: dict[str, str] = {}
    weekdays: dict[str, list[int]] = {}
    due_days: dict[str, int] = {}
    last_rank = 0

    for i, chore in enumerate(chores):
        loc = f"chores[{i}]"
        if not isinstance(chore, dict):
            fail(f"{loc} must be an object")
        for key in REQUIRED_CHORE_KEYS:
            if key not in chore:
                fail(f"{loc} missing key: {key}")
        unknown = set(chore) - set(REQUIRED_CHORE_KEYS) - set(OPTIONAL_CHORE_KEYS)
        if unknown:
            fail(f"{loc} has unknown keys: {sorted(unknown)}")

        cid = chore["id"]
        if not isinstance(cid, str) or not cid.strip():
            fail(f"{loc}.id must be a non-empty string")
        if cid in seen_ids:
            fail(f"duplicate id: {cid}")
        seen_ids.add(cid)

        if not isinstance(chore["title"], str) or not chore["title"].strip():
            fail(f"{loc}.title must be a non-empty string")

        cadence = chore["cadence"]
        if cadence not in VALID_CADENCES:
            fail(f"{loc}.cadence invalid: {cadence!r} (want {list(CADENCE_ORDER)})")
        rank = CADENCE_ORDER.index(cadence)
        if rank < last_rank:
            fail(f"{loc} ({cid}) is out of order: the file is grouped {', '.join(CADENCE_ORDER)}")
        last_rank = rank
        by_cadence[cadence] += 1

        assignee = chore["fixedAssignee"]
        if assignee is not None and assignee not in VALID_ASSIGNEES:
            fail(f"{loc}.fixedAssignee invalid: {assignee!r} (want null|anne|wes)")
        if assignee is not None:
            pinned[cid] = assignee

        if chore["category"] not in VALID_CATEGORIES:
            fail(f"{loc}.category invalid: {chore['category']!r} (want {sorted(VALID_CATEGORIES)})")

        together = chore.get("together", False)
        if not isinstance(together, bool):
            fail(f"{loc}.together must be true or false")
        if together and assignee is not None:
            fail(f"{loc} ({cid}): a together chore has no fixedAssignee")

        if "season" in chore:
            check_season(loc, chore["season"], chore)
        if "weekdays" in chore:
            check_weekdays(loc, chore["weekdays"], chore)
            weekdays[cid] = chore["weekdays"]
        if "dueDay" in chore:
            check_due_day(loc, chore["dueDay"], chore)
            due_days[cid] = chore["dueDay"]
        elif cadence in WINDOW_MONTH_CADENCES:
            fail(f"{loc} ({cid}): every {cadence} chore needs a dueDay (1..28) so nothing bunches on the 1st")

    if by_cadence != EXPECTED_COUNTS:
        fail(f"per-cadence counts {by_cadence} do not match {EXPECTED_COUNTS}")
    if pinned != EXPECTED_PINNED:
        fail(f"pinned chores {pinned} do not match {EXPECTED_PINNED}")
    if weekdays != EXPECTED_WEEKDAYS:
        fail(f"weekday windows {weekdays} do not match {EXPECTED_WEEKDAYS}")
    if due_days != EXPECTED_DUE_DAYS:
        fail(f"due days {due_days} do not match {EXPECTED_DUE_DAYS}")

    print(f"OK: {CHORES_PATH.relative_to(REPO_ROOT)}")
    print(f"  version: {data['version']}")
    print(f"  chores: {len(chores)}")
    for cadence in CADENCE_ORDER:
        print(f"  {cadence}: {by_cadence[cadence]}")
    print("  pinned: " + ", ".join(f"{cid}→{who}" for cid, who in pinned.items()))
    print("  season: " + ", ".join(c["id"] for c in chores if "season" in c))
    print("  together: " + ", ".join(c["id"] for c in chores if c.get("together")))
    print("  weekdays: " + ", ".join(f"{cid}→{d}" for cid, d in weekdays.items()))
    print("  dueDay: " + ", ".join(f"{cid}→{d}" for cid, d in due_days.items()))


if __name__ == "__main__":
    main()
