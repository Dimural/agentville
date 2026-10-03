# Privacy

Purpose: what Agentville knows, what it never knows, and how anyone can verify that.

## What Agentville knows

Per event, from a local Claude Code session: the **event name**, the **session id**, the **project folder name** (only the last path component), the **tool name** (with MCP tools reduced to `mcp`), and small enums (notification type, start source, end reason, error type, subagent id and type). Plus a timestamp. That's all. See [data-contract.md](../architecture/data-contract.md).

## What Agentville never knows

Prompts, Claude's replies, tool inputs and outputs, commands, file paths, file contents, transcript paths, model names, cost or token figures, session titles, permission rules or classifier verdicts. These are dropped **inside the hook process**, before anything is sent anywhere.

## Where data goes

- From the hook to the app over a **local Unix-domain socket** in the user's private temp directory. It never touches a network interface.
- The app keeps session state **in memory only**. On quit, it's gone.
- **On disk:** only preferences (`UserDefaults`, written only by `Sources/Agentville/Preferences.swift`; today one key, `announceDone`). When the user presses Connect: a symlink to the helper, and on the settings-file path our marked hooks in `~/.claude/settings.json` plus a backup of it that they can see and delete. All of these are written only by `Sources/Agentville/Installer.swift`, and only when the user asks (except re-pointing a dangling helper link at launch). Diagnostics stay in memory; **Copy Diagnostics** puts them on the clipboard only when the user picks it.
- **Network:** none. There is no networking code to send anything anywhere.

## Things that are visible on screen

Folder names appear in bubbles and the list, and so can show up in screenshots or screen shares. A **"Hide project names"** setting (open question 10, proposed default: off) replaces them with the character's generated nickname.

## How to verify

```sh
scripts/check-no-network.sh        # greps every source file for networking APIs
scripts/check-no-disk-writes.sh    # file-writing APIs only in allowlisted files
scripts/test.sh --filter Privacy   # secret-marker tests on the hook filter
```

Or read `Sources/AgentvilleWire/HookPayloadFilter.swift` and `Sanitize.swift`. The whole boundary is in those two files.
