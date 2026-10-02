# Motion and behaviour constants

Purpose: every number that shapes how the crew moves and behaves, copied from the prototype. Code constants live in `Sources/AgentvilleCore/Sessions/Constants.swift` (`Limits`, `Timing`, `Motion`, `Phrases`) and must cite this doc. The choreography itself is `CrewSim` (`Sources/AgentvilleCore/Crew/`), tested by `CrewSimTests`.

## Physics

| Constant | Value |
|---|---|
| Gravity `G` | 1500 pt/s² |
| Release flight duration | 0.8–1.1 s (random) |
| Release stagger | first at 120 ms, then **85 ms** apart; crowd 60 ms after the last |
| Recall flight duration | 0.5–0.7 s |
| Recall stagger | 60 ms + i·**55 ms**, sorted bottom-most first |
| Recall force-complete | **2.6 s** (anything still flying or waiting is removed) |
| Flight arc | `z(t) = (G·T/2)·t − G·t²/2`; `x, y, scale` lerp linearly; stretched `sx .92, sy 1.1` |
| Landing | squash 1 → 0 at 6/s (`sx = 1 + .22·squash`, `sy = 1 − .22·squash`) and 5 dust particles |
| Step-out from crowd | 0.7 s flight, "My turn!" |
| New session while released | drops from 70% of screen height (dangle), lands, "Hello!" |

## Speeds (pt/s)

| Movement | Speed |
|---|---|
| Walk (working) | 48 |
| Search creep | 26 |
| Idle stroll | 32 |
| "Needs you" run | 120 |
| Walk-on in | 95 |
| Walk-on out | 110 |
| Crowd wander | 22 |
| Sidekick follow | 140 |

## Roaming

- Act duration: working 3–7 s, idle 6–12 s; then walk to a nearby target (radius 220 working, 120 idle; the crowd uses 160; y range × 0.6).
- Walkable area: x in [36, W − 36]; y from `TOP + 26·S + 6` to `H − 16`.
- Needs you: walk to (clamp(x, 60, W − 60), H − 26), then wave and hop `|sin(7t)|·9`.
- Cheer after Done: 2.6 s, hop `|sin(9t)|·12`, confetti sprinkles.
- Sidekick: follows at `x − face·11·S`, `y + 3`; types when still. Pops in and out with yellow sparkles. Several subagents: one sidekick with a small yellow count badge above its head (open question 12's default).
- Done: the bubble reads **Done!** in green over "name · turn time" for 5 s, with 26 confetti. Needs you: **Needs you** in red over the name, while waiting.

## Meetings (`checkMeetings`)

- Checked every 0.35 s, among roaming, walking, working characters.
- Meet when within **44 pt** and both cooldowns have expired. Each gets a new cooldown of **18–30 s** (initial 6–16 s).
- Both stop for 1.6 s, face each other, and cheer for the first 0.8 s. One shows heart (⅔) or question (⅓). 50% say "hi!", "nice commit", "lunch?" or "high five!". Pink sparkles between them.

## Throwing

| Constant | Value |
|---|---|
| Max throw speed | 1500 pt/s |
| Dizzy threshold | > 900 pt/s → 1.8 s dizzy |
| "waaah!" threshold | > 700 pt/s |
| Lift on throw `vz` | clamp(speed × 0.35, 80, 460) |
| Wall bounce | velocity × 0.6, squash 0.8 |
| Ground bounce | fall faster than 260 pt/s → `vz × −0.42`, `vx, vy × 0.65`, dust |
| Slide friction | `exp(−7·dt)` per frame; settle below 18 pt/s |

## Notices (walk-ons while the crew is inside)

- Slots: **3** (W ≥ 900), 2 (W ≥ 560), 1 otherwise. Slot k stands at x = `W − 80 − k·130`, y = `H − 22 − k·6`.
- Done hold: **6.5 s** (cheer 2.4 s, 30 confetti). Needs-you hold: up to **16 s**, or until it's no longer waiting.
- Queue cap: 24 (overflow counts toward "+N more"). Done notices fold into "+N more" when ≥ 2 are pending.

## Limits

| Limit | Value |
|---|---|
| Roaming characters | **12** (`CAP`) |
| Crowd display | 3 half-size members + a "+N" badge |
| Walk-ons | 3 |
| Particles | **520** (oldest dropped) |
| Desks | 6 |

## Particles

| Kind | Spawn | Life | Notes |
|---|---|---|---|
| confetti | 26–30 per cheer (÷4 with reduced motion) | 1.3–2.2 s | gravity 0.55·G; flutters; settles on the ground |
| dust | 4–6 on landing/leaving | 0.35–0.6 s | grows, fades |
| sparkle | release/recall/meetings | 0.4–0.9 s | plus-shaped |
| zzz | idle sleepers, about 0.9/s | 1.8 s | drifts up and right |
| bits | typing, about 3/s | 0.8–1.3 s | 2×1 coloured blocks |

## Hover and accessibility

- Hover fade: target alpha **0.16** when the cursor is within the hit box + 6 pt (and not in grab mode); eased at `min(1, dt·14)`.
- **Reduced motion:** confetti cut to a quarter; skip the desk panel burp/gulp and the button's invite bounce.

## Window animations

- Burp (release): 0.55 s, `scale(1.035, .965)` → `scale(.985, 1.02) translateY(−4)` → identity, overshoot easing.
- Gulp (last one home): 0.35 s, `scale(1.02)` → identity.

## Phrases

- Release: "Wheee!", "Freedom!", "Hi!", "Let's go!", "Stretch time" (35% chance)
- Recall: "Coming!", "Okay!", "Back to work!", "On my way" (30%)
- Tap: "hey!", "boop", "hi there", "\*giggle\*"
- Throw: "waaah!", "whoa!", "aaa!"
- Meet: "hi!", "nice commit", "lunch?", "high five!"
- Other: "Hello!" (drop-in), "My turn!" (from crowd), "Bye!" (leaving), "Done!", "Needs you"
