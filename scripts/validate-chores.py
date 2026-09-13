#!/usr/bin/env python3
"""Validate data/chores.json against the Roost chore seed schema.

Schema (simple, Swift/SwiftData-friendly):
  Root object:
    version: int
    source: str          # e.g. "chore-master-list.html"
    locked: str          # ISO date the master list was locked
    notes: str           # optional human note
    chores: list[Chore]

  Chore object:
    id: str              # stable slug, unique
    title: str           # display title from master list
    cadence: str         # one of: daily | weekly | biweekly | monthly
    fixedAssignee: str|null  # anne | wes | null
    category: str        # chore | cat_care

Expected chore count matches the locked master list body
(chore-master-list.html group totals: 11+9+5+6 = 31).
HTML meta / NOTES historically say "32"; that figure is wrong —
do not invent a 32nd task to satisfy the label.

Exit codes:
  0  valid
  1  invalid JSON, schema, count, duplicate ids, or bad enums
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CHORES_PATH = REPO_ROOT / "data" / "chores.json"

EXPECTED_COUNT = 31  # 11 daily + 9 weekly + 5 biweekly + 6 monthly
VALID_CADENCES = frozenset({"daily", "weekly", "biweekly", "monthly"})
VALID_ASSIGNEES = frozenset({"anne", "wes"})
VALID_CATEGORIES = frozenset({"chore", "cat_care"})
REQUIRED_CHORE_KEYS = ("id", "title", "cadence", "fixedAssignee", "category")


def fail(msg: str) -> None:
    print(f"FAIL: {msg}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    if not CHORES_PATH.is_file():
        fail(f"missing file: {CHORES_PATH}")

    try:
        raw = CHORES_PATH.read_text(encoding="utf-8")
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON: {exc}")

    if not isinstance(data, dict):
        fail("root must be an object")

    for key in ("version", "source", "locked", "chores"):
        if key not in data:
            fail(f"root missing required key: {key}")

    if not isinstance(data["version"], int):
        fail("version must be an int")
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
    by_cadence: dict[str, int] = {c: 0 for c in sorted(VALID_CADENCES)}

    for i, chore in enumerate(chores):
        loc = f"chores[{i}]"
        if not isinstance(chore, dict):
            fail(f"{loc} must be an object")

        for key in REQUIRED_CHORE_KEYS:
            if key not in chore:
                fail(f"{loc} missing key: {key}")

        cid = chore["id"]
        if not isinstance(cid, str) or not cid.strip():
            fail(f"{loc}.id must be a non-empty string")
        if cid in seen_ids:
            fail(f"duplicate id: {cid}")
        seen_ids.add(cid)

        title = chore["title"]
        if not isinstance(title, str) or not title.strip():
            fail(f"{loc}.title must be a non-empty string")

        cadence = chore["cadence"]
        if cadence not in VALID_CADENCES:
            fail(f"{loc}.cadence invalid: {cadence!r} (want {sorted(VALID_CADENCES)})")
        by_cadence[cadence] += 1

        assignee = chore["fixedAssignee"]
        if assignee is not None and assignee not in VALID_ASSIGNEES:
            fail(
                f"{loc}.fixedAssignee invalid: {assignee!r} "
                f"(want null|{ '|'.join(sorted(VALID_ASSIGNEES)) })"
            )

        category = chore["category"]
        if category not in VALID_CATEGORIES:
            fail(f"{loc}.category invalid: {category!r} (want {sorted(VALID_CATEGORIES)})")

    # Spot-check pinned assignees from the master list
    by_id = {c["id"]: c for c in chores}
    laundry = by_id.get("laundry")
    garbage = by_id.get("garbage-can-to-street-sunday")
    if laundry is None or laundry.get("fixedAssignee") != "anne":
        fail("laundry must be fixedAssignee=anne")
    if garbage is None or garbage.get("fixedAssignee") != "wes":
        fail("garbage-can-to-street-sunday must be fixedAssignee=wes")

    print(f"OK: {CHORES_PATH.relative_to(REPO_ROOT)}")
    print(f"  chores: {len(chores)}")
    for cadence in ("daily", "weekly", "biweekly", "monthly"):
        print(f"  {cadence}: {by_cadence[cadence]}")
    print(f"  pinned: laundry→anne, garbage-can-to-street-sunday→wes")


if __name__ == "__main__":
    main()
