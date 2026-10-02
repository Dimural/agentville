# Sprites, looks and poses

Purpose: the exact sprite system to port from the prototype (`lookFor`, `drawChar`, `sprite`, `outline`, `ICON`, `drawEmote`).

## Looks

A look is derived **deterministically from the project folder name**: the same folder always gets the same character.

Algorithm (port exactly; golden-tested against `Tests/AgentvilleCoreTests/Fixtures/look-vectors.json`):

1. `hash(name)`: 32-bit FNV-1a over the **UTF-16 code units** of the name (JS `charCodeAt`): `h = 2166136261; for each unit: h ^= u; h = imul(h, 16777619)`; result as an unsigned 32-bit integer.
2. `rng(seed)`: xorshift32 with state `s = seed || 1`. Each call: `s ^= s << 13; s ^= s >>> 17; s ^= s << 5` (all `uint32`), returning `(s % 100000) / 100000`.
3. `r = rng(hash(name) + 11)` (with 32-bit wraparound); discard two values; then pick in this exact order, `pick(a) = a[floor(r() * a.length)]`:
   `skin, hair, style, acc, shirt, pants, shoe, cap, pattern`. Then `rest = r() < .5 ? coffee : sleep`, then `desk`.
4. Fix-ups: if `cap == shirt`, then `cap = SHIRT[(indexOf(shirt) + 3) % len]`. If style is `cap` or `beanie` and acc is `headphones`, then acc = `none`.
5. Derived shades (`shade(h, f)`: f < 0 darkens by multiplying by (1+f); f > 0 lightens toward white. `mix` is linear RGB. Round to nearest and clamp):
   `skinD = shade(skin, −.13)`, `hairD = shade(hair, −.28)`, `hairL = shade(hair, .28)`, `shirtD = shade(shirt, −.26)`, `shirtL = shade(shirt, .32)`, `pantsD = shade(pants, −.3)`, `capD = shade(cap, −.3)`, `capL = shade(cap, .38)`, `blush = mix(skin, #FF5C8A, .38)`.

Palettes (the order matters; duplicates are intentional weighting):

```
SKIN    #FFD9BC #F3BE92 #D8976A #AE7048 #7C4B2E
HAIR    #2B2140 #5A3825 #A0522D #F2C95B #FF77A8 #3AA7FF #8E7CC3 #EDEAF5 #E4572E #1F8A70 #2B2140
SHIRT   #FF004D #29ADFF #00C853 #FFA300 #7E2553 #FF77A8 #83769C #2E8B72 #FFD23F #4A5BD4 #E86A33
PANTS   #1D2B53 #3B3355 #5F574F #2F4858 #6B4A3A
SHOES   #2A2140 #5A3825 #F4F0E8 #C93A3A #2A2140
STYLES  short spiky cap beanie long bun curly
ACCS    none none shades headphones none none
PATTERN plain stripe pocket hood plain
DESK    mug plant duck mug stack
```

The `cap` colour is picked from SHIRT.

## Sprite canvas

- Each frame: **28×28 pixels** with a 2 px pad (drawing is translated by (2, 2)).
- **Feet anchor (12, 26).** Facing right by default; left is a horizontal flip about the anchor.
- After drawing, `outline()` adds a 1 px `#1A1330` outline (4-neighbour) around every opaque pixel. Grab mode adds a second, `#FFF6DA` outline.
- Cache key: `(look, pose, frame, highlight)`.

## Poses

All poses have **2 frames** except `walk` (4).

| Pose | Used for | fps | Notes |
|---|---|---|---|
| `idle` | standing, crowd idle | 1.2 | bob 1 px; `blink` overrides `idle` for 0.12 s every 2.5–5 s |
| `walk` | wandering, walk-ons | 8 | 4 leg frames, arm swing |
| `type` | editing (desktop) | 6 | seated with a laptop; code bits rise |
| `deskType` | at desk; generic working | 6 | in the office, running uses 11 fps |
| `read` | reading | 1.2 | the book's page flips |
| `bash` | running a command | 3 | hammer up/down on a CRT; sparks on the down frame |
| `search` | searching | 3 | magnifying glass; creeps at 26 pt/s |
| `web` | on the web | 1.6 | telescope; twinkling stars |
| `think` | thinking | 2 | hand on chin; "…" emote |
| `wave` | needs you, leaving | 5 | |
| `cheer` | finished, flight out, meetings | 5 | |
| `coffee` | idle (rest = coffee) | 0.7 | seated, sipping |
| `sleep` | idle (rest = sleep) | 1 | seated, Z's |
| `nap` | idle at desk | 1 | head down |
| `dangle` | grabbed, flying home, dropping | 7 | legs kicking |
| `dizzy` | after a hard throw | 4 | × eyes, two circling stars |
| `blink` | idle blink | n/a | |

**New poses (art TBD; open question 12):** `error` (`StopFailure`: trips, or a small storm cloud), `clipboard` (planning tools), `gadget` (MCP tools). Until drawn, they fall back to `think`, `think` and `deskType` respectively.

## Emotes

A 9×9 bubble (rounded corners via two overlapping rects, plus a 1 px tail below), paper `#FFF8EC`, ink `#1A1330`, with a 5×5 icon:

```
bang   ..#..  ..#..  ..#..  .....  ..#..
check  ....#  ...##  #.##.  ###..  .#...
heart  .#.#.  #####  #####  .###.  ..#..
quest  .###.  ....#  ..##.  .....  ..#..
dots   animated: floor(t*3) % 4 dots
```

## Avatars

The list avatar is the `idle` frame 0 sprite, cropping source rect (5, 1, 13, 14), drawn at 2× (26×28).

## Code

`Sources/AgentvilleCore/Looks/`: `PixelCanvas` (fill, clear, translate, `outline`, crop), `SpriteRenderer` (`render` = `sprite`, `avatar`, `emote` = `drawEmote` at scale 1), `Pose` (with `frameCount`), `Emote`, `SpriteCache`. Converting a `PixelCanvas` to `CGImage`/`SKTexture` and scaling (nearest-neighbour, integer) happens in the app.

## Done when

- [x] `LookGenerator` matches `look-vectors.json` exactly (all names, including Unicode and empty): `LookGeneratorTests`
- [x] Every pose × frame × style × accessory renders pixel-identical to the prototype: `SpriteRendererTests` (19 looks: every style × accessory, all 4 patterns; 741 frames + 8 emotes from `sprite-vectors.json`). Frames are exported from the prototype's own code on a real browser canvas and stored as palette-indexed text rows, so a failure prints an ASCII diff
- [x] Sprite cache is bounded (LRU, `Limits.spriteCache` = 2,000 entries): `SpriteCache`, tested in `SpriteRendererTests`
