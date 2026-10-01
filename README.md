# Agentville

**A cozy pixel town for your Claude Code sessions.**

Every Claude Code session running on your Mac gets its own little pixel character. It acts out what its session is doing: it types while code is being edited, hammers a tiny terminal while a command runs, and flips through a book while files are read. When a session finishes, or needs you, its character walks onto your screen and tells you. Press **Release the crew** and everyone pours out of their office window to roam your desktop. They stay fully click-through, so you keep working underneath them.

> **Status:** pre-alpha, milestone M0 (scaffolding). Nothing to install yet. See [docs/process/milestones.md](docs/process/milestones.md).

> **Unofficial.** Agentville is an independent open-source project. It is not made by, affiliated with, or endorsed by Anthropic. "Claude" and "Claude Code" are used only to describe what the app works with.

## The promises

These are hard rules, enforced by tests and CI. They aren't aspirations.

| Promise | What it means | How it's enforced |
|---|---|---|
| **Private** | The app only ever learns an event name, a tool name, a session id and the *folder name* of the project. Never prompts, code, file paths, file contents or Claude's replies. | The hook drops everything not on an allowlist before anything leaves it. Tests feed it real-shaped payloads stuffed with secrets and assert that none come out. |
| **Offline** | No networking code at all. No analytics, crash reporters or update checks. | `scripts/check-no-network.sh` fails the build if any networking API appears. |
| **Stores nothing** | Nothing is written to disk except your preferences. No event logs. | `scripts/check-no-disk-writes.sh` plus code review rules. |
| **Never slows Claude Code** | The hook sends one tiny local message and exits 0 at once. It does nothing if the app isn't running or has been deleted. | Hook integration tests check the exit code, empty stdout and timing. |
| **Light on your Mac** | At most 12 characters on screen, capped particles, UI updates 4× a second, near-zero CPU when the crew is inside. Small binaries. | Budgets in [docs/quality/performance-budget.md](docs/quality/performance-budget.md), checked by `scripts/check-footprint.sh` and stress scenarios. |
| **Always out of your way** | Clicks pass through the crew unless you hold ⌥. ⌃⌥C or the menu bar calls everyone back from anywhere. Quitting removes everything. | Release checklist and the non-negotiables in [docs/quality/non-negotiables.md](docs/quality/non-negotiables.md). |
| **No special permissions** | No Accessibility, Input Monitoring, Screen Recording, Automation or Full Disk Access. | Release checklist. |

### Verify it yourself

```sh
scripts/check-no-network.sh    # no networking APIs anywhere in the source
scripts/check-no-disk-writes.sh
scripts/test.sh                # includes the hook privacy tests
```

## How it works (one paragraph)

A tiny Claude Code plugin registers an `async` hook that runs `agentville-hook` on session events. The helper reads the event JSON, keeps only allowlisted fields (the event name, the tool name, the session id, the folder name and a few small enums), and sends one datagram to a local Unix socket. Then it exits 0. The menu bar app listens on that socket, keeps an in-memory session store, and draws the office window and the click-through desktop overlay. Full details: [docs/architecture/overview.md](docs/architecture/overview.md).

## Build from source

This needs macOS 14 or later and the Swift 6 toolchain (Xcode or the Command Line Tools).

```sh
scripts/test.sh            # build + run every test
swift build -c release     # build the hook, the replay tool and the app
```

## Contributing

Humans: start with [CONTRIBUTING.md](CONTRIBUTING.md). AI coding agents: start with [AGENTS.md](AGENTS.md). Both lead into the docs index at [docs/README.md](docs/README.md).

## License

MIT. See [LICENSE](LICENSE). All pixel art is original and drawn procedurally in code.
