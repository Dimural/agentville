# Development workflow

Purpose: how humans and agents make changes here so that the repo stays easy to pick up cold.

## The loop

1. **Find the doc.** Use the [docs index](../README.md). If the change isn't specified, specify it first (a short doc edit or an ADR).
2. **Write the test.** Core and hook changes start with a failing test.
3. **Implement** the smallest change that passes.
4. **Run `scripts/ci.sh`.** Tests, guards and doc-link check.
5. **Update docs and checklists** in the same commit (tick only with evidence).
6. **Commit** with a Conventional Commit message. Commit small and often; every commit builds and passes tests.

## Commit messages

```
<type>(<scope>): <imperative summary>

<why, if not obvious>
```

Types: `feat`, `fix`, `test`, `docs`, `refactor`, `perf`, `chore`, `ci`. Scopes: `core`, `hook`, `replay`, `app`, `plugin`, `docs`, `scripts`.

## Branches and PRs

- `main` is always green.
- Feature work goes on short-lived branches (`m1/session-store`, `fix/hook-timing`), then a PR with the checklist items it ticks.
- PR description: what changed, which doc and checklist items, and the test evidence (command + result).

## Agent-specific guidance

- Read `AGENTS.md` first; it has the commands and the repo map.
- **Never commit `Pixel Crew.html` or `PROJECT_BRIEF.md`.** They're gitignored; don't force-add them.
- Don't add dependencies, networking, disk writes, entitlements or permissions. Each needs an ADR and the owner's approval.
- Prefer porting prototype code line-for-line over "improving" it; cite the function name.
- When unsure about a product decision, add it to [open-questions.md](../decisions/open-questions.md) with a proposed default and keep going with that default.
- Keep files focused: one type per file in Core, named after the type.

## Toolchain

- Swift 6 language mode, macOS 14+ deployment target.
- `scripts/swift.sh` wraps `swift` and falls back to the Command Line Tools when Xcode isn't usable (for example, an unaccepted licence), adding Swift Testing framework paths.
- No `.xcodeproj`. Open `Package.swift` in Xcode if you want an IDE.
