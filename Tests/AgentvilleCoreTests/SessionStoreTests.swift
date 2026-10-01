import Foundation
import Testing
@testable import AgentvilleCore

/// One test per transition in docs/product/sessions-and-states.md.
@Suite("Session store")
struct SessionStoreTests {
    func ev(_ k: WireEvent.Kind, _ sid: String = "s1", project: String = "blog", tool: String? = nil,
            notification: String? = nil, agent: String? = nil, source: String? = nil) -> WireEvent {
        WireEvent(event: k, session: sid, project: project, tool: tool, notification: notification, agentId: agent, source: source, ts: 0)
    }

    @Test("SessionStart creates an idle session with a look from the folder name")
    func start() throws {
        let st = SessionStore()
        let fx = st.apply(ev(.sessionStart, source: "startup"), now: 0)
        #expect(fx == [.added(id: "s1")])
        let s = try #require(st.sessions["s1"])
        #expect(s.status == .idle && s.project == "blog" && s.twinIndex == 1)
        #expect(s.look == LookGenerator.look(for: "blog"))
    }

    @Test("Prompt → thinking; PreToolUse → activity; PostToolUse → thinking")
    func working() throws {
        let st = SessionStore()
        st.apply(ev(.sessionStart), now: 0)
        st.apply(ev(.userPromptSubmit), now: 1)
        #expect(st.sessions["s1"]?.status == .working(.thinking))
        st.apply(ev(.preToolUse, tool: "Edit"), now: 2)
        #expect(st.sessions["s1"]?.status == .working(.editing))
        #expect(st.sessions["s1"]?.tool == "Edit")
        st.apply(ev(.postToolUse, tool: "Edit"), now: 3)
        #expect(st.sessions["s1"]?.status == .working(.thinking))
        #expect(st.sessions["s1"]?.tool == nil)
        st.apply(ev(.preToolUse, tool: "Bash"), now: 4)
        st.apply(ev(.postToolUseFailure, tool: "Bash"), now: 5)
        #expect(st.sessions["s1"]?.status == .working(.thinking))
    }

    @Test("Task/Agent keeps the previous activity")
    func subagentLauncher() {
        let st = SessionStore()
        st.apply(ev(.preToolUse, tool: "Grep"), now: 0)
        st.apply(ev(.preToolUse, tool: "Task"), now: 1)
        #expect(st.sessions["s1"]?.status == .working(.searching))
    }

    @Test("Stop → finished with turn duration; announce only long turns; idle after the hold")
    func stop() throws {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 100)
        let fx = st.apply(ev(.stop), now: 355)
        #expect(fx == [.finished(id: "s1", duration: 255, announce: true)])
        #expect(st.sessions["s1"]?.status == .finished)
        #expect(st.sessions["s1"]?.lastTurnDuration == 255)
        st.tick(now: 355 + Timing.finishedHold - 0.1)
        #expect(st.sessions["s1"]?.status == .finished)
        st.tick(now: 355 + Timing.finishedHold)
        #expect(st.sessions["s1"]?.status == .idle)

        st.apply(ev(.userPromptSubmit), now: 400)
        #expect(st.apply(ev(.stop), now: 405) == [.finished(id: "s1", duration: 5, announce: false)])
    }

    @Test("Stop without a known turn start: no duration, no announcement")
    func stopUnknownTurn() {
        let st = SessionStore()
        st.apply(ev(.sessionStart), now: 0)
        #expect(st.apply(ev(.stop), now: 50).contains(.finished(id: "s1", duration: nil, announce: false)))
    }

    @Test("Hooks installed mid-turn: first tool event starts the clock")
    func midTurn() {
        let st = SessionStore()
        st.apply(ev(.preToolUse, tool: "Read"), now: 10)
        #expect(st.apply(ev(.stop), now: 40) == [.finished(id: "s1", duration: 30, announce: true)])
    }

    @Test("PermissionRequest and needs-you notifications → needsYou; next activity resolves it",
          arguments: [
            (WireEvent.Kind.permissionRequest, String?.none),
            (.notification, "permission_prompt"), (.notification, "elicitation_dialog"),
            (.notification, "elicitation_url_dialog"), (.notification, "agent_needs_input"),
          ])
    func needsYou(kind: WireEvent.Kind, note: String?) {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        let fx = st.apply(ev(kind, tool: kind == .permissionRequest ? "Bash" : nil, notification: note), now: 1)
        #expect(fx == [.needsYou(id: "s1")])
        #expect(st.sessions["s1"]?.status == .needsYou)
        #expect(st.summary.needYou == 1)
        // A repeated prompt doesn't re-announce.
        #expect(st.apply(ev(.notification, notification: "permission_prompt"), now: 2).isEmpty)
        #expect(st.apply(ev(.preToolUse, tool: "Bash"), now: 3) == [.resolved(id: "s1")])
        #expect(st.sessions["s1"]?.status == .working(.running))
    }

    @Test("Stop while waiting resolves and finishes")
    func stopWhileWaiting() {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        st.apply(ev(.permissionRequest, tool: "Bash"), now: 1)
        let fx = st.apply(ev(.stop), now: 2)
        #expect(fx.contains(.resolved(id: "s1")))
        #expect(fx.contains(.finished(id: "s1", duration: 2, announce: false)))
    }

    @Test("idle_prompt → idle, but never hides a pending permission")
    func idlePrompt() {
        let st = SessionStore()
        st.apply(ev(.stop), now: 0)
        st.apply(ev(.notification, notification: "idle_prompt"), now: 60)
        #expect(st.sessions["s1"]?.status == .idle)
        st.apply(ev(.permissionRequest, tool: "Bash"), now: 61)
        st.apply(ev(.notification, notification: "idle_prompt"), now: 62)
        #expect(st.sessions["s1"]?.status == .needsYou)
    }

    @Test("Other notification types change nothing visible")
    func otherNotifications() {
        let st = SessionStore()
        st.apply(ev(.preToolUse, tool: "Edit"), now: 0)
        for n in ["auth_success", "elicitation_complete", "agent_completed", "other"] {
            st.apply(ev(.notification, notification: n), now: 1)
            #expect(st.sessions["s1"]?.status == .working(.editing), "\(n)")
        }
    }

    @Test("StopFailure → error")
    func failure() {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        #expect(st.apply(ev(.stopFailure), now: 1) == [.failed(id: "s1")])
        #expect(st.sessions["s1"]?.status == .error)
        st.apply(ev(.userPromptSubmit), now: 2)
        #expect(st.sessions["s1"]?.status == .working(.thinking))
    }

    @Test("Subagents: several at once, stop removes the right one, unknown stop ignored, cleared on Stop")
    func subagents() {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        #expect(st.apply(ev(.subagentStart, agent: "a1"), now: 1) == [.subagentStarted(id: "s1", agent: "a1")])
        st.apply(ev(.subagentStart, agent: "a2"), now: 1)
        #expect(st.apply(ev(.subagentStart, agent: "a1"), now: 1).isEmpty, "duplicate start ignored")
        #expect(st.sessions["s1"]?.subagents == ["a1", "a2"])
        #expect(st.apply(ev(.subagentStop, agent: "a1"), now: 2) == [.subagentStopped(id: "s1", agent: "a1")])
        #expect(st.apply(ev(.subagentStop, agent: "zz"), now: 2).isEmpty)
        #expect(st.sessions["s1"]?.subagents == ["a2"])
        st.apply(ev(.stop), now: 3)
        #expect(st.sessions["s1"]?.subagents == [])
    }

    @Test("Subagents are capped per session")
    func subagentCap() {
        let st = SessionStore()
        for i in 0..<100 { st.apply(ev(.subagentStart, agent: "a\(i)"), now: 0) }
        #expect(st.sessions["s1"]?.subagents.count == Limits.subagentsPerSession)
    }

    @Test("SessionEnd removes; late events don't resurrect; SessionStart does")
    func endAndTombstone() {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        #expect(st.apply(ev(.sessionEnd), now: 1) == [.removed(id: "s1", reason: .ended)])
        #expect(st.sessions.isEmpty && st.order.isEmpty)
        #expect(st.apply(ev(.postToolUse, tool: "Read"), now: 2).isEmpty)
        #expect(st.sessions.isEmpty)
        #expect(st.apply(ev(.sessionStart, source: "resume"), now: 3) == [.added(id: "s1")])
        #expect(st.apply(ev(.sessionEnd, "never-seen"), now: 4).isEmpty)
    }

    @Test("Compaction doesn't interrupt work; other SessionStart sources reset to idle")
    func sessionStartSources() {
        let st = SessionStore()
        st.apply(ev(.preToolUse, tool: "Edit"), now: 0)
        st.apply(ev(.sessionStart, source: "compact"), now: 1)
        #expect(st.sessions["s1"]?.status == .working(.editing))
        st.apply(ev(.sessionStart, source: "clear"), now: 2)
        #expect(st.sessions["s1"]?.status == .idle)
    }

    @Test("Twins in the same folder get increasing badges; a freed index is reused")
    func twins() {
        let st = SessionStore()
        st.apply(ev(.sessionStart, "a", project: "api"), now: 0)
        st.apply(ev(.sessionStart, "b", project: "api"), now: 0)
        st.apply(ev(.sessionStart, "c", project: "web"), now: 0)
        #expect(st.sessions["a"]?.twinIndex == 1 && st.sessions["b"]?.twinIndex == 2 && st.sessions["c"]?.twinIndex == 1)
        st.apply(ev(.sessionEnd, "a", project: "api"), now: 1)
        st.apply(ev(.sessionStart, "d", project: "api"), now: 2)
        #expect(st.sessions["d"]?.twinIndex == 1)
        #expect(st.order == ["b", "c", "d"])
    }

    @Test("Staleness: a long-running tool survives; quiet sessions are pruned per rule")
    func staleness() {
        let st = SessionStore()
        st.apply(ev(.preToolUse, "bash", tool: "Bash"), now: 0)
        st.apply(ev(.postToolUse, "think", tool: "Read"), now: 0)
        st.apply(ev(.sessionStart, "idle"), now: 0)
        st.apply(ev(.permissionRequest, "wait", tool: "Bash"), now: 0)

        #expect(st.tick(now: Timing.Stale.working - 1).isEmpty)
        #expect(st.tick(now: Timing.Stale.working) == [.removed(id: "think", reason: .stale)])
        #expect(st.sessions["bash"] != nil, "a 15-minute Bash command must not be pruned")
        #expect(st.tick(now: Timing.Stale.toolRunning) == [.removed(id: "bash", reason: .stale)])
        #expect(st.tick(now: Timing.Stale.idle) == [.removed(id: "idle", reason: .stale)])
        #expect(st.tick(now: Timing.Stale.needsYou) == [.removed(id: "wait", reason: .stale)])
        #expect(st.sessions.isEmpty)
    }

    @Test("Any event refreshes the staleness clock")
    func refresh() {
        let st = SessionStore()
        st.apply(ev(.sessionStart), now: 0)
        st.apply(ev(.notification, notification: "auth_success"), now: Timing.Stale.idle - 10)
        #expect(st.tick(now: Timing.Stale.idle + 1).isEmpty)
    }

    @Test("Summary counts")
    func summary() {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit, "a"), now: 0)
        st.apply(ev(.permissionRequest, "b", tool: "Bash"), now: 0)
        st.apply(ev(.permissionRequest, "c", tool: "Bash"), now: 0)
        st.apply(ev(.stop, "d"), now: 0)
        #expect(st.summary == .init(active: 4, needYou: 2, justFinished: 1))
    }

    @Test("Revision moves on every change, so the 4 Hz UI knows when to redraw")
    func revision() {
        let st = SessionStore()
        let r0 = st.revision
        st.apply(ev(.sessionStart), now: 0)
        #expect(st.revision > r0)
        let r1 = st.revision
        st.tick(now: 1)
        #expect(st.revision == r1)
    }

    @Test("Tracked sessions are capped; quiet idle sessions are evicted first")
    func cap() {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit, "busy"), now: 0)  // oldest, but working
        for i in 0..<(Limits.trackedSessions - 1) { st.apply(ev(.sessionStart, "s\(i)"), now: Double(i + 1)) }
        #expect(st.sessions.count == Limits.trackedSessions)
        let fx = st.apply(ev(.sessionStart, "new"), now: 10_000)
        #expect(fx.contains(.removed(id: "s0", reason: .evicted)))
        #expect(st.sessions.count == Limits.trackedSessions)
        #expect(st.sessions["busy"] != nil)
    }
}
