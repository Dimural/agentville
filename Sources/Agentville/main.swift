// Agentville menu bar app: M0 shell. Lifecycle, status item and clean quit only.
// The listener, store, office and overlay arrive in M1–M3 (docs/process/milestones.md).
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "◕‿◕ 0"
        item.button?.toolTip = "Agentville"
        let menu = NSMenu()
        let header = NSMenuItem(title: "Agentville: 0 sessions", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Agentville", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing survives quit (non-negotiable #3). Later: tear down overlays, unlink socket.
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
