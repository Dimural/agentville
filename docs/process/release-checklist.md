# Release checklist

Purpose: everything verified by hand before a release. Copy this into the release PR and tick each item with a date.

## Automated (must be green)

- [ ] `scripts/ci.sh` on the release commit
- [ ] `claude plugin validate ./Plugin/agentville` and `claude plugin validate .`
- [ ] `scripts/check-footprint.sh` against the **bundled** `.app`

## Real-world

- [ ] Connect via Path A on a fresh macOS user account; first character in < 60 s
- [ ] Connect via Path B (no CLI on PATH); preview + backup shown
- [ ] Real sessions seen from: CLI in Terminal, iTerm2/Ghostty, the VS Code extension, the desktop app (local)
- [ ] A permission prompt triggers "Needs you" in < 1 s; answering it clears it
- [ ] A long turn triggers "Done!" per the announce setting
- [ ] Claude Code behaves identically with the app running, quit and deleted (no "hook error" notices anywhere)

## Overlay and input

- [ ] With the crew out: buttons, text fields, scrolling, drag-and-drop and window resizing underneath all work
- [ ] ⌥-grab, drag, throw, tap on every display; releasing ⌥ restores click-through immediately
- [ ] ⌃⌥C from another app, both directions
- [ ] Recall from: mid-drag, mid-throw, window hidden, 100 sessions (replay), during walk-ons (≤ 2.6 s each)
- [ ] Status item reachable with the crew out on every display
- [ ] Spaces and full-screen behaviour match the chosen setting

## Permissions and privacy

- [ ] No permission prompt at any point on a fresh account
- [ ] `codesign -d --entitlements :- Agentville.app` shows no network entitlements
- [ ] After quit: no Agentville process, no socket file (`ls $(getconf DARWIN_USER_TEMP_DIR)agentville.sock`)
- [ ] After Disconnect + delete: `~/.claude` matches the pre-install state; only the prefs plist remains

## Visual

- [ ] Side-by-side with the prototype: every pose, all 9 monitor screens, bubbles, release/recall choreography, crowd, walk-ons
- [ ] Day and night office; reduced motion respected
- [ ] Crisp on 1× and 2× displays

## Performance

- [ ] Idle CPU < 0.5% (60 s), released with 100 sessions < 15%, memory within budget
