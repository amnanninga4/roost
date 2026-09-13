# Roost

A shared household app concept for tracking chores, cat care, and reminders — built for Anne & Wes.

## What's in here

- **`roost-app-mockup.html`** — clickable concept mockup of the app: Tasks (with a head-to-head streak and bonus points), Shopping list, Meal ideas, and Projects (bigger jobs broken into subtasks).
- **`chore-master-list.html`** — the finalized reference list of household tasks by frequency (daily/weekly/biweekly/monthly), including which ones are fixed to one person.
- **`data/chores.json`** — structured seed of that master list (cadence, pinned assignees, category hints) for a future Swift/SwiftData model. See `data/README.md`.

Open either HTML file directly in a browser to view it.

## Validate chore seed

```bash
python3 scripts/validate-chores.py
```

Dependency-free (Python 3 stdlib only). Fails on invalid JSON/schema, wrong count, duplicate ids, or bad cadence values.

## Status

Concept/design stage — not yet a working app.
