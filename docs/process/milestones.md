# Milestones

Purpose: the build order. Each milestone ends with something the owner can see and check. Tick items only with evidence.

**Current milestone: M1** (data path), built; replay checked by the owner, a real-session check remains. M0 is done apart from the owner's answers. Next: M2.

| # | Milestone | Done when |
|---|---|---|
| M0 | Repo skeleton, docs, privacy promises, guards, CI | The owner agrees on the open questions marked M0 |
| M1 | `agentville-hook`, wire codec, socket listener, session store, replay tool | Replay scenarios produce correct session states in a debug list; all hook tests pass |
| M2 | Menu bar item + desk window (office + list); sprite renderer port | The office matches the prototype with replayed sessions, all states and monitor screens |
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
- [x] Debug list window in the app showing live store state (menu → *Session List (Debug)…*, ⌘D)
- [x] Owner checks a replayed scenario in the debug window: 2026-10-01, `demo-mix` final state matched every `expect` line (5 sessions, 18 events received, 0 dropped)
- [ ] Owner checks a real Claude Code session in the debug window (plugin installed + `scripts/dev-link-hook.sh`)

## Later milestones

Detailed checklists are written at the start of each milestone, using the per-area lists in [success-checklists.md](../quality/success-checklists.md).
