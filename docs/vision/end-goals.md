# End goals

Purpose: what "done" means for Agentville 1.0, stated as outcomes we can check.

## The 1.0 end state

A developer on a fresh Mac runs one Homebrew command, clicks **Connect to Claude Code**, restarts their sessions, and **within a minute** sees a pixel character for each session in the menu bar office. From then on:

1. **They never miss a session that needs them.** Whenever a local session asks for permission, a character walks on screen with a red `!` and **"Needs you"** within about a second, and stays until it's handled (or a time limit passes).
2. **They know when long work finishes.** When a qualifying turn ends, a character walks on, cheers, and shows **"Done!"** with the project and duration.
3. **They can glance at everything.** The office window and its list show every session's activity, status and elapsed time, updated 4× a second.
4. **They can release the crew for fun** and get the full prototype-quality show: pour-out, roaming, activity poses, meetings, grab and throw, crowd. All of it click-through.
5. **They forget it costs anything.** No measurable slowdown of Claude Code, near-zero CPU at rest, and a small memory and disk footprint (see the [performance budget](../quality/performance-budget.md)).
6. **They trust it.** The README's privacy promises are verifiable from the source by anyone, and CI enforces them.
7. **They can leave cleanly.** Disconnect plus deleting the app leaves no hooks firing, no errors, no files except an optional preferences plist.

## Success measures

| Area | Measure | Target |
|---|---|---|
| Time to first character | Fresh install → a real session's character visible | < 60 s (excluding the Homebrew download) |
| Needs-you latency | `PermissionRequest` fires → walk-on starts | < 1 s |
| Hook cost | Hook wall time with the app running / absent | p99 < 50 ms / < 10 ms |
| Recall | Call-back from any state → every character home or removed | ≤ 2.6 s (hard limit 3 s) |
| Idle cost | CPU with the crew inside and the desk panel closed | ≈ 0% (< 0.5% averaged over 60 s) |
| Busy cost | CPU with 12 roaming plus a crowd, at 100 sessions | < 15% of one core on Apple Silicon |
| Memory | Resident memory, 100 sessions, crew released | < 150 MB |
| Size | App bundle / hook binary | < 15 MB / < 2 MB |
| Privacy | Fields leaving the hook that aren't on the allowlist | 0 (enforced by tests) |
| Network | Networking APIs in source | 0 (enforced by CI) |
| Delight | Owner's side-by-side review against the prototype | Every pose, screen and choreography matches |

## Stretch goals (post-1.0, not promised)

- Optional, off-by-default chiptune blips (release, done, needs you).
- Characters walking between displays.
- An opt-in "click a walk-on to jump to its terminal" (needs a permission, so it's opt-in only).
- More poses: error storm cloud, clipboard for planning tools, MCP gadget.

## Overall success checklist

The platform is successful when **all** of these are true. The detailed per-area checklists are in [quality/success-checklists.md](../quality/success-checklists.md).

- [ ] All 12 [non-negotiables](../quality/non-negotiables.md) have a passing test or a ticked manual check
- [ ] Every success measure above is met on the owner's Mac
- [ ] Side-by-side review against the prototype passes for poses, office, bubbles and choreography
- [ ] Real sessions verified from the CLI, the VS Code extension and the desktop app
- [ ] Install → first character in under a minute on a fresh user account
- [ ] Disconnect + delete leaves nothing behind (checked by the release checklist)
- [ ] The README's privacy claims are reproducible by an outsider following the README
- [ ] The owner finds it fun to use for a week of real work without turning it off
