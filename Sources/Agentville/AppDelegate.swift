// Lifecycle and ownership: socket listener → session store → status item, desk panel and the
// crew's overlay (roamers, the crowd and walk-ons).
import AgentvilleCore
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Only touched on the main actor. Pure Core state machine (docs/product/sessions-and-states.md).
    let store = SessionStore()
    private(set) var listener: SocketListener?

    private var statusItem: StatusItemController?
    private var deskPanel: DeskPanelController?
    private var overlay: OverlayController?
    private var hotKey: HotKey?
    private var tickTimer: Timer?
    /// SIGTERM/SIGINT (`kill`, Ctrl-C) become a normal quit, so the socket file is removed then too.
    private var signalSources: [DispatchSourceSignal] = []
    /// In memory only (non-negotiable #8); copied from the status menu.
    private(set) var diagnostics = Diagnostics()
    /// Coalesces status item updates so a storm of batches redraws at most at 4 Hz.
    private var refreshPending = false

    /// Monotonic seconds; the store only ever compares times, so uptime is enough and immune to clock changes.
    static func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Dev and the soak harness (`scripts/soak-overlay.sh`): `--diagnostics-stderr` also prints each
    /// line to stderr. Never a file (non-negotiable #8).
    private let echoDiagnostics = CommandLine.arguments.contains("--diagnostics-stderr")

    func log(_ message: String) {
        diagnostics.log(message)
        if echoDiagnostics, let line = diagnostics.lines.last { FileHandle.standardError.write(Data((line + "\n").utf8)) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.announceDone = Preferences.announceDone
        buildStatusItem()
        startListening()
        log("launched; \(listener == nil ? "not listening (socket unavailable)" : "listening")")
        hotKey = HotKey { [weak self] in self?.toggleCrew() }
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
        // Dev and scripts/check-quit-cleanup.sh: `Agentville --release-crew` lets the crew out at
        // launch; sessions that arrive later drop in.
        if CommandLine.arguments.contains("--release-crew") {
            DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.toggleCrew() } }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Nothing survives quit (non-negotiable #3): close the socket and remove its file.
        listener?.stop()
        tickTimer?.invalidate()
        hotKey?.unregister()
        overlay?.close()
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
        let before = store.order
        var effects: [StoreEffect] = []
        for e in batch { effects += store.apply(e, now: now) }
        if store.order != before { overlay?.sessionsChanged(store.ordered) }
        // Finished turns and sessions that need you walk on while the crew is inside (M6).
        if Self.wantsWalkOn(effects) { crew().notify(effects) } else { overlay?.notify(effects) }
        scheduleRefresh()
    }

    /// Anything that may bring a character out while the crew is inside. The overlay is built on
    /// first need, so an app that never shows anyone never creates it.
    private static func wantsWalkOn(_ effects: [StoreEffect]) -> Bool {
        effects.contains {
            switch $0 {
            case .finished(_, _, let announce): announce
            case .needsYou: true
            default: false
            }
        }
    }

    private func tick() {
        let before = store.revision, order = store.order
        // Stale sessions (docs/product/sessions-and-states.md#staleness) leave like ended ones.
        store.tick(now: Self.now())
        if store.order != order { overlay?.sessionsChanged(store.ordered) }
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
        statusItem?.onToggleCrew = { [weak self] in self?.toggleCrew() }
        statusItem?.isReleased = { [weak self] in self?.overlay?.sim.released ?? false }
        statusItem?.onAnnounceChange = { [weak self] rule in self?.store.announceDone = rule }
        statusItem?.diagnostics = { [weak self] in self?.diagnosticsText() ?? "" }
    }

    private func diagnosticsText() -> String {
        let stats = listener?.stats
        let o = overlay
        var head = "Agentville diagnostics\n"
        head += "sessions: \(store.order.count), events received: \(stats?.received ?? 0), dropped: \(stats?.dropped ?? 0)\n"
        head += "crew: \(o?.sim.released == true ? "out" : "inside"), overlay: \(o?.stateDescription ?? "not created")\n\n"
        return head + diagnostics.text
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
        p.away = { [weak self] in self?.overlay?.sim.awayIDs ?? [] }
        p.onToggleCrew = { [weak self] in self?.toggleCrew() }
        deskPanel = p
        return p
    }

    // MARK: - The crew (docs/product/user-experience.md#releasing-the-crew)

    /// Built on first release; asleep (paused, off screen) whenever the crew is home.
    private func crew() -> OverlayController {
        if let o = overlay { return o }
        let o = OverlayController()
        o.log = { [weak self] in self?.log($0) }
        o.sessions = { [weak self] in self?.store.sessions ?? [:] }
        o.sim.home = { [weak self, weak o] id in
            guard let self, let o else { return Home(x: 0, y: 0, scale: 1) }
            return self.home(for: id, overlay: o)
        }
        o.onEvent = { [weak self] e in if e == .gulp { self?.deskPanel?.gulp() } }
        o.sessionsChanged(store.ordered)
        overlay = o
        return o
    }

    private func toggleCrew() {
        let o = crew(), p = panel()
        if o.sim.released {
            o.recall()
        } else {
            // Like the prototype: the crew pours out of the desk panel, so open it first.
            if !p.isVisible { p.show() }
            if o.release(store.ordered).contains(.burp) { p.burp() }
        }
        p.setReleased(o.sim.released)
    }

    /// Port of `homePos`: the session's desk while the panel is open (the list for sessions
    /// without a desk), otherwise the menu bar icon, drawn smaller.
    private func home(for id: String, overlay o: OverlayController) -> Home {
        if let p = deskPanel, p.isVisible {
            let i = store.order.firstIndex(of: id) ?? Int.max
            if let pt = p.deskFeet(i) ?? p.listAnchor {
                let s = o.simPoint(pt)
                return Home(x: s.x, y: s.y, scale: 2)
            }
        }
        if let pt = statusItem?.iconHome {
            let s = o.simPoint(pt)
            return Home(x: s.x, y: s.y, scale: 1)
        }
        return Home(x: o.sim.stage.width - 80, y: 0, scale: 1)
    }
}
