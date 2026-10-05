import Foundation
import Testing
@testable import AgentvilleCore

/// Is Claude Code connected, and what to tell the user (docs/architecture/installation.md#after-either-path).
@Suite("Connection")
struct ConnectionTests {
    let installed = """
    {"version": 2, "plugins": {
      "superpowers@claude-plugins-official": [{"scope": "user"}],
      "agentville@agentville": [{"scope": "user", "version": "0.0.1"}]
    }}
    """
    let otherPlugins = #"{"version": 2, "plugins": {"github@claude-plugins-official": [{"scope": "user"}]}}"#

    @Test("Plugin installed and enabled (or not mentioned in enabledPlugins): connected by plugin")
    func plugin() {
        #expect(Connection.detect(installedPlugins: installed, settings: #"{"enabledPlugins": {"agentville@agentville": true}}"#) == .plugin)
        #expect(Connection.detect(installedPlugins: installed, settings: "{}") == .plugin)
        #expect(Connection.detect(installedPlugins: installed, settings: nil) == .plugin)
    }

    @Test("Plugin installed but turned off in enabledPlugins")
    func disabledPlugin() {
        #expect(Connection.detect(installedPlugins: installed, settings: #"{"enabledPlugins": {"agentville@agentville": false}}"#) == .pluginDisabled)
    }

    @Test("Our marked hooks in settings.json: connected by settings file")
    func settings() throws {
        let s = try ClaudeSettingsHooks.connect("{}")
        #expect(Connection.detect(installedPlugins: otherPlugins, settings: s) == .settingsFile)
        #expect(Connection.detect(installedPlugins: nil, settings: s) == .settingsFile)
    }

    @Test("Both at once: every event would arrive twice")
    func both() throws {
        #expect(Connection.detect(installedPlugins: installed, settings: try ClaudeSettingsHooks.connect("{}")) == .both)
    }

    @Test("Neither, or files we can't read: not connected")
    func neither() {
        #expect(Connection.detect(installedPlugins: nil, settings: nil) == .none)
        #expect(Connection.detect(installedPlugins: otherPlugins, settings: "{}") == .none)
        #expect(Connection.detect(installedPlugins: "garbage", settings: "garbage") == .none)
        #expect(!Connection.none.isConnected)
        #expect(!Connection.pluginDisabled.isConnected)
        #expect(Connection.plugin.isConnected && Connection.settingsFile.isConnected && Connection.both.isConnected)
    }

    @Test("The live line: waiting, then how long ago the last event was")
    func liveLine() {
        #expect(Connection.liveLine(lastEventAgo: nil) == "Waiting for the first event…")
        #expect(Connection.liveLine(lastEventAgo: 0.4) == "Last event just now")
        #expect(Connection.liveLine(lastEventAgo: 3.2) == "Last event 3 s ago")
        #expect(Connection.liveLine(lastEventAgo: 59.9) == "Last event 59 s ago")
        #expect(Connection.liveLine(lastEventAgo: 125) == "Last event 2 min ago")
        #expect(Connection.liveLine(lastEventAgo: 3 * 3600 + 5) == "Last event 3 h ago")
    }

    @Test("Nothing arriving: explain disableAllHooks first, then the restart, only after a while")
    func explanation() {
        let wait = Connection.quietWarning
        #expect(Connection.explanation(connected: true, sinceConnect: wait + 1, anyEvent: false, hooksDisabled: true)?.contains("disableAllHooks") == true)
        // disableAllHooks is worth saying at once, even before the wait.
        #expect(Connection.explanation(connected: true, sinceConnect: 1, anyEvent: false, hooksDisabled: true) != nil)
        #expect(Connection.explanation(connected: true, sinceConnect: 1, anyEvent: false, hooksDisabled: false) == nil)
        #expect(Connection.explanation(connected: true, sinceConnect: wait + 1, anyEvent: false, hooksDisabled: false)?.contains("Restart") == true)
        #expect(Connection.explanation(connected: true, sinceConnect: wait + 1, anyEvent: true, hooksDisabled: false) == nil)
        #expect(Connection.explanation(connected: false, sinceConnect: wait + 1, anyEvent: false, hooksDisabled: false) == nil)
    }
}

/// Open question 10: hide project names for screenshots and screen shares.
@Suite("Name mask")
struct NameMaskTests {
    func sessions(_ names: [String]) -> [Session] {
        let store = SessionStore()
        for (i, n) in names.enumerated() {
            _ = store.apply(WireEvent(event: .sessionStart, session: "s\(i)", project: n, ts: 0), now: Double(i))
        }
        return store.ordered
    }

    @Test("Names become 'session 1', 'session 2'… in list order; looks, ids and states are kept")
    func masks() {
        let real = sessions(["secret-client", "api", "api"])
        let masked = NameMask.apply(real)
        #expect(masked.map(\.project) == ["session 1", "session 2", "session 3"])
        #expect(masked.map(\.twinIndex) == [1, 1, 1])
        #expect(masked.map(\.id) == real.map(\.id))
        #expect(masked.map(\.look) == real.map(\.look))
        #expect(masked.map(\.status) == real.map(\.status))
        #expect(DeskList.Row(masked[0], now: 1).name == "session 1")
    }

    @Test("No project name survives anywhere in a masked session's text")
    func nothingLeaks() {
        let masked = NameMask.apply(sessions(["secret-client"]))
        #expect(!"\(masked)".contains("secret-client"))
    }
}
