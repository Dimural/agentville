import Foundation

/// The stable per-user link that Claude Code's hook command runs (docs/decisions/0007-hook-location.md):
/// `~/Library/Application Support/Agentville/bin/agentville-hook` → the app bundle's helper.
/// Pure decisions; the app reads the link and does the file work.
public enum HelperLink {
    public enum State: Equatable, Sendable {
        case missing
        /// Points at this copy's helper.
        case ours
        /// Points at a helper that's gone (the app moved or was deleted). Hooks are silent meanwhile.
        case dangling(String)
        /// Points at another helper that exists: a developer's build (`scripts/dev-link-hook.sh`) or
        /// another copy of the app.
        case elsewhere(String)
    }

    public enum Action: Equatable, Sendable { case create, replace }

    public static func path(home: String) -> String {
        home + "/Library/Application Support/Agentville/bin/agentville-hook"
    }

    /// `destination` is what the link holds (nil when there's no link); `targetExists` whether it resolves.
    public static func state(destination: String?, targetExists: Bool, ours: String) -> State {
        guard let destination else { return .missing }
        let tidy = (destination as NSString).standardizingPath
        if tidy == (ours as NSString).standardizingPath { return .ours }
        return targetExists ? .elsewhere(destination) : .dangling(destination)
    }

    /// At launch: create the link if the user connected but it's gone; repair a dangling one (the
    /// app moved, or an old copy was deleted). A link that works is someone's choice: leave it.
    public static func launchAction(_ state: State, connected: Bool) -> Action? {
        switch state {
        case .missing: connected ? .create : nil
        case .dangling: .replace
        case .ours, .elsewhere: nil
        }
    }

    /// Connect makes this copy the one Claude Code talks to.
    public static func connectAction(_ state: State) -> Action? {
        switch state {
        case .missing: .create
        case .dangling, .elsewhere: .replace
        case .ours: nil
        }
    }
}
