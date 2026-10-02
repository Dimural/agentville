import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// M4: what the crew does on the desktop besides walking about (docs/design/motion-and-behaviour.md):
/// Done and Needs-you bubbles, confetti, the activity particles, meetings and subagent sidekicks.
/// Ports of the prototype's `onDone`, `roam`, `checkMeetings`, the sidekick block of `updateEnt`,
/// `confetti`, `zzz`, `bits` and `stepParts`.
@Suite("Crew activity")
struct CrewActivityTests {
    typealias T = CrewSimTests

    static func ev(_ k: WireEvent.Kind, _ id: String, project: String = "p0", tool: String? = nil, agent: String? = nil) -> WireEvent {
        WireEvent(event: k, session: id, project: project, tool: tool, notification: nil, agentId: agent, source: nil, ts: 0)
    }

    /// Released and landed: everyone is on the desktop, resting.
    static func landed(_ store: SessionStore, seed: UInt64 = 1) -> CrewSim {
        let sim = T.sim(store, seed: seed)
        sim.release(store.ordered)
        T.run(sim, store, until: 1.5)
        return sim
    }

    // MARK: - Done and Needs you

    @Test("Finishing a turn: Done! bubble with the name and turn time, and a burst of 26 confetti")
    func doneBubble() throws {
        let store = SessionStore()
        store.apply(Self.ev(.userPromptSubmit, "s0"), now: 0)
        store.apply(Self.ev(.preToolUse, "s0", tool: "Edit"), now: 0)
        let sim = Self.landed(store)
        let before = sim.particles.filter { $0.kind == .confetti }.count
        store.apply(Self.ev(.stop, "s0"), now: 4)
        T.run(sim, store, until: 1.5 + 1.0 / 120)
        let m = try #require(sim.members["s0"])
        let b = try #require(m.bubble)
        #expect(b.text == "Done!" && b.kind == .done && b.sub == "p0 · 4s")
        #expect(sim.particles.filter { $0.kind == .confetti }.count - before >= 26)
        // The bubble stays for 5 s.
        T.run(sim, store, until: 6.3)
        #expect(sim.members["s0"]?.bubble?.kind == .done)
        T.run(sim, store, until: 6.6)
        #expect(sim.members["s0"]?.bubble == nil)
    }

    @Test("Reduced motion cuts confetti to a quarter")
    func reducedMotion() {
        let store = T.sessions(1)
        let sim = Self.landed(store)
        sim.reduceMotion = true
        let before = sim.particles.filter { $0.kind == .confetti }.count
        store.apply(Self.ev(.stop, "s0"), now: 1)
        T.run(sim, store, until: 1.5 + 1.0 / 120)
        let burst = sim.particles.filter { $0.kind == .confetti }.count - before
        #expect(burst >= 7 && burst <= 8)  // ceil(26 / 4), plus maybe one sprinkle of ceil(2 / 4)
    }

    @Test("Confetti flies up, falls at 0.55 G, flutters and settles on the ground")
    func confettiPhysics() {
        let store = T.sessions(1)
        let sim = Self.landed(store)
        store.apply(Self.ev(.stop, "s0"), now: 1)
        T.run(sim, store, until: 1.6)
        var settled = false
        while sim.time < 3.5 {
            T.run(sim, store, until: sim.time + 0.05)
            let c = sim.particles.filter { $0.kind == .confetti }
            #expect(c.allSatisfy { $0.z >= 0 })
            if c.contains(where: { $0.z == 0 && $0.vz == 0 }) { settled = true }
            #expect(c.allSatisfy { $0.life < $0.max && $0.max >= 1.3 && $0.max <= 2.2 })
        }
        #expect(settled)
    }

    @Test("Needs you: a red Needs you bubble with the project name, gone once answered")
    func needsYouBubble() throws {
        let store = T.sessions(1)
        let sim = Self.landed(store)
        store.apply(Self.ev(.permissionRequest, "s0", tool: "Bash"), now: 1)
        T.run(sim, store, until: 2)
        let b = try #require(sim.members["s0"]?.bubble)
        #expect(b.text == "Needs you" && b.kind == .wait && b.sub == "p0")
        T.run(sim, store, until: 10)
        #expect(sim.members["s0"]?.bubble?.kind == .wait)
        store.apply(Self.ev(.preToolUse, "s0", tool: "Edit"), now: 2)
        T.run(sim, store, until: 10.1)
        #expect(sim.members["s0"]?.bubble == nil)
    }

    @Test("Twins are named with their number")
    func twinName() throws {
        let store = SessionStore()
        store.apply(Self.ev(.preToolUse, "a", project: "api", tool: "Edit"), now: 0)
        store.apply(Self.ev(.preToolUse, "b", project: "api", tool: "Edit"), now: 0)
        let sim = Self.landed(store)
        store.apply(Self.ev(.permissionRequest, "b", project: "api"), now: 1)
        T.run(sim, store, until: 2)
        #expect(sim.members["b"]?.bubble?.sub == "api 2")
    }

    // MARK: - Activity particles

    /// Particles spawned near one character over `seconds` of roaming.
    static func particles(tool: String?, seconds: Double = 30, seed: UInt64 = 1) -> [Particle] {
        let store = SessionStore()
        store.apply(Self.ev(.preToolUse, "s0", tool: tool), now: 0)
        let sim = Self.landed(store, seed: seed)
        var seen: [Particle] = []
        while sim.time < 1.5 + seconds {
            let before = sim.particles.count
            T.run(sim, store, until: sim.time + 1.0 / 120)
            if sim.particles.count > before { seen += sim.particles.suffix(sim.particles.count - before) }
        }
        return seen
    }

    @Test("Typing throws coloured bits (about 3/s)")
    func bits() {
        let bits = Self.particles(tool: "Edit").filter { $0.kind == .bit }
        #expect(bits.count > 20)
        #expect(Set(bits.map(\.color)).isSubset(of: Set(CrewSim.bitColors)))
        #expect(bits.allSatisfy { $0.vz >= 30 && $0.vz <= 50 && $0.max >= 0.8 && $0.max <= 1.3 })
    }

    @Test("Hammering Bash sends sparks on each strike; the telescope twinkles")
    func bashAndWeb() {
        let bash = Self.particles(tool: "Bash").filter { $0.kind == .spark && $0.color == RGB(0xFFA300) }
        #expect(bash.count > 10)
        let web = Self.particles(tool: "WebFetch").filter { $0.kind == .spark && $0.max == 0.7 }
        #expect(web.count > 5)
        #expect(web.allSatisfy { $0.color == RGB(0xFFEC27) })
    }

    @Test("Sleepers puff z's that drift up and right")
    func zzz() throws {
        // A look that naps rather than drinks coffee.
        let name = try #require((0..<200).map { "proj\($0)" }.first { LookGenerator.look(for: $0).rest == .sleep })
        let store = SessionStore()
        store.apply(Self.ev(.preToolUse, "s0", project: name, tool: "Edit"), now: 0)
        store.apply(Self.ev(.stop, "s0", project: name), now: 0)
        store.tick(now: 100)
        let sim = Self.landed(store)
        var zs: [Particle] = []
        while sim.time < 40 {
            T.run(sim, store, until: sim.time + 0.1)
            zs += sim.particles.filter { $0.kind == .zzz && $0.life < 0.1 }
        }
        #expect(!zs.isEmpty)
        #expect(zs.allSatisfy { $0.vx >= 8 && $0.vx <= 18 && $0.vz == 22 && $0.max == 1.8 })
    }

    // MARK: - Meetings (port of checkMeetings)

    @Test("Two working walkers within 44 pt meet: stop 1.6 s, face each other, cheer, heart or ?, pink sparkles")
    func meeting() throws {
        let store = T.sessions(2)
        let sim = Self.landed(store)
        // Put them side by side, walking the same way, with expired cooldowns.
        sim.modify("s0") { $0.x = 500; $0.y = 500; $0.phase = .walk; $0.tx = 900; $0.ty = 500; $0.meetCd = 0 }
        sim.modify("s1") { $0.x = 530; $0.y = 500; $0.phase = .walk; $0.tx = 950; $0.ty = 500; $0.meetCd = 0 }
        let pinkBefore = sim.particles.filter { $0.color == RGB(0xFF77A8) }.count
        T.run(sim, store, until: sim.time + 0.4)
        let a = try #require(sim.members["s0"]), b = try #require(sim.members["s1"])
        #expect(a.phase == .meet && b.phase == .meet)
        #expect(a.face == 1 && b.face == -1)
        #expect(a.pose == .cheer && b.pose == .cheer)
        #expect([a.emote, b.emote].compactMap { $0 }.count == 1)
        #expect([Emote.icon(.heart), .icon(.quest)].contains(a.emote ?? b.emote ?? .icon(.bang)))
        #expect(a.meetCd >= 18 - 0.4 && a.meetCd <= 30 && b.meetCd >= 18 - 0.4 && b.meetCd <= 30)
        #expect(sim.particles.filter { $0.color == RGB(0xFF77A8) }.count - pinkBefore == 5)
        if let said = a.bubble?.text { #expect(Phrases.meet.contains(said)) }
        // Cheer for the first 0.8 s, then stand, then carry on.
        T.run(sim, store, until: sim.time + 1.0)
        #expect(sim.members["s0"]?.pose == .idle)
        T.run(sim, store, until: sim.time + 0.8)
        #expect(sim.members["s0"]?.phase != .meet)
    }

    @Test("No meeting while cooling down, when far apart, or when not working")
    func noMeeting() {
        let store = T.sessions(3)
        store.apply(Self.ev(.stop, "s2", project: "p2"), now: 1)
        store.tick(now: 100)
        let sim = Self.landed(store)
        sim.modify("s0") { $0.x = 500; $0.y = 500; $0.phase = .walk; $0.tx = 900; $0.ty = 500; $0.meetCd = 5 }
        sim.modify("s1") { $0.x = 530; $0.y = 500; $0.phase = .walk; $0.tx = 950; $0.ty = 500; $0.meetCd = 0 }
        sim.modify("s2") { $0.x = 515; $0.y = 500; $0.phase = .walk; $0.tx = 920; $0.ty = 500; $0.meetCd = 0 }
        T.run(sim, store, until: sim.time + 0.4)
        #expect(sim.members.values.allSatisfy { $0.phase != .meet })
    }

    @Test("First cooldown is 6–16 s")
    func initialCooldown() {
        let store = T.sessions(12)
        let sim = T.sim(store)
        sim.release(store.ordered)
        T.run(sim, store, until: 1.2)
        #expect(sim.members.values.allSatisfy { $0.meetCd > 6 - 1.3 && $0.meetCd <= 16 })
    }

    // MARK: - Sidekicks (subagents)

    @Test("A subagent pops in as a sidekick with yellow sparkles, follows at 140 pt/s, types when still, poofs on stop")
    func sidekick() throws {
        let store = T.sessions(1)
        let sim = Self.landed(store)
        #expect(sim.members["s0"]?.side == nil)
        let yellow = { sim.particles.filter { $0.color == RGB(0xFFEC27) && $0.kind == .spark }.count }
        let y0 = yellow()
        store.apply(Self.ev(.subagentStart, "s0", agent: "a1"), now: 1)
        T.run(sim, store, until: sim.time + 1.0 / 120)
        let side = try #require(sim.members["s0"]?.side)
        #expect(side.count == 1)
        #expect(yellow() - y0 >= 6)

        // It follows: never faster than 140 pt/s, ends up at x − face·11·S, y + 3.
        sim.modify("s0") { $0.x = 300; $0.y = 400; $0.phase = .act; $0.timer = 100 }
        var last = try #require(sim.members["s0"]?.side)
        for _ in 0..<(8 * 120) {
            T.run(sim, store, until: sim.time + 1.0 / 120)
            let s = try #require(sim.members["s0"]?.side)
            #expect(hypot(s.x - last.x, s.y - last.y) <= 140.0 / 120 + 1e-6)
            last = s
        }
        let m = try #require(sim.members["s0"])
        #expect(abs(last.x - (m.x - m.face * 11 * 3)) <= 3 && abs(last.y - (m.y + 3)) <= 3)
        #expect(!last.moving && last.pose == .type && last.face == m.face)

        store.apply(Self.ev(.subagentStart, "s0", agent: "a2"), now: 2)
        T.run(sim, store, until: sim.time + 0.1)
        #expect(sim.members["s0"]?.side?.count == 2)

        store.apply(Self.ev(.subagentStop, "s0", agent: "a1"), now: 3)
        store.apply(Self.ev(.subagentStop, "s0", agent: "a2"), now: 3)
        let sparks = sim.particles.filter { $0.kind == .spark }.count
        T.run(sim, store, until: sim.time + 1.0 / 120)
        #expect(sim.members["s0"]?.side == nil)
        #expect(sim.particles.filter { $0.kind == .spark }.count - sparks >= 5)
    }

    @Test("Sidekicks go home with the crew")
    func sidekickRecall() {
        let store = T.sessions(1)
        store.apply(Self.ev(.subagentStart, "s0", agent: "a1"), now: 1)
        let sim = Self.landed(store)
        #expect(sim.members["s0"]?.side != nil)
        sim.recall()
        T.run(sim, store, until: sim.time + 0.1)
        #expect(sim.members["s0"]?.side == nil)
    }

    @Test("Particles stay capped under a storm of activity")
    func cap() {
        let store = T.sessions(12)
        let sim = Self.landed(store)
        for i in 0..<12 { store.apply(Self.ev(.stop, "s\(i)", project: "p\(i)"), now: 1) }
        T.run(sim, store, until: 4)
        #expect(sim.particles.count <= Limits.particles)
    }
}
