import Foundation

/// Finding and driving the `claude` CLI for Path A of Connect
/// (docs/architecture/installation.md#path-a-plugin-preferred). Pure: the app runs the processes.
public enum ClaudeCLI {
    /// This repo is the marketplace; the plugin inside it is `agentville`.
    public static let marketplace = "Dimural/agentville"
    public static let plugin = "agentville@agentville"

    /// Connect, in order. Both are shown to the user with their output.
    public static let connectCommands: [[String]] = [
        ["plugin", "marketplace", "add", marketplace],
        ["plugin", "install", plugin, "--scope", "user"],
    ]
    /// When the plugin is installed but turned off.
    public static let enableCommand = ["plugin", "enable", plugin]
    public static let disconnectCommands: [[String]] = [
        ["plugin", "uninstall", plugin],
    ]

    /// Asked first: the login shell's `PATH` (`/bin/zsh -lc 'command -v claude'`), which sees what
    /// the user's profile adds.
    public static let shellLookup = ["/bin/zsh", "-lc", "command -v claude"]

    /// Then the usual install locations, in this order.
    public static func candidates(home: String) -> [String] {
        [
            home + "/.local/bin/claude",          // the native installer
            home + "/.claude/local/claude",       // the older local install
            "/opt/homebrew/bin/claude",           // Homebrew on Apple Silicon
            "/usr/local/bin/claude",              // Homebrew on Intel, npm -g
            home + "/.npm-global/bin/claude",
            home + "/.bun/bin/claude",
            home + "/.volta/bin/claude",
        ]
    }

    /// The shell lookup's output → a usable path, or nil (aliases and functions print a name, not a path).
    public static func parseShellLookup(_ output: String) -> String? {
        let line = output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.hasPrefix("/") ? line : nil
    }

    /// "Already added/installed" counts as success, so Connect can run twice.
    public static func succeeded(status: Int32, output: String) -> Bool {
        status == 0 || output.lowercased().contains("already")
    }

    /// For the disclosure area: the command as the user would type it.
    public static func display(_ args: [String]) -> String { (["claude"] + args).joined(separator: " ") }
}
