# Agentville docs

Everything about what Agentville is, how it works and how we know it's good lives here. These docs are the spec. Code that disagrees with them is a bug in one or the other: fix whichever is wrong, in the same commit.

## Reading order for a newcomer

1. [vision/vision.md](vision/vision.md): what we're building and why it should feel delightful
2. [vision/end-goals.md](vision/end-goals.md): what "finished" looks like, and the success measures
3. [product/user-experience.md](product/user-experience.md): the whole experience, end to end
4. [architecture/overview.md](architecture/overview.md): the four parts and how data flows
5. [quality/non-negotiables.md](quality/non-negotiables.md): the 12 rules
6. [process/milestones.md](process/milestones.md): where we are and what's next

## What to read for which task

| You're working on… | Read |
|---|---|
| The hook helper (`agentville-hook`) | [architecture/data-contract.md](architecture/data-contract.md), [architecture/hook.md](architecture/hook.md), [quality/privacy.md](quality/privacy.md) |
| The plugin, installing, Connect/Disconnect | [architecture/installation.md](architecture/installation.md), [decisions/0007-hook-location.md](decisions/0007-hook-location.md) |
| Session states and the store | [product/sessions-and-states.md](product/sessions-and-states.md), [architecture/app.md](architecture/app.md) |
| Sprites, looks, poses | [design/art-direction.md](design/art-direction.md), [design/sprites-and-poses.md](design/sprites-and-poses.md) |
| The office (desk window) | [design/office.md](design/office.md) |
| The overlay, release/recall, roaming, grabbing | [design/motion-and-behaviour.md](design/motion-and-behaviour.md), [architecture/input-and-safety.md](architecture/input-and-safety.md) |
| Performance, memory, CPU, size | [quality/performance-budget.md](quality/performance-budget.md) |
| Tests | [quality/testing-strategy.md](quality/testing-strategy.md) |
| Shipping a release | [process/release-checklist.md](process/release-checklist.md) |
| Anything you're tempted to decide on your own | [decisions/](decisions/) and [decisions/open-questions.md](decisions/open-questions.md) |

## Folder layout

| Folder | Holds | Changes when |
|---|---|---|
| `vision/` | Why, for whom, end goals, non-goals, personality | Rarely; owner decides |
| `product/` | What the user sees and does; session state rules | Behaviour changes |
| `architecture/` | Components, data contract, install flow, input/safety mechanics | Structure or contract changes |
| `design/` | Art direction, sprites, office, motion constants | Look and feel changes (the prototype wins on these) |
| `quality/` | Non-negotiables, success checklists, test strategy, budgets, privacy | We learn what "good" needs to mean |
| `process/` | Milestones, workflow, release checklist | Every milestone |
| `decisions/` | Numbered ADRs plus open questions for the owner | A decision is made or reversed |
| `reference/` | Pointers to the owner's local ground-truth files and how to use them | Rarely |

## Conventions

- Each doc opens with a one-line purpose. Docs that define something checkable end with a **Done when** checklist.
- Use the real names: `agentville-hook`, `WireEvent`, `SessionStore`. Grep should find docs and code together.
- Numbers (speeds, caps, timings) are copied from the prototype and live in [design/motion-and-behaviour.md](design/motion-and-behaviour.md). Code constants cite that doc.
