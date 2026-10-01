# Art direction

Purpose: the look Agentville must have, and the rules that keep it crisp, original and cohesive.

## The look

Cozy and chunky. Big-headed pixel characters, outlined in deep purple-black **`#1A1330`**, drawn in a **PICO-8-inspired palette**. The office is a warm little room: indigo striped wall, plank floor, magenta rug, wooden desks, glowing monitors.

## Crispness rules

- **Nearest-neighbour** filtering everywhere (`SKTexture.filteringMode = .nearest`, `CGContext.interpolationQuality = .none`).
- **Integer scales only.** Desktop: 3 pt per sprite pixel (2 on small screens, below 700 pt wide). Office: 2 pt per unit, characters at 2 pt per pixel. The sidekick and crowd are one step smaller (`max(1, scale − 1)`).
- **Snap** drawn positions to whole points.
- Sprite frames advance at low pixel-art rates; motion is smooth at display rate.

## Core palette (from the prototype)

| Role | Colours |
|---|---|
| Outline / eyes / ink | `#1A1330` |
| Grab-mode highlight outline | `#FFF6DA` |
| Bubble paper | `#FFF8EC` |
| Accent (Release button) | `#FFA300`; the recall button is `#29ADFF` |
| Confetti | `#FF004D #FFA300 #FFEC27 #00E436 #29ADFF #FF77A8 #83769C #FFF1E8` |
| Emotes | bang `#E0103F`, check `#0B9A4B`, heart `#FF3F7F`, question `#2B7BD6`, dots `#5B5578` |
| "Done" text / "Needs you" text | `#0B7A3E` / `#D0103E` |

Character palettes (skin, hair, shirt, pants, shoes) are listed in [sprites-and-poses.md](sprites-and-poses.md#looks).

## Typography (desk window and bubbles)

- Display and bubbles: a pixel font in the spirit of the prototype's *Pixelify Sans*. **Bundle an OFL-licensed pixel font** in the app; never fetch fonts from the network.
- Body: the system font (SF Pro). Mono details (tool names, durations): SF Mono with tabular numerals.

## Speech bubbles

Paper `#FFF8EC`, a 2 px `#1A1330` border, a hard drop shadow (3, 4) at 28% ink, a small stepped pixel tail. Title in bold (14 pt); optional subtitle in 12 pt at 80% opacity. Variants:
- `done`: green title
- `wait`: red title
- `count` (crowd): orange background, bold

Bubbles clamp inside the screen, sit above the emote, and fade with the character's hover alpha (minimum 0.15).

## Integrity

- **All art is original and procedurally drawn.** No third-party characters, sprites or fonts without a compatible licence (recorded in `THIRD_PARTY.md`).
- **No Anthropic or Claude logos, mascots, colours used as branding, or anything that implies officialness.**
- Dark mode: the office window shows night (stars, moon, darker wall and floor). The menu bar icon follows the system appearance (template image).

## Done when

- [ ] Every sprite renders pixel-exact to the prototype (golden tests, M2)
- [ ] No blurry scaling anywhere at any display scale (manual check on 1× and 2× displays)
- [ ] `THIRD_PARTY.md` lists every bundled asset that isn't ours (font only)
