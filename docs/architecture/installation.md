# Installation, Connect and Disconnect

Purpose: how Agentville gets onto a Mac and into Claude Code, and how it leaves cleanly.

## Distribution

- **Primary:** a Homebrew cask in our own tap: `brew install --cask <owner>/tap/agentville` (the tap is a separate repo, `homebrew-tap`).
- **Secondary:** a `.dmg` on GitHub Releases.
- **Signing:** a smooth first launch needs a Developer ID–signed, notarized build. Without one, the README explains the System Settings approval. See open question 3.
- The `.app` is assembled from SwiftPM products by `scripts/bundle-app.sh` → `dist/Agentville.app`: `Contents/MacOS/Agentville`, `Contents/Helpers/agentville-hook`, an `Info.plist` with `LSUIElement` (no Dock icon), `LSMinimumSystemVersion` 14.0, the plugin's version, and the bundle id from open question 16. Hardened runtime, **not** sandboxed: running `claude` and writing `~/.claude` are incompatible with the App Sandbox. No entitlements beyond the hardened-runtime defaults; `scripts/check-footprint.sh` builds the bundle and fails on any entitlement, a missing helper, a missing `LSUIElement` or more than 15 MB. Signed ad hoc until open question 3 is answered (M8). 2026-10-03: 1.6 MB; the bundled app launched, the bundled helper delivered an event, and quitting removed the socket

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
- **How (built in M7):** `ClaudeSettingsHooks` (Core, `Install/`) works on the text, never re-serialising it. A strict span parser (`JSONSpans`) finds where things are; Connect appends our entry after the last member or element of the object or list it joins, copying that file's separator, indentation and line endings (one-line files get one-line additions); Disconnect deletes exactly what was appended, and a container that empties (an event list, `hooks`) goes with it, so the file comes back byte for byte. The marker is a shell comment at the end of the command (`…; exit 0 # agentville-hook`). Refused: anything that isn't strict JSON (comments, trailing commas, duplicate keys), a top level that isn't an object, and `hooks` not shaped as Claude Code expects. Known limits: an empty `"hooks": {}` or event list that was there before Connect is dropped by Disconnect (same meaning), and `{\n}` comes back as `{}`. `ClaudeSettingsHooksTests` (empty, missing, existing hooks, tabs, 4 spaces, CRLF, one line, BOM, escapes, partial, mixed groups, refusals); checked against the owner's real 20 KB settings file in memory, 2026-10-03: exact round trip

### After either path

- "Connected. Restart any open Claude Code sessions to see them."
- A live line: "Waiting for the first event…" → "Last event 3 s ago".
- If nothing arrives after a while: check for `"disableAllHooks": true` and explain.
- **Built (M7):** `Connection` (Core) reads `installed_plugins.json` (is `agentville@agentville` there?) and `settings.json` (is it turned off in `enabledPlugins`? are our marked hooks there?) and says none / plugin / plugin turned off / settings file / both. `Connection.liveLine` and `Connection.explanation` (disableAllHooks at once; the restart reminder 90 s after a Connect with no events). `ConnectionTests`. A plugin that's installed but turned off is turned back on with `claude plugin enable agentville@agentville`.
- **Trying it safely:** `AGENTVILLE_HOME=/tmp/x` makes the app use a pretend home for all of this (its `.claude`, its helper link, and `HOME` for the `claude` CLI). 2026-10-04: Path B Connect and Disconnect run in the app against a pretend home with existing hooks: backup written, hooks added, link created; Disconnect restored the file byte for byte and removed the link and its folders

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
