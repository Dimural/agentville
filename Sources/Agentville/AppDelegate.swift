// Lifecycle and ownership: socket listener → session store → status item and desk panel.
// The overlay arrives in M3 (docs/process/milestones.md).
import AgentvilleCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Only touched on the main actor. Pure Core state machine (docs/product/sessions-and-states.md).
    let store = SessionStore()
    private(set) var listener: SocketListener?

    private var statusItem: StatusItemController?
    private var deskPanel: DeskPanelController?
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
        // Dev convenience for side-by-side reviews: `Agentville --show-desk` opens the panel pinned.
        // Next turn of the run loop, once the status item has a place on the menu bar.
        if CommandLine.arguments.contains("--show-desk") {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let p = self?.panel() else { return }
                    p.setPinned(true)
                    p.show()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing survives quit (non-negotiable #3): close the socket and remove its file.
        listener?.stop()
        tickTimer?.invalidate()
        deskPanel?.close()
        statusItem?.remove()
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

    // MARK: - Status item and desk panel

    private func buildStatusItem() {
        statusItem = StatusItemController(
            onTogglePanel: { [weak self] in self?.panel().toggle() },
            isPinned: { [weak self] in self?.deskPanel?.pinned ?? false },
            onTogglePin: { [weak self] in
                guard let p = self?.panel() else { return }
                p.setPinned(!p.pinned)
                if p.pinned, !p.isVisible { p.show() }
            })
    }

    private func refreshStatusItem() {
        statusItem?.update(store.summary, listening: listener != nil)
    }

    /// Built on first use, so an app nobody opens never creates the panel.
    private func panel() -> DeskPanelController {
        if let p = deskPanel { return p }
        let p = DeskPanelController(app: self,
                                    anchor: { [weak self] in self?.statusItem?.anchor },
                                    moreMenu: { [weak self] in self?.statusItem?.moreMenu ?? NSMenu() })
        p.onVisibilityChange = { [weak self] open in self?.statusItem?.setPanelOpen(open) }
        deskPanel = p
        return p
    }
}
