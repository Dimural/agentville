# 0007: Helper symlink in Application Support + silent shell-form hook
Status: Proposed
Date: 2026-10-01

## Context
The plugin's hook command must find `agentville-hook`, and must succeed silently (exit 0) if the app or helper is missing, so a user who deletes the app never sees hook errors. Options: (1) the helper ships in the app bundle behind a stable per-user link; (2) the plugin ships its own copy. Option 2 means committing a binary to git (the marketplace is this repo), which is bad for an open-source repo and for review.

## Decision
Option 1. The app maintains `~/Library/Application Support/Agentville/bin/agentville-hook` as a symlink to `Agentville.app/Contents/Helpers/agentville-hook`. The plugin uses the **shell form**:

    h="$HOME/Library/Application Support/Agentville/bin/agentville-hook"; if [ -x "$h" ]; then "$h"; else cat >/dev/null; fi; exit 0

## Consequences
- App deleted → dangling link → `-x` is false → stdin drained → exit 0. Silent.
- The only file outside the app bundle (besides prefs) is this symlink, created when the user presses Connect and removed on Disconnect.
- For development, `scripts/dev-link-hook.sh` points the link at `.build/debug/agentville-hook`.
- Exec form (`args`) was rejected: a missing executable would surface as a hook error.
