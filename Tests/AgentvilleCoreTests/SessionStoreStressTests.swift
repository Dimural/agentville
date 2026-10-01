import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// Non-negotiable #11: event storms from 100 sessions must not stall or grow without bound.
@Suite("Session store under load")
struct SessionStoreStressTests {
    @Test("100 sessions × 50,000 events: bounded state and fast batches")
    func storm() {
        let st = SessionStore()
        var rng = XorShift32(seed: 7)
        let kinds: [WireEvent.Kind] = [.preToolUse, .postToolUse, .preToolUse, .postToolUse, .permissionRequest,
                                       .userPromptSubmit, .stop, .subagentStart, .subagentStop, .notification]
        let tools = ["Read", "Edit", "Bash", "Grep", "WebFetch", "mcp", "Task", "TodoWrite", "Mystery"]
        var worstBatch = 0.0
        var now = 0.0
        for _ in 0..<50 {
            let t0 = Date()
            for _ in 0..<1000 {
                now += 0.002 // 500 events per second
                let i = Int(rng.next() * 100)
                let e = WireEvent(event: rng.pick(kinds), session: "s\(i)", project: "p\(i % 30)",
                                  tool: rng.pick(tools), notification: "permission_prompt",
                                  agentId: "a\(Int(rng.next() * 50))", ts: 0)
                st.apply(e, now: now)
            }
            st.tick(now: now)
            worstBatch = max(worstBatch, Date().timeIntervalSince(t0))
        }
        #expect(st.sessions.count == 100)
        #expect(st.order.count == 100)
        #expect(st.sessions.values.allSatisfy { $0.subagents.count <= Limits.subagentsPerSession })
        // Debug-build budget: 1,000 events in < 50 ms (docs/quality/performance-budget.md).
        #expect(worstBatch < 0.05, "worst 1,000-event batch took \(worstBatch)s")
    }

    @Test("A flood of unique session ids stays capped")
    func uniqueFlood() {
        let st = SessionStore()
        for i in 0..<5000 {
            st.apply(WireEvent(event: .sessionStart, session: "u\(i)", project: "p", ts: 0), now: Double(i))
        }
        #expect(st.sessions.count == Limits.trackedSessions)
        #expect(st.order.count == Limits.trackedSessions)
    }

    @Test("Churn: start/end cycles leave nothing behind")
    func churn() {
        let st = SessionStore()
        for i in 0..<10_000 {
            st.apply(WireEvent(event: .userPromptSubmit, session: "c\(i)", project: "p", ts: 0), now: Double(i))
            st.apply(WireEvent(event: .sessionEnd, session: "c\(i)", project: "p", reason: "other", ts: 0), now: Double(i))
        }
        #expect(st.sessions.isEmpty && st.order.isEmpty)
    }
}
