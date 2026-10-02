import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// The desk window's session list and summary line: port of the prototype's `fmtDur`,
/// `statusLabel` and `renderList` (docs/product/user-experience.md#desk-window-the-office).
@Suite("Desk list")
struct DeskListTests {
    func ev(_ k: WireEvent.Kind, _ sid: String = "s1", project: String = "blog", tool: String? = nil,
            notification: String? = nil, agent: String? = nil) -> WireEvent {
        WireEvent(event: k, session: sid, project: project, tool: tool, notification: notification, agentId: agent, source: nil, ts: 0)
    }

    @Test("fmtDur: seconds, then minutes with zero-padded seconds")
    func durations() {
        #expect(DeskList.duration(0) == "0s")
        #expect(DeskList.duration(-3) == "0s")
        #expect(DeskList.duration(9.9) == "9s")
        #expect(DeskList.duration(59) == "59s")
        #expect(DeskList.duration(60) == "1m 00s")
        #expect(DeskList.duration(255) == "4m 15s")
        #expect(DeskList.duration(3725) == "62m 05s")
    }

    @Test("Working row: activity chip, tool in small text, elapsed turn time")
    func working() throws {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 100)
        st.apply(ev(.preToolUse, tool: "Edit"), now: 101)
        let r = DeskList.Row(try #require(st.sessions["s1"]), now: 355)
        #expect(r.name == "blog" && r.twin == nil)
        #expect(r.chip == .working && r.label == "Editing")
        #expect(r.detail == "Edit")
        #expect(r.elapsed == "4m 15s")
        #expect(r.tooltip == nil)
    }

    @Test("Subagents show as “+ subagent”, or a count when there are several")
    func subagents() throws {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        st.apply(ev(.preToolUse, tool: "Bash"), now: 0)
        st.apply(ev(.subagentStart, agent: "a"), now: 0)
        #expect(DeskList.Row(try #require(st.sessions["s1"]), now: 1).detail == "Bash + subagent")
        st.apply(ev(.subagentStart, agent: "b"), now: 0)
        st.apply(ev(.postToolUse, tool: "Bash"), now: 0)
        #expect(DeskList.Row(try #require(st.sessions["s1"]), now: 1).detail == "+ 2 subagents")
    }

    @Test("Needs you: red chip, tooltip instead of the prototype's Answer button (open question 11)")
    func needsYou() throws {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        st.apply(ev(.permissionRequest, tool: "Bash"), now: 5)
        let r = DeskList.Row(try #require(st.sessions["s1"]), now: 30)
        #expect(r.chip == .needsYou && r.label == "Needs you")
        #expect(r.tooltip == "Answer it in your terminal")
        #expect(r.detail == "")
        #expect(r.elapsed == "30s")
    }

    @Test("Finished shows the last turn's duration; idle and error show none")
    func finishedIdleError() throws {
        let st = SessionStore()
        st.apply(ev(.userPromptSubmit), now: 0)
        st.apply(ev(.stop), now: 75)
        var r = DeskList.Row(try #require(st.sessions["s1"]), now: 77)
        #expect(r.chip == .finished && r.label == "Finished" && r.elapsed == "1m 15s")
        st.tick(now: 200)
        r = DeskList.Row(try #require(st.sessions["s1"]), now: 200)
        #expect(r.chip == .idle && r.label == "Idle" && r.elapsed == "")
        st.apply(ev(.userPromptSubmit), now: 201)
        st.apply(ev(.stopFailure), now: 202)
        r = DeskList.Row(try #require(st.sessions["s1"]), now: 203)
        #expect(r.chip == .error && r.label == "Error" && r.elapsed == "")
    }

    @Test("Twins get a number badge (open question 14)")
    func twins() throws {
        let st = SessionStore()
        st.apply(ev(.sessionStart, "a", project: "api"), now: 0)
        st.apply(ev(.sessionStart, "b", project: "api"), now: 0)
        #expect(DeskList.Row(try #require(st.sessions["a"]), now: 0).twin == nil)
        #expect(DeskList.Row(try #require(st.sessions["b"]), now: 0).twin == 2)
    }

    @Test("Summary line: counts, with need/needs agreement, and the empty message")
    func summary() {
        typealias S = SessionStore.Summary
        #expect(DeskList.summary(S()).map(\.text) == ["No sessions yet. Start Claude Code in any terminal."])
        let one = DeskList.summary(S(active: 3, needYou: 1, justFinished: 0))
        #expect(one.map(\.text) == ["3 active", "1 needs you"])
        #expect(one.map(\.count) == ["3", "1"])
        #expect(one.map(\.tone) == [.plain, .warn])
        let all = DeskList.summary(S(active: 7, needYou: 2, justFinished: 1))
        #expect(all.map(\.text) == ["7 active", "2 need you", "1 just finished"])
        #expect(all.last?.tone == .ok)
    }

    @Test("Menu bar: count, red dot, header noun")
    func menuBar() {
        typealias S = SessionStore.Summary
        #expect(DeskList.menuHeader(S()) == "0 sessions")
        #expect(DeskList.menuHeader(S(active: 1)) == "1 session")
        #expect(DeskList.menuHeader(S(active: 5, needYou: 1)) == "5 sessions")
    }
}

@Suite("Menu bar icon")
struct MenuBarIconTests {
    @Test("Port of the prototype's 9×9 head pattern (paintIcons)")
    func head() {
        let c = MenuBarIcon.head
        #expect(c.width == 9 && c.height == 9)
        let rows = (0..<9).map { y in String((0..<9).map { c.isOpaque(x: $0, y: y) ? "#" : "." }) }
        #expect(rows == ["..#####..", ".#######.", "##.....##", "#..#.#..#", "#.......#",
                         ".#.###.#.", "..#####..", ".#.....#.", "#.......#"])
    }
}
