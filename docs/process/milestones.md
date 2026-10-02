# Milestones

Purpose: the build order. Each milestone ends with something the owner can see and check. Tick items only with evidence.

**Current milestone: M3** (overlay, release and recall). M2 is done: the owner approved the desk panel on 2026-10-02. M1 is done: replay and real sessions verified by the owner on 2026-10-01. M0 is done apart from the owner's answers.

| # | Milestone | Done when |
|---|---|---|
| M0 | Repo skeleton, docs, privacy promises, guards, CI | The owner agrees on the open questions marked M0 |
| M1 | `agentville-hook`, wire codec, socket listener, session store, replay tool | Replay scenarios produce correct session states in a debug list; all hook tests pass |
| M2 | Menu bar item + desk panel (office + list); sprite renderer port | The office matches the prototype with replayed sessions, all states and monitor screens |
| M3 | Overlay, release and recall | Pour-out and suck-back match the prototype; click-through verified over real apps; recall rules pass |
| M4 | Roaming, meetings, particles, subagent sidekicks | All activity poses play on the desktop driven by replayed events |
| M5 | ⌥ grab, drag, throw; hover fade; global shortcut | Grab rules pass; no permissions requested |
| M6 | Walk-on notices, crowd and caps, staleness | 100-session and burst scenarios stay smooth; the done-announcement setting works |
| M7 | Plugin packaging, app bundle, welcome window, Connect/Disconnect (both paths), settings | A fresh Mac goes from install to a real session's character in under a minute |
| M8 | Signing/notarization (if chosen), cask, release checklist, multi-monitor | A public release candidate |

## M0: scaffolding

- [x] Docs: vision, end goals, UX, states, architecture, data contract, design, quality, process, decisions
- [x] `AGENTS.md` / `CLAUDE.md` entry point; docs index
- [x] Reference files gitignored; fixtures generated from the prototype
- [x] SwiftPM package: Core, hook, replay, app targets; tests
- [x] Guard scripts: no-network, no-disk-writes, footprint, docs links; `scripts/ci.sh`
- [x] GitHub Actions workflow calling `scripts/ci.sh`
- [x] Plugin + marketplace manifests (validated with `claude plugin validate`)
- [ ] Owner answers the M0 open questions (name/licence confirmed; min macOS)

## M1: data path

- [x] `HookPayloadFilter` + `WireEvent` + `WireCodec` with privacy tests
- [x] `ActivityMapping` with a table test
- [x] Look generator with golden vectors
- [x] `agentville-hook` executable + integration tests (exit 0, empty stdout, socket contents, timing)
- [x] `SessionStore` with every transition, staleness and stress tests
- [x] `SocketListener` in the app (bind, batch, unlink on quit): `SocketListenerTests` (real socket: order, drops, re-sanitize, burst batching, socket → store equals direct apply, unlink only our own file). Manual 2026-10-01: replay `demo-mix` and a 1,080-event burst all accepted; quit by SIGTERM/SIGINT leaves no socket file; 0.00 s CPU over 30 s idle
- [x] `agentville-replay` + all scenarios in [testing-strategy.md](../quality/testing-strategy.md#replay-scenarios-m1) (scenarios are executable specs)
- [x] Debug list window in the app showing live store state (menu → *Session List (Debug)…*, ⌘D). Replaced in M2 by the desk panel
- [x] Owner checks a replayed scenario in the debug window: 2026-10-01, `demo-mix` final state matched every `expect` line (5 sessions, 18 events received, 0 dropped)
- [x] Owner checks a real Claude Code session in the debug window: 2026-10-01, plugin installed from the local marketplace + `scripts/dev-link-hook.sh`; owner confirmed the states looked right

## M2: menu bar + desk panel

- [x] Sprite renderer port (`drawChar`, `sprite`, `outline`, `avatar`, `drawEmote`) with golden frames exported from the prototype: `SpriteRendererTests`
- [x] Bounded sprite cache (`SpriteCache`, LRU 2,000)
- [x] `PixelCanvas` → `CGImage` in the app, nearest-neighbour, integer scales: `PixelImage` (Core, CoreGraphics only), `PixelImageTests`
- [x] Office renderer port (`drawOffice`, `screenFor`, `deskUnits`): day/night, 6 desks, every monitor screen, "+N more below" count; golden office frames: `OfficeRendererTests`. About 2 ms per frame in a debug build
- [x] Desk window: office (≈12 fps, stops when hidden; "+N more below" badge) + session list (avatar, name, tool, chip, elapsed; ≤ 4 Hz); replaces the debug list. `DeskPanelController` + `DeskList` (`DeskListTests`); 2026-10-02: snapshots of the window during `demo-mix` and an 8-session twins replay checked against the prototype's layout
- [x] Status item: pixel head, count, red dot when anything needs you: `StatusItemController`, `MenuBarIcon` (`MenuBarIconTests`). Not yet seen on a real menu bar: part of the owner's review
- [x] Owner's first review (2026-10-02): contents approved; asked for a dropdown instead of a window → [0009](../decisions/0009-desk-panel-dropdown.md): `DeskPanelController`, `PanelPlacement` (`PanelPlacementTests`)
- [x] Owner's side-by-side review of the dropdown panel against the prototype with replayed sessions: approved 2026-10-02

## M3: overlay, release and recall

Scope: the crew pours out of the desk panel onto the desktop and gets sucked back, exactly as in the prototype. On the desktop each character plays its session's pose **in place**; walking, meetings, sidekicks and the rest of the particles are M4. Grabbing, hover fade, the HUD and ⌃⌥C are M5. One display (the one with the menu bar) until M8.

- [ ] `CrewSim` (Core): a pure, seeded simulation of the crew on the desktop. Ports of `release`, `recall`, `sendHome`, `spawnFromHome`, `Ent.launch`/`land`, the `fly`/`wait`/`drop`/`leave` modes of `updateEnt`, and the sparkle/dust/trail particles (cap 520). `CrewSimTests`: stagger timings, flight arc and stretch, landing squash and dust, ≤ 12 out, release/recall shouts, new and ended sessions while out, idle when everyone is home
- [ ] Recall rules (non-negotiable #2): everything home or removed ≤ 2.6 s from every state (mid-release, mid-flight, 100 sessions, panel closed, sessions ending): `CrewSimTests`
- [ ] Overlay window: borderless, transparent, shadowless, **always click-through** in M3, below the menu bar, on all Spaces, not over full-screen apps; SpriteKit scene paused and window ordered out whenever the crew is home
- [ ] Overlay rendering: nearest-neighbour sprite textures, shadows, particles, emotes and speech bubbles; draw order shadows → particles → sprites (by y) → emotes → bubbles
- [ ] Desk panel footer: the chunky **Release the crew** button (orange, invite bounce until first use) that turns blue and reads **Call the crew back**; the same item in the status menu; burp on release, gulp when the last one is home; empty desks while the crew is out
- [ ] Homes: desks while the panel is open, otherwise the menu bar icon
- [ ] Manual: click-through over real apps (buttons, text, scroll, drag-and-drop, resize); quit with the crew out leaves nothing
- [ ] Owner's side-by-side review of release and recall against the prototype

## Later milestones

Detailed checklists are written at the start of each milestone, using the per-area lists in [success-checklists.md](../quality/success-checklists.md).
