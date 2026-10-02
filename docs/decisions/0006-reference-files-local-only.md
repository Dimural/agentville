# 0006: Prototype and brief stay local, never committed
Status: Accepted
Date: 2026-10-01

## Context
The owner provided `Pixel Crew.html` (prototype) and `PROJECT_BRIEF.md` (brief) as ground truth, and explicitly asked that they not be committed. The brief itself had suggested committing the prototype under `prototype/`; the owner's instruction overrides that.

## Decision
Both files are gitignored by exact name at the repo root. Their content is digested into `docs/`, and anything machine-checkable is extracted into test fixtures (e.g. `look-vectors.json`) generated from the prototype's own code.

## Consequences
- A fresh clone can build and test everything from `docs/` and the fixtures.
- Golden image tests commit fixtures exported from the prototype (`Tools/fixtures/export-sprites.mjs` → `sprite-vectors.json`, palette-indexed text rows rather than PNGs so failures diff as ASCII art), never the prototype itself. The export script reads the local file at run time and contains none of its code.
- Agents must never `git add -f` these files.
