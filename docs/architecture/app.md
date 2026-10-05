# The app

Purpose: how `Agentville.app` is structured internally, and the performance rules every part follows.

## Components

| Component | Responsibility | Tech |
|---|---|---|
| `AppDelegate` | Lifecycle; `.accessory` activation policy (no Dock icon); owns everything below; tears down on quit. Each socket batch goes into the store; then the overlay hears about new and gone sessions (`sessionsChanged`, in store order) and the batch's `StoreEffect`s (`notify`), which is how finished turns and sessions that need you walk on while the crew is inside. The overlay is built on first release or first walk-on | AppKit |
| `SocketListener` (Core, `Transport/`) | Binds the `AF_UNIX` datagram socket (mode 600), drains it on a background `DispatchSource` with one reused buffer, decodes with `WireCodec`, and hands events to the store on the main queue **in batches** of at most `Limits.listenerBatch`. Counts dropped (undecodable) datagrams for diagnostics. `stop()` removes the socket file only if it is still the one this listener bound. Lives in Core so it's tested on a real socket (`SocketListenerTests`) | Darwin + Dispatch |
| `SessionStore` (Core) | In-memory state machine ([sessions-and-states.md](../product/sessions-and-states.md)); bounded; emits change notifications | Pure Swift |
| `StatusItemController` | Menu bar icon: `MenuBarIcon.head` as a 9×9 template image at 2 pt per pixel (exact 1× and 2× bitmaps), the session count in mono digits, and a 7×7 warn-coloured dot over the head's top-right while anything needs you. Left click toggles the desk panel (pressed look while it's open); right click or ⌃-click shows the menu: header ("Agentville  N sessions"), Release the crew / Call the crew back (⌃⌥C), Keep Panel Open, **Announce Finished Turns** ▸ (Every Turn / Turns of 20 s or More / Never; `Preferences.announceDone`, applied to `SessionStore.announceDone`), Quit. Settings (M7) joins later and takes over the announce choice | `NSStatusItem` |
| `DeskPanelController` | The desk as a dropdown panel under the icon ([0009](../decisions/0009-desk-panel-dropdown.md)): borderless non-activating `NSPanel`, placed by `PanelPlacement` (Core); closes on icon click, outside click (global mouse monitor, only while open and unpinned) or Esc; pinnable and draggable. Inside: the office (`OfficeRenderer` → `PixelImage` at ≈12 fps, `Timing.officeFrame`; "+N more below" and twin badges drawn over it), the summary line, the session list (`DeskList` rows, view-based table, ≤ 4 Hz) and a footer (pin, "⋯"). Both timers run only while the panel is visible and not covered. Colours are the prototype's `--win*` tokens (`Theme`). The Release button arrives with M3. `Agentville --show-desk` opens it pinned (for side-by-side reviews) | AppKit; office drawn to a `CGImage` from Core's pixel renderer |
| `OverlayController` | One borderless, transparent, shadowless window over the menu bar's display (more displays in M8), click-through except while ⌥ is held over a character or a drag is in progress (polled each frame in `pollInput`; a non-activating `OverlayPanel` that never becomes key), one level below the menu bar, on all Spaces, not over full-screen apps. A SpriteKit scene (`CrewScene`) steps `CrewSim` (Core) each frame and draws it with reused nodes: shadows → particles → sprites (by y) → emotes → speech bubbles; nearest-neighbour textures (`TextureCache`). The crowd is drawn as its first three members at one size smaller, with an orange "+N" bubble. Walk-ons (`CrewSim+WalkOns.swift`) wake the overlay while the crew is inside. When the sim is idle (nobody out, nothing queued, no particles) the view pauses and the window leaves the screen. Against [bug 0001](../bugs/0001-grey-screen-overlay.md): the view's layer is explicitly clear and non-opaque; while awake an `OverlayWatchdog` (Core) is told about every frame and asked once a second, and after 2 s without a frame makes the window transparent and click-through (not counting while a full-screen Space hides it), then restarts SpriteKit's rendering after 1, 2, 4… up to 30 s; the window goes on screen transparent on every wake and is revealed only after two frames, so it's never visible without a drawn frame; the window follows display changes (`didChangeScreenParameters`: frame, scene size and `CrewSim.stage`) and leaves the screen while the display sleeps. Wake, first frame, sleep, stalls and display changes go to `Diagnostics`. Homes: the desk feet while the desk panel is open (the list for sessions without a desk), otherwise just under the menu bar icon | AppKit + SpriteKit |
| `InputPoller` (`OverlayController.pollInput`) | While the crew is out (each overlay frame): polls modifier flags and the cursor; toggles `ignoresMouseEvents` only when ⌥ is held *and* the cursor is over a character, or mid-drag (`CrewSim.capturesMouse`); feeds the hover fade and grab mode; letting go of ⌥ ends a drag | AppKit |
| `HotKey` | ⌃⌥C via Carbon `RegisterEventHotKey` (no permission needed); unregistered on quit | Carbon |
| `Preferences` | Small `UserDefaults` values (`announceDone`, `hideNames`). The one file allowed `UserDefaults` by `scripts/check-no-disk-writes.sh` | Foundation |
| `Diagnostics` (Core, `Support/`) | A bounded in-memory list of timestamped lines (`Limits.diagnosticsLines`) about what the app did; never session contents, never written to disk. Settings → Diagnostics shows it and **Copy Diagnostics** puts it, with the counts, on the clipboard. `--diagnostics-stderr` also prints each line to stderr (dev and `scripts/soak-overlay.sh`) | Foundation |
| `Installer` | Connect and Disconnect's disk and process work, only when the user asks: the helper link (`HelperLink` in Core decides; at launch only a dangling link is repaired), Path B's backup and write of `~/.claude/settings.json` (`ClaudeSettingsHooks` in Core does the text; written through a symlinked file, permissions kept, refused if the file changed since the preview), and running `claude` for Path A (`ClaudeCLI` in Core: where to look, the commands). With `Preferences`, the only file allowed to write | Foundation |
| `ConnectModel` | What the windows show about Connect: the detected `Connection` (Core), the phase (working, Path B preview, connected, failed), the commands' transcript, the live line and the "nothing arrives" explanation. Path A when `claude` is found, otherwise Path B after its preview | Observation |
| `WelcomeWindow`, `SettingsWindow` | The first-run window (pixel character, one sentence, **Connect to Claude Code**), shown at launch until connected, and Settings (`SettingsModel`: open at login via `SMAppService`, the done rule, hide names, the shortcut, Claude Code, Diagnostics). SwiftUI in AppKit windows; the app activates itself to bring them forward. Dev flags: `--no-welcome` (scripts), `--show-settings`, and with `AGENTVILLE_HOME` set, `--dev-connect=settings` and `--dev-disconnect` | SwiftUI |
| Hide names | `AppDelegate.shownOrdered` masks sessions with `NameMask` (Core) while the setting is on (cached per store revision); the list, the office and the crew read sessions only through it | Pure Swift |

## Rendering

- Sprites are generated procedurally (a port of `drawChar` + `outline`) into a small RGBA buffer, **once per (look, pose, frame, highlight)**, and cached as `SKTexture`/`CGImage` with **nearest-neighbour** filtering.
- Integer scales only: 3 points per pixel on the desktop (2 on small screens), 2 in the office.
- `PixelImage.cgImage(canvas, scale:)` (Core) turns a `PixelCanvas` into a `CGImage`, pre-scaled by an integer factor with interpolation off (`PixelImageTests`). Images replaced every frame (the office) go through `PixelColorMatcher` instead: the same, but with each palette colour converted once into the screen's colour space, so Core Animation doesn't colour-match every frame (`PixelColorMatcherTests`). Views that show it set their layer's `magnificationFilter` to `.nearest`, so an integer upscale to the backing scale stays crisp without a per-frame copy.
- Positions are snapped to whole points when drawn; motion runs at display rate, while sprite frames advance at pixel-art rates ([motion-and-behaviour.md](../design/motion-and-behaviour.md)).
- Draw order: shadows → particles → sprites (sorted by y) → emotes; speech bubbles are their own layer, clamped inside the screen.

## Performance rules

1. **Idle means idle.** When the crew is inside and no walk-on is active, every overlay scene is **paused** (`isPaused = true`, windows ordered out) and the input poller is stopped. When the desk panel is closed, the office timer is stopped. The only remaining work is the socket's dispatch source.
2. **Batch UI.** Socket events update the store immediately (cheap). The list and summary redraw on a **4 Hz** timer only if the store's revision changed. The status item coalesces updates the same way: the first batch schedules one redraw 0.25 s later, so a storm costs at most 4 redraws a second and a quiet app schedules none.
3. **Bounded everything.** ≤ 12 roamers, ≤ 3 walk-ons, ≤ 520 particles, ≤ 24 queued notices, ≤ 512 tracked sessions (oldest idle evicted first), diagnostics ring buffer ≤ 200 lines.
4. **No per-frame allocation in hot paths.** Reuse nodes and particle structs.
5. **Timers stop when unused.** Use display-link/SpriteKit updates only while a scene is running.
6. **One coarse clock.** `SessionStore.tick` (finished → idle, staleness) runs every `Timing.storeTick` (5 s, 50% tolerance). Store time is monotonic system uptime.

## Escape hatches (must never depend on the overlay accepting input)

- The status item menu is always above the overlay (overlay level is below the menu bar).
- ⌃⌥C toggles the crew from any app.
- Quit tears down every overlay at once; nothing survives quit. SIGTERM and SIGINT are turned into a normal quit, so `kill` also removes the socket file.
- Force Quit works as for any app.
- No login item unless the user opts in.

## Done when

- [ ] Instruments shows ≈0% CPU with the crew inside and the desk panel closed
- [ ] The 100-session / burst replay scenarios meet the [performance budget](../quality/performance-budget.md)
- [ ] Quit leaves no process, no overlay and no socket file
