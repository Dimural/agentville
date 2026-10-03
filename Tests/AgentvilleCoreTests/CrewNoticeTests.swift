import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// M6: walk-on notices while the crew is inside (docs/design/motion-and-behaviour.md#notices-walk-ons-while-the-crew-is-inside).
/// Ports of the prototype's `onDone`, `onWaiting`, `queueNotice`, `processNotices`, `slotsMax` and the
/// `notify-in`/`notify-hold`/`notify-out` modes of `updateEnt`.
@Suite("Crew walk-on notices")
struct CrewNoticeTests {
    typealias T = CrewSimTests
    static let stage = T.stage

    static func ev(_ k: WireEvent.Kind, _ id: String, project: String? = nil, tool: String? = nil) -> WireEvent {
        let p = project ?? "p" + id.dropFirst()
        return WireEvent(event: k, session: id, project: p, tool: tool, notification: nil, agentId: nil, source: nil, ts: 0)
    }

    /// What the app does with each batch: apply, tell the crew about new and gone sessions, then the effects.
    static func apply(_ store: SessionStore, _ sim: CrewSim, _ e: WireEvent, now: Double) {
        let before = store.order
        let fx = store.apply(e, now: now)
        if store.order != before { sim.sessionsChanged(store.ordered) }
        sim.notify(fx)
    }

    /// `n` sessions s0…, each mid-turn since t = 0, known to the sim, crew inside.
    static func setup(_ n: Int, width: Double = 1440, seed: UInt64 = 1) -> (SessionStore, CrewSim) {
        let store = SessionStore()
        let sim = CrewSim(stage: Stage(width: width, height: 900, top: 25, bottom: 900), seed: seed)
        sim.home = { _ in Home(x: 1200, y: 120, scale: 2) }
        for i in 0..<n {
            apply(store, sim, ev(.userPromptSubmit, "s\(i)"), now: 0)
            apply(store, sim, ev(.preToolUse, "s\(i)", tool: "Edit"), now: 0)
        }
        return (store, sim)
    }

    static func walkOns(_ sim: CrewSim) -> [CrewMember] {
        sim.members.values.filter { $0.walkOn != nil }.sorted { $0.walkOn!.slot < $1.walkOn!.slot }
    }

    @Test("Done: walks in from the right edge at 95 pt/s, cheers with 30 confetti and a Done! bubble for 6.5 s, walks off at 110 pt/s")
    func doneWalkOn() throws {
        let (store, sim) = Self.setup(1)
        #expect(sim.isIdle)
        Self.apply(store, sim, Self.ev(.stop, "s0"), now: 25)
        #expect(!sim.isIdle)  // a notice is queued: the overlay must wake
        T.run(sim, store, until: 1.0 / 120)
        var m = try #require(sim.members["s0"])
        #expect(m.mode == .walkIn && m.face == -1 && m.pose == .walk)
        #expect(abs(m.x - (1440 + 30 - 95.0 / 120)) < 0.01 && m.y == 900 - 22)
        // 110 pt to its spot at 95 pt/s (the last 2 pt snap).
        T.run(sim, store, until: 1.12)
        #expect(sim.members["s0"]?.mode == .walkIn)
        let confettiBefore = sim.particles.filter { $0.kind == .confetti }.count
        T.run(sim, store, until: 1.17)
        m = try #require(sim.members["s0"])
        #expect(m.mode == .hold && m.x == 1440 - 80)
        #expect(sim.particles.filter { $0.kind == .confetti }.count - confettiBefore == 30)
        let b = try #require(m.bubble)
        #expect(b.text == "Done!" && b.kind == .done && b.sub == "p0 · 25s")
        T.run(sim, store, until: 2.0)
        #expect(sim.members["s0"]?.pose == .cheer && sim.members["s0"]?.emote == .icon(.check))
        T.run(sim, store, until: 3.7)
        #expect(sim.members["s0"]?.pose == .idle || sim.members["s0"]?.pose == .blink)
        // Holds 6.5 s in all, then heads off the right edge at 110 pt/s.
        T.run(sim, store, until: 1.17 + 6.45)
        #expect(sim.members["s0"]?.mode == .hold)
        T.run(sim, store, until: 1.17 + 6.55)
        m = try #require(sim.members["s0"])
        #expect(m.mode == .walkOff && m.bubble == nil)
        T.run(sim, store, until: 1.17 + 6.55 + 0.5)
        #expect(abs(try #require(sim.members["s0"]).x - (m.x + 110 * 0.5)) < 0.01)
        T.run(sim, store, until: 1.17 + 6.5 + 120.0 / 110 + 0.05)
        #expect(sim.members["s0"] == nil)
        T.run(sim, store, until: 12)
        #expect(sim.isIdle)
    }

    @Test("The announce rule: a short turn has no walk-on by default; every turn walks on when chosen; never means never")
    func announceRule() {
        for (rule, expected) in [(DoneAnnouncement.longTurns, false), (.everyTurn, true), (.never, false)] {
            let (store, sim) = Self.setup(1)
            store.announceDone = rule
            Self.apply(store, sim, Self.ev(.stop, "s0"), now: 5)
            T.run(sim, store, until: 0.5)
            #expect((sim.members["s0"] != nil) == expected, "\(rule)")
        }
        let (store, sim) = Self.setup(1)
        store.announceDone = .never
        Self.apply(store, sim, Self.ev(.stop, "s0"), now: 600)
        T.run(sim, store, until: 0.5)
        #expect(sim.members.isEmpty && sim.isIdle)
    }

    @Test("Needs you: waves and hops under a !, red bubble, until answered; then walks straight off")
    func needsYouWalkOn() throws {
        let (store, sim) = Self.setup(1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        T.run(sim, store, until: 2)
        var m = try #require(sim.members["s0"])
        #expect(m.mode == .hold && m.walkOn?.kind == .needsYou)
        #expect(m.pose == .wave && m.emote == .icon(.bang))
        let b = try #require(m.bubble)
        #expect(b.text == "Needs you" && b.kind == .wait && b.sub == "p0 is waiting for permission")
        var hopped = false
        while sim.time < 3 { T.run(sim, store, until: sim.time + 0.05); hopped = hopped || (sim.members["s0"]?.hop ?? 0) > 4 }
        #expect(hopped)
        // Still waiting at 10 s: still there.
        T.run(sim, store, until: 10)
        #expect(sim.members["s0"]?.mode == .hold)
        Self.apply(store, sim, Self.ev(.preToolUse, "s0", tool: "Bash"), now: 11)
        T.run(sim, store, until: 10.02)
        m = try #require(sim.members["s0"])
        #expect(m.mode == .walkOff)
    }

    @Test("Needs you that's never answered leaves after 16 s")
    func needsYouTimeout() {
        let (store, sim) = Self.setup(1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        T.run(sim, store, until: 1.17 + 15.9)
        #expect(sim.members["s0"]?.mode == .hold)
        T.run(sim, store, until: 1.17 + 16.1)
        #expect(sim.members["s0"]?.mode == .walkOff)
    }

    @Test("Slots: 3 on wide screens, 2 below 900 pt, 1 below 560 pt; slot k stands at W − 80 − k·130, H − 22 − k·6",
          arguments: [(1440.0, 3), (899, 2), (560, 2), (559, 1)])
    func slots(width: Double, count: Int) {
        let (store, sim) = Self.setup(5, width: width)
        for i in 0..<5 { Self.apply(store, sim, Self.ev(.permissionRequest, "s\(i)", tool: "Bash"), now: 1) }
        T.run(sim, store, until: 0.1)
        let w = Self.walkOns(sim)
        #expect(w.count == count)
        for (k, m) in w.enumerated() {
            #expect(m.walkOn?.slot == k)
            #expect(m.tx == width - 80 - Double(k) * 130 && m.y == 900 - 22 - Double(k) * 6)
        }
        // The rest wait their turn: answer the first and another walks on once it has gone.
        #expect(sim.noticeQueue.count == 5 - count)
    }

    @Test("Queued notices walk on as slots free up; a needs-you that was answered meanwhile is skipped")
    func queueDrains() {
        let (store, sim) = Self.setup(3, width: 500)
        for i in 0..<3 { Self.apply(store, sim, Self.ev(.permissionRequest, "s\(i)", tool: "Bash"), now: 1) }
        T.run(sim, store, until: 0.1)
        #expect(Set(sim.members.keys) == ["s0"])
        Self.apply(store, sim, Self.ev(.preToolUse, "s1", tool: "Read"), now: 2)  // answered while queued
        Self.apply(store, sim, Self.ev(.preToolUse, "s0", tool: "Read"), now: 2)
        // Answered on the way in: it notices once it has arrived (like the prototype) and turns back.
        T.run(sim, store, until: 0.2)
        #expect(sim.members["s0"]?.mode == .walkIn)
        T.run(sim, store, until: 1.3)
        #expect(sim.members["s0"]?.mode == .walkOff)
        // Slots count walkers on their way off too, like the prototype.
        #expect(sim.members["s2"] == nil)
        T.run(sim, store, until: 6)
        #expect(sim.members["s0"] == nil && sim.members["s1"] == nil && sim.members["s2"] != nil)
    }

    @Test("Done notices fold into \"+N more\" when 2 or more are pending")
    func folding() throws {
        let (store, sim) = Self.setup(5)
        for i in 0..<4 { Self.apply(store, sim, Self.ev(.stop, "s\(i)"), now: 30) }
        T.run(sim, store, until: 2)
        #expect(Self.walkOns(sim).count == 1)
        let m = try #require(sim.members["s0"])
        #expect(m.walkOn?.more == 3 && m.bubble?.sub == "p0 · 30s · +3 more")
        #expect(sim.noticeQueue.isEmpty)
        // One pending isn't folded: both walk on.
        let (store2, sim2) = Self.setup(2)
        for i in 0..<2 { Self.apply(store2, sim2, Self.ev(.stop, "s\(i)"), now: 30) }
        T.run(sim2, store2, until: 2)
        #expect(Self.walkOns(sim2).count == 2 && Self.walkOns(sim2).allSatisfy { $0.walkOn?.more == 0 })
    }

    @Test("The queue holds 24; overflow counts toward \"+N more\"; the same notice isn't queued twice")
    func queueCap() throws {
        let (store, sim) = Self.setup(32, width: 500)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        Self.apply(store, sim, Self.ev(.preToolUse, "s0", tool: "Bash"), now: 1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        #expect(sim.noticeQueue.count == 1)
        for i in 1..<31 { Self.apply(store, sim, Self.ev(.permissionRequest, "s\(i)", tool: "Bash"), now: 1) }
        #expect(sim.noticeQueue.count == Limits.noticeQueue)
        #expect(sim.overflowDone == 7)
        Self.apply(store, sim, Self.ev(.stop, "s31"), now: 40)
        #expect(sim.noticeQueue.count == Limits.noticeQueue)
        // Everyone answers; the done notice walks on and carries the overflow.
        for i in 0..<31 { Self.apply(store, sim, Self.ev(.preToolUse, "s\(i)", tool: "Read"), now: 2) }
        T.run(sim, store, until: 0.1)
        let m = try #require(sim.members["s31"])
        #expect(m.walkOn?.kind == .done && m.walkOn?.more == 8)
        #expect(sim.overflowDone == 0)
    }

    @Test("Grabbing a walk-on: a tap sends it home; a throw lands it and it walks off")
    func grabWalkOn() throws {
        let (store, sim) = Self.setup(2)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s1", tool: "Bash"), now: 1)
        T.run(sim, store, until: 2)
        let a = try #require(sim.members["s0"])
        #expect(sim.hitTest(x: a.x, y: a.y - 20) == "s0")
        #expect(sim.capturesMouse(optionHeld: true, x: a.x, y: a.y - 20))
        sim.grab("s0", x: a.x, y: a.y - 20, at: 2)
        sim.endDrag(cancel: false)
        #expect(sim.members["s0"]?.mode == .walkOff)

        let b = try #require(sim.members["s1"])
        sim.grab("s1", x: b.x, y: b.y - 20, at: 2)
        sim.dragTo(x: b.x - 150, y: b.y - 120, at: 2.1)
        sim.endDrag(cancel: false)
        guard case .thrown = sim.members["s1"]?.mode else { Issue.record("not thrown"); return }
        T.run(sim, store, until: 5)
        #expect(sim.members["s1"]?.mode == .walkOff)
    }

    @Test("Releasing the crew turns walk-ons into roamers; a walk-on whose session ends waves Bye!")
    func releaseAndEnd() throws {
        let (store, sim) = Self.setup(2)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s1", tool: "Bash"), now: 1)
        T.run(sim, store, until: 2)
        Self.apply(store, sim, Self.ev(.sessionEnd, "s1"), now: 3)
        #expect(sim.members["s1"]?.mode == .leave && sim.members["s1"]?.bubble?.text == "Bye!")
        sim.release(store.ordered)
        T.run(sim, store, until: 2.2)
        #expect(sim.members["s0"]?.mode == .rest)
        // Needs you on the desktop: it runs to the bottom of the screen and waves, as a roamer.
        T.run(sim, store, until: 4)
        #expect(sim.members["s0"]?.pose == .wave && sim.members["s0"]?.bubble?.sub == "p0")
    }

    @Test("While the crew is out, roamers cheer in place: no walk-on for them")
    func roamersDontWalkOn() {
        let (store, sim) = Self.setup(2)
        sim.release(store.ordered)
        T.run(sim, store, until: 1.5)
        Self.apply(store, sim, Self.ev(.stop, "s0"), now: 30)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s1", tool: "Bash"), now: 30)
        #expect(sim.noticeQueue.isEmpty)
        T.run(sim, store, until: 1.6)
        #expect(sim.members["s0"]?.bubble?.text == "Done!" && sim.members["s0"]?.walkOn == nil)
    }

    @Test("A walk-on with subagents brings its sidekick")
    func walkOnSidekick() throws {
        let (store, sim) = Self.setup(1)
        Self.apply(store, sim, WireEvent(event: .subagentStart, session: "s0", project: "p0", tool: nil, notification: nil,
                                         agentId: "a1", source: nil, ts: 0), now: 1)
        Self.apply(store, sim, Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        T.run(sim, store, until: 0.5)
        #expect(sim.members["s0"]?.side != nil)
    }

    @Test("Recall with walk-ons out: everyone is home within 2.6 s")
    func recallWithWalkOns() {
        let (store, sim) = Self.setup(6)
        sim.release(store.ordered)
        T.run(sim, store, until: 0.3)
        sim.recall()
        for i in 0..<6 { Self.apply(store, sim, Self.ev(.stop, "s\(i)"), now: 40) }
        T.run(sim, store, until: 0.3 + Timing.recallForceComplete + 0.01)
        #expect(sim.members.values.allSatisfy { $0.walkOn != nil || $0.mode == .leave })
    }
}
