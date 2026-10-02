# Open questions for the owner

Purpose: decisions that are the owner's to make. Each has a **proposed default** that the code uses until the owner answers. When one is answered, record the answer here and, if it's structural, write an ADR.

| # | Question | Needed by | Proposed default | Answer |
|---|---|---|---|---|
| 1 | **When to announce "done"?** Every turn, only turns ≥ N s, only when no terminal/IDE is frontmost, or a combination | M6 | Turns ≥ **20 s**; setting offers "every turn / long turns / never" | |
| 2 | **Click a walk-on to jump to its terminal?** Needs Accessibility/Automation, which conflicts with non-negotiable #9 | M6 | **Leave out** of 1.0 | |
| 3 | **Signing and distribution.** A paid Apple Developer account for notarized builds, or unsigned with instructions? Tap name and owner account? | M8 | Unsigned first, with README instructions; tap `Dimural/homebrew-tap` | |
| 4 | **Name and licence.** Confirm "Agentville" is free on GitHub, Homebrew and the App Store; confirm MIT | M0 | Agentville + MIT ([0001](0001-name-agentville.md), [0002](0002-mit-license.md)) | Name chosen by owner |
| 5 | **Minimum macOS version** | M0 | **macOS 14** ([0003](0003-macos-14-minimum.md)) | |
| 6 | **Spaces, full-screen and multiple displays.** Follow across Spaces? Appear over full-screen apps? Which displays? Walk between displays? | M3/M8 | Join all Spaces: yes. Over full-screen: off. Displays: all. Walk between displays: no (stretch goal) | |
| 7 | **Sound** | later | None in 1.0; optional off-by-default blips as a stretch goal | |
| 8 | **Where the hook helper lives** | M1/M7 | App bundle + stable symlink ([0007](0007-hook-location.md)) | |
| 9 | **Staleness detection.** Silence timeouts only, or also forward a process id for liveness? Which timeouts? | M6 | Timeouts only (see [sessions-and-states.md](../product/sessions-and-states.md#staleness-sessions-that-vanish-without-sessionend)); revisit PID liveness later | |
| 10 | **Hide project names** setting for screenshots and screen shares | M7 | Provide the setting, **off** by default | |
| 11 | **Replacement for the prototype's "Answer" button** | M2 | Remove it; the row shows a blinking red "Needs you" chip and a tooltip: "Answer it in your terminal" | **Accepted 2026-10-02**: as proposed (`DeskList.Row.tooltip`, chip square blinks like the prototype's `.chip.waiting`) |
| 12 | **New poses**: Error, clipboard (planning), MCP gadget; how several subagents look | M4 | Fallback poses until drawn (error and planning think, MCP tinkers); several subagents = one mini-me + count badge (built in M4 on the desktop: `Sidekick.count`) | |
| 13 | **Settings scope** | M7 | Launch at login (off), shortcut, done rule, displays, Spaces/full-screen, hide names, Disconnect, Diagnostics | |
| 14 | **Twins** (several sessions in one folder): number badge or a changed accessory? | M2 | Small number badge | **Accepted 2026-10-02**: a small number badge (2, 3…) after the name in the list and on the desk's nameplate in the office |
