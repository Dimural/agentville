// The welcome window (docs/product/user-experience.md#first-run): one pixel character, one
// sentence, one button, **Connect to Claude Code**. Shown at launch until Claude Code is connected,
// and from Settings. SwiftUI in an AppKit window; the app has no Dock icon, so it activates itself
// to come forward.
import AgentvilleCore
import AppKit
import SwiftUI

@MainActor
final class WelcomeWindowController {
    private let window: NSWindow

    init(model: ConnectModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        window.title = "Welcome to Agentville"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(rootView: WelcomeView(model: model) { [weak self] in self?.close() })
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
}

struct WelcomeView: View {
    let model: ConnectModel
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            PixelSprite(name: "agentville", pose: .wave, scale: 5, animated: true)
                .padding(.top, 18)
            Text("Agentville")
                .font(.system(size: 24, weight: .heavy))
            Text("Your Claude Code sessions, as a little pixel crew that lives in your menu bar.")
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("It only hears event and tool names, session ids and folder names, over a socket on this Mac. Nothing leaves your Mac.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ConnectPanel(model: model)
            if model.connection.isConnected {
                Button("Done", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(width: 460)
    }
}

/// Connect, its progress, Path B's preview, the result and the live line. Shared by the welcome
/// window and Settings.
struct ConnectPanel: View {
    let model: ConnectModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.phase {
            case .preview:
                PreviewBox(model: model)
            case .working(let what):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(what).font(.system(size: 12.5))
                }
                .frame(maxWidth: .infinity)
            default:
                if !model.connection.isConnected {
                    Button(model.connection == .pluginDisabled ? "Turn the plugin back on" : "Connect to Claude Code") {
                        Task { await model.connect() }
                    }
                    .buttonStyle(PixelButtonStyle())
                    .frame(maxWidth: .infinity)
                    if !model.connection.isConnected, !model.isFailed {
                        Button("Or add the hooks to settings.json yourself…") { model.preparePreview() }
                            .buttonStyle(.link)
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            if case .failed(let message) = model.phase {
                Text(message).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.warn))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add the hooks to settings.json instead…") { model.preparePreview() }
                    .controlSize(.small)
            }
            if model.connection.isConnected || model.phase == .connected {
                StatusLines(model: model, justConnected: model.phase == .connected)
            }
            if !model.transcript.isEmpty {
                DisclosureGroup("Details") {
                    ScrollView {
                        Text(model.transcript)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 110)
                }
                .font(.system(size: 12))
            }
        }
    }
}

/// "Connected. Restart…", then the live line and, if nothing arrives, why.
struct StatusLines: View {
    let model: ConnectModel
    let justConnected: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let now = AppDelegate.now()
            VStack(alignment: .leading, spacing: 4) {
                if justConnected {
                    Label("Connected. Restart any open Claude Code sessions to see them.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color(nsColor: Theme.ok))
                        .font(.system(size: 12.5, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.liveLine(now: now))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let why = model.explanation(now: now) {
                    Text(why)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: Theme.warn))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Path B: exactly what will be added, where, and the backup, before anything is written.
struct PreviewBox: View {
    let model: ConnectModel
    @State private var showFile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agentville will add this hook to \(ClaudeSettingsHooks.events.count) events in \(displayPath(model.settingsPath)):")
                .font(.system(size: 12.5, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.entry)
                .font(.system(size: 10.5, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: Theme.chipFill)))
            Text(ClaudeSettingsHooks.events.joined(separator: ", "))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(model.plan?.original == nil
                 ? "There's no settings.json yet, so Agentville will create one with only these hooks."
                 : "Nothing else in the file changes. A backup is saved next to it first, and Disconnect removes exactly these entries.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("The whole file after the change", isExpanded: $showFile) {
                ScrollView {
                    Text(model.plan?.patched ?? "")
                        .font(.system(size: 10.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
            }
            .font(.system(size: 12))
            HStack {
                Spacer()
                Button("Cancel") { model.cancelPreview() }
                Button("Add Hooks") { model.confirmPreview() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private static let entry = """
    {
      "hooks": [
        {
          "type": "command",
          "command": "…/Agentville/bin/agentville-hook … exit 0 # agentville-hook",
          "async": true
        }
      ]
    }
    """

    private func displayPath(_ p: String) -> String {
        let home = Installer.home
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}

/// The prototype's chunky `.pbtn`: orange, a 2 pt ink ring, a hard drop shadow that the button
/// presses into.
struct PixelButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(nsColor: Theme.pixDark))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Rectangle().fill(Color(nsColor: Theme.accent)))
            .overlay(Rectangle().strokeBorder(Color(nsColor: Theme.pixDark), lineWidth: 2))
            .background(Rectangle().fill(Color(nsColor: Theme.pixDark)).offset(x: down ? 1 : 3, y: down ? 1 : 4))
            .offset(x: down ? 2 : 0, y: down ? 3 : 0)
            .padding(.bottom, 4)
    }
}

/// A character from `SpriteRenderer`, nearest-neighbour at an integer scale; waves when animated.
struct PixelSprite: View {
    let name: String
    let pose: Pose
    let scale: CGFloat
    var animated = false

    var body: some View {
        if animated {
            TimelineView(.periodic(from: .now, by: 0.35)) { ctx in
                image(frame: Int(ctx.date.timeIntervalSinceReferenceDate / 0.35))
            }
        } else {
            image(frame: 0)
        }
    }

    private func image(frame: Int) -> some View {
        let canvas = SpriteRenderer.render(LookGenerator.look(for: name), pose, frame: frame)
        let size = CGFloat(SpriteRenderer.size) * scale
        return Group {
            if let cg = PixelImage.cgImage(canvas) {
                Image(decorative: cg, scale: 1).interpolation(.none).resizable()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
