# The office (desk window)

Purpose: the exact pixel room to port from `drawOffice`, `screenFor` and `deskUnits`.

## Geometry

- The room is **216×136 units**, drawn at **2 pt per unit** (432×272 pt). Redraw at about **12 fps** while visible; stop when hidden.
- **6 desks**, 2 rows of 3: `deskUnits(i)`: `row = i / 3`, `col = i % 3`, `gx = 4 + col·70`, `top = row ? 118 : 72`. The feet anchor is at (`gx + 22`, `top + 8`).
- Sessions occupy desks in store order. When there are more than 6, a "+N more below" badge appears bottom-right (pixel font, accent background, 2 px ink border).

## Room (day / night)

| Element | Day | Night (dark mode) |
|---|---|---|
| Wall (0,0,216,46) with stripes every 12 units | `#3B4078` / `#434985` | `#262A56` / `#2C3060` |
| Skirting (0,43,216,3) | `#2A2D5A` | `#1B1E40` |
| Window (10,7,42,28), frame `#5B4A6B`, sill `#7A6690` | sky `#8FD3FF`, clouds drifting, sun `#FFE27A` | `#131B45`, moon `#FFF1C9`, twinkling stars |
| Pinboard (128,9,42,24) | cork `#B98556`/`#D9A86C`, 7 sticky notes, red pins | same |
| Clock (186,9,14,14) | **real time**: minute hand ink, hour hand red | same |
| Plant (≈204,24) | terracotta pot, greens | same |
| Floor (0,46,216,90) | planks `#B07A4F`, seams `#9C6A43` every 9 rows, offset joints | `#8A5E3F` / `#744E33` |
| Rug (6,93,204,22) | `#7E2553` / `#963363`, stripe `#B04477` | `#4A1D3F` / `#5E2750` / `#6E3060` |

## Each desk

Chair (`#2D3150`); the character (if present and not out roaming); the desk top `#E0B084`, body `#B98556`, drawer pull; a **nameplate in the character's shirt colour**; a keyboard `#C9CEDF`; a monitor (`#20233D`, 18×12) with a 16×10 screen at (`gx+39`, `top−14`); and the desk item from the look (mug, plant, duck, book stack).

While the crew is out: the chair is pulled out (extra seat line), the desk is empty, and **the monitor keeps showing the session's activity**.

Subagent: a mini-me (desktop `type` pose at 1× scale) sits on the monitor.

## Character at desk

| Session | Pose | Lift | fps | Emote |
|---|---|---|---|---|
| needsYou | `wave` | 5 + |sin(6t)|·2 | 5 | `bang` |
| finished | `cheer` | 4 + |sin(8t)|·3 | 5 | `check` |
| idle | `nap` | n/a | 1 | floating Z (every third beat) |
| reading | `read` | n/a | 1.2 | |
| searching | `search` | n/a | 3 | |
| web | `web` | n/a | 1.6 | |
| thinking | `think` | n/a | 2 | `dots` |
| running | `deskType` | n/a | 11 | |
| editing / other | `deskType` | n/a | 6 | |

The frame phase is offset per desk by `i·0.3 s` so the room doesn't animate in lockstep.

## Monitor screens (`screenFor`, `tick = floor(t·4)`)

| State | Screen |
|---|---|
| Editing | dark `#1B1E34`; 4 coloured code lines typing in; blinking cursor |
| Reading | light `#ECEAF4` page; grey lines scrolling |
| Running | `#0B1A12`; green `#3CFF7A` prompt lines appearing; blinking cursor |
| Searching | dark; grey rows; a highlight bar `rgba(255,236,39,.45)` moving down |
| Web | blue `#2B6CB0`; a globe `#29ADFF` with green land moving |
| Thinking | dark; 0–3 dots |
| Needs you | flashing `#FF004D` / `#7E2553` with a white `!` |
| Finished | `#0F7A43` with a white check |
| Idle / away | `#15172C` with one bouncing coloured pixel (screensaver) |

## Done when

- [ ] Golden-image test: the office at fixed `t` with a fixed set of sessions matches the prototype export, day and night
- [ ] All 9 monitor screens are visible via the replay demo-mix scenario
