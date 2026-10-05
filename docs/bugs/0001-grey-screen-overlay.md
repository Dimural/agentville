# 0001: The whole screen turned flat grey while the crew's overlay was up

Status: **Open**, not yet reproduced. Blocks closing M6 ([milestones.md](../process/milestones.md)).
Severity: **Critical.** While it lasts the user can't see anything but the menu bar. That breaks the promise that the crew is glass ([non-negotiables](../quality/non-negotiables.md) #1) and would make anyone uninstall the app.
Reported: 2026-10-03 by the owner, during the M6 checks.

## What the owner saw

- Everything below the menu bar turned one flat grey: no windows, no wallpaper, **no Dock**, no characters, no HUD. The menu bar stayed visible and normal.
- It happened **twice** on 2026-10-03. The second time the owner took a screenshot (12:36:47 PM). The time of the first is unknown.
- It **went away by itself**. The owner didn't quit anything or restart.
- Unknown: how long each lasted, and whether clicks still reached the apps underneath.

## Evidence

From the owner's screenshot (`~/Documents/Screenshots/Screenshot 2026-10-03 at 12.36.47 PM.png`, kept on the owner's Mac, not in the repo):

- Every sampled pixel below the menu bar, including the Dock's area, is the same grey: **RGB 191, 191, 191** (Display P3 screenshot).
- The menu bar shows **two** Agentville items:
  - **"100" with the red dot**: an agent's private test copy (release build, own socket), started with `--release-crew` and fed `agentville-replay --generate hundred --seconds 30 --rate 200` (100 sessions, about 3% permission requests, so many need you). Its test script then failed to stop it, so it stayed up with the crew out until the agent stopped it by hand a few minutes later.
  - **"1"**: the owner's own debug build of the pre-M6 code (on the normal socket), crew believed inside.
- The frontmost app was Safari.

Why the overlay is the prime suspect:

- **The shape matches.** The grey covers exactly the overlay window's frame: the whole screen, at level `mainMenuWindow − 1`, so above the Dock and below the menu bar ([app.md](../architecture/app.md), `OverlayController`). No other Agentville window sits there, and in the owner's 12:20 screenshot the Dock was normally visible.
- **No content was drawn.** No characters and no HUD appear in the grey. So SpriteKit wasn't painting a background behind the crew: the window as a whole showed flat grey instead of its content.

What the logs say:

- No crash report from Agentville or WindowServer, and no kernel panic (the Mac had been up 19 days).
- No WindowServer errors or faults between 12:00 and 14:20.
- The unified log kept **nothing** from 12:36:30–12:37:00, so there is no log record of the event.
- The display slept at 13:08 and woke at 14:02 (on battery, 26%). Probably unrelated: both sightings were earlier.

## Attempts to reproduce (all failed)

Each attempt ran a private copy of the app and captured only its overlay window (`screencapture -l`), then measured how much of the window was opaque. A normal frame is about 0–5% opaque (the crew, bubbles and HUD); the bug would show as ~100%.

| Attempt | Setup | Captures | Most opaque |
|---|---|---|---|
| 1 | 6 fresh launches, crew inside; a needs-you walk-on wakes the overlay twice per launch; captured right after each wake | 55 | 0.17% |
| 2 | Release build, `--release-crew`, `--generate hundred` at 200 events/s for 40 s; one capture every ~0.8 s | 50 | 4.9% |
| 3 | 3 launches of a freshly copied release binary (cold shader cache), `--release-crew`, 100 sessions; a capture every ~0.1 s from launch | 110 | 5.0% |

Not yet tried:
- ~~running two copies at once~~ (soak runs below);
- heavy memory pressure (a release build was compiling just before; builds ran alongside soak 2, mild at most);
- a long soak of tens of minutes on an unlocked screen (soak 2 was mostly behind the lock screen);
- Safari frontmost;
- sleep/wake or a display change while the crew is out.

## Hypotheses (unconfirmed)

1. **The overlay's surface lost its content and WindowServer showed a placeholder.** The overlay is a full-screen, non-opaque window drawn by a Metal-backed `SKView`. If its drawable were purged or not presented (memory pressure, a GPU stall, the app busy), WindowServer might fill it with grey rather than leave it transparent. This fits the flat colour and the missing crew.
2. **A frame was presented with the view's layer opaque.** For example, the `SKView`'s backing layer treated as opaque before `allowsTransparency` took effect, or after a re-present. Less likely: the capture tests never saw it, and it wouldn't explain several seconds of grey.
3. **Not Agentville at all.** Something else drew a full-screen window between the Dock and the menu bar. Unlikely given the match and the timing, but not ruled out.

## Impact on users

If it's the overlay, any user with the crew out could lose their screen for an unknown time. The menu bar stays visible, so **Quit Agentville** and ⌃⌥C should still be reachable. Click-through probably still works, since the window ignores the mouse, but that's unverified. Nothing about privacy or data is involved.

## Work done (2026-10-03)

Hardening, whatever the cause (next step 3), and a trace for next time (step 2):

- **Clear layers.** The overlay view's layer is set non-opaque with a clear background, on top of the window's `isOpaque = false` and the `SKView`'s `allowsTransparency`.
- **Watchdog.** `OverlayWatchdog` (Core, `OverlayWatchdogTests`): while the overlay is awake the scene reports every frame; after `Timing.overlayStall` (2 s) without one, the window is ordered out, then tried again after 1 s, 2 s, 4 s… up to 30 s, or at once when a frame arrives. A full-screen Space hiding the overlay doesn't count as a stall. If hypothesis 1 is right and the surface stops being presented because frames stop, the grey can last at most about 2 s.
- **Displays.** The overlay follows display changes (it used to keep its launch-time frame) and leaves the screen while the display sleeps, returning with a fresh clock on wake.
- **Diagnostics.** Wake (with its reason), time to first frame, sleep, watchdog trips and recoveries, and display changes go to an in-memory `Diagnostics` buffer. **If it happens again: right-click the menu bar icon → Settings… → Diagnostics → Copy Diagnostics**, and paste it into this file with the time.
- **Soak harness.** `scripts/soak-overlay.sh [--minutes M] [--copies N] [--rate R]` runs private release copies with the crew out under load, captures each overlay window every second (`Tools/soak/overlay-probe.swift`), keeps any mostly opaque frame, and counts watchdog trips in the copies' diagnostics.

What the watchdog can't catch: a surface that goes grey while frames keep coming. The soak harness is the check for that.

Later the same day: every gap of more than 250 ms between overlay frames is logged too ("overlay frame gap N ms"), the overlay is never animated in or out (`animationBehavior = .none`), and a window frame that differs from the display's is logged and corrected when the overlay wakes.

## Soak runs (2026-10-03)

| Run | Setup | Result |
|---|---|---|
| 1 | 1 min, 2 copies, 200 events/s each | 86 captures, most opaque 5.2%, no watchdog trip |
| 2 | 30 min, 2 copies, 200 events/s each, builds running alongside | 2,510 captures, none mostly opaque (most 5.7%), no watchdog trip. **Caveat:** the owner's Mac locked partway through (the copies logged a display change at 17:44:50; the display turned off at 18:14), so most of this ran behind the lock screen and doesn't count towards the hour in "Done when" |
| 3 | 2 min, 2 copies, Mac locked, display off | Overlays never drew a frame; the watchdog took them off screen twice per copy, as designed. The harness flagged this, correctly |
| 4 (2026-10-04) | 20 min, 2 copies, 200 events/s each, **unlocked, display on throughout** (checked at the end) | 1,632 captures, none mostly opaque (most 5.8%), no watchdog trip, no frame gap over 250 ms. The first valid stretch towards the hour |
| 5 (2026-10-04) | 11 runs of 45 s, one copy, 100 sessions, 200 events/s, unlocked, no probe | **One run (21:31) had frames stop for ~40 s while the window counted as visible**: 5 watchdog trips (it was taken off screen and retried with backoff each time), no frame gap logged because frames never resumed before the run ended. The other 10 runs were clean. The run's log wasn't kept and the system log had nothing for that minute. Since then the watchdog's line records the window's state (occlusion, active Space, paused, frame, app active) |

Learned on the way, all from the lock screen, not Agentville:
- **Behind the lock screen, WindowServer shows every app window at 90% around the screen's centre** (the window list reports the overlay at 1324×862 on a 1470×956 display while AppKit's frame is unchanged), the overlay is occluded, and SpriteKit stops drawing. While the copies were behind it, SpriteKit logged "SKView: no drawables available for rendering. Skipping this frame." every 5–6 s; single copies on an unlocked screen don't (3 runs of 60 s: idle, under load, under load with the probe).
- The probe now finds the overlay by owner and level rather than exact size, and reports a window shown at a size other than the display's.

2026-10-04, unlocked: the "no drawables" warning also shows in two-copy soaks on an unlocked screen (about every 6 s per copy, from launch) and once in a single copy (2 in one 45 s run), never with a frame gap, so SpriteKit gives up on a drawable quickly rather than waiting. Unexplained; no visible effect so far.

The frame stop in run 5 is the closest thing to the bug seen so far: if the window had stayed up while not drawing, the screen could have shown whatever WindowServer keeps for it. With the watchdog it was off screen within about 2 s.

Still worth trying, with someone at the Mac: lock and unlock, display sleep and wake, and plugging in or removing an external display, all with the crew out (`scripts/soak-overlay.sh` running alongside).

## Next steps

1. **Reproduce.** Build a soak harness: run the app with the crew out under load for long stretches, varying conditions (two copies at once, memory pressure, Safari frontmost, sleep/wake, display changes). Sample the overlay window every second and flag any frame that's mostly opaque, saving it with the time.
2. **Instrument.** Log the overlay's wake, sleep and present state in memory (in the diagnostics ring buffer, never to disk) so the next occurrence leaves a trace.
3. **Harden, whatever the cause.**
   - Explicitly non-opaque, clear-backed layers on the overlay view and window.
   - Order the window out whenever the scene hasn't drawn for a while.
   - Consider covering only the area the crew actually uses instead of the whole screen.
4. **If it happens again**, note the time and run this within the hour, before the logs roll over:
   ```sh
   log show --last 30m --predicate 'process == "WindowServer" OR process == "Agentville"'
   ```

## Done when

- [ ] Reproduced, or the cause found by instrumentation
- [ ] Fixed, with a regression check (the soak harness, or a test where possible)
- [ ] The harness runs for an hour under load with no opaque frame
- [ ] Owner confirms it hasn't recurred over a week of normal use
