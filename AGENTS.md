# AGENTS.md: start here

You are working on **Agentville**, a native macOS menu bar app. It turns every local Claude Code session into a pixel character that acts out what the session is doing. This file is the entry point for AI coding agents. `CLAUDE.md` imports it.

## 1. Read before you touch anything

1. [docs/README.md](docs/README.md): the docs index, with a "what to read for which task" table.
2. [docs/quality/non-negotiables.md](docs/quality/non-negotiables.md): the 12 rules no change may break.
3. The doc for the area you're changing (the index tells you which).

**Ground truth.** The owner has two local reference files at the repo root, `Pixel Crew.html` (the interactive prototype) and `PROJECT_BRIEF.md` (the original brief). They are **gitignored on purpose. Never commit them, move them, or copy them into tracked files.** If they exist on disk, read them. If they don't (a fresh clone), the docs in `docs/` are the digested spec. See [docs/reference/README.md](docs/reference/README.md).

- On **look, feel and motion**, the prototype wins over the docs.
- On **data flow, privacy and what's allowed**, the docs win.

## 2. Commands

| Task | Command |
|---|---|
| Build and test everything | `scripts/test.sh` |
| Build only | `scripts/swift.sh build` |
| Release build | `scripts/swift.sh build -c release` |
| Privacy guard: no networking | `scripts/check-no-network.sh` |
| Privacy guard: no stray disk writes | `scripts/check-no-disk-writes.sh` |
| Footprint check (binary and bundle sizes, no entitlements) | `scripts/check-footprint.sh` |
| Build `dist/Agentville.app` (ad-hoc signed) | `scripts/bundle-app.sh` |
| Quit leaves nothing behind (needs a logged-in Mac; launches the app) | `scripts/check-quit-cleanup.sh` |
| All checks CI runs | `scripts/ci.sh` |
| Validate the Claude Code plugin | `claude plugin validate ./Plugin/agentville` and `claude plugin validate .` |
| Soak the overlay (bug 0001; launches the app, needs Screen Recording) | `scripts/soak-overlay.sh --minutes 30 --copies 2` |
| Send replay scenarios to a running app | `swift run agentville-replay Tools/scenarios/<name>.jsonl` |
| Point real Claude Code sessions at a dev hook build | `scripts/dev-link-hook.sh` (undo: `--remove`) |

`scripts/swift.sh` wraps `swift`. It works with full Xcode and with the Command Line Tools alone (it adds the Swift Testing framework paths when needed). Use it rather than bare `swift test`.

## 3. Repository map

```
AGENTS.md / CLAUDE.md        agent entry point (you are here)
Package.swift                one SwiftPM package; no .xcodeproj (see ADR 0004)
Sources/AgentvilleWire/      THE privacy boundary: hook payload → allowlisted WireEvent, codec, socket
Sources/AgentvilleCore/      pure, testable app logic (re-exports AgentvilleWire); no AppKit
  Sessions/                  tool→activity mapping, SessionStore state machine, Scenario parser, constants
  Looks/                     deterministic character looks (port of prototype lookFor), sprite + office renderers
  Crew/                      CrewSim: the crew on the desktop (release, recall, roaming, particles), pure and seeded
  Transport/                 SocketListener: the app's receiving end of the hook socket
  Support/                   Diagnostics: the in-memory diagnostics buffer
Sources/agentville-hook/     the hook helper Claude Code runs (links only AgentvilleWire)
Sources/agentville-replay/   dev tool: sends scripted events to the app socket
Sources/agentville-icon/     build tool: writes the app icon (AppIcon in Core) for scripts/bundle-app.sh
Sources/Agentville/          the menu bar app (AppKit + SpriteKit)
Tests/                       Swift Testing suites + fixtures
Plugin/agentville/           the Claude Code plugin (manifest + hooks/hooks.json)
.claude-plugin/              marketplace.json so this repo is installable as a marketplace
Tools/scenarios/             replay scenarios (.jsonl)
Tools/fixtures/              golden-fixture exporters (run the local prototype in headless Chrome)
Tools/soak/                  overlay-probe for scripts/soak-overlay.sh (bug 0001)
scripts/                     build/test/guard scripts (all CI logic lives here)
docs/                        all specs, decisions, checklists
.claude/settings.json        project permissions for agents (repo scripts allowed; `git add -f` denied)
```

## 4. How to work here

- **Docs first.** If a change alters behaviour, a constant, the data contract or a decision, update the doc in the same commit. If the docs and the code disagree, that's a bug.
- **Small commits, often.** Use Conventional Commits: `feat(core): …`, `fix(hook): …`, `docs: …`, `test: …`, `chore: …`. Each commit should build and pass `scripts/test.sh`.
- **Test-first for Core and the hook.** Everything in `AgentvilleCore` is pure and must have tests. A bug fix starts with a failing test.
- **Port, don't reinvent.** Sprite drawing, looks, motion constants and timings come from the prototype. Port them faithfully and cite the prototype function name in a comment (e.g. `// port of drawChar`).
- **Constants live in one place.** Tool→activity mapping is in `Sessions/ActivityMapping.swift`. Motion and limit constants go in `Constants.swift`. Don't scatter magic numbers.
- **Scenarios are specs.** A new session behaviour gets a `Tools/scenarios/*.jsonl` file with `expect` lines; `ScenarioTests` runs it automatically.
- **Never add:** networking code, analytics, logging to disk, new entitlements, permission prompts, third-party art or brand marks, or dependencies without an ADR in `docs/decisions/`.
- **Decisions.** Anything a future agent might re-litigate gets a short ADR in `docs/decisions/`. Open questions for the owner live in [docs/decisions/open-questions.md](docs/decisions/open-questions.md). Don't silently decide one: propose a default there and flag it.
- **Done means** the relevant checklist in [docs/quality/success-checklists.md](docs/quality/success-checklists.md) is ticked, tests pass, and the guards pass.

## 5. Environment notes

- You can build the app, hook and tests on any Mac with Swift 6. You can only *look at* the app on the owner's Mac. Cloud and Linux agents can write and unit-test Core logic but can't run the UI.
- If `swift` fails with an Xcode licence error, `scripts/swift.sh` falls back to the Command Line Tools automatically. The owner can fix it permanently with `sudo xcodebuild -license accept`.
