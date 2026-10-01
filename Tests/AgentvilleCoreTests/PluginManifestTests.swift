import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// The plugin must register exactly the events the wire schema knows, always async and silent.
@Suite("Plugin manifest")
struct PluginManifestTests {
    func hooks() throws -> [String: [[String: Any]]] {
        let data = Data(try readRepoFile("Plugin/agentville/hooks/hooks.json").utf8)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(obj["hooks"] as? [String: [[String: Any]]])
    }

    @Test("Registered events == WireEvent.Kind.allCases")
    func eventsMatch() throws {
        #expect(Set(try hooks().keys) == Set(WireEvent.Kind.allCases.map(\.rawValue)))
    }

    @Test("Every hook is async, shell-form, silent when the helper is missing, and ends in exit 0")
    func hookShape() throws {
        for (event, matchers) in try hooks() {
            for m in matchers {
                let hs = try #require(m["hooks"] as? [[String: Any]])
                for h in hs {
                    #expect(h["type"] as? String == "command", "\(event)")
                    #expect(h["async"] as? Bool == true, "\(event) must be async")
                    #expect(h["args"] == nil, "\(event) must use shell form (exec form errors when the binary is missing)")
                    let cmd = try #require(h["command"] as? String)
                    #expect(cmd.hasSuffix("exit 0"), "\(event)")
                    #expect(cmd.contains("[ -x \"$h\" ]"), "\(event)")
                    #expect(cmd.contains("cat >/dev/null"), "\(event) must drain stdin when absent")
                }
            }
        }
    }

    @Test("Plugin and marketplace names agree")
    func names() throws {
        let plugin = try #require(try JSONSerialization.jsonObject(with: Data(try readRepoFile("Plugin/agentville/.claude-plugin/plugin.json").utf8)) as? [String: Any])
        let market = try #require(try JSONSerialization.jsonObject(with: Data(try readRepoFile(".claude-plugin/marketplace.json").utf8)) as? [String: Any])
        let entries = try #require(market["plugins"] as? [[String: Any]])
        #expect(plugin["name"] as? String == "agentville")
        #expect(entries.first?["name"] as? String == plugin["name"] as? String)
        #expect(entries.first?["source"] as? String == "./Plugin/agentville")
    }
}
