# 0001: The product is named Agentville
Status: Accepted
Date: 2026-10-01

## Context
The prototype and brief used the working name "Pixel Crew". The owner named the project and repository **Agentville**.

## Decision
The product, app, repo, plugin and marketplace are all **Agentville** (`agentville` in identifiers). The binaries are `agentville-hook` and `agentville-replay`. In-app copy keeps the prototype's "crew" vocabulary ("Release the crew", "Call the crew back"); Agentville is the town, and the crew are its residents.

## Consequences
- The plugin name `agentville` passes Claude Code's reserved-name rules (it doesn't start with `claude-` or `anthropic-`).
- Docs that refer to the prototype call it "the prototype" (its file is `Pixel Crew.html`).
- Still to verify before M8: the name is free on GitHub, Homebrew and the App Store (open question 4).
