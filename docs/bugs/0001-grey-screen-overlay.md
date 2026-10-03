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
- running two copies at once, as happened when it occurred;
- heavy memory pressure (a release build was compiling just before);
- a long soak of tens of minutes;
- Safari frontmost;
- sleep/wake or a display change while the crew is out.

## Hypotheses (unconfirmed)

1. **The overlay's surface lost its content and WindowServer showed a placeholder.** The overlay is a full-screen, non-opaque window drawn by a Metal-backed `SKView`. If its drawable were purged or not presented (memory pressure, a GPU stall, the app busy), WindowServer might fill it with grey rather than leave it transparent. This fits the flat colour and the missing crew.
2. **A frame was presented with the view's layer opaque.** For example, the `SKView`'s backing layer treated as opaque before `allowsTransparency` took effect, or after a re-present. Less likely: the capture tests never saw it, and it wouldn't explain several seconds of grey.
3. **Not Agentville at all.** Something else drew a full-screen window between the Dock and the menu bar. Unlikely given the match and the timing, but not ruled out.

## Impact on users

If it's the overlay, any user with the crew out could lose their screen for an unknown time. The menu bar stays visible, so **Quit Agentville** and ⌃⌥C should still be reachable. Click-through probably still works, since the window ignores the mouse, but that's unverified. Nothing about privacy or data is involved.

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
