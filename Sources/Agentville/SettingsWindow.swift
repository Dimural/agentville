// Settings (open question 13's scope; docs/product/user-experience.md): open at login, the
// done-announcement rule, hide names, the shortcut, Claude Code (Connect/Disconnect), and
// Diagnostics: what the app received and what it did, in memory only, with a Copy button.
import AgentvilleCore
import AppKit
import ServiceManagement
import SwiftUI

@MainActor
@Observable
final class SettingsModel {
    var announce: DoneAnnouncement = Preferences.announceDone {
        didSet { Preferences.announceDone = announce; onAnnounceChange(announce) }
    }
    var hideNames: Bool = Preferences.hideNames {
        didSet { Preferences.hideNames = hideNames; onHideNamesChange(hideNames) }
    }
    private(set) var loginItemError: String?

    var onAnnounceChange: (DoneAnnouncement) -> Void = { _ in }
    var onHideNamesChange: (Bool) -> Void = { _ in }
    /// Header lines, the feed of received events and the app's own log.
    var diagnostics: () -> (summary: String, events: [String], log: [String]) = { ("", [], []) }
    var copyDiagnostics: () -> Void = {}
    var showWelcome: () -> Void = {}

    /// Open at login: the system's login item for this app (`SMAppService`), off unless chosen.
    /// Only a bundled app can register; a development build says so.
    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                loginItemError = nil
            } catch {
                loginItemError = Bundle.main.bundleIdentifier == nil
                    ? "Only the Agentville app (not a development build) can open at login."
                    : error.localizedDescription
            }
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: SettingsModel, connect: ConnectModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        window.title = "Agentville Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 420)
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, connect: connect))
        window.setContentSize(NSSize(width: 520, height: 620))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
}

struct SettingsView: View {
    @Bindable var settings: SettingsModel
    let connect: ConnectModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: Binding(get: { settings.openAtLogin }, set: { settings.openAtLogin = $0 }))
                if let e = settings.loginItemError {
                    Text(e).font(.caption).foregroundStyle(Color(nsColor: Theme.warn))
                }
                Picker("Walk on when a turn finishes", selection: $settings.announce) {
                    Text("Every turn").tag(DoneAnnouncement.everyTurn)
                    Text("Turns of \(Int(Timing.announceDoneMinTurn)) s or more").tag(DoneAnnouncement.longTurns)
                    Text("Never").tag(DoneAnnouncement.never)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Hide project names", isOn: $settings.hideNames)
                    Text("Shows “session 1”, “session 2”… instead of folder names, for screenshots and screen sharing.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Call the crew out or back") {
                    Text("⌃⌥C").font(.system(.body, design: .monospaced))
                }
            }
            Section("Claude Code") {
                ClaudeCodeSection(connect: connect, showWelcome: settings.showWelcome)
            }
            Section("Diagnostics") {
                DiagnosticsSection(settings: settings)
            }
        }
        .formStyle(.grouped)
        .onAppear { connect.refresh() }
    }
}

struct ClaudeCodeSection: View {
    let connect: ConnectModel
    let showWelcome: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status).font(.system(size: 13, weight: .semibold))
            switch connect.connection {
            case .both:
                Text("Both the plugin and the settings-file hooks are set up, so every event arrives twice.")
                    .font(.caption).foregroundStyle(Color(nsColor: Theme.warn))
                Button("Remove the settings-file hooks") { connect.removeSettingsHooks() }
            case .pluginDisabled:
                Text("The Agentville plugin is installed but turned off in Claude Code.")
                    .font(.caption).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
            ConnectPanel(model: connect)
            if connect.connection.isConnected || connect.connection == .pluginDisabled {
                HStack {
                    Spacer()
                    Button("Disconnect") { Task { await connect.disconnect() } }
                        .disabled(connect.isBusy)
                }
            }
            if connect.phase == .disconnected {
                Text("Disconnected. Claude Code sessions started from now on won't send Agentville anything.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var status: String {
        switch connect.connection {
        case .none: "Not connected"
        case .plugin: "Connected through the Agentville plugin"
        case .pluginDisabled: "Plugin turned off"
        case .settingsFile: "Connected through ~/.claude/settings.json"
        case .both: "Connected twice"
        }
    }
}

struct DiagnosticsSection: View {
    let settings: SettingsModel
    @State private var tab = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let d = settings.diagnostics()
            VStack(alignment: .leading, spacing: 8) {
                Text(d.summary).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(.secondary)
                Picker("", selection: $tab) {
                    Text("What the app received").tag(0)
                    Text("What the app did").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ScrollView {
                    Text((tab == 0 ? d.events : d.log).suffix(200).reversed().joined(separator: "\n"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                HStack {
                    Text("Kept in memory only; gone when Agentville quits.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copy Diagnostics") { settings.copyDiagnostics() }
                }
            }
        }
    }
}
