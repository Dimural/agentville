# User experience, end to end

Purpose: everything the user sees and does, in order. The prototype is the reference for how each step looks and moves.

## First run

1. Install with `brew install --cask <owner>/tap/agentville`, or a `.dmg` from GitHub Releases.
2. A small **welcome window** appears: one pixel character, one sentence about what the app does, one button: **Connect to Claude Code**.
3. The button installs the hook ([installation.md](../architecture/installation.md)):
   - **Path A (preferred):** if the `claude` CLI is found, add this repo as a marketplace and install the `agentville` plugin at user scope. Show the exact commands and their output in a disclosure area.
   - **Path B (fallback):** add a clearly marked hooks entry to `~/.claude/settings.json`, after showing a preview and writing a timestamped backup.
4. Confirm: **"Connected. Restart any open Claude Code sessions to see them."** (Hooks load when a session starts.)
5. A live line reads "Waiting for the first event…", which becomes "Last event 3 s ago". If `"disableAllHooks": true` is in the settings, it says so at once; if nothing arrives 90 s after Connect, it suggests restarting sessions and sending a prompt.
6. **Done** closes the window. From then on the app lives in the **menu bar** only (no Dock icon).

Details (built in M7): under the button, a small link, **Or add the hooks to settings.json yourself…**, goes straight to Path B's preview (for people who'd rather not use the CLI). Path B's preview names the file, shows the entry and the 12 events, says a backup is made first, and has a disclosure with the whole file after the change; **Add Hooks** writes it, **Cancel** changes nothing. If the CLI fails, the error is shown with **Add the hooks to settings.json instead…**. A **Details** disclosure shows each command and its output. The window comes back at every launch until Claude Code is connected (detected from `~/.claude/plugins/installed_plugins.json` and `settings.json`, read only).

## Settings

One window, three groups:

- **General:** **Open at login** (off; the system login item, only for the bundled app), **Walk on when a turn finishes** (Every turn / Turns of 20 s or more / Never), **Hide project names** ("session 1", "session 2"… in the list, the bubbles and the event feed; off), and the shortcut, **⌃⌥C** (shown, not yet changeable).
- **Claude Code:** how it's connected (plugin, settings file, plugin turned off, both, or not at all), the live line, **Connect to Claude Code** when not connected, **Disconnect** when connected. "Both" warns that every event arrives twice and offers **Remove the settings-file hooks**.
- **Diagnostics:** counts (sessions, events received and dropped, the crew and overlay state, the connection), then **What the app received** (the last 200 events: event, tool, folder and the start of the session id, which is exactly what crosses the privacy boundary) and **What the app did** (wake, sleep, stalls, display changes, connect), both in memory only. **Copy Diagnostics** copies the counts and what the app did, not the received events (they hold folder names).

## Menu bar item

It shows a pixel head, the active session count, and a red dot when any session needs the user. **Left click** drops the desk panel down below it ([0009](../decisions/0009-desk-panel-dropdown.md)). **Right click** (or ⌃-click, or the panel's "⋯" button) opens its menu:

- **Release the crew / Call the crew back** (⌃⌥C)
- **Keep Panel Open** (the panel's pin)
- **Settings…** (⌘,)
- **Quit Agentville** (⌘Q)

The menu header shows "N sessions".

## Desk panel (the office)

A dropdown under the menu bar icon, like Wi-Fi or Control Center: rounded, no title bar. It folds away when you click the icon again, click anywhere else, or press Esc. Pinned (the footer's pin, or *Keep Panel Open*), it stays open and can be dragged anywhere.

**Top: the pixel office** ([office.md](../design/office.md)). It has 6 desks in 2 rows of 3. Each desk's character acts out its session, and its monitor shows a matching animated screen. When there are more sessions than desks, a **"+N more below"** badge appears.

**Below: the summary line**, e.g. "7 active · 2 need you · 1 just finished". With no sessions it reads: "No sessions yet. Start Claude Code in any terminal."

**The session list**, one row per session:
- avatar (the head cropped from the sprite, at 2×)
- project folder name, with a small number badge for twins (2, 3…), plus the current tool in small mono text while working (and "+ subagent", or "+ N subagents" when there are several)
- status chip: **Editing, Reading, Running, Searching, On the web, Thinking, Needs you, Finished, Idle** (plus **Error** and **Planning / Tinkering** for the new states)
- elapsed time for the current turn (`4m 15s`, also while it needs you), or the duration of the last turn when Finished
- a **Needs you** row has a red chip whose square blinks, and the tooltip "Answer it in your terminal" (the prototype's "Answer" button is gone: open question 11)

Code: `DeskList` (Core) produces each row, the summary line and the menu header; `DeskListTests`.

**Footer:** a pin and a "⋯" (more) button on the right, and on the left the chunky **Release the crew** button (orange, with a gentle "invite" bounce until first use). Once released it turns blue and reads **Call the crew back**. Next to it is a `⌃⌥C toggles` hint.

The list re-renders **at most 4× per second**, however many events arrive.

## When a session finishes (crew inside)

1. The character walks in from the right screen edge to the bottom-right area (95 pt/s).
2. It celebrates: confetti, a jumping cheer, a check-mark emote.
3. Speech bubble: **"Done!"** over `project-name · 4m 15s`.
4. After about 6.5 s it walks back off the edge (110 pt/s).

Extra "done" notices fold into the newest bubble as **"+N more"**. Whether *every* turn announces is a setting (open question 1; default: turns of 20 s or more). Inside the office, every `Stop` still shows the cheer.

While the crew is **out**, there are no walk-ons: a roaming character cheers where it stands, and a session in the crowd is announced by the crowd ("api-server finished").

## When a session needs permission (crew inside)

Same walk-on, but the character **waves and jumps under a red `!`** with a **"Needs you"** bubble ("project is waiting for permission"). It stays until the session stops waiting, for at most 16 s (as in the prototype), then walks off.

At most **3 walk-ons at once** (2 on screens narrower than 900 pt, 1 below 560 pt). A tap on a walk-on (in grab mode) sends it home.

## Releasing the crew

Triggered by the button, the menu item or ⌃⌥C (from M5). If the desk panel is closed it opens first, so the crew pours out of it:

1. The desk panel **burps** (when open): squash-and-stretch plus a burst of sparkles.
2. One by one (first at 120 ms, then 85 ms apart), each character **leaps out of its desk** in an arc, stretched in flight with a sparkle trail.
3. Each **lands** at a random spot with a squash and a dust puff. About 35% shout "Wheee!", "Freedom!", "Hi!", "Let's go!" or "Stretch time".
4. On the desktop, each acts out its real session:

| Session state | Desktop behaviour |
|---|---|
| Editing | Sits cross-legged typing on a laptop; coloured code bits float up |
| Running a command | Hammers a tiny CRT terminal; sparks on each strike |
| Reading | Stands reading a book whose pages flip |
| Searching code | Creeps slowly with a magnifying glass |
| On the web | Looks through a telescope; stars twinkle |
| Thinking | Hand on chin under an animated "…" bubble |
| Subagent running | A half-size mini-me follows them, and types on its own laptop when they stop |
| Needs you | Runs to the bottom of the screen, jumps and waves under `!`, "Needs you" bubble |
| Finished a turn | Celebrates in place with confetti, "Done! · duration" bubble |
| Idle | Sips coffee or naps with floating Z's (chosen per character) |

5. Between activities they **wander**. Two working characters who meet stop, face each other, and pop a heart or `?`, sometimes with "hi!", "nice commit", "lunch?" or "high five!".
6. In the office, the desks are empty: chairs pulled out, monitors still showing each session's activity.
7. A HUD pill reads: "Clicks pass through · hold ⌥ to grab · ⌃⌥C calls them back".

## Calling them back

Triggered by the same button (now **Call the crew back**), the menu or ⌃⌥C:

1. Each character pops a `!`, about 30% say "Coming!", "Okay!", "Back to work!" or "On my way", then dangles through an arc back to its desk, shrinking to desk scale on the way.
2. The desk panel **gulps** (when open).
3. Everything is back or removed **within 2.6 s, no matter what**.
4. If the panel is closed, characters fly into the **menu bar icon** instead.

## Grabbing

- **Normally the crew is glass.** Every click, scroll and drag goes to whatever is underneath.
- **Hovering** over a character fades it to about 16% opacity (eased), so you can see what you're about to click.
- **Holding ⌥** turns on grab mode. Every character gets a light outline, and the HUD reads "Grab mode · drag anyone, let go to throw".
  - Press on a character to pick it up. It dangles, legs kicking.
  - Drag to move it. Let go to throw it with the cursor's velocity. It bounces off screen edges and the ground and slides to a stop. After a hard throw it's dizzy, with stars circling.
  - A tap without dragging gives a happy hop and "hey!", "boop", "hi there" or "*giggle*".
- **Releasing ⌥** makes everyone glass again immediately (and drops anyone held).

## Limits the user can notice

- **12 characters** roam at most. Extra sessions gather into a **crowd**: three overlapping half-size characters with a "+N" badge ("N need you" when relevant). When a roamer's session ends, the next one steps out of the crowd ("My turn!").
- **3 walk-on notices** at most.
- **Particles** are capped (520).
- When an ending session's character is out, it waves **"Bye!"**, then vanishes in a sparkle and dust poof.

## Quitting

Quit removes every character instantly. Nothing keeps running, and the user's Claude Code sessions are unaffected.

## Done when

- [ ] Every step above can be demonstrated with `agentville-replay` scenarios
- [ ] Every string above appears exactly as written (or the doc is updated)
- [ ] Owner's side-by-side check against the prototype passes
