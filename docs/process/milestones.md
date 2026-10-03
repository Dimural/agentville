# Milestones

Purpose: the build order. Each milestone ends with something the owner can see and check. Tick items only with evidence.

**Current milestone: M6** (walk-on notices, crowd and caps, staleness): built and checked in the app 2026-10-03; blocked by [bug 0001](../bugs/0001-grey-screen-overlay.md) (grey screen); also waiting for the owner's review and one open budget item. M5 is done: the owner checked grabbing, ⌃⌥C and click-through and approved it on 2026-10-03. M4 is done apart from the owner's look at the three new poses. M3 is done: approved 2026-10-02. M2 is done: approved 2026-10-02. M1 is done: verified 2026-10-01. M0 is done apart from the owner's answers.

| # | Milestone | Done when |
|---|---|---|
| M0 | Repo skeleton, docs, privacy promises, guards, CI | The owner agrees on the open questions marked M0 |
| M1 | `agentville-hook`, wire codec, socket listener, session store, replay tool | Replay scenarios produce correct session states in a debug list; all hook tests pass |
| M2 | Menu bar item + desk panel (office + list); sprite renderer port | The office matches the prototype with replayed sessions, all states and monitor screens |
| M3 | Overlay, release and recall | Pour-out and suck-back match the prototype; click-through verified over real apps; recall rules pass |
| M4 | Roaming, meetings, particles, subagent sidekicks | All activity poses play on the desktop driven by replayed events |
| M5 | ⌥ grab, drag, throw; hover fade; global shortcut | Grab rules pass; no permissions requested |
| M6 | Walk-on notices, crowd and caps, staleness | 100-session and burst scenarios stay smooth; the done-announcement setting works |
| M7 | Plugin packaging, app bundle, welcome window, Connect/Disconnect (both paths), settings | A fresh Mac goes from install to a real session's character in under a minute |
| M8 | Signing/notarization (if chosen), cask, release checklist, multi-monitor | A public release candidate |

## M0: scaffolding

- [x] Docs: vision, end goals, UX, states, architecture, data contract, design, quality, process, decisions
- [x] `AGENTS.md` / `CLAUDE.md` entry point; docs index
- [x] Reference files gitignored; fixtures generated from the prototype
- [x] SwiftPM package: Core, hook, replay, app targets; tests
- [x] Guard scripts: no-network, no-disk-writes, footprint, docs links; `scripts/ci.sh`
- [x] GitHub Actions workflow calling `scripts/ci.sh`
- [x] Plugin + marketplace manifests (validated with `claude plugin validate`)
- [ ] Owner answers the M0 open questions (name/licence confirmed; min macOS)

## M1: data path

- [x] `HookPayloadFilter` + `WireEvent` + `WireCodec` with privacy tests
- [x] `ActivityMapping` with a table test
- [x] Look generator with golden vectors
- [x] `agentville-hook` executable + integration tests (exit 0, empty stdout, socket contents, timing)
- [x] `SessionStore` with every transition, staleness and stress tests
- [x] `SocketListener` in the app (bind, batch, unlink on quit): `SocketListenerTests` (real socket: order, drops, re-sanitize, burst batching, socket → store equals direct apply, unlink only our own file). Manual 2026-10-01: replay `demo-mix` and a 1,080-event burst all accepted; quit by SIGTERM/SIGINT leaves no socket file; 0.00 s CPU over 30 s idle
- [x] `agentville-replay` + all scenarios in [testing-strategy.md](../quality/testing-strategy.md#replay-scenarios-m1) (scenarios are executable specs)
- [x] Debug list window in the app showing live store state (menu → *Session List (Debug)…*, ⌘D). Replaced in M2 by the desk panel
- [x] Owner checks a replayed scenario in the debug window: 2026-10-01, `demo-mix` final state matched every `expect` line (5 sessions, 18 events received, 0 dropped)
- [x] Owner checks a real Claude Code session in the debug window: 2026-10-01, plugin installed from the local marketplace + `scripts/dev-link-hook.sh`; owner confirmed the states looked right

## M2: menu bar + desk panel

- [x] Sprite renderer port (`drawChar`, `sprite`, `outline`, `avatar`, `drawEmote`) with golden frames exported from the prototype: `SpriteRendererTests`
- [x] Bounded sprite cache (`SpriteCache`, LRU 2,000)
- [x] `PixelCanvas` → `CGImage` in the app, nearest-neighbour, integer scales: `PixelImage` (Core, CoreGraphics only), `PixelImageTests`
- [x] Office renderer port (`drawOffice`, `screenFor`, `deskUnits`): day/night, 6 desks, every monitor screen, "+N more below" count; golden office frames: `OfficeRendererTests`. About 2 ms per frame in a debug build
- [x] Desk window: office (≈12 fps, stops when hidden; "+N more below" badge) + session list (avatar, name, tool, chip, elapsed; ≤ 4 Hz); replaces the debug list. `DeskPanelController` + `DeskList` (`DeskListTests`); 2026-10-02: snapshots of the window during `demo-mix` and an 8-session twins replay checked against the prototype's layout
- [x] Status item: pixel head, count, red dot when anything needs you: `StatusItemController`, `MenuBarIcon` (`MenuBarIconTests`). Not yet seen on a real menu bar: part of the owner's review
- [x] Owner's first review (2026-10-02): contents approved; asked for a dropdown instead of a window → [0009](../decisions/0009-desk-panel-dropdown.md): `DeskPanelController`, `PanelPlacement` (`PanelPlacementTests`)
- [x] Owner's side-by-side review of the dropdown panel against the prototype with replayed sessions: approved 2026-10-02

## M3: overlay, release and recall

Scope: the crew pours out of the desk panel onto the desktop and gets sucked back, exactly as in the prototype. On the desktop each character acts out its session and wanders between acts (roaming, pulled forward from M4); meetings, sidekicks and the rest of the particles are M4. Grabbing, hover fade, the HUD and ⌃⌥C are M5. "Invite until first use" is per launch until settings are stored (M7). One display (the one with the menu bar) until M8.

- [x] `CrewSim` (Core): a pure, seeded simulation of the crew on the desktop. Ports of `release`, `recall`, `sendHome`, `spawnFromHome`, `Ent.launch`/`land`, the `fly`/`wait`/`drop`/`leave` modes of `updateEnt`, and the sparkle/dust/trail particles (cap 520). `CrewSimTests`: stagger timings, flight arc and stretch, landing squash and dust, ≤ 12 out, release/recall shouts, new and ended sessions while out, idle when everyone is home
- [x] Recall rules (non-negotiable #2): everything home or removed ≤ 2.6 s from every state (mid-release, mid-flight, 100 sessions, panel closed, sessions ending): `CrewSimTests`
- [x] Overlay window: borderless, transparent, shadowless, **always click-through** in M3, below the menu bar, on all Spaces, not over full-screen apps; SpriteKit scene paused and window ordered out whenever the crew is home
- [x] Overlay rendering: nearest-neighbour sprite textures, shadows, particles, emotes and speech bubbles; draw order shadows → particles → sprites (by y) → emotes → bubbles
- [x] Desk panel footer: the chunky **Release the crew** button (orange, invite bounce until first use) that turns blue and reads **Call the crew back**; the same item in the status menu; burp on release, gulp when the last one is home; empty desks while the crew is out
- [x] Homes: desks while the panel is open, otherwise the menu bar icon. 2026-10-02: in-app snapshots during `demo-mix` checked: the crew leaves the desks, lands spread over the screen in its poses with emotes and shadows, and is home with the desktop empty 2 s after recall
- [x] Pulled forward from M4 at the owner's request (2026-10-02): **roaming**. Port of `roam`, `walkTo`, `nearbyTarget`: act 3–7 s (idle 6–12 s), then walk to a nearby spot at 48 pt/s (search creep 26, idle stroll 32); "needs you" runs to the bottom of the screen at 120 pt/s and waves; a finished turn cheers for 2.6 s first. `CrewSimTests` (speeds, bounds over 2 minutes with 12 out, poses). Meetings, sidekicks and activity particles stay in M4
- [x] Quit with the crew out leaves nothing (non-negotiable #3): `scripts/check-quit-cleanup.sh` launches the app with `--release-crew`, replays `demo-mix` so sessions drop in, quits by SIGTERM and SIGINT. 2026-10-02: exits within 5 s, no child processes, socket file removed, both signals
- [x] Manual: click-through over real apps (buttons, text, scroll, drag-and-drop, resize): owner checked 2026-10-02
- [x] Owner's side-by-side review of release and recall against the prototype: approved 2026-10-02

## M4: roaming, meetings, particles, sidekicks

Scope: everything a released character does on the desktop, driven by real or replayed events. Roaming came early (M3). The crowd ("+N", "My turn!") and walk-ons are M6; dizziness follows throwing in M5.

- [x] Done: a 2.6 s cheer, a green **Done!** bubble with "name · turn time" for 5 s, 26 confetti (a quarter with reduced motion) and sprinkles while cheering (port of `onDone`). Needs you: a red **Needs you** bubble with the name while waiting, cleared when answered. Twins are named "api 2". `CrewActivityTests`
- [x] Activity particles (ports of `confetti`, `zzz`, `bits`, `stepParts`): typing bits about 3/s, Bash sparks on each hammer strike, the telescope's twinkles, sleepers' z's; confetti falls at 0.55 G, flutters and settles. All under the 520 cap. `CrewActivityTests`
- [x] Meetings (port of `checkMeetings`): every 0.35 s, two working walkers within 44 pt stop 1.6 s, face each other, cheer 0.8 s, heart (⅔) or ? (⅓), 50% say a line, pink sparkles; cooldown 18–30 s (6–16 s at first). `CrewActivityTests`
- [x] Subagent sidekicks: a one-size-smaller mini-me pops in with yellow sparkles, follows at 140 pt/s to `x − face·11·S, y + 3`, walks while catching up and types when still, poofs on the last `SubagentStop` or a recall; several subagents show a yellow count badge (open question 12's default). `CrewActivityTests`
- [x] Overlay drawing: confetti flakes, z's, bits, sidekicks with shadows and the badge, bubble kinds with a subtitle line. 2026-10-02: in-app snapshots during `desktop-tour` show the Done! bubble with confetti, the "3" badge, and the Needs you bubble
- [x] `Tools/scenarios/desktop-tour.jsonl`: every activity, a sidekick of 3, a Done!, a Needs you and an idle sleeper
- [x] Owner's side-by-side review of the desktop tour against the prototype: approved 2026-10-02
- [x] Error, planning and MCP poses (open question 12, answered 2026-10-03): original `plan`, `tinker` and `error` poses plus a `storm` emote, at the desk (own monitor screens) and on the desktop (tinkering fizzes). `AgentvillePosesTests`; preview sheet and office render checked 2026-10-03
- [ ] Owner's look at the three new poses (`--release-crew` with a planning, an MCP and a failed session)

## M5: grab, drag, throw; hover fade; global shortcut

Scope: the crew stays glass unless ⌥ is held over a character ([input-and-safety.md](../architecture/input-and-safety.md)). No permissions: modifier keys and the cursor are polled, never tapped; the shortcut uses Carbon's `RegisterEventHotKey`.

- [x] Core grab model (ports of `hitBox`, `hitTest`, the `pointerdown`/`pointermove` handlers, `endDrag`, the `thrown` mode, `settle`, dizziness): hit box, front-most wins, drag follows the cursor with its offset, tap = hop + "hey!"/"boop"/"hi there"/"*giggle*" + pink sparkles, throw from the first and last of 6 samples (cap 1500 pt/s, `vy × 0.6`, `vz = clamp(speed × 0.35, 80, 460)`), wall and ground bounces, slide friction, settle below 18 pt/s, > 900 pt/s → 1.8 s dizzy, > 700 → "waaah!"/"whoa!"/"aaa!". `CrewGrabTests`
- [x] The click-through decision (non-negotiable #1): capture the mouse only while ⌥ is held over a character, or while a drag is in progress. `CrewGrabTests`
- [x] Hover fade: a character under the cursor eases to 16% opacity (not in grab mode), at `min(1, dt·14)`. `CrewGrabTests`
- [x] Recall from mid-drag and mid-throw within 2.6 s (non-negotiable #2). `CrewGrabTests`
- [x] App: `InputPoller` (30–60 Hz, only while the crew is out) polls `NSEvent.modifierFlags` and `NSEvent.mouseLocation`, flips `ignoresMouseEvents`; the overlay turns mouse down/drag/up into grabs; releasing ⌥ ends a drag; grab mode outlines everyone (highlight sprites). Done as `OverlayController.pollInput()`, run each frame by the scene (so only while the crew is out); the overlay is a non-activating panel that never becomes key, so grabbing doesn't take focus from the user's app; hover fade and dizzy stars drawn
- [x] HUD pill while the crew is out: "Clicks pass through · hold ⌥ to grab · ⌃⌥C calls them back"; in grab mode: "Grab mode · drag anyone, let go to throw"
- [x] ⌃⌥C toggles the crew from any app (Carbon hot key, `HotKey`); the footer shows the "⌃⌥C toggles" hint, and the menu item shows the shortcut. 2026-10-03: HUD and footer hint checked in in-app snapshots; the hot key itself is part of the manual check
- [x] Manual: no permission prompt; grab, throw and tap over real apps; releasing ⌥ is click-through again at once: owner checked 2026-10-03
- [x] Owner's review of grabbing against the prototype: approved 2026-10-03

## M6: walk-on notices, crowd and caps, staleness

Scope: what happens when the crew is inside and a session finishes or needs you (walk-ons), and what happens when there are more sessions than the desktop holds (the crowd). Ports of the prototype's `queueNotice`, `processNotices`, `slotsMax`, the `notify-in`/`notify-hold`/`notify-out` modes, `spawnCrowd`, `roamCrowd`, `syncRoamers` and the crowd parts of `drawEnt`, `hitBox` and `endDrag`. Staleness itself was built in M1; M6 checks its effect on the desktop. The Settings window is M7, so the done-announcement setting lives in the status menu until then.

- [x] Walk-ons while the crew is inside: from the right edge at 95 pt/s to slot k at x = `W − 80 − k·130`; 3 slots (W ≥ 900), 2 (W ≥ 560), 1 otherwise; **Done!** holds 6.5 s (cheer 2.4 s, 30 confetti, "name · turn time"); **Needs you** waves under `!` until answered, at most 16 s; out at 110 pt/s; queue ≤ 24; "+N more" folding. `CrewNoticeTests`; 2026-10-03: overlay-only captures of `walk-ons.jsonl` in the app show the Done! cheer with confetti and "blog · 22s", a second walk-on arriving, the answered one walking off, "api-server · 40s · +2 more", and "Bye!"
- [x] The done-announcement rule (open question 1's default): `DoneAnnouncement` = every turn / long turns (≥ 20 s, the default) / never decides the Done walk-on only; roamers and the office cheer every turn. `SessionStoreTests`, `CrewNoticeTests`
- [ ] The setting: status menu → **Announce Finished Turns** ▸ Every Turn / Turns of 20 s or More / Never, kept in `UserDefaults` (preferences only, non-negotiable #8). Built (`Preferences`, `StatusItemController`; `check-no-disk-writes` allows `UserDefaults` only in `Preferences.swift`); the menu itself is part of the owner's review
- [x] Walk-ons and grabbing: a tap sends a walk-on home; a thrown one lands and walks off; releasing the crew turns walk-ons into roamers; a walk-on whose session ends waves "Bye!". `CrewNoticeTests` (`grabWalkOn`, `releaseAndEnd`)
- [x] The crowd: more than 12 sessions → one crowd leaps out 60 ms after the last roamer; three half-size members, an orange "+N" bubble ("N need you"), `!` while any waits; wanders at 22 pt/s; a member's finished turn: "name finished" and 12 confetti; when a roamer's session ends the next one steps out ("My turn!", 0.7 s); empty → sparkle poof; grab: a tap resumes wandering, a throw is never dizzy. `CrewCrowdTests`; 2026-10-03: overlay captures of `crowd.jsonl` show the three half-size members with "+4 / 2 need you" under a `!`, "My turn!" beside a "Bye!", and the crowd back as "+2"
- [x] Recall with the crowd and walk-ons out completes within 2.6 s (non-negotiable #2): `CrewCrowdTests.recall100` (100 sessions, crowd mid-drag), `CrewNoticeTests.recallWithWalkOns`; `scripts/check-quit-cleanup.sh` passes on the M6 build
- [x] Caps under 100 sessions and an event burst: ≤ 12 roamers + 1 crowd + 3 walk-ons, ≤ 520 particles, ≤ 24 queued notices; a sim step with 100 sessions costs a small fraction of a frame: `CrewCrowdTests.caps`, 0.10 ms per step in a debug build
- [x] Overlay: the crowd and its count bubble drawn; walk-ons wake the overlay while the crew is inside, and it sleeps again (paused, ordered out) once they've gone. 2026-10-03: captures above; CPU 0% before the first walk-on, 4–10% while out, 0% again as soon as the last one leaves
- [x] Staleness on the desktop: a pruned session's character waves "Bye!" like an ended one (`AppDelegate.tick` → `sessionsChanged`, the same path as `SessionEnd`); docs say what the app actually does (`tick` every 5 s)
- [x] Scenarios: `walk-ons.jsonl`, `crowd.jsonl`: store `expect` lines in `ScenarioTests`, and the crew behaviour their comments promise in `CrewScenarioTests`
- [x] Measured: `--generate hundred` and `--generate burst` replays with the crew out, release build, 2026-10-03 (table in [performance-budget.md](../quality/performance-budget.md#measurements)): every event accepted (6,200 and 10,080); 100 sessions released 11.9% CPU and 68 MB once events stop; a burst of 2,000 events/s peaks at 27–37% and settles within 5 s. Found on the way and fixed: the open desk panel was over budget (4.3% → 2.2%, `PixelColorMatcher`)
- [ ] Over budget while a storm lasts: 100 sessions released during 200 events/s was 20.6% against < 15%. 2026-10-03: profiled and fixed the app's own costs (particle colours, the desk list's `reloadData`, bubble lookups; see [performance-budget.md](../quality/performance-budget.md#measurements)); a run with the panel closed then read 14.9%. Next step: re-measure on an idle Mac (the owner's Mac in use adds ±3% noise) and tick this if it holds
- [ ] **Blocker:** [bug 0001](../bugs/0001-grey-screen-overlay.md): the whole screen went flat grey (twice, 2026-10-03) while a test copy had the crew out with 100 sessions; not yet reproduced
- [ ] Owner's review of walk-ons and the crowd against the prototype; owner answers open questions 1 and 9

## Later milestones

Detailed checklists are written at the start of each milestone, using the per-area lists in [success-checklists.md](../quality/success-checklists.md).
