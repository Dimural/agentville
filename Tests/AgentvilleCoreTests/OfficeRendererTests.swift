import Foundation
import Testing
@testable import AgentvilleCore

/// Golden tests for the office: the prototype's own `drawOffice` / `screenFor`, exported from a real
/// browser canvas by Tools/fixtures/export-office.mjs.
@Suite("Office matches the prototype")
struct OfficeRendererTests {
    struct Fixture: Decodable {
        struct Screen: Decodable { let status: String; let act: String?; let seed: UInt32; let steps: [[String]] }
        struct Screens: Decodable { let palette: [String: String]; let items: [Screen] }
        struct Desk: Decodable { let id: Int; let name, status: String; let act: String?; let sub: Bool; let seed: UInt32; let away: Bool }
        struct Frame: Decodable { let scene: String; let night: Bool; let t: Double; let clock: [Int]; let pixels: String }
        let screens: Screens
        let scenes: [String: [Desk]]
        let palette: [String]
        let frames: [Frame]
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "office-vectors", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    static func state(_ status: String, _ act: String?) -> OfficeScene.DeskState {
        switch status {
        case "waiting": .needsYou
        case "done": .finished
        case "idle": .idle
        default: .working(OfficeScene.Act(rawValue: act ?? "think")!)
        }
    }

    static func rle(_ c: PixelCanvas, palette: [String: String]) -> [String] {
        let byHex = Dictionary(uniqueKeysWithValues: palette.map { ($0.value, $0.key) })
        return (0..<c.height).map { y in
            var out = "", run: Character = " ", n = 0
            for x in 0..<c.width {
                let ch: Character = c.color(x: x, y: y).map { Character(byHex[$0.hex] ?? "?") } ?? "."
                if ch == run { n += 1 } else { if n > 0 { out += "\(run)\(n)" }; run = ch; n = 1 }
            }
            return out + "\(run)\(n)"
        }
    }

    @Test("Every monitor screen matches at 24 animation steps")
    func screens() throws {
        let f = Self.fixture.screens
        #expect(f.items.count == 10)
        let look = LookGenerator.look(for: "blog")
        for item in f.items {
            let desk: OfficeScene.Desk? = item.status == "away" ? nil
                : OfficeScene.Desk(look: look, state: Self.state(item.status, item.act), seed: item.seed)
            for (k, want) in item.steps.enumerated() {
                var c = PixelCanvas(width: 32, height: 20)
                OfficeRenderer.drawScreen(&c, desk: desk, sx: 0, sy: 0, t: Double(k) / 4)
                let got = Self.rle(c, palette: f.palette)
                #expect(got == want, "\(item.status)/\(item.act ?? "-") step \(k): first bad row \(want.indices.first { $0 >= got.count || want[$0] != got[$0] } ?? -1)")
            }
        }
    }

    @Test("Whole office frames match, day and night", arguments: fixture.frames.indices)
    func frame(index: Int) throws {
        let fx = Self.fixture, frame = fx.frames[index]
        let desks = try #require(fx.scenes[frame.scene])
        var scene = OfficeScene(night: frame.night, clock: (hour: frame.clock[0], minute: frame.clock[1]))
        scene.desks = desks.map {
            OfficeScene.Desk(look: LookGenerator.look(for: $0.name), state: Self.state($0.status, $0.act),
                             seed: $0.seed, subagent: $0.sub, away: $0.away)
        }
        let got = OfficeRenderer.render(scene, t: frame.t)
        #expect(got.width == OfficeRenderer.pixelSize.width && got.height == OfficeRenderer.pixelSize.height)

        let packed = try #require(Data(base64Encoded: frame.pixels))
        let indices = try (packed as NSData).decompressed(using: .zlib) as Data
        #expect(indices.count == got.width * got.height)
        let palette = fx.palette.map(RGB.init)
        var bad: [String] = [], badCount = 0
        for (i, idx) in indices.enumerated() {
            let want = palette[Int(idx)], x = i % got.width, y = i / got.width
            let have = got.color(x: x, y: y)
            if have != want {
                badCount += 1
                if bad.count < 12 { bad.append("(\(x),\(y)) want \(want.hex) got \(have?.hex ?? "clear")") }
            }
        }
        #expect(badCount == 0, "\(frame.scene) \(frame.night ? "night" : "day") t=\(frame.t): \(badCount) pixels differ: \(bad.joined(separator: "; "))")
    }

    @Test("Sessions map onto desk states (Core activities → prototype acts)")
    func sessionMapping() {
        let cases: [(SessionStatus, OfficeScene.DeskState)] = [
            (.idle, .idle), (.needsYou, .needsYou), (.finished, .finished), (.error, .error),
            (.working(.editing), .working(.edit)), (.working(.reading), .working(.read)),
            (.working(.running), .working(.bash)), (.working(.searching), .working(.search)),
            (.working(.web), .working(.web)), (.working(.thinking), .working(.think)),
            (.working(.planning), .working(.plan)), (.working(.tinkering), .working(.tinker)),
            (.working(.working), .working(.other)),
        ]
        for (status, want) in cases { #expect(OfficeScene.DeskState(status) == want, "\(status)") }
        #expect(SessionStatus.allCasesForTests.count == cases.count)
    }

    @Test("Scene from the store: first 6 sessions get desks, the rest count as more below")
    func sceneFromStore() {
        let st = SessionStore()
        for i in 0..<9 {
            st.apply(WireEvent(event: .preToolUse, session: "s\(i)", project: "p\(i)", tool: "Edit", ts: 0), now: 0)
        }
        st.apply(WireEvent(event: .subagentStart, session: "s1", project: "p1", agentId: "a", ts: 0), now: 0)
        let scene = OfficeScene(sessions: st.ordered, night: false, clock: (10, 0))
        #expect(scene.desks.count == Limits.desks)
        #expect(scene.moreBelow == 3)
        #expect(scene.desks[1]?.subagent == true && scene.desks[0]?.subagent == false)
        #expect(scene.desks[0]?.seed == scene.desks[0]?.seed && scene.desks[0]?.seed != scene.desks[2]?.seed)
    }

    @Test("A frame renders fast enough for 12 fps with headroom")
    func speed() {
        var scene = OfficeScene(night: false, clock: (10, 8))
        scene.desks = (0..<6).map { OfficeScene.Desk(look: LookGenerator.look(for: "p\($0)"), state: .working(.edit), seed: UInt32($0)) }
        let cache = SpriteCache()
        _ = OfficeRenderer.render(scene, t: 0, cache: cache)
        let t0 = Date()
        for i in 0..<24 { _ = OfficeRenderer.render(scene, t: Double(i) / 12, cache: cache) }
        let perFrame = Date().timeIntervalSince(t0) / 24
        // Debug build; release is several times faster. Budget: well under the 83 ms frame interval.
        #expect(perFrame < 0.02, "office frame took \(perFrame * 1000) ms")
    }
}

extension SessionStatus {
    static var allCasesForTests: [SessionStatus] {
        [.idle, .needsYou, .finished, .error] + Activity.allCases.map { .working($0) }
    }
}
