# The hook helper: `agentville-hook`

Purpose: the exact behaviour of the tiny program Claude Code runs on every hook event. It runs inside the user's coding sessions, so it's the most safety-critical code in the project.

## Contract

1. Read stdin, up to **4 MiB**. Claude Code payloads can be large (`tool_output` after reading a big file, `last_assistant_message`), and a lower cap would silently lose real events (found by the integration tests). Anything beyond the limit is discarded and the event is dropped. stdin is always drained, so Claude Code never sees a broken pipe.
2. Parse JSON. If it fails, exit 0.
3. `HookPayloadFilter.filter` → `WireEvent?`. If nil, exit 0.
4. Encode (≤ 1024 bytes) and `sendto` the socket with `MSG_DONTWAIT`. Ignore every error.
5. **Exit 0. Always.**

## Hard rules

| Rule | Why |
|---|---|
| Never write to **stdout** | Exit 0 + stdout is parsed by Claude Code and, for some events, injected into Claude's context |
| Never write to **stderr** in normal operation | Keeps debug logs clean; a crash still can't block (async) |
| Never **exit non-zero**, never exit 2 | Non-zero shows "hook error"; 2 can block actions |
| Never **wait** on the app: no connect retries, no reads, no sleeps | The session must never feel it |
| Never **write files** | Privacy promise |
| Never import AppKit, SwiftUI or a networking framework | Startup time; no-network promise |
| Finish in **< 50 ms p99** with the app running, **< 10 ms** with it absent | Footprint promise |

Signals and crashes: the `main` entry is wrapped so any thrown error lands in `exit(0)`. SIGPIPE is ignored.

## How Claude Code invokes it

The plugin's `hooks/hooks.json` uses the **shell form**, so the command can stay silent when the helper is missing (the app was deleted):

```sh
h="$HOME/Library/Application Support/Agentville/bin/agentville-hook"; if [ -x "$h" ]; then "$h"; else cat >/dev/null; fi; exit 0
```

`$HOME/Library/Application Support/Agentville/bin/agentville-hook` is a symlink the app maintains, pointing at the helper inside `Agentville.app`. If the app is deleted, the symlink dangles, `-x` is false, stdin is drained, and the hook exits 0. See [ADR 0007](../decisions/0007-hook-location.md).

## Tests (in `Tests/HookIntegrationTests`)

- Real-shaped payloads for every registered event, including a 200 KB `tool_output` and `last_assistant_message`, with secret markers → only allowlisted fields arrive at a test socket.
- Exit code is 0 and stdout is empty for: valid events, unregistered events, malformed JSON, empty stdin, binary garbage, a 1 MB payload, a missing socket, a socket path that is a regular file.
- Timing: 200 runs with a listening socket and 200 without; assert p99 under budget.
- The shell-form command line from `hooks.json` with the helper absent → exit 0, empty stdout.

## Done when

- [x] All tests above pass locally (`HookBinaryTests`, 2026-10-01); CI pending the first push
- [x] The release binary is < 2 MB: 152 KB (`scripts/check-footprint.sh`, 2026-10-01)
- [x] `otool -L` of the binary shows no networking or UI frameworks (`check-footprint.sh`)
