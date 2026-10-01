# Testing strategy

Purpose: how we test heavily without being able to "look" in CI, and what each layer guarantees.

## Layers

| Layer | Where | Runs in CI | What it proves |
|---|---|---|---|
| **Unit (Core)** | `Tests/AgentvilleCoreTests` | Yes | Filter, codec, mapping, store transitions, staleness, looks, caps, all pure and deterministic |
| **Golden** | `Tests/AgentvilleCoreTests/Fixtures` | Yes | Ports match the prototype exactly (look vectors now; sprite and office PNGs from M2) |
| **Stress** | `SessionStoreStressTests` | Yes | 100 sessions × thousands of events: bounded memory, time per batch |
| **Hook integration** | `Tests/HookIntegrationTests` | Yes | Spawns the real built `agentville-hook` binary: exit codes, stdout, socket contents, timing |
| **Static guards** | `scripts/check-*.sh` | Yes | No networking APIs, no stray disk writes, binary sizes, doc links |
| **Plugin validation** | `claude plugin validate` | When the `claude` CLI is available | The manifest and marketplace are valid |
| **Replay scenarios** | `Tools/scenarios/*.jsonl` + `agentville-replay` | No (needs the app) | Drives the real app through every state for visual and manual checks |
| **Manual / release** | [release-checklist.md](../process/release-checklist.md) | No | Click-through over real apps, permissions, real sessions, side-by-side visuals |

## Rules

- **Core is pure and gets tests first.** No AppKit in Core; inject clocks (`now: Date`/`TimeInterval` parameters) rather than reading the system clock, so time-based logic is deterministic.
- **Randomness is injectable** in behaviour code (seeded RNG) so behaviour tests are reproducible.
- **Every bug fix starts with a failing test.**
- **Privacy tests use secret markers.** Put strings like `SECRET-PROMPT-7f3a` in every non-allowlisted field and assert that the marker never appears in the output bytes.
- **Tests run serially** (`--no-parallel`) so the hook wall-time measurements aren't skewed by other suites hogging the CPU.
- **Prove a test can fail.** For new guards and spec runners, break the input once on purpose and watch it go red (done for `ScenarioTests`, `check-docs`, and the guard self-tests).
- **The hook integration tests build first.** `scripts/test.sh` builds the `agentville-hook` product before running tests; the tests locate it in `.build/<config>/`.
- **Timing tests measure the hook's own cost.** Each run is compared against a baseline spawn of `/usr/bin/true` with the same stdin, because shared CI VMs spend about 130 ms just spawning a process (first CI run, 2026-10-01). The added cost must meet the budget everywhere (2× slack on CI for tails). On a real Mac the absolute wall time must meet it too.

## Replay scenarios (M1)

Scenario files carry `expect` lines, so they are **executable specs**: `ScenarioTests` runs every file in `Tools/scenarios/` through `WireCodec` + `SessionStore`, and checks them. See [Tools/scenarios/README.md](../../Tools/scenarios/README.md).

| Scenario | Covers |
|---|---|
| `lifecycle.jsonl` | start → prompt → tools → permission → tools → stop → idle → end |
| `demo-mix.jsonl` | the prototype's 5 sessions (one finishes at about 5 s, one asks for permission at about 15 s) |
| `--generate hundred` | 100 sessions with a realistic mix |
| `--generate burst` | 500+ events per second (verified: 2,000/s, all delivered) |
| `silent.jsonl` | a session goes quiet with no `SessionEnd` |
| `long-bash.jsonl` | `PreToolUse(Bash)` then 20 minutes of silence |
| `malformed.jsonl` | malformed, wrong-version, unknown-event and hostile messages |
| `subagents.jsonl` | several subagents starting and stopping |

## Running

```sh
scripts/test.sh                 # everything
scripts/test.sh --filter Hook   # a subset (args are passed to `swift test`)
scripts/ci.sh                   # tests + all guards, exactly as CI
```
