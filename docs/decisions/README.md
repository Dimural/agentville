# Decisions (ADRs)

Purpose: short records of decisions a future contributor might otherwise re-litigate. One file per decision, numbered, never renumbered. To reverse a decision, add a new ADR that supersedes the old one, and mark the old one `Superseded by NNNN`.

Statuses: **Accepted** (in force), **Proposed** (default in use, awaiting the owner's confirmation), **Superseded**.

| # | Decision | Status |
|---|---|---|
| [0001](0001-name-agentville.md) | The product is named Agentville | Accepted |
| [0002](0002-mit-license.md) | MIT licence | Proposed |
| [0003](0003-macos-14-minimum.md) | Minimum macOS 14 Sonoma | Proposed |
| [0004](0004-swiftpm-no-xcodeproj.md) | One SwiftPM package, no .xcodeproj | Accepted |
| [0005](0005-socket-location.md) | Datagram socket in the per-user Darwin temp dir | Accepted |
| [0006](0006-reference-files-local-only.md) | Prototype and brief stay local, never committed | Accepted |
| [0007](0007-hook-location.md) | Helper symlink in Application Support + silent shell-form hook | Proposed |
| [0008](0008-swift-testing.md) | Swift Testing for all tests | Accepted |
| [0009](0009-desk-panel-dropdown.md) | The desk is a dropdown panel under the menu bar icon | Accepted |

Owner-facing questions that aren't decided yet: [open-questions.md](open-questions.md).

## Template

```md
# NNNN: Title
Status: Proposed | Accepted | Superseded by NNNN
Date: YYYY-MM-DD

## Context
## Decision
## Consequences
```
