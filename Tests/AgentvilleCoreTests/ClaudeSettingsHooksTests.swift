import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// Path B of Connect (docs/architecture/installation.md#path-b-settings-file-fallback-no-cli):
/// our hooks go into `~/.claude/settings.json` with the smallest possible edit, carry a marker, and
/// Disconnect gives back the file exactly as it was.
@Suite("Claude settings hooks (Path B)")
struct ClaudeSettingsHooksTests {
    typealias H = ClaudeSettingsHooks

    func object(_ text: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    /// Our command for each event, read back from a patched file.
    func ourCommands(_ text: String) throws -> [String: [String]] {
        let hooks = try object(text)["hooks"] as? [String: Any] ?? [:]
        var out: [String: [String]] = [:]
        for (event, groups) in hooks {
            for g in groups as? [[String: Any]] ?? [] {
                for h in g["hooks"] as? [[String: Any]] ?? [] {
                    if let c = h["command"] as? String, c.contains(H.marker) { out[event, default: []].append(c) }
                }
            }
        }
        return out
    }

    func expectConnected(_ text: String) throws {
        let ours = try ourCommands(text)
        #expect(Set(ours.keys) == Set(H.events))
        for (_, cmds) in ours { #expect(cmds == [H.command]) }
        #expect(H.isConnected(text))
    }

    /// Connect, check, Disconnect: the original comes back byte for byte.
    func roundTrip(_ original: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let connected = try H.connect(original)
        try expectConnected(connected)
        #expect(try H.connect(connected) == connected, "Connect twice changes nothing", sourceLocation: sourceLocation)
        #expect(try H.disconnect(connected) == original, sourceLocation: sourceLocation)
        #expect(!H.isConnected(original))
    }

    // MARK: - The command and the events

    @Test("Same events and the same silent shell command as the plugin, plus the marker")
    func matchesPlugin() throws {
        let data = Data(try readRepoFile("Plugin/agentville/hooks/hooks.json").utf8)
        let plugin = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["hooks"] as? [String: [[String: Any]]])
        #expect(Set(H.events) == Set(plugin.keys))
        #expect(Set(H.events) == Set(WireEvent.Kind.allCases.map(\.rawValue)))
        for (_, groups) in plugin {
            let cmd = try #require((groups.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
            #expect(H.command == cmd + " " + H.marker)
        }
        #expect(H.command.hasSuffix("exit 0 # agentville-hook"))
    }

    // MARK: - Connect

    @Test("No file, an empty file or only whitespace: a new file with just our hooks")
    func fresh() throws {
        for original in [nil, "", "  \n"] as [String?] {
            let text = try H.connect(original)
            try expectConnected(text)
            #expect(text.hasPrefix("{\n  \"hooks\": {\n    \"SessionStart\": [\n"))
            #expect(text.hasSuffix("}\n"))
            let group = try #require(((try object(text)["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.first)
            let hook = try #require((group["hooks"] as? [[String: Any]])?.first)
            #expect(hook["type"] as? String == "command")
            #expect(hook["async"] as? Bool == true)
        }
    }

    @Test("An empty object round-trips")
    func emptyObject() throws {
        try roundTrip("{}")
        try roundTrip("{}\n")
        // `{\n}` comes back as `{}`: an empty object's inside can't be told from one we filled.
        #expect(try H.disconnect(try H.connect("{\n}\n")) == "{}\n")
    }

    @Test("A typical file: other keys untouched and in order; hooks added last")
    func typical() throws {
        let original = """
        {
          "model": "opus",
          "permissions": {
            "allow": [
              "Bash(git status:*)"
            ]
          },
          "statusLine": {
            "type": "command",
            "command": "~/.claude/statusline.sh"
          }
        }

        """
        try roundTrip(original)
        let connected = try H.connect(original)
        // Everything up to the end of the last member is unchanged; ours follows it.
        let end = try #require(original.range(of: "statusline.sh\"\n  }")).upperBound
        let head = String(original[..<end])
        #expect(connected.hasPrefix(head + ",\n  \"hooks\": {\n    \"SessionStart\": [\n      {\n        \"hooks\": [\n"))
        #expect(try object(connected)["model"] as? String == "opus")
    }

    @Test("Existing hooks, some on the same events: theirs stay first and unchanged, ours are appended")
    func existingHooks() throws {
        let original = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "matcher": "Bash",
                "hooks": [
                  { "type": "command", "command": "~/bin/check-bash.sh" }
                ]
              }
            ],
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "say done" }
                ]
              }
            ],
            "PreCompact": [
              { "hooks": [ { "type": "command", "command": "echo compact" } ] }
            ]
          },
          "env": { "FOO": "bar" }
        }

        """
        try roundTrip(original)
        let connected = try H.connect(original)
        let hooks = try #require(try object(connected)["hooks"] as? [String: [[String: Any]]])
        #expect(hooks["PreToolUse"]?.count == 2)
        #expect(hooks["PreToolUse"]?.first?["matcher"] as? String == "Bash")
        #expect(hooks["Stop"]?.count == 2)
        #expect(hooks["PreCompact"]?.count == 1)
        #expect((try object(connected)["env"] as? [String: String]) == ["FOO": "bar"])
    }

    @Test("Unusual formatting: tabs, 4 spaces, CRLF, one line, a byte-order mark, odd spacing")
    func formatting() throws {
        try roundTrip("{\n\t\"model\": \"opus\"\n}\n")
        try roundTrip("{\n    \"model\": \"opus\",\n    \"hooks\": {\n        \"Stop\": [\n            {\"hooks\": []}\n        ]\n    }\n}")
        try roundTrip("{\r\n  \"model\": \"opus\"\r\n}\r\n")
        try roundTrip("{\"model\":\"opus\",\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"x\"}]}]}}")
        try roundTrip("\u{FEFF}{\n  \"model\": \"opus\"\n}\n")
        try roundTrip("{ \"model\" : \"opus\" , \"n\" : [ 1 , 2.5e3 , -0.1 , true , false , null ] }")
        // Their values with escapes and non-ASCII text come through byte for byte.
        try roundTrip("{\n  \"note\": \"caf\\u00e9 \\\"quoted\\\" \\\\ \\/ ✓ 日本\"\n}\n")
    }

    @Test("One-line files get one-line additions")
    func compact() throws {
        let connected = try H.connect("{\"model\":\"opus\"}")
        #expect(!connected.contains("\n"))
        try expectConnected(connected)
    }

    @Test("New output uses the file's indentation and line endings")
    func indentation() throws {
        let tabs = try H.connect("{\n\t\"model\": \"opus\"\n}\n")
        #expect(tabs.contains("\n\t\"hooks\": {\n\t\t\"SessionStart\": [\n"))
        let crlf = try H.connect("{\r\n  \"model\": \"opus\"\r\n}\r\n")
        #expect(!crlf.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    @Test("A partly connected file (they removed one of ours) gets only what's missing")
    func partial() throws {
        let full = try H.connect("{\n  \"model\": \"opus\"\n}\n")
        // Drop our Stop entry by hand.
        var obj = try object(full)
        var hooks = try #require(obj["hooks"] as? [String: Any])
        hooks["Stop"] = nil
        obj["hooks"] = hooks
        let edited = String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
        #expect(!H.isConnected(edited))
        let again = try H.connect(edited)
        try expectConnected(again)
        // Their text is kept up to the end of the hooks object's last member; ours follows.
        let cut = try #require(edited.range(of: "]", options: .backwards)).upperBound
        #expect(again.hasPrefix(String(edited[..<cut]) + ","))
    }

    // MARK: - Disconnect

    @Test("Removes only marked hooks, even from a group the user mixed with theirs")
    func onlyOurs() throws {
        let original = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "say done" },
                  { "type": "command", "command": "\(H.command.replacingOccurrences(of: "\"", with: "\\\""))", "async": true }
                ]
              }
            ],
            "PreToolUse": [
              { "hooks": [ { "type": "command", "command": "agentville-something-else" } ] }
            ]
          }
        }
        """
        let out = try H.disconnect(original)
        #expect(!H.isConnected(out))
        let hooks = try #require(try object(out)["hooks"] as? [String: [[String: Any]]])
        #expect((hooks["Stop"]?.first?["hooks"] as? [[String: Any]])?.map { $0["command"] as? String } == ["say done"])
        #expect((hooks["PreToolUse"]?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String == "agentville-something-else")
    }

    @Test("An empty hooks object or event list that was there before is dropped on Disconnect (same meaning)")
    func emptiedContainers() throws {
        let original = "{\n  \"model\": \"opus\",\n  \"hooks\": {\n    \"Stop\": []\n  }\n}\n"
        let out = try H.disconnect(try H.connect(original))
        #expect(out == "{\n  \"model\": \"opus\"\n}\n")
    }

    @Test("Nothing of ours: Disconnect changes nothing")
    func nothingToRemove() throws {
        let original = "{\n  \"hooks\": {\n    \"Stop\": []\n  }\n}\n"
        #expect(try H.disconnect(original) == original)
        #expect(try H.disconnect("{}") == "{}")
    }

    // MARK: - Refusals: never overwrite what we can't understand

    @Test("Unparseable or unexpected shapes are refused, never rewritten")
    func refusals() {
        let bad = [
            "{ \"a\": 1,, }", "{ \"a\": 1, }", "{\"a\": tru}", "[1, 2]", "\"text\"", "{\"a\": 1} trailing",
            "{ // comment\n}", "{\"a\": \"unterminated}", "{\"a\": 01}", "{\"a\": \"tab\there\"}",
            "{\"hooks\": []}", "{\"hooks\": {\"Stop\": {}}}", "{\"hooks\": {\"Stop\": [1]}}",
        ]
        for text in bad {
            #expect(throws: ClaudeSettingsHooks.Failure.self, "\(text)") { try H.connect(text) }
        }
        #expect(throws: ClaudeSettingsHooks.Failure.self) { try H.disconnect("{,}") }
    }

    @Test("Duplicate keys are refused (which one Claude Code reads is unclear)")
    func duplicateKeys() {
        #expect(throws: ClaudeSettingsHooks.Failure.self) { try H.connect("{\"hooks\": {}, \"hooks\": {}}") }
    }

    // MARK: - Reading

    @Test("disableAllHooks is noticed, for the 'nothing arrives' explanation")
    func disabled() {
        #expect(H.hooksDisabled("{\"disableAllHooks\": true}"))
        #expect(!H.hooksDisabled("{\"disableAllHooks\": false}"))
        #expect(!H.hooksDisabled("{}"))
        #expect(!H.hooksDisabled("not json"))
    }
}
