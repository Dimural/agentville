# Replay scenarios

Scripted event sequences in the `WireEvent` schema. They're used two ways:

1. **Executable specs.** `ScenarioTests` runs every file here through `SessionStore` and checks the `expect` lines. Add a scenario and you've added a test.
2. **Driving the real app.** `swift run agentville-replay Tools/scenarios/<file>.jsonl [--speed 4]` sends the events to the running app's socket. `expect` and `tick` lines are skipped.

Format: see `Sources/AgentvilleCore/Sessions/Scenario.swift`. Generated load (not stored as files):

```sh
swift run agentville-replay --generate hundred --seconds 30 --rate 200   # 100 sessions, realistic mix
swift run agentville-replay --generate burst --seconds 5 --rate 2000     # event storm
```

| File | Covers |
|---|---|
| `lifecycle.jsonl` | start → prompt → tools → permission → tools → stop → idle → end |
| `demo-mix.jsonl` | the prototype's 5-session opening scene |
| `subagents.jsonl` | overlapping subagents and a stray stop |
| `long-bash.jsonl` | a 20-minute Bash command isn't pruned |
| `silent.jsonl` | a killed terminal (no SessionEnd) is pruned |
| `malformed.jsonl` | broken and hostile datagrams are dropped |
