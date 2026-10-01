import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

@Suite("Tool → activity mapping")
struct ActivityMappingTests {
    @Test func knownTools() {
        #expect(ActivityMapping.activity(forTool: "Read") == .reading)
        #expect(ActivityMapping.activity(forTool: "MultiEdit") == .editing)
        #expect(ActivityMapping.activity(forTool: "Bash") == .running)
        #expect(ActivityMapping.activity(forTool: "Glob") == .searching)
        #expect(ActivityMapping.activity(forTool: "WebFetch") == .web)
        #expect(ActivityMapping.activity(forTool: "TodoWrite") == .planning)
        #expect(ActivityMapping.activity(forTool: "mcp") == .tinkering)
    }

    @Test func fallbacks() {
        #expect(ActivityMapping.activity(forTool: "SomeNewTool") == .working)
        #expect(ActivityMapping.activity(forTool: "other") == .working)
        #expect(ActivityMapping.activity(forTool: nil) == .thinking)
        #expect(ActivityMapping.activity(forTool: "Task") == nil)
        #expect(ActivityMapping.activity(forTool: "Agent") == nil)
    }

    @Test func labels() {
        #expect(Activity.web.label == "On the web")
        #expect(Set(Activity.allCases.map(\.label)).count == Activity.allCases.count)
    }

    /// Docs and code must not drift: parse the mapping table in sessions-and-states.md.
    @Test("Code matches the table in docs/product/sessions-and-states.md")
    func matchesDocTable() throws {
        let doc = try readRepoFile("docs/product/sessions-and-states.md")
        let section = try #require(doc.components(separatedBy: "## Tool → activity mapping").last)
        let rows = section.split(separator: "\n").filter { $0.hasPrefix("| `") }
        var checked = 0
        for row in rows {
            let cols = row.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 2 else { continue }
            let tools = cols[0].components(separatedBy: "`").enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            let act = cols[1].replacingOccurrences(of: "`", with: "")
            for tool in tools {
                let got = ActivityMapping.activity(forTool: tool)
                if act.hasPrefix("*(no change)") {
                    #expect(got == nil, "\(tool) should not change activity")
                } else {
                    #expect(got?.rawValue == act, "\(tool): doc says \(act), code says \(String(describing: got))")
                }
                checked += 1
            }
        }
        #expect(checked >= 25, "expected to check the whole table, checked \(checked)")
    }
}
