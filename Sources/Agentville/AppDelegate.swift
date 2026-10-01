// Lifecycle and ownership: socket listener → session store → status item and debug window.
// M1 data path (docs/process/milestones.md). The office and overlay arrive in M2–M3.
import AgentvilleCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Only touched on the main actor. Pure Core state machine (docs/product/sessions-and-states.md).
    let store = SessionStore()
    private(set) var listener: SocketListener?

    private var statusItem: NSStatusItem?
    private var headerItem: NSMenuItem?
    private var debugWindow: DebugWindowController?
    private var tickTimer: Timer?
    /// SIGTERM/SIGINT (`kill`, Ctrl-C) become a normal quit, so the socket file is removed then too.
    private var signalSources: [DispatchSourceSignal] = []
    /// Coalesces status item updates so a storm of batches redraws at most at 4 Hz.
    private var refreshPending = false

    /// Monotonic seconds; the store only ever compares times, so uptime is enough and immune to clock changes.
    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        startListening()
        quitOnSignals()
        // Finished → idle and staleness need a clock. Cheap, coarse and tolerant, so idle stays idle.
        let timer = Timer(timeInterval: Timing.storeTick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = Timing.storeTick / 2
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        refreshStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing survives quit (non-negotiable #3): close the socket and remove its file.
        listener?.stop()
        tickTimer?.invalidate()
        debugWindow?.close()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }

    private func quitOnSignals() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            src.resume()
            signalSources.append(src)
        }
    }

    // MARK: - Data path

    private func startListening() {
        guard let path = SocketPath.resolve() else { return }
        let l = SocketListener(path: path, deliverOn: .main) { [weak self] batch in
            MainActor.assumeIsolated { self?.ingest(batch) }
        }
        listener = l.start() ? l : nil
    }

    func ingest(_ batch: [WireEvent]) {
        let now = Self.now()
        for e in batch { store.apply(e, now: now) }
        // Effects (walk-ons, cheers) are consumed from M2 on; for now the UI just reflects state.
        scheduleRefresh()
    }

    private func tick() {
        let before = store.revision
        store.tick(now: Self.now())
        if store.revision != before { scheduleRefresh() }
    }

    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Timing.listRefresh) { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshPending = false
                self?.refreshStatusItem()
            }
        }
    }

    // MARK: - Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Agentville"
        let menu = NSMenu()
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let debug = NSMenuItem(title: "Session List (Debug)…", action: #selector(showDebugWindow), keyEquivalent: "d")
        debug.target = self
        menu.addItem(debug)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Agentville", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
        headerItem = header
    }

    private func refreshStatusItem() {
        let s = store.summary
        statusItem?.button?.title = "◕‿◕ \(s.active)" + (s.needYou > 0 ? " !" : "")
        if listener == nil {
            headerItem?.title = "Agentville: not listening (socket unavailable)"
        } else {
            let noun = s.active == 1 ? "session" : "sessions"
            headerItem?.title = "Agentville: \(s.active) \(noun)" + (s.needYou > 0 ? ", \(s.needYou) need you" : "")
        }
    }

    @objc private func showDebugWindow() {
        if debugWindow == nil { debugWindow = DebugWindowController(app: self) }
        debugWindow?.present()
    }
}
