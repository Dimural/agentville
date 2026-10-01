# Architecture overview

Purpose: the four parts of Agentville, how data flows between them, and why it's built this way.

```
 Claude Code session(s)                       Agentville.app (menu bar, no Dock icon)
 ┌──────────────────────┐  hook event   ┌───────────────────────────────────────────────┐
 │ CLI / VS Code /      │ JSON on stdin │                                               │
 │ desktop (local)      │ ────────────▶ │  SocketListener ─▶ SessionStore ─▶ UI @ 4 Hz  │
 │                      │ agentville-   │  (AF_UNIX dgram)  (state machine)             │
 │ plugin hooks,        │ hook          │                        │                      │
 │ async: true          │ (allowlist,   │                        ▼                      │
 └──────────────────────┘  send, exit 0)│  Desk window (office + list)                  │
                    one datagram ─────▶ │  Overlay windows (one per display, click-thru)│
                    over a local        │  Status item (menu bar)                       │
                    Unix socket only    └───────────────────────────────────────────────┘
```

## The four parts

| Part | Code | Job |
|---|---|---|
| **Hook helper** `agentville-hook` | `Sources/agentville-hook/` + `AgentvilleCore/Wire/` | Claude Code runs it on each hook event. Reads stdin JSON, keeps **only allowlisted fields** ([data-contract.md](data-contract.md)), sends one datagram to the app's socket, exits 0. Silent and instant if the app is absent. Details: [hook.md](hook.md). |
| **Plugin** | `Plugin/agentville/` + `.claude-plugin/marketplace.json` | Registers the hook for the events we need, with `"async": true`. This repo doubles as the marketplace. |
| **App** | `Sources/Agentville/` + `AgentvilleCore/Sessions/`, `Looks/` | Native Swift menu bar app: socket listener, in-memory session store, desk window, overlay, status item. Details: [app.md](app.md). |
| **Installer flow** | App welcome window + Homebrew cask | Connect / Disconnect (plugin path or settings-file path). Details: [installation.md](installation.md). |

Plus a dev-only fifth part: **`agentville-replay`** sends scripted `WireEvent`s to the socket, standing in for the prototype's simulator.

## Module boundaries

```
AgentvilleWire   (Foundation/Darwin only) HookPayloadFilter, Sanitize, WireEvent, WireCodec, SocketPath, DatagramSocket
AgentvilleCore   (no AppKit, no global state, 100% unit-testable; re-exports AgentvilleWire)
   ├── Sessions   ActivityMapping, SessionStore, Session, StoreEffect, Scenario, Constants
   └── Looks      LookHash (hash + rng), RGB, Palette, Look, LookGenerator; later: PixelCanvas, SpriteRenderer
agentville-hook  → AgentvilleWire only. Tiny (≈150 KB); must start fast.
agentville-replay→ AgentvilleCore
Agentville (app) → AgentvilleCore + AppKit + SpriteKit (+ SwiftUI for settings and welcome)
```

Rules:
- **All logic that can be pure is in Core** and tested there. The app target is thin glue and rendering.
- **The hook depends on nothing but AgentvilleWire and Foundation/Darwin.** No AppKit; startup time matters. The compiler enforces this: the hook target can't see Core.
- **No networking framework is imported anywhere.** Unix-domain sockets go through Darwin's `socket(AF_UNIX, …)`, and CI checks this.

## Why this design

- **A command hook, not Claude Code's `http` hook type.** The `http` type posts the *entire* payload (prompts, tool inputs, Claude's messages), so private data would reach the app even if it threw it away. It also turns "app not running" into a visible hook error. A filtering helper that always exits 0 avoids both.
- **`async: true`.** Async hooks run in the background and their timeout isn't enforced, so a session never waits on Agentville.
- **A plugin rather than editing `settings.json`.** Install, update, disable and uninstall are standard one-line operations, and we don't touch the user's config in the normal case.
- **A local Unix datagram socket, not HTTP or files.** No network stack, nothing to clean up, and the app's absence is detected instantly (`ECONNREFUSED` / `ENOENT`). Datagrams are fire-and-forget: the hook never blocks on the app.
- **SwiftPM only, no `.xcodeproj`.** Plain-text, diff-able, agent-friendly builds. The `.app` bundle is assembled by a script ([ADR 0004](../decisions/0004-swiftpm-no-xcodeproj.md)).

## Data flow invariants

1. Untrusted input crosses **two** boundaries. Each one validates:
   - hook stdin → `HookPayloadFilter` (allowlist, sanitize, size-cap)
   - socket → `WireCodec.decode` (size cap, schema version, known event names, re-sanitize)
2. Nothing in the app ever sees a field that isn't on the allowlist.
3. Session state lives **only in memory**. Quitting discards it.
4. UI work is **batched**: the store can absorb thousands of events per second, while the list and summary redraw at 4 Hz.
