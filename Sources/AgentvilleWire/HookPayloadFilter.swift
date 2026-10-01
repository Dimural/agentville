import Foundation

/// THE privacy boundary. Turns Claude Code's hook stdin JSON into a `WireEvent`, keeping only
/// allowlisted fields. Anything not read explicitly below is dropped, including fields
/// Claude Code adds in future. Spec: docs/architecture/data-contract.md.
public enum HookPayloadFilter {
    /// Hook stdin larger than this is not parsed at all (docs/architecture/hook.md).
    public static let maxInputBytes = 4 * 1024 * 1024

    public static func filter(data: Data, now: Date = Date()) -> WireEvent? {
        guard !data.isEmpty, data.count <= maxInputBytes,
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any]
        else { return nil }
        return filter(dict, now: now)
    }

    public static func filter(_ p: [String: Any], now: Date = Date()) -> WireEvent? {
        guard let name = p["hook_event_name"] as? String,
              let kind = WireEvent.Kind(rawValue: name),
              let rawSession = p["session_id"] as? String
        else { return nil }

        let event = WireEvent(
            event: kind,
            session: rawSession,
            project: Sanitize.projectName(fromCwd: p["cwd"] as? String),
            tool: p["tool_name"] as? String,
            notification: p["notification_type"] as? String,
            agentId: p["agent_id"] as? String,
            agentType: p["agent_type"] as? String,
            source: p["source"] as? String,
            reason: p["reason"] as? String,
            error: p["error_type"] as? String,
            ts: Int64((now.timeIntervalSince1970 * 1000).rounded())
        )
        // `sanitized()` enforces every per-field rule and per-event field scoping.
        return event.sanitized()
    }
}
