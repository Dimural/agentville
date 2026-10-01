import Foundation

/// Repo root, derived from this file's location (Tests/AgentvilleCoreTests/TestSupport.swift).
let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func readRepoFile(_ relative: String) throws -> String {
    try String(contentsOf: repoRoot.appendingPathComponent(relative), encoding: .utf8)
}

/// Markers planted in every non-allowlisted field. None may ever appear in output.
enum Secret {
    static let prompt = "SECRET-PROMPT-7f3a"
    static let toolInput = "SECRET-INPUT-91bc"
    static let toolOutput = "SECRET-OUTPUT-c0de"
    static let message = "SECRET-MESSAGE-5eed"
    static let path = "SECRET-PATH-0a0a"
    static let transcript = "SECRET-TRANSCRIPT-beef"
    static let model = "SECRET-MODEL-d00d"
    static let title = "SECRET-TITLE-face"
    static let error = "SECRET-ERROR-f00d"
    static let all = [prompt, toolInput, toolOutput, message, path, transcript, model, title, error]
}

/// A realistic payload for `event`, stuffed with secret markers in every field we must drop.
func realisticPayload(_ event: String, extra: [String: Any] = [:]) -> [String: Any] {
    var p: [String: Any] = [
        "session_id": "sess-123",
        "transcript_path": "/Users/sam/.claude/projects/\(Secret.transcript)/t.jsonl",
        "cwd": "/Users/sam/\(Secret.path)/api-server",
        "hook_event_name": event,
        "permission_mode": "default",
        "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
        "scratchpad_dir": "/tmp/\(Secret.path)/scratch",
        "effort": ["level": "medium"],
        "user_prompt": "please use password \(Secret.prompt)",
        "prompt": Secret.prompt,
        "tool_input": ["command": "psql -p \(Secret.toolInput)", "file_path": "/etc/\(Secret.path)"],
        "tool_output": String(repeating: "x", count: 1000) + Secret.toolOutput,
        "tool_response": ["stdout": Secret.toolOutput],
        "tool_use_id": "toolu_01ABC",
        "message": "Claude needs your permission: \(Secret.message)",
        "last_assistant_message": "Here is what I did: \(Secret.message)",
        "model": Secret.model,
        "session_title": Secret.title,
        "error_message": Secret.error,
        "rule_used": "Bash(\(Secret.toolInput))",
        "classifier_verdict": ["category": Secret.message],
        "context_tokens": 182340,
        "estimated_cache_write_usd": 1.13,
        "future_field_we_dont_know": Secret.message,
    ]
    for (k, v) in extra { p[k] = v }
    return p
}
