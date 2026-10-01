# Installation, Connect and Disconnect

Purpose: how Agentville gets onto a Mac and into Claude Code, and how it leaves cleanly.

## Distribution

- **Primary:** a Homebrew cask in our own tap: `brew install --cask <owner>/tap/agentville` (the tap is a separate repo, `homebrew-tap`).
- **Secondary:** a `.dmg` on GitHub Releases.
- **Signing:** a smooth first launch needs a Developer ID–signed, notarized build. Without one, the README explains the System Settings approval. See open question 3.
- The `.app` is assembled from SwiftPM products by `scripts/bundle-app.sh` (M7). Hardened runtime, **not** sandboxed: running `claude` and writing `~/.claude` are incompatible with the App Sandbox. No entitlements beyond the hardened-runtime defaults.

## Connect (welcome window → **Connect to Claude Code**)

Before either path, the app ensures the stable helper link exists:
`~/Library/Application Support/Agentville/bin/agentville-hook` → `Agentville.app/Contents/Helpers/agentville-hook`.

### Path A: plugin (preferred)

- **Requirement:** the `claude` CLI is found on the login shell's `PATH` (`/bin/zsh -lc 'command -v claude'`) or in common install locations (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `~/.claude/local`).
- **Commands** (verified against the plugin docs, 2026-10-01):
  ```sh
  claude plugin marketplace add <owner>/agentville
  claude plugin install agentville@agentville --scope user
  ```
- Show both commands and their full output in a disclosure area.

### Path B: settings file (fallback, no CLI)

For people who only use the desktop app or VS Code:

- Add a hooks entry to `~/.claude/settings.json` calling the same shell command for the same events.
- **Before:** show a preview of exactly what will be added, and write a timestamped backup next to the file (`settings.json.agentville-backup-YYYYMMDD-HHMMSS`).
- **Merge:** preserve every existing key and hook. Never reorder or reformat beyond what's necessary.
- **Mark:** each added hook command contains the marker comment `# agentville-hook` so Disconnect removes only ours.
- **Failure:** if the file can't be parsed, stop and explain. **Never overwrite it.**

### After either path

- "Connected. Restart any open Claude Code sessions to see them."
- A live line: "Waiting for the first event…" → "Last event 3 s ago".
- If nothing arrives after a while: check for `"disableAllHooks": true` and explain.

## Disconnect (Settings)

- Path A: `claude plugin uninstall agentville@agentville` (optionally `claude plugin marketplace remove agentville`).
- Path B: remove only the entries carrying our marker; offer to restore the backup.
- Remove the helper symlink and its folder if empty.

## Uninstall promise

After Disconnect and dragging the app to the Bin, nothing is left except the preferences plist (`~/Library/Preferences/<bundle-id>.plist`). Even if the user skips Disconnect, hooks stay silent: the symlink dangles, and the shell command exits 0.

## Sandbox and permissions

The app **never** requires Accessibility, Input Monitoring, Screen Recording, Automation or Full Disk Access. Everything works without them:
- modifier keys: `NSEvent.modifierFlags` (a class property, polled)
- cursor position: `NSEvent.mouseLocation` (polled)
- global hotkey: Carbon `RegisterEventHotKey`
- click-through: `NSWindow.ignoresMouseEvents`

## Done when

- [ ] A fresh macOS user account goes from install to a real session's character in < 60 s
- [ ] Path B tested against settings files that are empty, have other hooks, have unusual formatting, and don't parse
- [ ] Disconnect leaves `~/.claude` exactly as before Connect (diff test for Path B)
- [ ] `claude plugin validate` passes for both the plugin and the marketplace
