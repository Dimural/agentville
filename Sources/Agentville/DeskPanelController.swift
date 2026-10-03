// The desk panel: drops down under the menu bar icon like Wi-Fi or Control Center
// (docs/decisions/0009-desk-panel-dropdown.md). Inside: the pixel office, the summary line, the
// session list and a small footer (pin, more). Click the icon again, click elsewhere or press Esc
// to fold it away; pinned, it stays open and can be dragged anywhere.
// The office redraws at about 12 fps and the list at most at 4 Hz, both only while the panel is
// visible (docs/architecture/app.md#performance-rules). The Release button arrives with M3.
import AgentvilleCore
import AppKit

/// Borderless and non-activating, so opening it doesn't pull focus from the user's app, but it can
/// still become key for Esc.
final class DeskPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor
final class DeskPanelController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let app: AppDelegate
    private let panel: DeskPanel
    private let office = OfficeView()
    private let summary = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private let pinButton = NSButton()
    private let moreButton = NSButton()
    private let releaseButton = ReleaseButton()
    private let hint = NSTextField(labelWithString: "")
    private let content = WindowBackground()
    private var rows: [DeskList.Row] = []
    private var officeTimer: Timer?
    private var listTimer: Timer?
    private var outsideClicks: Any?
    private var shownRevision = -1
    private var shownSecond = -1
    private var shownBlink = false
    private let sprites = SpriteCache()
    private var avatars: [Look: CGImage] = [:]
    /// Where the icon is (screen rect) and which screen's visible frame to stay inside.
    private let anchor: () -> (icon: CGRect, screen: CGRect)?
    private let moreMenu: () -> NSMenu
    /// Sessions whose characters are out on the desktop: their desks are empty.
    var away: () -> Set<String> = { [] }
    /// The Release / Call back button.
    var onToggleCrew: (() -> Void)?
    /// Tells the status item to show its pressed state while the panel is open.
    var onVisibilityChange: ((Bool) -> Void)?

    /// Office layout in points: 2 pt per room unit (docs/design/office.md#geometry).
    static let officeSize = NSSize(width: OfficeRenderer.pixelSize.width, height: OfficeRenderer.pixelSize.height)
    static let rowHeight: CGFloat = 38
    static let summaryHeight: CGFloat = 33
    /// `.winfoot`: padding 10 12 12 around the chunky button.
    static let footerHeight: CGFloat = 63
    /// Transparent room around the panel so the burp's overshoot isn't clipped.
    static let margin: CGFloat = 14
    /// Four rows show at once; more scroll (the prototype's list scrolls too).
    static let size = NSSize(width: officeSize.width,
                             height: officeSize.height + summaryHeight + 1 + 4 * rowHeight + 1 + footerHeight)

    private(set) var pinned = false

    init(app: AppDelegate, anchor: @escaping () -> (icon: CGRect, screen: CGRect)?, moreMenu: @escaping () -> NSMenu) {
        self.app = app
        self.anchor = anchor
        self.moreMenu = moreMenu
        panel = DeskPanel(contentRect: NSRect(origin: .zero, size: NSSize(width: Self.size.width + 2 * Self.margin, height: Self.size.height + 2 * Self.margin)),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }
        buildContent()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { if panel.isVisible { hide() } else { show() } }

    func show() {
        place()
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        watchOutsideClicks()
        updateTimers()
        onVisibilityChange?(true)
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        watchOutsideClicks()
        updateTimers()
        onVisibilityChange?(false)
    }

    func close() {
        panel.orderOut(nil)
        if let m = outsideClicks { NSEvent.removeMonitor(m); outsideClicks = nil }
        updateTimers()
    }

    /// Pinned: stays open when you click elsewhere, floats above normal windows and can be dragged.
    /// Unpinned: snaps back under the icon.
    func setPinned(_ on: Bool) {
        pinned = on
        panel.isMovableByWindowBackground = on
        panel.level = on ? .floating : .popUpMenu
        pinButton.state = on ? .on : .off
        pinButton.image = Self.symbol(on ? "pin.fill" : "pin", label: on ? "Unpin" : "Keep open")
        pinButton.contentTintColor = on ? Theme.info : Theme.muted
        pinButton.toolTip = on ? "Unpin: close when you click elsewhere" : "Keep open"
        if !on, panel.isVisible { place() }
        watchOutsideClicks()
    }

    private func place() {
        guard let a = anchor() else { panel.center(); return }
        let f = PanelPlacement.frame(size: Self.size, under: a.icon, screen: a.screen)
        panel.setFrame(f.insetBy(dx: -Self.margin, dy: -Self.margin), display: false)
    }

    /// Clicks in other apps fold the panel away. A global mouse monitor needs no permission (only
    /// key monitors do: non-negotiable #9) and exists only while an unpinned panel is open.
    private func watchOutsideClicks() {
        let want = panel.isVisible && !pinned
        if want, outsideClicks == nil {
            outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            }
        } else if !want, let m = outsideClicks {
            NSEvent.removeMonitor(m)
            outsideClicks = nil
        }
    }

    // MARK: - The crew

    func setReleased(_ on: Bool) { releaseButton.setReleased(on) }

    /// Screen point of desk `i`'s feet (where a character sits), while the panel is open.
    func deskFeet(_ i: Int) -> CGPoint? {
        guard panel.isVisible, i < Limits.desks else { return nil }
        let d = OfficeRenderer.deskUnits(i)
        let p = office.convert(CGPoint(x: d.fx * 2, y: d.fy * 2), to: nil)
        return panel.convertPoint(toScreen: p)
    }

    /// Screen point for sessions without a desk: the top of the list (prototype `homePos`).
    var listAnchor: CGPoint? {
        guard panel.isVisible else { return nil }
        let p = office.convert(CGPoint(x: office.bounds.midX, y: office.bounds.maxY + Self.summaryHeight + 30), to: nil)
        return panel.convertPoint(toScreen: p)
    }

    /// The window burps as the crew pours out: 0.55 s, overshoot easing (port of `@keyframes burp`).
    func burp() {
        animate(key: "burp", duration: 0.55, times: [0, 0.25, 0.55, 1],
                values: [(1, 1, 0), (1.035, 0.965, 0), (0.985, 1.02, 4), (1, 1, 0)],
                timing: CAMediaTimingFunction(controlPoints: 0.3, 1.6, 0.5, 1))
    }

    /// The window gulps when the last one is home: 0.35 s ease-out (port of `@keyframes gulp`).
    func gulp() {
        animate(key: "gulp", duration: 0.35, times: [0, 0.4, 1],
                values: [(1, 1, 0), (1.02, 1.02, 0), (1, 1, 0)],
                timing: CAMediaTimingFunction(name: .easeOut))
    }

    /// Scales about the panel's centre; `lift` moves it up (CSS translateY(−4)).
    private func animate(key: String, duration: Double, times: [Double], values: [(CGFloat, CGFloat, CGFloat)],
                         timing: CAMediaTimingFunction) {
        guard panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = content.layer else { return }
        let c = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = values.map { sx, sy, lift in
            var t = CATransform3DMakeTranslation(c.x, c.y + lift, 0)
            t = CATransform3DScale(t, sx, sy, 1)
            return NSValue(caTransform3D: CATransform3DTranslate(t, -c.x, -c.y, 0))
        }
        a.keyTimes = times.map { NSNumber(value: $0) }
        a.timingFunctions = Array(repeating: timing, count: times.count - 1)
        a.duration = duration
        layer.add(a, forKey: key)
    }

    // MARK: - NSWindowDelegate

    /// Another of our windows taking key (a future Settings window) also folds an unpinned panel.
    func windowDidResignKey(_ notification: Notification) {
        guard !pinned else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, NSApp.keyWindow != nil, NSApp.keyWindow !== self.panel else { return }
                self.hide()
            }
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateTimers() }

    // MARK: - Timers (run only while the panel can be seen)

    private var canBeSeen: Bool {
        panel.isVisible && panel.occlusionState.contains(.visible)
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

    // MARK: - Footer

    private static func symbol(_ name: String, label: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
    }

    @objc private func togglePin() { setPinned(!pinned) }

    @objc private func showMore() {
        let m = moreMenu()
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.height + 4), in: moreButton)
    }

    // MARK: - Office

    private func drawOffice() {
        let sessions = app.store.ordered
        let clock = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let scene = OfficeScene(sessions: sessions, awayIDs: away(), night: Theme.isDark(office),
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

        let rule = Self.rule()
        let footRule = Self.rule()

        for (b, sel) in [(pinButton, #selector(togglePin)), (moreButton, #selector(showMore))] {
            b.isBordered = false
            b.bezelStyle = .regularSquare
            b.imagePosition = .imageOnly
            b.target = self
            b.action = sel
            b.contentTintColor = Theme.muted
        }
        moreButton.image = Self.symbol("ellipsis.circle", label: "More")
        moreButton.toolTip = "More"
        setPinned(false)

        releaseButton.onPress = { [weak self] in self?.onToggleCrew?() }

        // Rounded like Control Center's panels; the clear window shadow follows the corners.
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor(white: 0.5, alpha: 0.25).cgColor
        // `.winfoot .hint`: "⌃⌥C toggles", the keys in a kbd box (mono).
        let h = NSMutableAttributedString(string: " ⌃⌥C ", attributes: [.font: Theme.mono(12, .medium), .foregroundColor: Theme.ink,
                                                                     .backgroundColor: Theme.chipFill])
        h.append(NSAttributedString(string: " toggles", attributes: [.font: Theme.body(12), .foregroundColor: Theme.muted]))
        hint.attributedStringValue = h
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [office, summary, rule, scroll, footRule, releaseButton, hint, pinButton, moreButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            // A borderless window takes its size from the content, so pin it.
            content.widthAnchor.constraint(equalToConstant: Self.size.width),
            content.heightAnchor.constraint(equalToConstant: Self.size.height),
            office.topAnchor.constraint(equalTo: content.topAnchor),
            office.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            office.widthAnchor.constraint(equalToConstant: Self.officeSize.width),
            office.heightAnchor.constraint(equalToConstant: Self.officeSize.height),
            summary.topAnchor.constraint(equalTo: office.bottomAnchor, constant: 9),
            summary.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            summary.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            rule.topAnchor.constraint(equalTo: office.bottomAnchor, constant: Self.summaryHeight),
            rule.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            rule.heightAnchor.constraint(equalToConstant: 1),
            scroll.topAnchor.constraint(equalTo: rule.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footRule.topAnchor),
            footRule.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            footRule.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            footRule.heightAnchor.constraint(equalToConstant: 1),
            footRule.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.footerHeight),
            releaseButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            releaseButton.topAnchor.constraint(equalTo: footRule.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: releaseButton.trailingAnchor, constant: 12),
            hint.centerYAnchor.constraint(equalTo: releaseButton.centerYAnchor),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: pinButton.leadingAnchor, constant: -8),
            moreButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            moreButton.centerYAnchor.constraint(equalTo: content.bottomAnchor, constant: -Self.footerHeight / 2),
            moreButton.widthAnchor.constraint(equalToConstant: 24),
            moreButton.heightAnchor.constraint(equalToConstant: 24),
            pinButton.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -4),
            pinButton.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            pinButton.widthAnchor.constraint(equalToConstant: 24),
            pinButton.heightAnchor.constraint(equalToConstant: 24),
        ])
        let container = NSView(frame: NSRect(origin: .zero, size: panel.frame.size))
        content.frame = container.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        content.translatesAutoresizingMaskIntoConstraints = true
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        panel.contentView = container
    }

    private static func rule() -> NSBox {
        let r = NSBox()
        r.boxType = .custom
        r.borderWidth = 0
        r.fillColor = Theme.line
        return r
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
