import Foundation
import Testing
@testable import AgentvilleCore

/// Every file in Tools/scenarios is an executable spec: run it through SessionStore and check its
/// `expect` lines. Raw datagrams go through WireCodec.decode, exactly like the app's socket path.
@Suite("Replay scenarios")
struct ScenarioTests {
    static let dir = repoRoot.appendingPathComponent("Tools/scenarios")

    static func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".jsonl") }.sorted()
    }

    @Test func thereAreScenarios() { #expect(Self.files().count >= 6) }

    @Test("Scenario passes its expectations", arguments: files())
    func run(file: String) throws {
        let text = try String(contentsOf: Self.dir.appendingPathComponent(file), encoding: .utf8)
        let scenario = try Scenario.parse(text)
        let store = SessionStore()
        var expectations = 0
        for (at, step) in scenario.steps {
            switch step {
            case .event(let e):
                // Same path as the app: encode → decode → apply.
                let wire = try #require(WireCodec.encode(e))
                if let decoded = WireCodec.decode(wire) { store.apply(decoded, now: at) }
            case .raw(let d):
                if let decoded = WireCodec.decode(d) { store.apply(decoded, now: at) }
            case .tick:
                store.tick(now: at)
            case .expect(let sid, let want):
                expectations += 1
                let got = Scenario.statusString(store.sessions[sid])
                #expect(got == want, "\(file) @\(at)s: \(sid) is \(got), expected \(want)")
            }
        }
        #expect(expectations > 0, "\(file) has no expect lines")
    }

    @Test("Parser rejects bad lines with a line number")
    func parseErrors() {
        #expect(throws: Scenario.ParseError.self) { try Scenario.parse(#"{"event":"Stop"}"#) }
        #expect(throws: Scenario.ParseError.self) { try Scenario.parse(#"{"at":1,"event":"Nope","session":"s","project":"p"}"#) }
        #expect(throws: Scenario.ParseError.self) { try Scenario.parse(#"{"at":1,"expect":{"session":"s"}}"#) }
        #expect((try? Scenario.parse("// only a comment\n\n"))?.steps.isEmpty == true)
    }

    @Test("Same-time lines keep file order")
    func stableOrder() throws {
        let s = try Scenario.parse("""
        {"at": 1, "event": "UserPromptSubmit", "session": "a", "project": "p"}
        {"at": 0, "event": "SessionStart", "session": "a", "project": "p"}
        {"at": 1, "expect": {"session": "a", "status": "working:thinking"}}
        """)
        guard case .event(let first) = s.steps[0].step else { Issue.record("first step not an event"); return }
        #expect(first.event == .sessionStart)
        guard case .expect = s.steps[2].step else { Issue.record("expect should stay after the prompt"); return }
    }
}
