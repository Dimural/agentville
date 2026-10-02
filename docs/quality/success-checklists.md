# Success checklists

Purpose: concrete, tickable definitions of success for the whole platform and each part. A milestone is done when its parts' checklists are ticked. Keep these honest: tick only with evidence (a test name, a measurement, or a dated manual check).

## The platform as a whole

- [ ] All 12 [non-negotiables](non-negotiables.md) are verified
- [ ] Every [end-goal success measure](../vision/end-goals.md#success-measures) is met on the owner's Mac
- [ ] Install → first real character in < 60 s on a fresh account
- [ ] Real sessions verified from the CLI, VS Code and the desktop app
- [ ] Side-by-side review against the prototype passes
- [ ] Disconnect + delete leaves nothing behind
- [ ] `scripts/ci.sh` is green on `main`
- [ ] **Fun check:** the owner keeps it running for a week of real work and would show it to a friend

## Hook helper (`agentville-hook`)

- [ ] Exits 0 for every input in the test corpus (valid, invalid, huge, empty, binary)
- [ ] stdout is empty in every case; stderr is empty in normal operation
- [ ] Only allowlisted keys arrive at the socket; no secret marker ever arrives (fuzz test)
- [ ] p99 < 50 ms with the app listening; < 10 ms with no socket
- [ ] Release binary < 2 MB; links no networking framework
- [ ] The shell-form command in `hooks.json` exits 0 silently with the helper deleted

## Data contract / wire

- [ ] `WireEvent` v1 documented == implemented (one test per field rule)
- [ ] The decoder rejects oversize, non-object, wrong-version and unknown-event datagrams
- [ ] Registered events: `hooks.json` == `WireEvent.Kind.allCases` (test)

## Plugin and marketplace

- [ ] `claude plugin validate ./Plugin/agentville` passes with no warnings
- [ ] `claude plugin validate .` (marketplace) passes
- [ ] Every hook entry is `async: true`, shell form, and ends with `exit 0`
- [ ] Install, disable and uninstall via the CLI each work in one command

## Session store

- [ ] Every transition in [sessions-and-states.md](../product/sessions-and-states.md) has a test
- [ ] Turn duration is correct (prompt → stop)
- [ ] Subagents: add/remove per `agent_id`, several at once, stop-without-start is ignored
- [ ] Staleness rules: a long `PreToolUse` survives; a silent idle session is pruned
- [ ] 100 sessions × 500 events/s: bounded memory, < 50 ms per 1,000-event batch
- [ ] Unknown sessions are created on first event; gone sessions don't resurrect (except on `SessionStart`)

## Looks and sprites

- [x] Looks match the prototype's golden vectors exactly: `LookGeneratorTests`
- [x] Every pose/frame renders pixel-identical to prototype exports: `SpriteRendererTests` (19 looks: every style × accessory, all 4 patterns; 741 frames + 8 emotes from `sprite-vectors.json`)
- [ ] Nearest-neighbour everywhere; integer scales only

## Menu bar and desk window

- [ ] Icon shows the count and a red dot when anything needs you
- [ ] The office matches the prototype (day and night), all 9 monitor screens
- [ ] The list shows avatar, name, tool, chip and elapsed time; redraws ≤ 4 Hz
- [ ] The summary line and the "+N more below" badge are correct
- [ ] Window hidden → office rendering stops (CPU ≈ 0)

## Overlay: release, recall, roaming

- [ ] Release choreography matches the prototype (burp, 85 ms stagger, arcs, landings, shouts)
- [ ] Recall completes ≤ 2.6 s from every state in non-negotiable #2
- [ ] Every activity pose plays on the desktop, driven by replayed events
- [ ] Meetings, sidekicks, crowd ("+N", "My turn!") and particles all work, and are capped
- [ ] Crew inside + no walk-ons → scenes paused, poller stopped

## Input and grabbing

- [ ] Click-through verified over real apps (buttons, text, scroll, drag-and-drop, resize)
- [ ] ⌥ grab, drag, throw, tap, dizzy all match the prototype
- [ ] No permission prompt on a fresh account
- [ ] ⌃⌥C works from any app

## Walk-on notices

- [ ] Done and Needs-you walk-ons match the prototype; ≤ 3 at once; "+N more" folding
- [ ] The done-announcement setting is respected
- [ ] Needs-you leaves when the session stops waiting

## Install / Connect / Disconnect

- [ ] Path A and Path B both work; Path B is tested on empty, existing-hooks, odd-format and unparseable files
- [ ] Disconnect restores `~/.claude` exactly (Path B diff test)
- [ ] "Waiting for first event" → "Last event N s ago"; the `disableAllHooks` explanation

## Repo health (agentic development)

- [ ] `AGENTS.md` commands all work as written on a clean clone
- [ ] Docs index links resolve (`scripts/check-docs.sh`)
- [ ] Every ADR has a status; every open question has a proposed default
- [ ] `scripts/ci.sh` runs locally exactly as in CI
