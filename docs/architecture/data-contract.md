# Data contract

Purpose: exactly what Claude Code sends, exactly what `agentville-hook` forwards, and how the app validates it. This is the privacy boundary. Changing it requires updating [quality/privacy.md](../quality/privacy.md) and the tests in the same commit.

Source: the Claude Code hooks reference (https://code.claude.com/docs/en/hooks), checked 2026-10-01. Re-verify each milestone.

## What Claude Code sends on stdin (input)

Common fields on every event: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `permission_mode`. Conditional: `prompt_id`, `scratchpad_dir`, `effort`, `agent_id`, `agent_type`.

| Event | Notable event fields | Sensitive? |
|---|---|---|
| `SessionStart` | `source` (startup, resume, clear, compact, fork), `model`, `session_title`, cost/token fields | `model`, `session_title` and the cost fields are **dropped** |
| `UserPromptSubmit` | `user_prompt` | **dropped** |
| `PreToolUse` | `tool_name`, `tool_input`, `tool_use_id` | `tool_input` **dropped** |
| `PostToolUse` | `tool_name`, `tool_input`, `tool_output`, `tool_use_id` | input and output **dropped** |
| `PostToolUseFailure` | `tool_name`, … | everything but the tool name dropped |
| `PermissionRequest` | `tool_name`, `tool_input`, `rule_used`, `classifier_verdict` | all but the tool name **dropped** |
| `Notification` | `notification_type`, `message` | `message` **dropped** |
| `Stop` | `last_assistant_message` | **dropped** |
| `StopFailure` | `error_type`, `error_message` | `error_message` **dropped** |
| `SubagentStart` | `agent_type`, `agent_id` | kept (sanitized) |
| `SubagentStop` | `agent_type`, `agent_id`, `last_assistant_message` | message **dropped** |
| `SessionEnd` | `reason` (clear, resume, logout, prompt_input_exit, other) | kept (enum) |

Confirmed behaviour: exit 0 = success. Exit 2 **blocks** on blocking events (we never use it). Other non-zero codes show a "hook error" notice. Async hooks don't enforce a timeout. `SessionEnd` hooks share a 1.5 s budget.

## What the hook forwards: `WireEvent` v1

One JSON object per datagram, UTF-8, **≤ 1024 bytes** (the hook drops the event rather than send more). Keys:

| Key | Type | From | Rule |
|---|---|---|---|
| `v` | int | n/a | always `1` |
| `event` | string | `hook_event_name` | must be in the **registered events** list below, otherwise nothing is sent |
| `session` | string | `session_id` | keep `[A-Za-z0-9_-]` only, ≤ 64 chars; if empty, nothing is sent |
| `project` | string | `cwd` | **last path component only**; control and format characters removed; ≤ 64 Unicode scalars; `"unknown"` if missing |
| `tool` | string? | `tool_name` | `mcp__*` → `"mcp"`; else must match `^[A-Za-z][A-Za-z0-9_]{0,39}$`, otherwise `"other"`. Only on tool events. |
| `notification` | string? | `notification_type` | only values in the notification allowlist; others → `"other"` |
| `agent_id` | string? | `agent_id` | same rule as `session` |
| `agent_type` | string? | `agent_type` | `[A-Za-z0-9_:.-]`, ≤ 40 chars; otherwise dropped |
| `source` | string? | `source` | `SessionStart` only; allowlisted enum, else `"other"` |
| `reason` | string? | `reason` | `SessionEnd` only; allowlisted enum, else `"other"` |
| `error` | string? | `error_type` | `StopFailure` only; allowlisted enum, else `"unknown"` |
| `ts` | int | hook clock | Unix time in milliseconds |

**Never forwarded:** prompts, tool inputs and outputs, file paths (including the full `cwd`), file contents, messages, `transcript_path`, `scratchpad_dir`, `prompt_id`, `tool_use_id`, model names, permission mode, effort, session titles, cost or token figures, classifier verdicts. **Anything not listed above is dropped by default**, so fields Claude Code adds in future are dropped too.

### Registered events

`SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`.

### Enum allowlists

- `notification`: `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`
- `source`: `startup`, `resume`, `clear`, `compact`, `fork`
- `reason`: `clear`, `resume`, `logout`, `prompt_input_exit`, `other`
- `error`: `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `cloud_credential_error`, `unknown`

### Example

Claude Code's input (abridged):
```json
{"session_id":"abc123","cwd":"/Users/sam/code/api-server","hook_event_name":"PreToolUse",
 "tool_name":"Bash","tool_input":{"command":"psql -U admin -p hunter2"},"transcript_path":"/Users/sam/.claude/…"}
```
What leaves the hook:
```json
{"v":1,"event":"PreToolUse","session":"abc123","project":"api-server","tool":"Bash","ts":1790000000000}
```

## Transport

- **Socket:** an `AF_UNIX`, `SOCK_DGRAM` socket at `<Darwin per-user temp dir>/agentville.sock` (from `confstr(_CS_DARWIN_USER_TEMP_DIR)`, e.g. `/var/folders/…/T/agentville.sock`). That directory is private to the user and cleared on reboot. Tests and replay can override the path with `AGENTVILLE_SOCKET`. See [ADR 0005](../decisions/0005-socket-location.md).
- **Send:** non-blocking `sendto`. On any error (`ENOENT`, `ECONNREFUSED`, `ENOBUFS`, `EAGAIN`…) the hook gives up silently.
- **App side:** the app binds the socket at launch (removing a stale file first) and unlinks it on quit.

## App-side validation (`WireCodec.decode`)

The app treats every datagram as untrusted:
- drop datagrams over 2048 bytes, or that aren't a JSON object
- drop if `v` ≠ 1 or `event` isn't a registered event
- re-apply the same sanitization rules (never trust that the sender was our hook)
- unknown keys are ignored

## Done when

- [x] `HookPayloadFilter` implements every rule above; one test per rule (`HookPayloadFilterTests`)
- [x] Fuzz-style test: random JSON with secret markers in every non-allowlisted field → no marker in the output (`fuzz()`)
- [x] `WireCodec` round-trips, rejects oversize, wrong-version and unknown-event datagrams (`WireCodecTests`)
- [x] Registered events in `Plugin/agentville/hooks/hooks.json` == `WireEvent.Kind.allCases` (`PluginManifestTests`)
