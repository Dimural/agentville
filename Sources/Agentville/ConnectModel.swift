// Connect and Disconnect, as the Welcome and Settings windows see them
// (docs/architecture/installation.md, docs/product/user-experience.md#first-run). Path A (the
// plugin, through the `claude` CLI) when `claude` is found; otherwise Path B (our marked hooks in
// ~/.claude/settings.json), always after a preview and with a backup. The work is `Installer`'s;
// this keeps the state the windows show.
import AgentvilleCore
import Foundation
import Observation

@MainActor
@Observable
final class ConnectModel {
    enum Phase: Equatable {
        case idle
        case working(String)
        /// Path B, waiting for the user to look at what will be added.
        case preview
        case connected
        case disconnected
        case failed(String)
    }

    private(set) var phase = Phase.idle
    private(set) var connection = Connection.none
    /// Commands and their output, for the disclosure area.
    private(set) var transcript = ""
    /// Path B's plan while previewing.
    private(set) var plan: Installer.SettingsPlan?
    /// Uptime when Connect finished, for the "nothing arrives" explanation.
    private(set) var connectedAt: TimeInterval?
    /// Where Path B's backup went.
    private(set) var backupPath: String?

    /// Uptime of the last event received, from the app.
    var lastEventAt: () -> TimeInterval? = { nil }
    var log: (String) -> Void = { _ in }

    init() { refresh() }

    func refresh() { connection = Installer.detectConnection() }

    var isBusy: Bool { if case .working = phase { true } else { false } }
    var isFailed: Bool { if case .failed = phase { true } else { false } }

    var settingsPath: String { Installer.settingsPath }

    // MARK: - Connect

    /// The welcome window's button: Path A if `claude` is found, otherwise Path B's preview.
    func connect() async {
        guard !isBusy else { return }
        transcript = ""
        phase = .working("Looking for Claude Code…")
        guard linkHelper() else { return }
        guard let claude = await Installer.findClaude() else {
            note("The claude command wasn't found, so Agentville will add its hooks to settings.json instead.")
            preparePreview()
            return
        }
        note("Found \(claude)")
        let commands = connection == .pluginDisabled ? [ClaudeCLI.enableCommand] : ClaudeCLI.connectCommands
        for args in commands {
            phase = .working("Running \(ClaudeCLI.display(args))…")
            transcript += "$ \(ClaudeCLI.display(args))\n"
            let (status, out) = await Installer.run(claude, args)
            transcript += out.hasSuffix("\n") || out.isEmpty ? out : out + "\n"
            guard ClaudeCLI.succeeded(status: status, output: out) else {
                fail("\(ClaudeCLI.display(args)) didn't succeed (exit \(status)). You can add the hooks to settings.json instead.")
                return
            }
        }
        refresh()
        finishConnect(path: "plugin")
    }

    /// Path B on request (no CLI, or the CLI failed): show what will be added first.
    func preparePreview() {
        guard linkHelper() else { return }
        do {
            plan = try Installer.planConnect()
            phase = .preview
        } catch {
            fail("\(error)")
        }
    }

    /// The user approved the preview: back up, then write.
    func confirmPreview() {
        guard let plan else { return }
        do {
            backupPath = try Installer.apply(plan)
            self.plan = nil
            refresh()
            finishConnect(path: "settings file")
        } catch {
            fail("\(error)")
        }
    }

    func cancelPreview() {
        plan = nil
        phase = .idle
    }

    private func linkHelper() -> Bool {
        do {
            if let action = HelperLink.connectAction(Installer.linkState()) { try Installer.link(action) }
            return true
        } catch {
            fail("\(error)")
            return false
        }
    }

    private func finishConnect(path: String) {
        connectedAt = AppDelegate.now()
        phase = .connected
        log("connected (\(path))")
    }

    // MARK: - Disconnect

    /// Undoes whichever path is set up, then removes the helper link.
    func disconnect() async {
        guard !isBusy else { return }
        transcript = ""
        if connection == .plugin || connection == .both || connection == .pluginDisabled {
            phase = .working("Looking for Claude Code…")
            if let claude = await Installer.findClaude() {
                for args in ClaudeCLI.disconnectCommands {
                    phase = .working("Running \(ClaudeCLI.display(args))…")
                    transcript += "$ \(ClaudeCLI.display(args))\n"
                    let (status, out) = await Installer.run(claude, args)
                    transcript += out.hasSuffix("\n") || out.isEmpty ? out : out + "\n"
                    if status != 0 { note("(exit \(status))") }
                }
            } else {
                note("The claude command wasn't found. Remove the plugin in Claude Code with /plugin.")
            }
        }
        if connection == .settingsFile || connection == .both {
            do { try Installer.disconnectSettings() } catch {
                fail("\(error)")
                return
            }
        }
        Installer.unlink()
        refresh()
        connectedAt = nil
        phase = connection.isConnected ? .failed("Still connected; see the details below.") : .disconnected
        log("disconnected")
    }

    /// `.both`: keep the plugin, remove the settings-file hooks, so events stop arriving twice.
    func removeSettingsHooks() {
        do {
            try Installer.disconnectSettings()
            refresh()
        } catch {
            fail("\(error)")
        }
    }

    // MARK: - Status lines

    func liveLine(now: TimeInterval) -> String {
        Connection.liveLine(lastEventAgo: lastEventAt().map { now - $0 })
    }

    func explanation(now: TimeInterval) -> String? {
        let settings = try? Installer.readSettings()
        return Connection.explanation(connected: connection.isConnected,
                                      // Only after a Connect in this run: no events since launch is normal.
                                      sinceConnect: connectedAt.map { now - $0 } ?? 0,
                                      anyEvent: lastEventAt() != nil,
                                      hooksDisabled: settings.map(ClaudeSettingsHooks.hooksDisabled) ?? false)
    }

    private func note(_ s: String) { transcript += s + "\n" }

    private func fail(_ message: String) {
        phase = .failed(message)
        log("connect failed: \(message)")
    }
}
