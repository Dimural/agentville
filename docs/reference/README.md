# Reference material (local only)

The owner keeps two ground-truth files at the repo root. Both are **gitignored and must never be committed**, moved or copied into tracked files.

| File | What it is | Authority |
|---|---|---|
| `Pixel Crew.html` | The interactive prototype: one self-contained HTML file that simulates sessions in the browser. Open it in any browser. ("Pixel Crew" was the working name; the product is **Agentville**.) | **Wins on look, feel and motion**: pixel art, office, release/recall choreography, click-through and ⌥-grab, notifications, crowd, limits. |
| `PROJECT_BRIEF.md` | The original project brief: product, architecture, data contract, rules, milestones, open questions. | Digested into `docs/`. Where the docs and the brief differ, the docs are newer: they record decisions and current Claude Code facts. |

A fresh clone won't have these files. Everything needed to build lives in `docs/`, plus test fixtures generated from the prototype (for example `Tests/AgentvilleCoreTests/Fixtures/look-vectors.json`).

## Map of the prototype's script

Everything is in one `<script>` block. Search for these names:

| Area | Prototype names | Agentville home |
|---|---|---|
| Looks | `lookFor`, `hash`, `rng`, `SKIN` `HAIR` `SHIRT` `PANTS` `SHOES` `STYLES` `ACCS`, `shade`, `mix` | `Sources/AgentvilleCore/Looks/` (ported, golden-tested) |
| Sprites | `drawChar(g, L, pose, f)`, `sprite()`, `outline()`, `avatar()` | `Looks/SpriteRenderer.swift`, `PixelCanvas.swift` (ported, golden-tested) |
| Emotes | `ICON`, `drawPattern`, `drawEmote` | `SpriteRenderer.emote` (ported, golden-tested) |
| Office | `drawOffice`, `screenFor`, `deskUnits`, `DESKS` | `Looks/OfficeRenderer.swift` (ported, golden-tested); shown by the app desk window (M2) |
| Behaviour | `class Ent`, `updateEnt`, `roam`, `roamCrowd`, `checkMeetings`, `settle` | app overlay (M4) |
| Release / recall | `release`, `recall`, `spawnFromHome`, `sendHome`, `homePos`, `callEveryoneBack` | app overlay (M3) |
| Notices | `onDone`, `onWaiting`, `queueNotice`, `processNotices`, `slotsMax` | app overlay (M6) |
| Crowd | `roamers`, `crowdMembers`, `spawnCrowd`, `syncRoamers` | app overlay (M6) |
| Grab / throw | `grabMode`, `hitTest`, `hitBox`, stage `pointerdown` capture, `endDrag` | app input (M5) |
| Particles | `confetti`, `dust`, `sparkle`, `zzz`, `bits`, `stepParts`, `drawParts` | app overlay (M4) |
| Batched UI | `renderList` + the 0.25 s accumulator in `frame` | app desk window (M2) |

## Scaffolding that is NOT rebuilt

The prototype fakes a Mac desktop so it can run in a browser. These parts exist only for the demo:

- the pixel landscape wallpaper (`paintWallpaper`): the user's real desktop is the background
- the fake menu bar, plus the "Notes" and "Click test" windows
- the session simulator panel and random event generator (`stepSessions`, `newSession`, …): replaced by real hook events, and in development by `agentville-replay`
- the sprite-sheet cards and the "Built to stay out of your way" section (still useful as a checklist of poses and promises)
- the **Answer** button on "Needs you" rows: the real app can't answer permission prompts (see open questions)

The "What the app receives" feed is worth keeping as an optional, in-memory-only **Diagnostics** view. It shows the exact privacy boundary.

## How to regenerate fixtures from the prototype

Look vectors were produced by evaluating the prototype's own `hash`, `rng`, `shade`, `mix` and `lookFor` functions in Node, over a fixed list of folder names. To regenerate, extract those functions from `Pixel Crew.html` and dump `lookFor(name)` (minus `id` and `name`) for each name in the fixture. Never edit the fixture by hand.

Office frames and monitor screens: `node Tools/fixtures/export-office.mjs` (same requirements). It pins only the theme and the wall clock, by exact text patches that fail loudly if the prototype changes.

Sprite and emote frames: run `node Tools/fixtures/export-sprites.mjs` (needs Node and Google Chrome). It lifts the prototype's utils/looks/sprites section out of `Pixel Crew.html` at run time, runs it unmodified in headless Chrome, and rewrites `Tests/AgentvilleCoreTests/Fixtures/sprite-vectors.json`. The output is deterministic: rerunning it on an unchanged prototype gives a byte-identical file.
