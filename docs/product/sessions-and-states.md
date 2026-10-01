# Sessions and states

Purpose: which sessions Agentville sees, how a session's state is derived from hook events, and how tools map to activities. This is the spec for `SessionStore` and `ActivityMapping`.

## Which sessions it sees

Every Claude Code session running **locally on this Mac**. The CLI, the desktop app's local sessions and the VS Code extension all read the same `~/.claude` settings, so a plugin installed at user scope applies to all of them.

| Where the session runs | Seen? |
|---|---|
| Claude Code CLI in any terminal (Terminal, iTerm2, Warp, Ghostty, VS Code's terminal…) | Yes |
| VS Code extension | Yes |
| Claude desktop app, local sessions | Yes |
| JetBrains IDEs | Expected (they run the CLI). **Verify.** |
| claude.ai/code and other cloud sessions | No. They don't load local plugins. |
| SSH, Docker or dev containers | No. The hook runs on another machine and can't reach the local socket. |

Consequences:
- Sessions started before the hook was installed are invisible until restarted.
- If the settings contain `"disableAllHooks": true`, nothing arrives. The app detects "connected but no events yet" and explains it.

## Identity and looks

- **Key:** the `session` field (Claude Code's `session_id`).
- **Display name:** the project **folder name** (the last path component of `cwd`).
- **Look:** derived deterministically from the folder name ([sprites-and-poses.md](../design/sprites-and-poses.md#looks)). The same folder always gets the same character.
- **Twins:** later sessions in the same folder get a small number badge so twins can be told apart.

## States

| State | Entered on | Office | Roaming | Crew inside |
|---|---|---|---|---|
| **idle** | `SessionStart`; `Notification(idle_prompt)`; `finishedHold` seconds after `Stop` | Naps at desk, screensaver on monitor | Sips coffee or sleeps (per look); slow stroll | Nothing |
| **working(activity)** | `UserPromptSubmit` → `thinking`; `PreToolUse` → activity from the tool; `PostToolUse` / `PostToolUseFailure` → `thinking` | Desk pose + matching monitor screen | Activity pose | Nothing |
| **needsYou** | `PermissionRequest`; `Notification(permission_prompt)`; `Notification(elicitation_dialog / elicitation_url_dialog / agent_needs_input)` | Stands, waves, `!` emote, flashing red screen | Runs to the bottom of the screen, waves, `!` + "Needs you" | Walk-on, "Needs you" |
| **finished** | `Stop` | Cheers, check emote, green screen | Confetti, "Done! · duration" | Walk-on, "Done!" (subject to the announce rule) |
| **error** | `StopFailure` | New pose (TBD; see open question 12) | New pose (e.g. a small storm cloud) | Optional walk-on |
| **gone** | `SessionEnd`, or the staleness rule | Removed | Waves "Bye!", then a sparkle and dust poof | Nothing |

Leaving **needsYou**: the next `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `UserPromptSubmit` or `Stop` for that session means the user answered.

**Subagents** layer on top of any working state. `SubagentStart(agent_id)` adds a mini-me and `SubagentStop(agent_id)` removes it. Several at once: show one mini-me with a count badge (proposed default; open question 12).

**Turn duration** ("Done!" bubble) runs from the `UserPromptSubmit` that started the turn to the `Stop`.

**Unknown or out-of-order events** never crash the store and never resurrect a gone session (except `SessionStart`). An event for an unknown session creates it, because hooks may have been installed mid-session.

## Staleness (sessions that vanish without `SessionEnd`)

A killed terminal sends no `SessionEnd`. The silence limit depends on the last event, so a long `Bash` command (a `PreToolUse` followed by minutes of silence) isn't killed. Proposed defaults (open question 9):

| Last event was | Session is removed after this much silence |
|---|---|
| `PreToolUse` (a tool is running) | 30 min |
| `PermissionRequest` / needs-you notification | 60 min |
| anything else, while working | 15 min |
| idle | 45 min |

The store exposes `prune(now:)`. The app calls it about once every 10 s.

## Tool → activity mapping

This lives in **one place**: `Sources/AgentvilleCore/Sessions/ActivityMapping.swift`. Unknown tools get a generic fallback.

| Tool names (as forwarded) | Activity | Chip label | Pose |
|---|---|---|---|
| `Read`, `NotebookRead` | `reading` | Reading | `read` |
| `Edit`, `Write`, `MultiEdit`, `NotebookEdit` | `editing` | Editing | `type` (desk: `deskType`) |
| `Bash`, `BashOutput`, `KillShell`, `KillBash`, `PowerShell` | `running` | Running | `bash` |
| `Grep`, `Glob`, `LS` | `searching` | Searching | `search` |
| `WebSearch`, `WebFetch` | `web` | On the web | `web` |
| `Task`, `Agent` | *(no change)*: covered by the subagent mini-me | n/a | n/a |
| `TodoWrite`, `TaskCreate`, `TaskUpdate`, `TaskList`, `ExitPlanMode`, `EnterPlanMode` | `planning` | Planning | new: clipboard (falls back to `think`) |
| `mcp` (any MCP tool, already reduced by the hook) | `tinkering` | Tinkering | new: gadget (falls back to `deskType`) |
| anything else | `working` | Working | `deskType` |
| *(no tool; after a prompt or a tool finishing)* | `thinking` | Thinking | `think` + "…" |

Tool names come from Claude Code and change over time. **Verify** them against the current tool list each milestone.

## "Done" announcement rule

`Stop` fires at the end of **every turn**. The walk-on is governed by a setting (open question 1). Proposed default: **announce when the turn lasted ≥ 20 s**. Inside the office, every `Stop` shows the cheer.

## Done when

- [ ] `SessionStore` implements every transition above, each with a unit test
- [ ] The mapping table above and `ActivityMapping.swift` match exactly (a test enumerates the table)
- [ ] Staleness never removes a session that is mid-`PreToolUse` within its limit (test)
- [ ] 100 sessions × 500 events/s are processed without growing memory without bound (test)
