import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// Agentville's own poses, for states the prototype never drew (open question 12): planning
/// (clipboard), MCP tools (gadget and wrench) and a failed turn (head scratch under a storm cloud).
/// There are no prototype exports to compare with, so these check the art's structure; the owner
/// reviews the look (docs/design/sprites-and-poses.md#agentvilles-own-poses).
@Suite("Agentville's own poses")
struct AgentvillePosesTests {
    static let look = LookGenerator.look(for: "api-server")

    static func colors(_ c: PixelCanvas) -> Set<RGB> {
        var s = Set<RGB>()
        for y in 0..<c.height { for x in 0..<c.width { if let k = c.color(x: x, y: y) { s.insert(k) } } }
        return s
    }

    @Test("The prototype's poses and Agentville's own split every pose exactly once")
    func split() {
        #expect(Set(Pose.prototypePoses).isDisjoint(with: Pose.agentvillePoses))
        #expect(Pose.prototypePoses.count + Pose.agentvillePoses.count == Pose.allCases.count)
    }

    @Test("Each new pose: 2 distinct frames, inside the frame, feet on the anchor, same head as idle", arguments: Pose.agentvillePoses)
    func structure(pose: Pose) {
        let f0 = SpriteRenderer.render(Self.look, pose, frame: 0), f1 = SpriteRenderer.render(Self.look, pose, frame: 1)
        #expect(pose.frameCount == 2)
        #expect(f0 != f1)
        for c in [f0, f1] {
            #expect((0..<c.width).allSatisfy { !c.isOpaque(x: $0, y: c.height - 1) && !c.isOpaque(x: $0, y: 0) })
            #expect((0..<c.height).allSatisfy { !c.isOpaque(x: 0, y: $0) && !c.isOpaque(x: c.width - 1, y: $0) })
            #expect(c.isOpaque(x: SpriteRenderer.anchor.x, y: SpriteRenderer.anchor.y - 1))
        }
        // Same character: its hair colour and skin are still there.
        let idle = Self.colors(SpriteRenderer.render(Self.look, .idle, frame: 0))
        #expect(Self.colors(f0).isSuperset(of: [Self.look.skin, Self.look.shirt]))
        #expect(idle.contains(Self.look.skin))
    }

    @Test("Planning holds a clipboard; the second tick lands in frame 2")
    func plan() {
        let f0 = Self.colors(SpriteRenderer.render(Self.look, .plan, frame: 0))
        #expect(f0.isSuperset(of: [RGB(0xB07A45), RGB(0xFFF4E6), RGB(0x0B9A4B)]))
        let ticks = { (f: Int) in
            let c = SpriteRenderer.render(Self.look, .plan, frame: f)
            return (0..<c.height).flatMap { y in (0..<c.width).filter { c.color(x: $0, y: y) == RGB(0x0B9A4B) } }.count
        }
        #expect(ticks(1) == ticks(0) + 1)
    }

    @Test("Tinkering: a gadget whose light blinks red then green, and a wrench")
    func tinker() {
        let f0 = Self.colors(SpriteRenderer.render(Self.look, .tinker, frame: 0))
        let f1 = Self.colors(SpriteRenderer.render(Self.look, .tinker, frame: 1))
        #expect(f0.isSuperset(of: [RGB(0x3A3F5C), RGB(0xFF004D), SpriteRenderer.metal]))
        #expect(f1.contains(RGB(0x00E436)) && !f1.contains(RGB(0xFF004D)))
    }

    @Test("Error: a frown and a sweat drop; the storm cloud emote is grey with an orange bolt")
    func error() {
        let f0 = Self.colors(SpriteRenderer.render(Self.look, .error, frame: 0))
        #expect(f0.isSuperset(of: [RGB(0x8FD3FF), RGB(0x7A1F35)]))
        let storm = Self.colors(SpriteRenderer.emote(.icon(.storm)))
        #expect(storm.isSuperset(of: [RGB(0x6E7690), RGB(0xFFA300)]))
    }

    // MARK: - In the office

    static func office(_ state: OfficeScene.DeskState, t: Double = 1.3) -> PixelCanvas {
        var scene = OfficeScene(night: false, clock: (10, 0))
        scene.desks = [OfficeScene.Desk(look: look, state: state, seed: 1)]
        return OfficeRenderer.render(scene, t: t)
    }

    @Test("The office draws the new states with their own pose, screen and emote, not the old fallbacks")
    func office() {
        let think = Self.office(.working(.think)), other = Self.office(.working(.other))
        #expect(Self.office(.working(.plan)) != think)
        #expect(Self.office(.working(.tinker)) != other)
        #expect(Self.office(.error) != think)
        #expect(OfficeRenderer.pose(for: .error, t: 0).pose == .error)
        #expect(OfficeRenderer.pose(for: .error, t: 0).emote == .icon(.storm))
        #expect(OfficeRenderer.pose(for: .working(.plan), t: 0).pose == .plan)
        #expect(OfficeRenderer.pose(for: .working(.tinker), t: 0).pose == .tinker)
        // The error screen is a steady red cross: the same at any time.
        var a = PixelCanvas(width: 40, height: 30), b = a
        OfficeRenderer.drawScreen(&a, desk: OfficeScene.Desk(look: Self.look, state: .error, seed: 1), sx: 1, sy: 1, t: 0)
        OfficeRenderer.drawScreen(&b, desk: OfficeScene.Desk(look: Self.look, state: .error, seed: 1), sx: 1, sy: 1, t: 0.3)
        #expect(a == b && Self.colors(a).contains(RGB(0xFF004D)))
        // The checklist ticks itself off over time.
        var p0 = PixelCanvas(width: 40, height: 30), p1 = p0
        OfficeRenderer.drawScreen(&p0, desk: OfficeScene.Desk(look: Self.look, state: .working(.plan), seed: 1), sx: 1, sy: 1, t: 0)
        OfficeRenderer.drawScreen(&p1, desk: OfficeScene.Desk(look: Self.look, state: .working(.plan), seed: 1), sx: 1, sy: 1, t: 0.8)
        #expect(!Self.colors(p0).contains(RGB(0x0B9A4B)) && Self.colors(p1).contains(RGB(0x0B9A4B)))
    }

    // MARK: - On the desktop

    @Test("On the desktop: planning holds the clipboard, MCP tinkers with fizz, a failed turn slumps under a storm cloud")
    func desktop() throws {
        let store = SessionStore()
        for (id, tool) in [("plan", "TodoWrite"), ("mcp", "mcp")] {
            store.apply(WireEvent(event: .preToolUse, session: id, project: id, tool: tool, ts: 0), now: 0)
        }
        store.apply(WireEvent(event: .userPromptSubmit, session: "err", project: "err", ts: 0), now: 0)
        store.apply(WireEvent(event: .stopFailure, session: "err", project: "err", ts: 0), now: 0)
        #expect(store.sessions["err"]?.status == .error)
        let sim = CrewSim(stage: CrewSimTests.stage, seed: 3)
        sim.home = { _ in Home(x: 1200, y: 120, scale: 2) }
        sim.release(store.ordered)
        var poses: [String: Set<Pose>] = [:], emotes: [String: Set<Emote>] = [:]
        var fizz = false
        while sim.time < 30 {
            let before = sim.particles.count
            _ = sim.update(dt: 1.0 / 60, sessions: store.sessions)
            if sim.particles.count > before, sim.particles.suffix(sim.particles.count - before).contains(where: { $0.color == RGB(0x29ADFF) && $0.max == 0.3 }) { fizz = true }
            for m in sim.members.values {
                poses[m.id, default: []].insert(m.pose)
                if let e = m.emote { emotes[m.id, default: []].insert(e) }
            }
        }
        #expect(poses["plan"]?.contains(.plan) == true)
        #expect(poses["mcp"]?.contains(.tinker) == true)
        #expect(fizz)
        #expect(poses["err"]?.contains(.error) == true)
        #expect(emotes["err"]?.contains(.icon(.storm)) == true)
    }
}
