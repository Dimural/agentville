import Foundation

/// Whether Claude Code will send us events, and what to tell the user about it
/// (docs/architecture/installation.md#after-either-path). Read from two files the app only reads:
/// `~/.claude/plugins/installed_plugins.json` (Path A) and `~/.claude/settings.json` (Path B, and
/// `enabledPlugins`). Pure: the app passes the files' text in.
public enum Connection: Equatable, Sendable {
    /// Neither path is set up.
    case none
    /// The plugin is installed (Path A).
    case plugin
    /// The plugin is installed but turned off in `enabledPlugins`.
    case pluginDisabled
    /// Our marked hooks are in settings.json (Path B).
    case settingsFile
    /// Both: every event would arrive twice. Settings offers to remove the settings-file hooks.
    case both

    public var isConnected: Bool { self == .plugin || self == .settingsFile || self == .both }

    /// After Connect, how long silence lasts before we suggest restarting sessions.
    public static let quietWarning: TimeInterval = 90

    public static func detect(installedPlugins: String?, settings: String?) -> Connection {
        let settingsObject = settings.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let pluginInstalled: Bool = {
            guard let text = installedPlugins,
                  let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let plugins = obj["plugins"] as? [String: Any] else { return false }
            return plugins[ClaudeCLI.plugin] != nil
        }()
        let pluginOff = (settingsObject?["enabledPlugins"] as? [String: Any])?[ClaudeCLI.plugin] as? Bool == false
        let hooks = settings.map(ClaudeSettingsHooks.isConnected) ?? false
        switch (pluginInstalled && !pluginOff, hooks) {
        case (true, true): return .both
        case (true, false): return .plugin
        case (false, true): return .settingsFile
        case (false, false): return pluginInstalled ? .pluginDisabled : .none
        }
    }

    /// "Waiting for the first event…" → "Last event 3 s ago".
    public static func liveLine(lastEventAgo: TimeInterval?) -> String {
        guard let ago = lastEventAgo else { return "Waiting for the first event…" }
        switch ago {
        case ..<1: return "Last event just now"
        case ..<60: return "Last event \(Int(ago)) s ago"
        case ..<3600: return "Last event \(Int(ago / 60)) min ago"
        default: return "Last event \(Int(ago / 3600)) h ago"
        }
    }

    /// Why nothing arrives, once it's worth saying. `disableAllHooks` at once; otherwise, after
    /// `quietWarning` without a single event, the restart reminder.
    public static func explanation(connected: Bool, sinceConnect: TimeInterval, anyEvent: Bool, hooksDisabled: Bool) -> String? {
        guard connected, !anyEvent else { return nil }
        if hooksDisabled {
            return "Your Claude Code settings contain \"disableAllHooks\": true, which turns off every hook, Agentville's included. Remove it from ~/.claude/settings.json to see your sessions."
        }
        guard sinceConnect > quietWarning else { return nil }
        return "Nothing yet. Restart any open Claude Code sessions (hooks load when a session starts), then send a prompt."
    }
}

/// Open question 10: "Hide project names" for screenshots and screen shares. The app hands masked
/// sessions to everything it draws: the list, the office and the crew's bubbles.
public enum NameMask {
    /// Folder names become "session 1", "session 2"… in list order. Everything else is kept, so
    /// looks (made from the real name) and states don't change.
    public static func apply(_ ordered: [Session]) -> [Session] {
        ordered.enumerated().map { i, s in
            var m = s
            m.project = "session \(i + 1)"
            m.twinIndex = 1
            return m
        }
    }
}
