# Non-negotiables

Purpose: the 12 rules no change may break. Each is an acceptance criterion with an automated test or a manual release check. A PR that weakens one needs an ADR and the owner's sign-off.

| # | Rule | Verified by |
|---|---|---|
| **Clicks and recall** | | |
| 1 | **Clicks always pass through** the crew unless ⌥ is held *and* the press lands on a character. Buttons, text fields, scrolling, drag-and-drop and window resizing underneath work as if the crew weren't there. | Manual (release checklist §Overlay); `InputPoller` unit tests for the decision function |
| 2 | **Recall always works within 3 s** from any state: mid-drag, mid-throw, window hidden, 100 sessions, a walk-on in progress. | Replay scenario + manual; overlay unit test on the force-complete timer |
| 3 | **Quitting leaves nothing behind.** No overlay, no helper process, no socket file in use. | Manual + `scripts/check-quit-cleanup.sh` (local, needs a GUI session) |
| **Claude Code must not be affected** | | |
| 4 | **The hook never affects Claude Code.** It always exits 0, never writes stdout, finishes < 50 ms p99 with the app running and < 10 ms with it absent, and stays silent when the app is deleted. | `Tests/HookIntegrationTests` (exit code, stdout, timing, absent app, deleted helper) |
| 5 | **Sessions behave identically** with Agentville installed, running, quit or deleted. | Release checklist §Real-world |
| **Privacy** | | |
| 6 | **Only allowlisted fields ever leave the hook.** | `HookPayloadFilterTests` incl. secret-marker fuzzing; hook integration tests read the socket |
| 7 | **No networking.** No network code, no network entitlements, no analytics, no crash reporters, no update checks. | `scripts/check-no-network.sh` in CI; `otool -L` check in `check-footprint.sh` |
| 8 | **Nothing written to disk except preferences** (and the Path B settings backup and helper symlink, both user-initiated). No event logs; diagnostics are in-memory only. | `scripts/check-no-disk-writes.sh` in CI; code review |
| **Footprint** | | |
| 9 | **No special permissions.** None of Accessibility, Input Monitoring, Screen Recording, Automation or Full Disk Access. | Manual on a fresh account; entitlement check in `check-footprint.sh` (M8) |
| 10 | **Bounded footprint.** ≤ 12 roamers, ≤ 3 walk-ons, capped particles, UI at about 4 Hz, near-zero CPU at rest. | Unit tests on caps; [performance budget](performance-budget.md) measurements |
| 11 | **Survives event storms.** Hundreds of events per second from 100 sessions don't stall the UI, grow memory without bound, or delay recall. | `SessionStoreStressTests`; replay `burst` scenario |
| **Integrity** | | |
| 12 | **Original art only.** No third-party characters, logos or brand marks; no implied officialness. | Review; `THIRD_PARTY.md` |
