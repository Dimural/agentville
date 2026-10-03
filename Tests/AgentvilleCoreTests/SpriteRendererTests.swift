import Foundation
import Testing
@testable import AgentvilleCore

/// Golden tests: every frame must be pixel-identical to the prototype's own `sprite()` output,
/// exported from a real browser canvas by Tools/fixtures/export-sprites.mjs.
@Suite("Sprites match the prototype")
struct SpriteRendererTests {
    struct Fixture: Decodable {
        struct Sprite: Decodable { let pose: String; let frame: Int; let highlight: Bool; let rows: [String] }
        struct LookVector: Decodable {
            let name, style, acc, pattern: String
            let palette: [String: String]
            let sprites: [Sprite]
        }
        struct Emote: Decodable { let kind: String; let dots: Int?; let rows: [String] }
        struct Emotes: Decodable { let palette: [String: String]; let items: [Emote] }
        let poses: [String]
        let looks: [LookVector]
        let emotes: Emotes
    }

    static let fixture: Fixture = {
        let url = Bundle.module.url(forResource: "sprite-vectors", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }()

    /// Encodes a canvas with the fixture's palette ('.' = transparent, '?' = a colour the prototype never drew).
    static func rows(_ c: PixelCanvas, palette: [String: String]) -> [String] {
        let byHex = Dictionary(uniqueKeysWithValues: palette.map { ($0.value, $0.key) })
        return (0..<c.height).map { y in
            String((0..<c.width).map { x -> Character in
                guard let col = c.color(x: x, y: y) else { return "." }
                return Character(byHex[col.hex] ?? "?")
            })
        }
    }

    static func diff(_ want: [String], _ got: [String]) -> String {
        zip(want, got).enumerated().map { i, p in "\(String(format: "%2d", i)) \(p.0)  \(p.1)\(p.0 == p.1 ? "" : "  <")" }
            .joined(separator: "\n")
    }

    @Test("Fixture covers every pose, style, accessory and pattern")
    func coverage() {
        let f = Self.fixture
        #expect(Set(f.poses) == Set(Pose.prototypePoses.map(\.rawValue)))
        #expect(Set(f.looks.map(\.style)) == Set(Look.HairStyle.allCases.map(\.rawValue)))
        #expect(Set(f.looks.map(\.acc)) == Set(Look.Accessory.allCases.map(\.rawValue)))
        #expect(Set(f.looks.map(\.pattern)) == Set(Look.Pattern.allCases.map(\.rawValue)))
        for L in f.looks {
            #expect(L.sprites.filter { !$0.highlight }.count == Pose.prototypePoses.reduce(0) { $0 + $1.frameCount })
        }
    }

    @Test("Every pose and frame is pixel-identical to the prototype", arguments: fixture.looks.map(\.name))
    func frames(name: String) throws {
        let vec = try #require(Self.fixture.looks.first { $0.name == name })
        let look = LookGenerator.look(for: name)
        #expect(look.style.rawValue == vec.style && look.acc.rawValue == vec.acc && look.pattern.rawValue == vec.pattern)
        for s in vec.sprites {
            let pose = try #require(Pose(rawValue: s.pose))
            let got = Self.rows(SpriteRenderer.render(look, pose, frame: s.frame, highlight: s.highlight), palette: vec.palette)
            #expect(got == s.rows, "\(name) \(s.pose)[\(s.frame)]\(s.highlight ? " highlight" : ""):\n\(Self.diff(s.rows, got))")
        }
    }

    @Test("Sprite geometry: 28x28, transparent border row, feet near the anchor")
    func geometry() {
        let c = SpriteRenderer.render(LookGenerator.look(for: "api-server"), .idle, frame: 0)
        #expect(c.width == SpriteRenderer.size && c.height == SpriteRenderer.size)
        #expect((0..<c.width).allSatisfy { !c.isOpaque(x: $0, y: c.height - 1) })
        #expect(c.isOpaque(x: SpriteRenderer.anchor.x, y: SpriteRenderer.anchor.y - 1))
    }

    @Test("Frame numbers wrap instead of trapping")
    func frameWrap() {
        let L = LookGenerator.look(for: "blog")
        #expect(SpriteRenderer.render(L, .walk, frame: 5) == SpriteRenderer.render(L, .walk, frame: 1))
        #expect(SpriteRenderer.render(L, .wave, frame: -1) == SpriteRenderer.render(L, .wave, frame: 1))
    }

    @Test("Avatar is the idle head crop (5, 1, 13, 14)")
    func avatar() throws {
        for vec in Self.fixture.looks {
            let idle = try #require(vec.sprites.first { $0.pose == "idle" && $0.frame == 0 && !$0.highlight })
            let want = idle.rows[1..<15].map { String(Array($0)[5..<18]) }
            let got = Self.rows(SpriteRenderer.avatar(LookGenerator.look(for: vec.name)), palette: vec.palette)
            #expect(got == want, "\(vec.name) avatar:\n\(Self.diff(want, got))")
        }
    }

    @Test("Emote bubbles match the prototype's drawEmote at scale 1")
    func emotes() throws {
        let e = Self.fixture.emotes
        #expect(e.items.count == 8)
        for item in e.items {
            let emote: Emote = switch item.kind {
            case "dots": .dots(try #require(item.dots))
            default: try #require(Emote.icon(rawValue: item.kind))
            }
            let got = Self.rows(SpriteRenderer.emote(emote), palette: e.palette)
            #expect(got == item.rows, "\(item.kind) \(item.dots ?? -1):\n\(Self.diff(item.rows, got))")
        }
    }

    @Test("Sprite cache returns identical frames and stays bounded")
    func cache() {
        let cache = SpriteCache(capacity: 50)
        let L = LookGenerator.look(for: "api-server")
        let a = cache.sprite(L, .walk, frame: 1, highlight: false)
        #expect(a == SpriteRenderer.render(L, .walk, frame: 1))
        #expect(cache.sprite(L, .walk, frame: 1, highlight: false) == a)
        #expect(cache.hits == 1 && cache.misses == 1)
        for i in 0..<300 { _ = cache.sprite(LookGenerator.look(for: "p\(i)"), .idle, frame: 0, highlight: false) }
        #expect(cache.count <= 50)
        // Recently used entries survive eviction.
        for i in 0..<40 {
            _ = cache.sprite(L, .idle, frame: 0, highlight: false)
            _ = cache.sprite(LookGenerator.look(for: "q\(i)"), .idle, frame: 0, highlight: false)
        }
        let before = cache.misses
        _ = cache.sprite(L, .idle, frame: 0, highlight: false)
        #expect(cache.misses == before)
    }
}
