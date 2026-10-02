# The app

Purpose: how `Agentville.app` is structured internally, and the performance rules every part follows.

## Components

| Component | Responsibility | Tech |
|---|---|---|
| `AppDelegate` | Lifecycle; `.accessory` activation policy (no Dock icon); owns everything below; tears down on quit | AppKit |
| `SocketListener` (Core, `Transport/`) | Binds the `AF_UNIX` datagram socket (mode 600), drains it on a background `DispatchSource` with one reused buffer, decodes with `WireCodec`, and hands events to the store on the main queue **in batches** of at most `Limits.listenerBatch`. Counts dropped (undecodable) datagrams for diagnostics. `stop()` removes the socket file only if it is still the one this listener bound. Lives in Core so it's tested on a real socket (`SocketListenerTests`) | Darwin + Dispatch |
| `SessionStore` (Core) | In-memory state machine ([sessions-and-states.md](../product/sessions-and-states.md)); bounded; emits change notifications | Pure Swift |
| `StatusItemController` | Menu bar icon: `MenuBarIcon.head` as a 9×9 template image at 2 pt per pixel (exact 1× and 2× bitmaps), the session count in mono digits, and a 7×7 warn-coloured dot over the head's top-right while anything needs you. Menu: header ("Agentville  N sessions"), Show/Hide Window, Quit. Release (M3) and Settings (M7) join later | `NSStatusItem` |
| `DeskWindowController` | The office (`OfficeRenderer` → `PixelImage` at ≈12 fps, `Timing.officeFrame`; "+N more below" and twin badges drawn over it), the summary line and the session list (`DeskList` rows, view-based table, ≤ 4 Hz). Both timers run only while the window is visible, not miniaturised and not occluded. Colours are the prototype's `--win*` tokens (`Theme`). The Release button arrives with M3. `Agentville --show-window` opens it at launch (for side-by-side reviews) | AppKit; office drawn to a `CGImage` from Core's pixel renderer |
| `OverlayController` | One borderless, transparent, shadowless, click-through window per display; a SpriteKit scene per window; release/recall, roaming, notices, crowd, particles | AppKit + SpriteKit |
| `InputPoller` | While the crew is out: polls modifier flags and the cursor at 30–60 Hz; toggles `ignoresMouseEvents` only when ⌥ is held *and* the cursor is over a character | AppKit |
| `HotKey` | ⌃⌥C via Carbon `RegisterEventHotKey` (no permission needed) | Carbon |
| `SettingsWindow`, `WelcomeWindow` | Settings, Connect/Disconnect, Diagnostics (in-memory event feed) | SwiftUI |

## Rendering

- Sprites are generated procedurally (a port of `drawChar` + `outline`) into a small RGBA buffer, **once per (look, pose, frame, highlight)**, and cached as `SKTexture`/`CGImage` with **nearest-neighbour** filtering.
- Integer scales only: 3 points per pixel on the desktop (2 on small screens), 2 in the office.
- `PixelImage.cgImage(canvas, scale:)` (Core) turns a `PixelCanvas` into a `CGImage`, pre-scaled by an integer factor with interpolation off (`PixelImageTests`). Views that show it set their layer's `magnificationFilter` to `.nearest`, so an integer upscale to the backing scale stays crisp without a per-frame copy.
- Positions are snapped to whole points when drawn; motion runs at display rate, while sprite frames advance at pixel-art rates ([motion-and-behaviour.md](../design/motion-and-behaviour.md)).
- Draw order: shadows → particles → sprites (sorted by y) → emotes; speech bubbles are their own layer, clamped inside the screen.

## Performance rules

1. **Idle means idle.** When the crew is inside and no walk-on is active, every overlay scene is **paused** (`isPaused = true`, windows ordered out) and the input poller is stopped. When the desk window is hidden, the office timer is stopped. The only remaining work is the socket's dispatch source.
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

- [ ] Instruments shows ≈0% CPU with the crew inside and the window closed
- [ ] The 100-session / burst replay scenarios meet the [performance budget](../quality/performance-budget.md)
- [ ] Quit leaves no process, no overlay and no socket file
