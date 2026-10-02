// The desk window: the pixel office on top, the summary line, then the session list
// (docs/product/user-experience.md#desk-window-the-office, docs/design/office.md).
// The office redraws at about 12 fps and the list at most at 4 Hz, both only while the window is
// visible (docs/architecture/app.md#performance-rules). The Release button arrives with M3.
import AgentvilleCore
import AppKit

@MainActor
final class DeskWindowController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let app: AppDelegate
    private let window: NSWindow
    private let office = OfficeView()
    private let summary = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private var rows: [DeskList.Row] = []
    private var officeTimer: Timer?
    private var listTimer: Timer?
    private var shownRevision = -1
    private var shownSecond = -1
    private var shownBlink = false
    private let sprites = SpriteCache()
    private var avatars: [Look: CGImage] = [:]

    /// Office layout in points: 2 pt per room unit (docs/design/office.md#geometry).
    static let officeSize = NSSize(width: OfficeRenderer.pixelSize.width, height: OfficeRenderer.pixelSize.height)
    static let rowHeight: CGFloat = 38

    init(app: AppDelegate) {
        self.app = app
        let w = Self.officeSize.width
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: Self.officeSize.height + 33 + 4 * Self.rowHeight),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: true)
        super.init()
        window.title = "Agentville"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.win
        window.contentMinSize = NSSize(width: w, height: Self.officeSize.height + 33 + 2 * Self.rowHeight)
        window.contentMaxSize = NSSize(width: w, height: 4000)
        window.delegate = self
        buildContent()
        window.center()
    }

    var isVisible: Bool { window.isVisible }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        updateTimers()
    }

    func hide() {
        window.orderOut(nil)
        updateTimers()
    }

    func close() {
        window.close()
        updateTimers()
    }

    // MARK: - Timers (run only while the window can be seen)

    private var canBeSeen: Bool {
        window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    private func updateTimers() {
        if canBeSeen {
            if officeTimer == nil {
                officeTimer = Self.repeating(Timing.officeFrame) { [weak self] in self?.drawOffice() }
                drawOffice()
            }
            if listTimer == nil {
                listTimer = Self.repeating(Timing.listRefresh) { [weak self] in self?.refreshList(force: false) }
                refreshList(force: true)
            }
        } else {
            officeTimer?.invalidate(); officeTimer = nil
            listTimer?.invalidate(); listTimer = nil
        }
    }

    private static func repeating(_ interval: TimeInterval, _ body: @escaping @MainActor () -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { body() } }
        t.tolerance = interval / 4
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    func windowWillClose(_ notification: Notification) {
        officeTimer?.invalidate(); officeTimer = nil
        listTimer?.invalidate(); listTimer = nil
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateTimers() }
    func windowDidMiniaturize(_ notification: Notification) { updateTimers() }
    func windowDidDeminiaturize(_ notification: Notification) { updateTimers() }

    // MARK: - Office

    private func drawOffice() {
        let sessions = app.store.ordered
        let clock = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let scene = OfficeScene(sessions: sessions, night: Theme.isDark(office),
                                clock: (clock.hour ?? 0, clock.minute ?? 0))
        office.pixels.image = PixelImage.cgImage(OfficeRenderer.render(scene, t: AppDelegate.now(), cache: sprites))
        office.update(moreBelow: scene.moreBelow,
                      twins: sessions.prefix(Limits.desks).map { $0.twinIndex > 1 ? $0.twinIndex : nil })
    }

    // MARK: - List and summary (≤ 4 Hz)

    func refreshList(force: Bool) {
        let now = AppDelegate.now()
        let store = app.store
        let s = store.summary
        // Redraw when the store moved, once a second for the elapsed times, and on the blink beat
        // while anything needs you (the prototype's `blink 1s steps(2)`).
        let second = Int(now)
        let blink = s.needYou > 0 && Int(now * 2) % 2 == 1
        guard force || store.revision != shownRevision || second != shownSecond || blink != shownBlink else { return }
        let structural = force || store.revision != shownRevision
        shownRevision = store.revision
        shownSecond = second
        shownBlink = blink

        rows = store.ordered.map { DeskList.Row($0, now: now) }
        if structural {
            table.reloadData()
        } else {
            // Only times and blink changed: update the visible cells in place.
            let visible = table.rows(in: table.visibleRect)
            for r in visible.location..<(visible.location + visible.length) where r < rows.count {
                (table.view(atColumn: 0, row: r, makeIfNecessary: false) as? SessionRowView)?
                    .show(rows[r], avatar: avatar(for: store.ordered[r].look), blinkOff: blink)
            }
        }
        summary.attributedStringValue = Self.summaryText(DeskList.summary(s))
    }

    private static func summaryText(_ segments: [DeskList.Segment]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.font: Theme.body(12.5), .foregroundColor: Theme.muted]
        for (i, seg) in segments.enumerated() {
            if i > 0 { out.append(NSAttributedString(string: " · ", attributes: base)) }
            var attrs = base
            switch seg.tone {
            case .plain: break
            case .warn: attrs[.foregroundColor] = Theme.warn
            case .ok: attrs[.foregroundColor] = Theme.ok
            }
            let piece = NSMutableAttributedString(string: seg.text, attributes: attrs)
            if let c = seg.count {
                piece.addAttributes([.font: Theme.body(12.5, .semibold), .foregroundColor: Theme.ink],
                                    range: NSRange(location: 0, length: (c as NSString).length))
            }
            out.append(piece)
        }
        return out
    }

    private func avatar(for look: Look) -> CGImage? {
        if let a = avatars[look] { return a }
        if avatars.count >= Limits.trackedSessions { avatars.removeAll(keepingCapacity: true) }
        let a = PixelImage.cgImage(SpriteRenderer.avatar(look))
        avatars[look] = a
        return a
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < rows.count else { return nil }
        let view = (tableView.makeView(withIdentifier: SessionRowView.id, owner: nil) as? SessionRowView) ?? SessionRowView()
        let ordered = app.store.ordered
        let look = row < ordered.count ? ordered[row].look : LookGenerator.look(for: rows[row].name)
        view.show(rows[row], avatar: avatar(for: look), blinkOff: shownBlink)
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    // MARK: - Layout

    private func buildContent() {
        summary.lineBreakMode = .byTruncatingTail
        summary.maximumNumberOfLines = 1

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.backgroundColor = Theme.win
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = Theme.line
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.style = .plain

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.win
        scroll.borderType = .noBorder

        let rule = NSBox()
        rule.boxType = .custom
        rule.borderWidth = 0
        rule.fillColor = Theme.line

        let content = WindowBackground()
        for v in [office, summary, rule, scroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            office.topAnchor.constraint(equalTo: content.topAnchor),
            office.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            office.widthAnchor.constraint(equalToConstant: Self.officeSize.width),
            office.heightAnchor.constraint(equalToConstant: Self.officeSize.height),
            summary.topAnchor.constraint(equalTo: office.bottomAnchor, constant: 9),
            summary.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            summary.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            rule.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 7),
            rule.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
    }
}

/// Fills with the prototype's `--win` colour, which follows light and dark mode.
final class WindowBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.win.setFill()
        dirtyRect.fill()
    }
}

/// The office image plus the badges drawn over it: "+N more below" (port of `.office-more`) and
/// twin number badges on the nameplates (open question 14).
@MainActor
final class OfficeView: NSView {
    let pixels = PixelView()
    private let more = PixelBadge(fill: Theme.accent, border: 2, font: Theme.mono(12, .semibold))
    private var twinBadges: [PixelBadge] = []

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.pixDark.cgColor
        addSubview(pixels)
        addSubview(more)
        more.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        pixels.frame = bounds
        let s = more.badgeSize
        // right: 8px, bottom: 8px; the 2 px ink border sits outside the box.
        more.frame = NSRect(x: bounds.width - 8 - s.width, y: bounds.height - 8 - s.height, width: s.width, height: s.height)
    }

    func update(moreBelow: Int, twins: [Int?]) {
        let text = moreBelow > 0 ? "+\(moreBelow) more below" : ""
        if more.text != text {
            more.text = text
            more.isHidden = moreBelow == 0
            needsLayout = true
        }
        while twinBadges.count < twins.count {
            let b = PixelBadge(fill: Theme.pixPaper, border: 1, font: Theme.mono(9, .bold))
            addSubview(b)
            twinBadges.append(b)
        }
        for (i, b) in twinBadges.enumerated() {
            let n = i < twins.count ? twins[i] : nil
            b.isHidden = n == nil
            guard let n else { continue }
            if b.text != "\(n)" { b.text = "\(n)" }
            // On the monitor's top-left corner (bezel at gx+38, top−15), in points (2 per unit).
            // Clear of the "+N more below" badge, which covers the last desk's front.
            let d = OfficeRenderer.deskUnits(i), s = b.badgeSize
            b.frame = NSRect(x: CGFloat(d.gx + 37) * 2, y: CGFloat(d.top - 16) * 2, width: s.width, height: s.height)
        }
    }
}

/// A square-cornered pixel label with an ink border (the prototype's `.office-more` look).
@MainActor
final class PixelBadge: NSView {
    private let label = NSTextField(labelWithString: "")
    private let border: CGFloat

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; invalidateIntrinsicContentSize() }
    }

    init(fill: NSColor, border: CGFloat, font: NSFont) {
        self.border = border
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = Theme.pixDark.cgColor
        layer?.borderWidth = border
        label.font = font
        label.textColor = Theme.pixDark
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    private var padding: NSSize { border > 1 ? NSSize(width: 7, height: 4) : NSSize(width: 3, height: 1) }

    override var intrinsicContentSize: NSSize { badgeSize }

    var badgeSize: NSSize {
        guard !text.isEmpty else { return .zero }
        let s = label.fittingSize
        return NSSize(width: ceil(s.width + 2 * (padding.width + border)), height: ceil(s.height + 2 * border + padding.height))
    }

    override func layout() {
        super.layout()
        let s = label.fittingSize
        label.frame = NSRect(x: border + padding.width, y: (bounds.height - s.height) / 2, width: s.width, height: s.height)
    }
}

/// One session row: avatar · name (+ twin badge, tool) · status chip · elapsed.
/// Port of the prototype's `.srow` (grid 22px | 1fr | auto | auto, gap 10, padding 5 12).
@MainActor
final class SessionRowView: NSTableCellView {
    static let id = NSUserInterfaceItemIdentifier("SessionRow")

    private let avatarView = PixelView()
    private let name = NSTextField(labelWithString: "")
    private let twin = PixelBadge(fill: Theme.pixPaper, border: 1, font: Theme.mono(9, .bold))
    private let detail = NSTextField(labelWithString: "")
    private let chip = ChipView()
    private let time = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.id
        name.lineBreakMode = .byTruncatingTail
        name.font = Theme.body(13, .semibold)
        name.textColor = Theme.ink
        name.setContentCompressionResistancePriority(.defaultLow + 1, for: .horizontal)
        name.setContentHuggingPriority(.required, for: .horizontal)
        detail.lineBreakMode = .byTruncatingTail
        detail.font = Theme.mono(11)
        detail.textColor = Theme.muted
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        time.font = Theme.digits(12)
        time.textColor = Theme.muted
        time.alignment = .right
        for v in [avatarView, name, twin, detail, chip, time] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        let a = SpriteRenderer.avatarCrop
        NSLayoutConstraint.activate([
            // The avatar at 2× (13×14 px → 26×28 pt): integer scale, unlike the prototype's 22×24.
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: CGFloat(a.w * 2)),
            avatarView.heightAnchor.constraint(equalToConstant: CGFloat(a.h * 2)),
            name.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            twinGap,
            twin.centerYAnchor.constraint(equalTo: centerYAnchor),
            // `.nm small`: 6 px after the name (and its twin badge).
            detail.leadingAnchor.constraint(equalTo: twin.trailingAnchor, constant: 6),
            detail.firstBaselineAnchor.constraint(equalTo: name.firstBaselineAnchor),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: chip.leadingAnchor, constant: -10),
            chip.centerYAnchor.constraint(equalTo: centerYAnchor),
            time.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 10),
            time.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            time.centerYAnchor.constraint(equalTo: centerYAnchor),
            time.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        twin.setContentHuggingPriority(.required, for: .horizontal)
        chip.setContentHuggingPriority(.required, for: .horizontal)
        chip.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private lazy var twinGap = twin.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 4)

    func show(_ row: DeskList.Row, avatar: CGImage?, blinkOff: Bool) {
        if avatarView.image !== avatar { avatarView.image = avatar }
        if name.stringValue != row.name { name.stringValue = row.name }
        if detail.stringValue != row.detail { detail.stringValue = row.detail }
        // A hidden badge still takes part in layout, so empty it to zero width instead.
        let badge = row.twin.map { "\($0)" } ?? ""
        if twin.text != badge { twin.text = badge }
        twin.isHidden = row.twin == nil
        twinGap.constant = row.twin == nil ? 0 : 4
        chip.set(row.chip, label: row.label, squareHidden: row.chip == .needsYou && blinkOff)
        if time.stringValue != row.elapsed { time.stringValue = row.elapsed }
        toolTip = row.tooltip
        chip.toolTip = row.tooltip
    }
}

/// The status chip: a pill with a small square in the text colour. Port of `.chip`:
/// 600 11px, padding 4px 7px, gap 6, square 6×6; working = info, waiting = white on warn,
/// done = ok, idle = muted. Error uses warn text on the plain fill.
@MainActor
final class ChipView: NSView {
    private var label = ""
    private var kind: DeskList.Row.Chip = .idle
    private var squareHidden = false
    private static let font = Theme.body(11, .semibold)

    func set(_ kind: DeskList.Row.Chip, label: String, squareHidden: Bool) {
        guard kind != self.kind || label != self.label || squareHidden != self.squareHidden else { return }
        let resize = label != self.label
        self.kind = kind; self.label = label; self.squareHidden = squareHidden
        if resize { invalidateIntrinsicContentSize() }
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        let w = (label as NSString).size(withAttributes: [.font: Self.font]).width
        return NSSize(width: ceil(7 + 6 + 6 + w + 7), height: 19)
    }

    override func draw(_ dirtyRect: NSRect) {
        let fg: NSColor, bg: NSColor
        switch kind {
        case .working: fg = Theme.info; bg = Theme.chipFill
        case .needsYou: fg = .white; bg = Theme.warn
        case .finished: fg = Theme.ok; bg = Theme.chipFill
        case .idle: fg = Theme.muted; bg = Theme.chipFill
        case .error: fg = Theme.warn; bg = Theme.chipFill
        }
        bg.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        if !squareHidden {
            fg.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: 7, y: (bounds.height - 6) / 2, width: 6, height: 6), xRadius: 1, yRadius: 1).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: fg]
        let s = (label as NSString).size(withAttributes: attrs)
        (label as NSString).draw(at: NSPoint(x: 19, y: (bounds.height - s.height) / 2), withAttributes: attrs)
    }
}
