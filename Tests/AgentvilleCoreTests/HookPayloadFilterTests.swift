import Foundation
import Testing
@testable import AgentvilleCore

/// Privacy boundary tests (non-negotiable #6). Spec: docs/architecture/data-contract.md.
@Suite("Privacy: HookPayloadFilter")
struct HookPayloadFilterTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func wireBytes(_ p: [String: Any]) -> String? {
        guard let e = HookPayloadFilter.filter(p, now: now), let d = WireCodec.encode(e) else { return nil }
        return String(decoding: d, as: UTF8.self)
    }

    @Test("No secret ever leaves the filter, for every registered event", arguments: WireEvent.Kind.allCases)
    func noSecretsLeak(kind: WireEvent.Kind) throws {
        let p = realisticPayload(kind.rawValue, extra: [
            "tool_name": "Bash", "notification_type": "permission_prompt", "source": "startup",
            "reason": "other", "error_type": "rate_limit", "agent_id": "agent-1", "agent_type": "Explore",
        ])
        let out = try #require(wireBytes(p))
        for s in Secret.all { #expect(!out.contains(s), "leaked \(s) in \(out)") }
        #expect(!out.contains("/"), "no path separators may leave the hook: \(out)")
    }

    @Test("Only allowlisted keys appear in the wire JSON")
    func onlyAllowlistedKeys() throws {
        let allowed: Set<String> = ["v", "event", "session", "project", "tool", "notification", "agent_id", "agent_type", "source", "reason", "error", "ts"]
        for kind in WireEvent.Kind.allCases {
            let p = realisticPayload(kind.rawValue, extra: ["tool_name": "Read", "notification_type": "idle_prompt", "agent_id": "a", "agent_type": "Plan"])
            let e = try #require(HookPayloadFilter.filter(p, now: now))
            let encoded = try #require(WireCodec.encode(e))
            let obj = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            #expect(Set(obj.keys).isSubset(of: allowed), "\(kind): \(obj.keys)")
        }
    }

    @Test("Project is the folder name only")
    func projectFolderOnly() throws {
        let e = try #require(HookPayloadFilter.filter(realisticPayload("Stop"), now: now))
        #expect(e.project == "api-server")
        let e2 = try #require(HookPayloadFilter.filter(realisticPayload("Stop", extra: ["cwd": "/Users/sam/code/my app/"]), now: now))
        #expect(e2.project == "my app")
        var noCwd = realisticPayload("Stop"); noCwd["cwd"] = nil
        #expect(HookPayloadFilter.filter(noCwd, now: now)?.project == "unknown")
        #expect(HookPayloadFilter.filter(realisticPayload("Stop", extra: ["cwd": "/"]), now: now)?.project == "unknown")
    }

    @Test("Fields are scoped to the events that own them")
    func fieldScoping() throws {
        let extra: [String: Any] = ["tool_name": "Bash", "notification_type": "idle_prompt", "source": "startup", "reason": "logout", "error_type": "overloaded"]
        let stop = try #require(HookPayloadFilter.filter(realisticPayload("Stop", extra: extra), now: now))
        #expect(stop.tool == nil && stop.notification == nil && stop.source == nil && stop.reason == nil && stop.error == nil)
        let pre = try #require(HookPayloadFilter.filter(realisticPayload("PreToolUse", extra: extra), now: now))
        #expect(pre.tool == "Bash" && pre.notification == nil)
        let start = try #require(HookPayloadFilter.filter(realisticPayload("SessionStart", extra: extra), now: now))
        #expect(start.source == "startup" && start.tool == nil)
        let end = try #require(HookPayloadFilter.filter(realisticPayload("SessionEnd", extra: extra), now: now))
        #expect(end.reason == "logout")
        let fail = try #require(HookPayloadFilter.filter(realisticPayload("StopFailure", extra: extra), now: now))
        #expect(fail.error == "overloaded")
        let note = try #require(HookPayloadFilter.filter(realisticPayload("Notification", extra: extra), now: now))
        #expect(note.notification == "idle_prompt")
    }

    @Test("MCP tools are reduced to 'mcp'; odd tool names become 'other'")
    func toolNames() throws {
        func tool(_ t: String) -> String? { HookPayloadFilter.filter(realisticPayload("PreToolUse", extra: ["tool_name": t]), now: now)?.tool }
        #expect(tool("mcp__github__create_issue") == "mcp")
        #expect(tool("mcp__plugin_secret_server__query") == "mcp")
        #expect(tool("Edit") == "Edit")
        #expect(tool("rm -rf /") == "other")
        #expect(tool("Bash(\(Secret.toolInput))") == "other")
        #expect(tool(String(repeating: "A", count: 41)) == "other")
        #expect(tool("") == "other")
        #expect(tool("Ünïcode") == "other")
    }

    @Test("Unknown enum values are coarsened, not forwarded")
    func enumCoarsening() throws {
        let n = try #require(HookPayloadFilter.filter(realisticPayload("Notification", extra: ["notification_type": "brand_new_\(Secret.message)"]), now: now))
        #expect(n.notification == "other")
        let s = try #require(HookPayloadFilter.filter(realisticPayload("SessionStart", extra: ["source": Secret.message]), now: now))
        #expect(s.source == "other")
        let f = try #require(HookPayloadFilter.filter(realisticPayload("StopFailure", extra: ["error_type": Secret.error]), now: now))
        #expect(f.error == "unknown")
    }

    @Test("Unregistered events, missing session or non-object input produce nothing")
    func rejects() {
        #expect(HookPayloadFilter.filter(realisticPayload("PreCompact"), now: now) == nil)
        #expect(HookPayloadFilter.filter(realisticPayload("FileChanged"), now: now) == nil)
        var noSession = realisticPayload("Stop"); noSession["session_id"] = nil
        #expect(HookPayloadFilter.filter(noSession, now: now) == nil)
        #expect(HookPayloadFilter.filter(realisticPayload("Stop", extra: ["session_id": "!!!"]), now: now) == nil)
        #expect(HookPayloadFilter.filter(data: Data("[1,2,3]".utf8), now: now) == nil)
        #expect(HookPayloadFilter.filter(data: Data("not json".utf8), now: now) == nil)
        #expect(HookPayloadFilter.filter(data: Data(), now: now) == nil)
        #expect(HookPayloadFilter.filter(data: Data(repeating: 0x7B, count: HookPayloadFilter.maxInputBytes + 1), now: now) == nil)
    }

    @Test("Identifiers are sanitized and capped")
    func identifiers() throws {
        let e = try #require(HookPayloadFilter.filter(realisticPayload("SubagentStart", extra: [
            "session_id": "ab/c..d\n" + String(repeating: "z", count: 200),
            "agent_id": "agent<script>1", "agent_type": "my custom agent with spaces",
        ]), now: now))
        #expect(e.session.count == 64 && e.session.hasPrefix("abcd"))
        #expect(e.agentId == "agentscript1")
        #expect(e.agentType == nil)
    }

    @Test("Randomized payloads never leak markers (fuzz)")
    func fuzz() throws {
        var rng = XorShift32(seed: 0xA9E7)
        let keys = ["user_prompt", "tool_input", "tool_output", "message", "last_assistant_message", "model", "transcript_path", "x_new", "error_message", "nested"]
        for i in 0..<500 {
            var p: [String: Any] = ["hook_event_name": rng.pick(WireEvent.Kind.allCases).rawValue, "session_id": "s\(i)", "cwd": "/a/\(Secret.path)/proj\(i)"]
            for k in keys where rng.next() < 0.7 {
                p[k] = rng.next() < 0.5 ? "\(Secret.message)-\(i)" : ["deep": ["deeper": Secret.toolInput]]
            }
            if rng.next() < 0.5 { p["tool_name"] = rng.next() < 0.5 ? "mcp__\(Secret.title)__x" : "Read" }
            if let out = wireBytes(p) {
                for s in Secret.all { #expect(!out.contains(s)) }
            }
        }
    }

    @Test("Timestamp comes from the injected clock")
    func timestamp() throws {
        let e = try #require(HookPayloadFilter.filter(realisticPayload("Stop"), now: now))
        #expect(e.ts == 1_790_000_000_000)
    }
}
