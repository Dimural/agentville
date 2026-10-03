import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// The crew on the desktop: release and recall choreography (docs/design/motion-and-behaviour.md),
/// ported from the prototype's `release`, `recall`, `spawnFromHome`, `sendHome` and `updateEnt`.
@Suite("Crew simulation")
struct CrewSimTests {
    static let stage = Stage(width: 1440, height: 900, top: 25, bottom: 900)

    /// A store with `n` working sessions, s0…s(n−1).
    static func sessions(_ n: Int, tool: String = "Edit") -> SessionStore {
        let st = SessionStore()
        for i in 0..<n {
            st.apply(WireEvent(event: .preToolUse, session: "s\(i)", project: "p\(i)", tool: tool, notification: nil,
                               agentId: nil, source: nil, ts: 0), now: 0)
        }
        return st
    }

    static func sim(_ store: SessionStore, seed: UInt64 = 1) -> CrewSim {
        let sim = CrewSim(stage: stage, seed: seed)
        sim.home = { _ in Home(x: 1200, y: 120, scale: 2) }
        return sim
    }

    /// Steps at 120 Hz until `until` (sim time), collecting events.
    @discardableResult
    static func run(_ sim: CrewSim, _ store: SessionStore, until: Double) -> [CrewEvent] {
        var events: [CrewEvent] = []
        while sim.time < until - 1e-9 { events += sim.update(dt: min(1.0 / 120, until - sim.time), sessions: store.sessions) }
        return events
    }

    @Test("Stage: 3 pt per pixel, 2 on narrow screens; walkable band from the prototype's minY")
    func stage() {
        #expect(Self.stage.scale == 3)
        #expect(Stage(width: 680, height: 500, top: 25, bottom: 500).scale == 2)
        #expect(Self.stage.minY == 25 + 26 * 3 + 6)
    }

    @Test("Release: burp, then one leap every 85 ms starting at 120 ms")
    func stagger() {
        let store = Self.sessions(4), sim = Self.sim(store)
        #expect(sim.release(store.ordered) == [.burp])
        #expect(sim.released)
        Self.run(sim, store, until: 0.119)
        #expect(sim.members.isEmpty)
        Self.run(sim, store, until: 0.121)
        #expect(sim.members.keys.sorted() == ["s0"])
        Self.run(sim, store, until: 0.12 + 0.085 * 2 + 0.001)
        #expect(sim.members.count == 3)
        Self.run(sim, store, until: 0.12 + 0.085 * 3 + 0.001)
        #expect(sim.members.count == 4)
    }

    @Test("At most 12 leave the desks; the rest come out as the crowd")
    func cap() {
        let store = Self.sessions(20), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 4)
        #expect(sim.awayIDs.count == Limits.roamers)
        #expect(sim.awayIDs == Set(store.ordered.prefix(12).map(\.id)))
        #expect(sim.members[CrewSim.crowdID]?.crowd?.count == 8)
    }

    @Test("Flight: starts at home scale, arcs up, stretched; lands at desktop scale with squash and dust")
    func flight() throws {
        let store = Self.sessions(1), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 0.121)
        var m = try #require(sim.members["s0"])
        guard case .fly(let f) = m.mode else { Issue.record("not flying"); return }
        #expect(f.duration >= 0.8 && f.duration <= 1.1)
        #expect(abs(m.x - 1200) < 15 && abs(m.y - 120) < 15 && m.scale < 2.02)  // one 1/120 s step in
        #expect(m.stretch.x == 0.92 && m.stretch.y == 1.1)
        #expect(m.pose == .cheer)
        // Mid-flight: z = (G·T/2)·t − G·t²/2 peaks at G·T²/8.
        Self.run(sim, store, until: 0.12 + f.duration / 2)
        m = try #require(sim.members["s0"])
        let peak = Motion.gravity * f.duration * f.duration / 8
        #expect(abs(m.z - peak) < peak * 0.05)
        // Landing.
        let dustBefore = sim.particles.filter { $0.kind == .dust }.count
        Self.run(sim, store, until: 0.12 + f.duration + 0.005)
        m = try #require(sim.members["s0"])
        #expect(m.mode == .rest)
        #expect(m.z == 0 && m.scale == 3)
        #expect(abs(m.x - f.to.x) < 0.001 && abs(m.y - f.to.y) < 0.001)
        #expect(m.squash > 0.9)
        #expect(sim.particles.filter { $0.kind == .dust }.count - dustBefore == 5)
        #expect(f.to.y >= Self.stage.minY + 10 && f.to.y <= Self.stage.bottom - 18)
        #expect(f.to.x >= 40 && f.to.x <= Self.stage.width - 40)
    }

    @Test("On the desktop, each acts out its session")
    func restPoses() throws {
        let store = Self.sessions(1, tool: "Bash"), sim = Self.sim(store)
        sim.release(store.ordered)
        var poses: Set<Pose> = []
        while sim.time < 10 { Self.run(sim, store, until: sim.time + 0.1); poses.insert(sim.members["s0"]?.pose ?? .idle) }
        #expect(poses.contains(.bash))
        store.apply(WireEvent(event: .permissionRequest, session: "s0", project: "p0", tool: "Bash", notification: nil, agentId: nil, source: nil, ts: 0), now: 1)
        Self.run(sim, store, until: 20)
        #expect(sim.members["s0"]?.pose == .wave)
        #expect(sim.members["s0"]?.emote == .icon(.bang))
        store.apply(WireEvent(event: .stop, session: "s0", project: "p0", tool: nil, notification: nil, agentId: nil, source: nil, ts: 0), now: 2)
        Self.run(sim, store, until: 20.2)
        #expect(sim.members["s0"]?.pose == .cheer)
        #expect(sim.members["s0"]?.emote == .icon(.check))
    }

    @Test("Recall: everyone waits under a !, then flies home bottom-most first; gulp when the last one lands")
    func recall() throws {
        let store = Self.sessions(5), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 3)
        let order = sim.members.values.sorted { $0.y > $1.y }.map(\.id)
        sim.recall()
        #expect(!sim.released)
        #expect(sim.members.values.allSatisfy { $0.mode == .wait && $0.emote == .icon(.bang) })
        Self.run(sim, store, until: 3.061)
        let flying = sim.members.values.filter { if case .fly = $0.mode { true } else { false } }.map(\.id)
        #expect(flying == [order[0]])
        let events = Self.run(sim, store, until: 3 + 2.5)
        #expect(sim.members.isEmpty)
        #expect(events.filter { $0 == .gulp }.count == 1)
    }

    @Test("Recall completes within 2.6 s from every state", arguments: [0.0, 0.05, 0.3, 0.9, 1.6, 4.0])
    func recallRule(after: Double) {
        let store = Self.sessions(100), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: after)
        // Sessions end and appear mid-recall too.
        sim.recall()
        store.apply(WireEvent(event: .sessionEnd, session: "s1", project: "p1", tool: nil, notification: nil, agentId: nil, source: nil, ts: 0), now: 1)
        store.apply(WireEvent(event: .sessionStart, session: "new", project: "new", tool: nil, notification: nil, agentId: nil, source: nil, ts: 0), now: 1)
        sim.sessionsChanged(store.ordered)
        Self.run(sim, store, until: after + Timing.recallForceComplete)
        #expect(sim.members.isEmpty, "still out: \(sim.members.keys.sorted())")
        Self.run(sim, store, until: after + 6)
        #expect(sim.members.isEmpty)
        #expect(sim.isIdle)
    }

    @Test("Releasing again mid-recall sends the crew back out without duplicates")
    func rerelease() {
        let store = Self.sessions(3), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 2)
        sim.recall()
        Self.run(sim, store, until: 2.2)
        sim.release(store.ordered)
        Self.run(sim, store, until: 6)
        #expect(sim.members.count == 3)
        #expect(sim.members.values.allSatisfy { $0.mode == .rest })
    }

    @Test("A new session while out drops in and says Hello!; an ended one waves Bye! and poofs")
    func dropInAndLeave() throws {
        let store = Self.sessions(2), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 2)
        store.apply(WireEvent(event: .sessionStart, session: "n", project: "new", tool: nil, notification: nil, agentId: nil, source: nil, ts: 0), now: 2)
        sim.sessionsChanged(store.ordered)
        let n = try #require(sim.members["n"])
        #expect(n.mode == .drop && n.z == Self.stage.height * 0.7)
        Self.run(sim, store, until: 4)
        #expect(sim.members["n"]?.mode == .rest)
        #expect(sim.members["n"]?.bubble?.text == "Hello!")

        store.apply(WireEvent(event: .sessionEnd, session: "s0", project: "p0", tool: nil, notification: nil, agentId: nil, source: nil, ts: 0), now: 4)
        sim.sessionsChanged(store.ordered)
        #expect(sim.members["s0"]?.mode == .leave)
        #expect(sim.members["s0"]?.bubble?.text == "Bye!")
        Self.run(sim, store, until: 5.2)
        #expect(sim.members["s0"] == nil)
    }

    @Test("Shouts come from the prototype's lists")
    func shouts() {
        var said: Set<String> = []
        for seed in 1...30 {
            let store = Self.sessions(6), sim = Self.sim(store, seed: UInt64(seed))
            sim.release(store.ordered)
            Self.run(sim, store, until: 0.7)
            said.formUnion(sim.members.values.compactMap { $0.bubble?.text })
            sim.recall()
            said.formUnion(sim.members.values.compactMap { $0.bubble?.text })
        }
        #expect(!said.isEmpty)
        #expect(said.isSubset(of: Set(Phrases.release + Phrases.recall)))
    }

    @Test("Particles are capped at 520, oldest dropped")
    func particleCap() {
        let sim = Self.sim(Self.sessions(0))
        for _ in 0..<100 { sim.sparkle(x: 10, y: 10, count: 10) }
        #expect(sim.particles.count == Limits.particles)
    }

    @Test("Same seed, same choreography")
    func deterministic() {
        func positions(_ seed: UInt64) -> [Double] {
            let store = Self.sessions(5), sim = Self.sim(store, seed: seed)
            sim.release(store.ordered)
            Self.run(sim, store, until: 2)
            return sim.members.values.sorted { $0.id < $1.id }.flatMap { [$0.x, $0.y] }
        }
        #expect(positions(7) == positions(7))
        #expect(positions(7) != positions(8))
    }

    @Test("Idle only when nobody is out, nothing is scheduled and the particles are gone")
    func idle() {
        let store = Self.sessions(1), sim = Self.sim(store)
        #expect(sim.isIdle)
        sim.release(store.ordered)
        #expect(!sim.isIdle)
        Self.run(sim, store, until: 2)
        sim.recall()
        Self.run(sim, store, until: 6)
        #expect(sim.isIdle)
    }

    // MARK: - Roaming (port of roam, walkTo, nearbyTarget)

    /// Median of the moving samples: the < 2 pt arrival snap (from `walkTo`) can't skew it.
    static func median(_ v: [Double]) -> Double {
        let m = v.filter { $0 > 1 }.sorted()
        return m.isEmpty ? 0 : m[m.count / 2]
    }

    static func ev(_ k: WireEvent.Kind, _ id: String, tool: String? = nil) -> WireEvent {
        WireEvent(event: k, session: id, project: "p", tool: tool, notification: nil, agentId: nil, source: nil, ts: 0)
    }

    @Test("Working characters act for a while, then walk somewhere nearby, at most 48 pt/s, and act again")
    func wander() throws {
        let store = Self.sessions(1), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 1.5)
        let landed = try #require(sim.members["s0"])
        #expect(landed.mode == .rest)
        var walked = false, lastX = landed.x, lastY = landed.y, speeds: [Double] = []
        var poses: Set<Pose> = []
        while sim.time < 40 {
            Self.run(sim, store, until: sim.time + 0.1)
            let m = try #require(sim.members["s0"])
            speeds.append(hypot(m.x - lastX, m.y - lastY) / 0.1)
            lastX = m.x; lastY = m.y
            poses.insert(m.pose)
            if m.pose == .walk { walked = true }
        }
        #expect(walked)
        #expect(poses.isSuperset(of: [.walk, .type]))
        #expect(abs(Self.median(speeds) - Motion.walk) < 1)
        #expect(hypot(lastX - landed.x, lastY - landed.y) > 1)
    }

    @Test("Everyone stays inside the walkable area")
    func bounds() {
        let store = Self.sessions(12, tool: "Read"), sim = Self.sim(store)
        sim.release(store.ordered)
        let st = Self.stage
        while sim.time < 120 {
            Self.run(sim, store, until: sim.time + 0.5)
            for m in sim.members.values where m.mode == .rest {
                #expect(m.x >= 36 - 0.001 && m.x <= st.width - 36 + 0.001, "\(m.id) x \(m.x)")
                #expect(m.y >= st.minY - 0.001 && m.y <= st.bottom - 16 + 0.001, "\(m.id) y \(m.y)")
            }
        }
    }

    @Test("Searching creeps along with the magnifier (26 pt/s)")
    func searchCreep() throws {
        let store = Self.sessions(1, tool: "Grep"), sim = Self.sim(store)
        sim.release(store.ordered)
        var speeds: [Double] = [], last = (0.0, 0.0), sawWalkingSearch = false
        Self.run(sim, store, until: 1.5)
        if let m = sim.members["s0"] { last = (m.x, m.y) }
        while sim.time < 40 {
            Self.run(sim, store, until: sim.time + 0.1)
            let m = try #require(sim.members["s0"])
            let v = hypot(m.x - last.0, m.y - last.1) / 0.1
            if v > 1 { sawWalkingSearch = sawWalkingSearch || m.pose == .search }
            speeds.append(v)
            last = (m.x, m.y)
        }
        #expect(sawWalkingSearch)
        #expect(abs(Self.median(speeds) - Motion.searchCreep) < 1)
    }

    @Test("Needs you: runs to the bottom of the screen, then waves and hops under a !")
    func needsYouRun() throws {
        let store = Self.sessions(1), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 1.5)
        store.apply(Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        Self.run(sim, store, until: 1.6)
        #expect(sim.members["s0"]?.pose == .walk)
        Self.run(sim, store, until: 15)
        let m = try #require(sim.members["s0"])
        #expect(abs(m.y - (Self.stage.bottom - 26)) < 0.001)
        #expect(m.pose == .wave && m.emote == .icon(.bang))
        // Answered: back to work and wandering.
        store.apply(Self.ev(.preToolUse, "s0", tool: "Edit"), now: 2)
        Self.run(sim, store, until: 15.2)
        #expect(sim.members["s0"]?.pose == .type)
    }

    @Test("Finishing a turn: a 2.6 s cheer, then idle strolling (32 pt/s) with coffee or a nap")
    func finishThenIdle() throws {
        let store = Self.sessions(1), sim = Self.sim(store)
        sim.release(store.ordered)
        Self.run(sim, store, until: 1.5)
        store.apply(Self.ev(.stop, "s0"), now: 1)
        Self.run(sim, store, until: 1.6)
        #expect(sim.members["s0"]?.pose == .cheer)
        #expect(sim.members["s0"]?.emote == .icon(.check))
        Self.run(sim, store, until: 4.3)
        let rest = try #require(sim.members["s0"]).look.rest == .sleep ? Pose.sleep : .coffee
        var poses: Set<Pose> = [], speeds: [Double] = [], last = (sim.members["s0"]!.x, sim.members["s0"]!.y)
        while sim.time < 60 {
            Self.run(sim, store, until: sim.time + 0.1)
            let m = try #require(sim.members["s0"])
            poses.insert(m.pose)
            speeds.append(hypot(m.x - last.0, m.y - last.1) / 0.1)
            last = (m.x, m.y)
        }
        #expect(!poses.contains(.cheer))
        #expect(poses.isSuperset(of: [rest, .walk]))
        #expect(abs(Self.median(speeds) - Motion.idleStroll) < 1)
    }
}
