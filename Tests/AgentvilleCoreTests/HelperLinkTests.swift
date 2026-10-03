import Testing
@testable import AgentvilleCore

/// The stable link Claude Code's hook command runs (docs/decisions/0007-hook-location.md).
@Suite("Helper link")
struct HelperLinkTests {
    let ours = "/Applications/Agentville.app/Contents/Helpers/agentville-hook"

    @Test("Lives in Application Support, at the path the plugin's command uses")
    func path() {
        #expect(HelperLink.path(home: "/Users/sam") == "/Users/sam/Library/Application Support/Agentville/bin/agentville-hook")
        #expect(ClaudeSettingsHooks.command.contains("$HOME/Library/Application Support/Agentville/bin/agentville-hook"))
    }

    @Test("Reading the link")
    func state() {
        #expect(HelperLink.state(destination: nil, targetExists: false, ours: ours) == .missing)
        #expect(HelperLink.state(destination: ours, targetExists: true, ours: ours) == .ours)
        // Relative or untidy destinations that resolve to ours count as ours.
        #expect(HelperLink.state(destination: "/Applications/./Agentville.app/Contents/Helpers/agentville-hook", targetExists: true, ours: ours) == .ours)
        #expect(HelperLink.state(destination: "/Old/Agentville.app/Contents/Helpers/agentville-hook", targetExists: false, ours: ours)
            == .dangling("/Old/Agentville.app/Contents/Helpers/agentville-hook"))
        #expect(HelperLink.state(destination: "/dev/agentville/.build/debug/agentville-hook", targetExists: true, ours: ours)
            == .elsewhere("/dev/agentville/.build/debug/agentville-hook"))
    }

    @Test("At launch: repair a link left dangling by a moved or replaced app; never touch a working one")
    func launch() {
        #expect(HelperLink.launchAction(.missing, connected: true) == .create)
        #expect(HelperLink.launchAction(.missing, connected: false) == nil)
        #expect(HelperLink.launchAction(.dangling("/Old/x"), connected: true) == .replace)
        #expect(HelperLink.launchAction(.dangling("/Old/x"), connected: false) == .replace)
        #expect(HelperLink.launchAction(.ours, connected: true) == nil)
        // A developer's link (scripts/dev-link-hook.sh) or another copy that works is left alone.
        #expect(HelperLink.launchAction(.elsewhere("/dev/x"), connected: true) == nil)
    }

    @Test("Connect points the link at this copy, whatever was there")
    func connect() {
        #expect(HelperLink.connectAction(.missing) == .create)
        #expect(HelperLink.connectAction(.dangling("/Old/x")) == .replace)
        #expect(HelperLink.connectAction(.elsewhere("/dev/x")) == .replace)
        #expect(HelperLink.connectAction(.ours) == nil)
    }
}

@Suite("Claude CLI (Path A)")
struct ClaudeCLITests {
    @Test("The commands from the install docs, against this repo's marketplace and plugin")
    func commands() throws {
        #expect(ClaudeCLI.connectCommands.map(ClaudeCLI.display) == [
            "claude plugin marketplace add Dimural/agentville",
            "claude plugin install agentville@agentville --scope user",
        ])
        #expect(ClaudeCLI.disconnectCommands.map(ClaudeCLI.display) == ["claude plugin uninstall agentville@agentville"])
        let market = try readRepoFile(".claude-plugin/marketplace.json")
        #expect(market.contains("\"name\": \"agentville\""))
    }

    @Test("Shell lookup: a path is used; an alias, a function or nothing is not")
    func lookup() {
        #expect(ClaudeCLI.parseShellLookup("/Users/sam/.local/bin/claude\n") == "/Users/sam/.local/bin/claude")
        #expect(ClaudeCLI.parseShellLookup("welcome to zsh\n/opt/homebrew/bin/claude\n") == "/opt/homebrew/bin/claude")
        #expect(ClaudeCLI.parseShellLookup("claude: aliased to ~/x/claude") == nil)
        #expect(ClaudeCLI.parseShellLookup("claude") == nil)
        #expect(ClaudeCLI.parseShellLookup("") == nil)
    }

    @Test("Candidates start with the native installer's location")
    func candidates() {
        #expect(ClaudeCLI.candidates(home: "/Users/sam").first == "/Users/sam/.local/bin/claude")
        #expect(ClaudeCLI.candidates(home: "/Users/sam").contains("/opt/homebrew/bin/claude"))
    }

    @Test("Already added or installed counts as success")
    func already() {
        #expect(ClaudeCLI.succeeded(status: 0, output: ""))
        #expect(ClaudeCLI.succeeded(status: 1, output: "Marketplace 'agentville' is already installed"))
        #expect(!ClaudeCLI.succeeded(status: 1, output: "error: not found"))
    }
}
