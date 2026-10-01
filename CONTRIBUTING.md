# Contributing to Agentville

Thanks for helping build a tiny pixel town! Start with the [docs index](docs/README.md).

## Ground rules

1. Read the [non-negotiables](docs/quality/non-negotiables.md). Every PR must keep all 12 intact.
2. No networking, analytics, disk logging, new entitlements or new permissions. These aren't up for debate in a PR.
3. No new dependencies without an ADR in `docs/decisions/`.
4. All art is original and procedural. Don't add third-party sprites, logos or brand marks.

## Making a change

```sh
scripts/ci.sh        # tests + privacy guards + docs check, exactly like CI
```

- Use small, focused commits with [Conventional Commit](https://www.conventionalcommits.org) messages.
- Update the relevant doc and checklist in the same PR.
- Core logic needs tests; a bug fix starts with a failing test.

See [docs/process/workflow.md](docs/process/workflow.md) for the full workflow.

## Unofficial project

Agentville isn't affiliated with Anthropic. Don't add anything that makes it look official.
