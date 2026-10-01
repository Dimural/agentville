# Input, click-through and safety mechanics

Purpose: how the crew can be grabbable *and* never steal a click, using no special permissions.

## Click-through and grabbing coexist like this

- Every overlay window has `ignoresMouseEvents = true` by default.
- While the crew is out (or a walk-on is active), `InputPoller` reads `NSEvent.modifierFlags` and `NSEvent.mouseLocation` at 30–60 Hz.
- **Only when ⌥ is held *and* the cursor is inside a character's hit box** does that display's overlay set `ignoresMouseEvents = false`, so the next press grabs the character.
- The moment either condition stops being true (and no drag is in progress), it goes back to `true`.
- This mirrors the prototype's capture-phase `pointerdown` listener, which only intercepts presses that actually hit a character (`hitTest`) and lets every other click through untouched.

### Hit box (from the prototype's `hitBox`)

Feet at `(x, y)`, scale `sc` points per pixel, lift `z + hop`:
- top = `y − lift − 24·sc`, bottom = `y`, half-width = `8·sc` (`16·sc` for the crowd), plus padding (6 pt for hover fade, 4 pt for grabbing).

## Reading input without permissions

- Modifier keys and cursor position: **poll the current values**. No event taps and no global monitors (those need Input Monitoring / Accessibility). **Verify** on the minimum macOS version that polling raises no prompt.
- Global shortcut ⌃⌥C: Carbon `RegisterEventHotKey` (no permission).
- Esc to call back works only while an Agentville window is key (like the prototype's page focus). The global path is ⌃⌥C.

## Grab, drag, throw (from `endDrag` and the `thrown` mode)

- Press: mode `drag`, pose `dangle`, z = 10, bubble cleared.
- Move: the character follows the cursor (clamped to the screen and the walkable area). Keep the last 6 position samples.
- Release with < 5 pt of movement = a **tap**: walk-ons go home; the crowd resumes roaming; anyone else hops, says "hey!", "boop", "hi there" or "*giggle*", with pink sparkles.
- Release otherwise = a **throw**: velocity from the first and last samples, capped at 1500 pt/s; `vy × 0.6`; `vz = clamp(speed × 0.35, 80, 460)`. A throw faster than 900 pt/s causes 1.8 s of dizziness on landing. Faster than 700: "waaah!", "whoa!" or "aaa!".
- Releasing ⌥ mid-drag ends the drag as a release (throw or tap).
- App deactivation or a screen change cancels the drag (the character settles where it is).

## Escape hatches (re-stated, because they're non-negotiable)

1. Status item menu is always reachable (overlay window level < menu bar).
2. ⌃⌥C works from any app.
3. Quit removes everything at once.
4. Force Quit works.
5. Recall completes within 2.6 s from any state: mid-drag, mid-throw, window hidden, 100 sessions, a walk-on in progress.

**None of these may depend on the overlay accepting input.**

## Done when

- [ ] Manual check: with the crew out, buttons, text fields, scrolling, drag-and-drop and window resizing underneath all work
- [ ] Manual check: ⌥-grab works on every display; releasing ⌥ returns to click-through instantly
- [ ] No permission prompt appears on a fresh account (minimum macOS)
- [ ] Recall from each state listed above (replay scenario + manual)
