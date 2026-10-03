import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// M6: more sessions than the desktop holds (docs/product/user-experience.md#limits-the-user-can-notice).
/// Ports of the prototype's `spawnCrowd`, `roamCrowd`, `syncRoamers`, and the crowd parts of
/// `onDone`, `onWaiting`, `hitBox`, `drawEnt` and `endDrag`.
@Suite("Crew crowd and caps")
struct CrewCrowdTests {
    typealias T = CrewSimTests
    typealias N = CrewNoticeTests
    static let crowd = CrewSim.crowdID

    /// `n` sessions released and landed, crowd included.
    static func released(_ n: Int, seed: UInt64 = 1) -> (SessionStore, CrewSim) {
        let (store, sim) = N.setup(n, seed: seed)
        sim.release(store.ordered)
        T.run(sim, store, until: 2.5)
        return (store, sim)
    }

    @Test("More than 12 sessions: the crowd leaps out 60 ms after the last roamer and lands as three half-size members with a +N bubble")
    func spawn() throws {
        let (store, sim) = N.setup(20)
        sim.release(store.ordered)
        let at = Motion.releaseFirst + 12 * Motion.releaseStagger + Motion.crowdAfterRoamers
        T.run(sim, store, until: at - 0.005)
        #expect(sim.members[Self.crowd] == nil)
        T.run(sim, store, until: at + 0.005)
        var c = try #require(sim.members[Self.crowd])
        guard case .fly(let f) = c.mode else { Issue.record("not flying"); return }
        #expect(f.duration == Motion.crowdFlight && abs(c.x - 1200) < 15 && c.scale < 2.1)  // one 1/120 s step in
        T.run(sim, store, until: at + Motion.crowdFlight + 0.02)
        c = try #require(sim.members[Self.crowd])
        #expect(c.mode == .rest && c.scale == 3)
        let info = try #require(c.crowd)
        #expect(info.count == 8 && info.waiting == 0)
        #expect(info.looks == store.ordered[12..<15].map(\.look))
        #expect(info.frames.count == 3)
        let b = try #require(c.bubble)
        #expect(b.text == "+8" && b.kind == .count && b.sub == nil)
        // Not a session: its desk isn't emptied, and it never meets anyone.
        #expect(sim.members.count == 13 && sim.awayIDs.count == 12 && !sim.awayIDs.contains(Self.crowd))
        // 12 or fewer: no crowd.
        let (store2, sim2) = Self.released(12)
        #expect(sim2.members[Self.crowd] == nil && sim2.members.count == 12)
        _ = store2
    }

    @Test("The crowd shows how many need you, under a !, and its members don't walk on")
    func waiting() throws {
        let (store, sim) = Self.released(16)
        N.apply(store, sim, N.ev(.permissionRequest, "s13", tool: "Bash"), now: 3)
        N.apply(store, sim, N.ev(.permissionRequest, "s15", tool: "Bash"), now: 3)
        #expect(sim.noticeQueue.isEmpty)
        T.run(sim, store, until: 2.6)
        let c = try #require(sim.members[Self.crowd])
        #expect(c.crowd?.waiting == 2 && c.bubble?.text == "+4" && c.bubble?.sub == "2 need you")
        #expect(c.emote == .icon(.bang))
    }

    @Test("A crowd member's finished turn: the crowd says so with 12 confetti; no walk-on")
    func finished() throws {
        let (store, sim) = Self.released(14)
        let before = sim.particles.filter { $0.kind == .confetti }.count
        N.apply(store, sim, N.ev(.stop, "s13"), now: 60)
        #expect(sim.noticeQueue.isEmpty)
        #expect(sim.particles.filter { $0.kind == .confetti }.count - before == 12)
        let c = try #require(sim.members[Self.crowd])
        #expect(c.bubble?.text == "p13 finished" && c.bubble?.kind == .say)
        // It shows for 2.4 s, then the count comes back.
        T.run(sim, store, until: 2.5 + 2.3)
        #expect(sim.members[Self.crowd]?.bubble?.text == "p13 finished")
        T.run(sim, store, until: 2.5 + 2.5)
        #expect(sim.members[Self.crowd]?.bubble?.text == "+2")
    }

    @Test("The crowd wanders slowly (22 pt/s) and stays on the walkable band")
    func wander() throws {
        let (store, sim) = Self.released(15, seed: 7)
        var last = try #require(sim.members[Self.crowd])
        var moved = 0.0
        while sim.time < 62 {
            T.run(sim, store, until: sim.time + 0.1)
            let c = try #require(sim.members[Self.crowd])
            let d = hypot(c.x - last.x, c.y - last.y)
            // `walkTo` snaps the last 2 pt onto the target, like the prototype's.
            #expect(d <= Motion.crowdWander * 0.1 + 2.01)
            #expect(c.x >= 36 && c.x <= 1440 - 36 && c.y >= T.stage.minY + 6 && c.y <= 900 - 16)
            moved += d
            last = c
        }
        #expect(moved > 100)
    }

    @Test("When a roamer's session ends, the next steps out of the crowd: \"My turn!\", a 0.7 s hop; the last one out poofs the crowd")
    func stepOut() throws {
        let (store, sim) = Self.released(13)
        let c = try #require(sim.members[Self.crowd])
        N.apply(store, sim, N.ev(.sessionEnd, "s4"), now: 5)
        #expect(sim.members["s4"]?.mode == .leave)
        let m = try #require(sim.members["s12"])
        guard case .fly(let f) = m.mode else { Issue.record("not flying"); return }
        #expect(f.duration == Motion.stepOutFlight && f.from == (c.x, c.y))
        #expect(hypot(f.to.x - c.x, f.to.y - c.y) <= hypot(140, 84) + 0.01)
        #expect(m.bubble?.text == "My turn!")
        T.run(sim, store, until: 2.6)
        #expect(sim.members[Self.crowd] == nil)
        T.run(sim, store, until: 2.5 + 0.75)
        #expect(sim.members["s12"]?.mode == .rest)
        #expect(sim.particles.contains { $0.kind == .spark })
    }

    @Test("Growing past 12 while the crew is out brings the crowd out; new sessions beyond 12 join it")
    func grow() throws {
        let (store, sim) = Self.released(12)
        N.apply(store, sim, N.ev(.userPromptSubmit, "s12"), now: 5)
        N.apply(store, sim, N.ev(.userPromptSubmit, "s13"), now: 5)
        #expect(sim.members["s12"] == nil && sim.members["s13"] == nil)
        T.run(sim, store, until: 2.6)
        #expect(sim.members[Self.crowd] != nil)
        T.run(sim, store, until: 4)
        #expect(sim.members[Self.crowd]?.crowd?.count == 2)
    }

    @Test("Grabbing the crowd: a wider hit box; a tap resumes wandering; a hard throw never makes it dizzy or shout")
    func grab() throws {
        let (store, sim) = Self.released(14)
        // Put it somewhere clear.
        sim.modify(Self.crowd) { $0.x = 700; $0.y = 500 }
        for id in sim.members.keys where id != Self.crowd { sim.modify(id) { $0.x = 100; $0.y = 800 } }
        #expect(sim.hitTest(x: 700 + 16 * 3 + 3, y: 480) == Self.crowd)
        #expect(sim.hitTest(x: 700 + 16 * 3 + 5, y: 480) == nil)
        sim.grab(Self.crowd, x: 700, y: 480, at: 0)
        #expect(sim.members[Self.crowd]?.bubble?.kind == .count)
        sim.endDrag(cancel: false)
        #expect(sim.members[Self.crowd]?.mode == .rest && sim.members[Self.crowd]?.bubble?.kind == .count)

        sim.grab(Self.crowd, x: 700, y: 480, at: 1)
        sim.dragTo(x: 900, y: 400, at: 1.05)
        sim.endDrag(cancel: false)
        guard case .thrown(_, _, let hard) = sim.members[Self.crowd]?.mode else { Issue.record("not thrown"); return }
        #expect(!hard)
        #expect(sim.members[Self.crowd]?.bubble?.kind != .say)
        T.run(sim, store, until: 6)
        #expect(sim.members[Self.crowd]?.mode == .rest && sim.members[Self.crowd]?.pose != .dizzy)
    }

    @Test("Recall with 100 sessions, the crowd out and a drag in progress: all home within 2.6 s")
    func recall100() {
        let (store, sim) = Self.released(100)
        let c = sim.members[Self.crowd]!
        sim.grab(Self.crowd, x: c.x, y: c.y - 10, at: 0)
        sim.recall()
        T.run(sim, store, until: 2.5 + Timing.recallForceComplete + 0.01)
        #expect(sim.members.isEmpty)
    }

    @Test("Caps under 100 sessions and an event storm: ≤ 12 roamers + 1 crowd + 3 walk-ons, ≤ 520 particles, ≤ 24 notices; a step stays cheap")
    func caps() {
        let (store, sim) = N.setup(100, seed: 3)
        sim.release(store.ordered)
        var rng = SplitMix64(seed: 99)
        let kinds: [(WireEvent.Kind, String?)] = [(.preToolUse, "Edit"), (.preToolUse, "Bash"), (.preToolUse, "Grep"),
                                                  (.postToolUse, "Read"), (.permissionRequest, "Bash"), (.stop, nil),
                                                  (.userPromptSubmit, nil), (.subagentStart, nil), (.subagentStop, nil)]
        var stepTime = 0.0, steps = 0, maxMembers = 0, maxParticles = 0, maxQueue = 0
        var now = 0.0
        while sim.time < 40 {
            // About 500 events a second, spread over 100 sessions.
            for _ in 0..<8 {
                let (k, tool) = kinds[Int(rng.next() % UInt64(kinds.count))]
                let id = "s\(rng.next() % 100)"
                N.apply(store, sim, WireEvent(event: k, session: id, project: "p" + id.dropFirst(), tool: tool, notification: nil,
                                              agentId: "a\(rng.next() % 3)", source: nil, ts: 0), now: now)
            }
            // Recall halfway through, so walk-ons happen too.
            if sim.time > 20, sim.released { sim.recall() }
            now += 1.0 / 60
            let t0 = DispatchTime.now().uptimeNanoseconds
            _ = sim.update(dt: 1.0 / 60, sessions: store.sessions)
            stepTime += Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
            steps += 1
            let walkOns = sim.members.values.filter { $0.walkOn != nil && $0.mode != .leave }.count
            #expect(walkOns <= Limits.walkOns)
            maxMembers = max(maxMembers, sim.members.count)
            maxParticles = max(maxParticles, sim.particles.count)
            maxQueue = max(maxQueue, sim.noticeQueue.count)
        }
        #expect(maxMembers <= Limits.roamers + 1 + Limits.walkOns + Limits.roamers)  // + those waving Bye!
        #expect(maxParticles <= Limits.particles)
        #expect(maxQueue <= Limits.noticeQueue && maxQueue > 0)
        // A 60 Hz frame is 16.7 ms; the sim gets a small slice of it even in a debug build.
        #expect(stepTime / Double(steps) < 0.002, "mean step \(stepTime / Double(steps) * 1000) ms")
    }
}
