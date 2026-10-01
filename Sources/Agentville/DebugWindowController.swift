// M1 debug list: live SessionStore state, for checking replay scenarios and real sessions by eye.
// Plain AppKit table, no art. Redraws at most at 4 Hz, only while the window is open
// (docs/architecture/app.md#performance-rules). Replaced by the desk window's list in M2.
import AgentvilleCore
import AppKit

@MainActor
final class DebugWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let app: AppDelegate
    private let window: NSWindow
    private let table = NSTableView()
    private let summary = NSTextField(labelWithString: "")
    private var rows: [Session] = []
    private var timer: Timer?
    private var shownRevision = -1
    private var lastFullRedraw: TimeInterval = 0

    private enum Column: String, CaseIterable {
        case project = "Project", status = "Status", tool = "Tool", subagents = "Subagents"
        case turn = "Turn", lastEvent = "Last event", quiet = "Quiet", session = "Session id"

        var width: CGFloat {
            switch self {
            case .project: 150
            case .status: 100
            case .tool: 90
            case .subagents: 70
            case .turn, .quiet: 60
            case .lastEvent: 130
            case .session: 160
            }
        }
    }

    init(app: AppDelegate) {
        self.app = app
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 360),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "Agentville: Sessions (Debug)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 480, height: 200)
        window.delegate = self
        buildContent()
        window.center()
    }

    func present() {
        refresh(force: true)
        startTimer()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Window hidden → no work (performance rule 1).
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Refresh

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: Timing.listRefresh, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(force: false) }
        }
        t.tolerance = Timing.listRefresh / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh(force: Bool) {
        let now = AppDelegate.now()
        // Redraw when the store moved; otherwise once a second so the elapsed columns keep counting.
        guard force || app.store.revision != shownRevision || now - lastFullRedraw >= 1 else { return }
        shownRevision = app.store.revision
        lastFullRedraw = now
        rows = Array(app.store.ordered.prefix(Limits.debugListRows))
        table.reloadData()

        let s = app.store.summary
        var text = "\(s.active) active · \(s.needYou) need you · \(s.justFinished) just finished"
        if let l = app.listener {
            let st = l.stats
            text += "    socket: \(st.received) events received, \(st.dropped) dropped"
        } else {
            text += "    socket: not listening"
        }
        if app.store.ordered.count > rows.count { text += "    (showing first \(rows.count))" }
        summary.stringValue = text
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier, let col = Column(rawValue: id.rawValue), row < rows.count else { return nil }
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: "")
            f.identifier = id
            f.lineBreakMode = .byTruncatingTail
            f.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            return f
        }()
        let s = rows[row]
        cell.stringValue = text(for: col, session: s, now: AppDelegate.now())
        cell.textColor = col == .status && s.status == .needsYou ? .systemRed : .labelColor
        return cell
    }

    private func text(for col: Column, session s: Session, now: TimeInterval) -> String {
        switch col {
        case .project: return s.twinIndex > 1 ? "\(s.project) #\(s.twinIndex)" : s.project
        case .status: return s.status.label
        case .tool: return s.tool ?? ""
        case .subagents: return s.subagents.isEmpty ? "" : "\(s.subagents.count)"
        case .turn:
            if let t = s.turnStartedAt { return Self.duration(now - t) }
            if let d = s.lastTurnDuration { return "(\(Self.duration(d)))" }
            return ""
        case .lastEvent: return s.lastEvent.rawValue
        case .quiet: return Self.duration(now - s.lastEventAt)
        case .session: return s.id
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let secs = max(0, Int(t))
        return secs < 60 ? "\(secs)s" : secs < 3600 ? "\(secs / 60)m\(secs % 60)s" : "\(secs / 3600)h\(secs / 60 % 60)m"
    }

    private func buildContent() {
        for c in Column.allCases {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.rawValue))
            col.title = c.rawValue
            col.width = c.width
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 18
        table.allowsColumnReordering = false

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true

        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.textColor = .secondaryLabelColor

        let content = NSView()
        for v in [summary, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            summary.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            summary.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }
}
