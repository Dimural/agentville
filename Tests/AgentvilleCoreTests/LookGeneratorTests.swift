import Foundation
import Testing
@testable import AgentvilleCore

/// Golden tests against vectors generated from the prototype's own `hash`/`rng`/`lookFor`
/// (docs/reference/README.md#how-to-regenerate-fixtures-from-the-prototype).
@Suite("Looks match the prototype")
struct LookGeneratorTests {
    struct Fixture: Decodable {
        struct Vector: Decodable { let name: String; let hash: UInt32; let look: [String: String] }
        let vectors: [Vector]
    }

    static func load() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "look-vectors", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureIsSubstantial() throws {
        #expect(try Self.load().vectors.count >= 16)
    }

    @Test("Hash matches JS FNV-1a over UTF-16")
    func hashes() throws {
        for v in try Self.load().vectors {
            #expect(LookHash.fnv1a(v.name) == v.hash, "\(v.name)")
        }
    }

    @Test("Every look field matches the prototype")
    func looks() throws {
        for v in try Self.load().vectors {
            let L = LookGenerator.look(for: v.name)
            let got: [String: String] = [
                "skin": L.skin.hex, "hair": L.hair.hex, "style": L.style.rawValue, "acc": L.acc.rawValue,
                "shirt": L.shirt.hex, "pants": L.pants.hex, "shoe": L.shoe.hex, "cap": L.cap.hex,
                "pattern": L.pattern.rawValue, "rest": L.rest.rawValue, "desk": L.desk.rawValue,
                "skinD": L.skinD.hex, "hairD": L.hairD.hex, "hairL": L.hairL.hex, "shirtD": L.shirtD.hex,
                "shirtL": L.shirtL.hex, "pantsD": L.pantsD.hex, "capD": L.capD.hex, "capL": L.capL.hex, "blush": L.blush.hex,
            ]
            for (k, want) in v.look {
                #expect(got[k] == want.lowercased(), "\(v.name).\(k): want \(want), got \(got[k] ?? "nil")")
            }
        }
    }

    @Test func deterministic() {
        #expect(LookGenerator.look(for: "agentville") == LookGenerator.look(for: "agentville"))
    }

    @Test func invariants() {
        for i in 0..<2000 {
            let L = LookGenerator.look(for: "project-\(i)")
            #expect(L.cap != L.shirt)
            if L.style == .cap || L.style == .beanie { #expect(L.acc != .headphones) }
        }
    }
}
