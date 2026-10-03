# Performance and footprint budget

Purpose: hard numbers that keep Agentville from slowing down the Mac or taking up space. These numbers are part of the product.

## Budgets

| Resource | Situation | Budget | How measured |
|---|---|---|---|
| **Hook wall time** | app listening | p99 < 50 ms (target < 15 ms) | `HookTimingTests` (200 runs) |
| | app absent / socket missing | p99 < 10 ms | `HookTimingTests` |
| **App CPU** | crew inside, window closed, sessions active | < 0.5% avg over 60 s | Activity Monitor / `top -l` |
| | window open (office at 12 fps) | < 3% | Instruments |
| | released, 12 roamers + crowd, 100 sessions | < 15% of one core (Apple Silicon) | Instruments |
| **App memory** | 10 sessions, crew inside | < 60 MB RSS | Activity Monitor |
| | 100 sessions, released | < 150 MB RSS | Activity Monitor |
| **Store throughput** | 1,000-event batch, 100 sessions | < 50 ms (debug), < 5 ms (release) | `SessionStoreStressTests` |
| **Disk: app bundle** | | < 15 MB | `scripts/check-footprint.sh` |
| **Disk: hook binary** | | < 2 MB | `scripts/check-footprint.sh` |
| **Disk: runtime writes** | | preferences plist only (< 4 KB) | `check-no-disk-writes.sh` + review |
| **Wake-ups** | idle | no timers running except the socket source | Instruments "Energy" |
| **Recall** | any state | ≤ 2.6 s | replay + manual |

## Design levers that keep us under budget

- **Pause what isn't visible.** Overlay scenes paused and windows ordered out when nothing is on the desktop; office timer stopped when the desk panel is closed; input poller only while the crew or a walk-on is out.
- **Caps everywhere.** 12 roamers, 3 walk-ons, 520 particles, 24 queued notices, 512 tracked sessions, a 200-line diagnostics buffer, an LRU sprite cache (about 2,000 textures × 28×28×4 B ≈ 6 MB worst case).
- **Batch UI** at 4 Hz.
- **Small binaries.** No dependencies, `-Osize` for the hook, dead-strip, no bundled frameworks besides the system's.
- **Datagrams, not connections.** The hook never waits.

## Measurements

Release builds on the owner's MacBook Air (Apple Silicon, P3 display), app on a private socket, CPU from cumulative `ps -o time` (not `%cpu`, which is a decaying estimate and misleads).

| Date | Situation | Result | Budget |
|---|---|---|---|
| 2026-10-03 | Crew inside, nothing out, 45 s | 0.0% (0.05 s CPU in all) | < 0.5% |
| 2026-10-03 | Desk panel open, empty | 4.3% → **2.2%** after `PixelColorMatcher` (office frames made in the screen's colour space, so Core Animation stops colour-matching each frame) | < 3% |
| 2026-10-03 | Walk-ons out (crew inside), debug build | 4–10% while they're out; back to 0% as they leave (overlay asleep again) | n/a |
| 2026-10-03 | Released, 12 roamers + crowd, 100 sessions, panel closed, events stopped | **11.9%**, 68 MB RSS | < 15%, < 150 MB |
| 2026-10-03 | Same, during a 200 events/s stream (`--generate hundred`) | **20.6%**: over budget while the storm lasts. Sampled: app code is a small share (socket decode ≈ 1% of samples, `CrewSim` under that); the rest is SpriteKit/Metal and event handling. Open: see M6 in [milestones.md](../process/milestones.md) | < 15% |
| 2026-10-03 | Released, burst of 2,000 events/s for 5 s (`--generate burst`) | 27–37% at the peak, back to ≈ 10% within 5 s; all 10,080 events accepted; 72 MB | n/a |
| 2026-10-03 | `CrewSim.update`, 100 sessions, ≈ 500 events/s, debug build (`CrewCrowdTests.caps`) | 0.10 ms per step | ≪ 16.7 ms frame |

## When a budget is missed

Treat it as a bug: open an issue with the measurement, add a regression test or scenario if one is possible, and fix it before the milestone closes. Don't quietly raise a budget. Changing one needs an ADR.
