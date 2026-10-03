import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// Grabbing the crew (docs/architecture/input-and-safety.md): ports of `hitBox`, `hitTest`, the
/// pointer handlers, `endDrag`, the `thrown` mode and `settle`.
@Suite("Crew grabbing")
struct CrewGrabTests {
    typealias T = CrewSimTests

    /// One working character landed at (500, 500), acting (not walking) for a long while.
    static func landed(_ n: Int = 1) -> (SessionStore, CrewSim) {
        let store = T.sessions(n), sim = T.sim(store)
        sim.release(store.ordered)
        T.run(sim, store, until: 2)
        for i in 0..<n {
            sim.modify("s\(i)") { $0.x = 500 + Double(i) * 10; $0.y = 500 + Double(i) * 10; $0.phase = .act; $0.timer = 100; $0.tx = $0.x; $0.ty = $0.y }
        }
        return (store, sim)
    }

    @Test("Hit box: feet at (x, y), 8·S either side, 24·S tall, plus padding (port of hitBox)")
    func hitBox() {
        let (_, sim) = Self.landed()
        // S = 3: x in (476, 524) ± 4, y in (500 − 72, 500) ± 4.
        #expect(sim.hitTest(x: 500, y: 450) == "s0")
        #expect(sim.hitTest(x: 527, y: 450) == "s0")
        #expect(sim.hitTest(x: 529, y: 450) == nil)
        #expect(sim.hitTest(x: 500, y: 503) == "s0")
        #expect(sim.hitTest(x: 500, y: 505) == nil)
        #expect(sim.hitTest(x: 500, y: 425) == "s0")
        #expect(sim.hitTest(x: 500, y: 423) == nil)
    }

    @Test("The front-most (lowest on screen) character wins; flying ones can't be grabbed")
    func frontMost() {
        let (store, sim) = Self.landed(2)
        #expect(sim.hitTest(x: 505, y: 480) == "s1")
        sim.recall()
        T.run(sim, store, until: sim.time + 0.2)
        #expect(sim.hitTest(x: 505, y: 480) == nil)
    }

    @Test("Click-through decision: capture only with ⌥ held over a character, or mid-drag")
    func capture() {
        let (_, sim) = Self.landed()
        #expect(!sim.capturesMouse(optionHeld: false, x: 500, y: 450))
        #expect(!sim.capturesMouse(optionHeld: true, x: 100, y: 100))
        #expect(sim.capturesMouse(optionHeld: true, x: 500, y: 450))
        sim.grab("s0", x: 500, y: 450, at: 0)
        #expect(sim.capturesMouse(optionHeld: false, x: 100, y: 100))
        sim.endDrag(cancel: true)
        #expect(!sim.capturesMouse(optionHeld: false, x: 500, y: 450))
    }

    @Test("A drag lifts and dangles the character, which follows the cursor with its grab offset")
    func drag() throws {
        let (store, sim) = Self.landed()
        sim.grab("s0", x: 505, y: 460, at: 0)
        var m = try #require(sim.members["s0"])
        #expect(m.mode == .drag && m.z == 10 && m.bubble == nil)
        sim.dragTo(x: 705, y: 560, at: 0.1)
        T.run(sim, store, until: sim.time + 0.05)
        m = try #require(sim.members["s0"])
        // x = p.x + ox, y = p.y + oy + 10 (prototype pointermove).
        #expect(m.x == 700 && m.y == 610)
        #expect(m.pose == .dangle)
        // Clamped to the screen and the walkable band.
        sim.dragTo(x: -100, y: 5, at: 0.2)
        m = try #require(sim.members["s0"])
        #expect(m.x == 20 && m.y == T.stage.minY)
    }

    @Test("A tap (< 5 pt of movement): a happy hop, a phrase and pink sparkles")
    func tap() throws {
        let (store, sim) = Self.landed()
        sim.grab("s0", x: 500, y: 450, at: 0)
        sim.dragTo(x: 502, y: 451, at: 0.05)
        let sparks = sim.particles.count
        sim.endDrag(cancel: false)
        let m = try #require(sim.members["s0"])
        #expect(m.mode == .rest && m.z == 0)
        #expect(Phrases.tap.contains(m.bubble?.text ?? ""))
        #expect(sim.particles.count - sparks == 4)
        T.run(sim, store, until: sim.time + 0.1)
        #expect(sim.members["s0"]?.pose == .cheer)
    }

    @Test("A throw: velocity from the samples (capped at 1500 pt/s), lifts, bounces, slides and settles")
    func throwIt() throws {
        let (store, sim) = Self.landed()
        sim.grab("s0", x: 500, y: 450, at: 0)
        for i in 1...8 { sim.dragTo(x: 500 + Double(i) * 10, y: 450, at: Double(i) * 0.01) }
        sim.endDrag(cancel: false)
        var m = try #require(sim.members["s0"])
        guard case .thrown(let vx, let vy, let hard) = m.mode else { Issue.record("not thrown: \(m.mode)"); return }
        // 6 samples kept: first at t=0.03 (x 530), last at 0.08 (x 580) → 1000 pt/s.
        #expect(abs(vx - 1000) < 0.001 && vy == 0 && hard)
        #expect(abs(m.vz - 350) < 0.001)
        #expect(Phrases.throwShout.contains(m.bubble?.text ?? ""))
        T.run(sim, store, until: sim.time + 0.1)
        #expect(sim.members["s0"]?.pose == .dangle)
        // It comes down, slides to a stop, then is dizzy (> 900 pt/s) for 1.8 s.
        var sawDizzy = false
        while sim.time < 12 {
            T.run(sim, store, until: sim.time + 0.05)
            m = try #require(sim.members["s0"])
            if m.pose == .dizzy { sawDizzy = true }
            #expect(m.x >= 24 - 0.001 && m.x <= T.stage.width - 24 + 0.001)
        }
        #expect(sawDizzy)
        #expect(sim.members["s0"]?.mode == .rest)
    }

    @Test("Throw speed is capped at 1500 pt/s")
    func cap() throws {
        let (_, sim) = Self.landed()
        sim.grab("s0", x: 500, y: 450, at: 0)
        sim.dragTo(x: 900, y: 450, at: 0.016)
        sim.endDrag(cancel: false)
        guard case .thrown(let vx, _, _) = try #require(sim.members["s0"]).mode else { Issue.record("not thrown"); return }
        #expect(abs(vx - 1500) < 0.001)
    }

    @Test("A gentle throw (≤ 900 pt/s) isn't dizzying, and ≤ 700 says nothing")
    func gentle() throws {
        let (store, sim) = Self.landed()
        sim.grab("s0", x: 500, y: 450, at: 0)
        sim.dragTo(x: 530, y: 450, at: 0.1) // 300 pt/s
        sim.endDrag(cancel: false)
        #expect(sim.members["s0"]?.bubble == nil)
        var poses: Set<Pose> = []
        while sim.time < 8 { T.run(sim, store, until: sim.time + 0.05); poses.insert(sim.members["s0"]?.pose ?? .idle) }
        #expect(!poses.contains(.dizzy))
    }

    @Test("Hover fade: the character under the cursor eases to 16%, and back when grab mode is on")
    func hover() throws {
        let (store, sim) = Self.landed()
        sim.pointer = (500, 450)
        T.run(sim, store, until: sim.time + 0.6)
        #expect(abs(try #require(sim.members["s0"]).alpha - Motion.hoverAlpha) < 0.01)
        sim.grabMode = true
        T.run(sim, store, until: sim.time + 0.6)
        #expect(abs(try #require(sim.members["s0"]).alpha - 1) < 0.01)
        sim.grabMode = false
        sim.pointer = nil
        T.run(sim, store, until: sim.time + 0.6)
        #expect(abs(try #require(sim.members["s0"]).alpha - 1) < 0.01)
    }

    @Test("Recall from mid-drag and mid-throw still completes within 2.6 s", arguments: [false, true])
    func recallWhileHeld(thrown: Bool) {
        let (store, sim) = Self.landed(3)
        sim.grab("s0", x: 500, y: 450, at: 0)
        if thrown {
            sim.dragTo(x: 900, y: 300, at: 0.05)
            sim.endDrag(cancel: false)
            T.run(sim, store, until: sim.time + 0.1)
        }
        let start = sim.time
        sim.recall()
        #expect(sim.dragging == nil)
        T.run(sim, store, until: start + Timing.recallForceComplete)
        #expect(sim.members.isEmpty)
    }
}
