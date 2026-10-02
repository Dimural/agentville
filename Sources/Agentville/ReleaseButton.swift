// The chunky pixel button in the desk panel's footer (port of the prototype's `.pbtn`): orange
// "Release the crew" with an up arrow, blue "Call the crew back" while the crew is out, and a
// gentle invite bounce until it's first used (docs/product/user-experience.md#desk-panel-the-office).
import AgentvilleCore
import AppKit

@MainActor
final class ReleaseButton: NSView {
    var onPress: (() -> Void)?
    private(set) var released = false
    private var pressed = false
    private var inviting = true
    private let font = NSFont.systemFont(ofSize: 15, weight: .bold)

    /// The 7×7 pixel arrow from the prototype's inline SVG.
    private static let arrow = ["...#...", "..###..", ".#####.", "...#...", "...#...", "...#...", "...#..."]

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityRole(.button)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private var title: String { released ? "Call the crew back" : "Release the crew" }

    func setReleased(_ on: Bool) {
        released = on
        stopInvite()
        invalidateIntrinsicContentSize()
        needsDisplay = true
        updateAccessibility()
    }

    private func updateAccessibility() { setAccessibilityLabel(title) }

    override var intrinsicContentSize: NSSize {
        let w = (title as NSString).size(withAttributes: [.font: font]).width
        // padding 10 16 12, 14 pt arrow, 8 pt gap, plus the 2 pt ink ring on each side.
        return NSSize(width: ceil(16 + 14 + 8 + w + 16 + 4), height: 15 + 22 + 4)
    }

    // MARK: - Invite bounce (2.4 s loop: 78% −3, 86% 0, 92% −2)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if inviting, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { startInvite() }
    }

    private func startInvite() {
        guard let layer, layer.animation(forKey: "invite") == nil else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.y")
        a.values = [0, 0, 3, 0, 2, 0] // the layer isn't flipped: up is positive
        a.keyTimes = [0, 0.7, 0.78, 0.86, 0.92, 1]
        a.duration = 2.4
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(a, forKey: "invite")
    }

    private func stopInvite() {
        inviting = false
        layer?.removeAnimation(forKey: "invite")
    }

    // MARK: - Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { pressed = true; needsDisplay = true }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != pressed { pressed = inside; needsDisplay = true }
    }

    override func mouseUp(with event: NSEvent) {
        let fire = pressed && bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        needsDisplay = true
        if fire { stopInvite(); onPress?() }
    }

    override func accessibilityPerformPress() -> Bool { onPress?(); return true }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let ring: CGFloat = 2, dy: CGFloat = pressed ? 2 : 0
        let outer = bounds.offsetBy(dx: 0, dy: dy).insetBy(dx: 0, dy: 1)
        let face = outer.insetBy(dx: ring, dy: ring)
        Theme.pixDark.setFill()
        NSBezierPath(roundedRect: outer, xRadius: 3 + ring, yRadius: 3 + ring).fill()
        (released ? Theme.color("#29ADFF") : Theme.accent).setFill()
        NSBezierPath(roundedRect: face, xRadius: 3, yRadius: 3).fill()
        // Bevels: inset −3 −4 dark, 3 3 light (swapped while pressed).
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: face, xRadius: 3, yRadius: 3).addClip()
        if pressed {
            NSColor(white: 0, alpha: 0.2).setFill()
            NSRect(x: face.minX, y: face.minY, width: face.width, height: 4).fill()
            NSRect(x: face.minX, y: face.minY, width: 3, height: face.height).fill()
        } else {
            NSColor(white: 0, alpha: 0.22).setFill()
            NSRect(x: face.minX, y: face.maxY - 4, width: face.width, height: 4).fill()
            NSRect(x: face.maxX - 3, y: face.minY, width: 3, height: face.height).fill()
            NSColor(white: 1, alpha: 0.35).setFill()
            NSRect(x: face.minX, y: face.minY, width: face.width, height: 3).fill()
            NSRect(x: face.minX, y: face.minY, width: 3, height: face.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let ink = Theme.color(released ? "#1A1330" : "#1C1A2E")
        ink.setFill()
        let ax = face.minX + 14, ay = face.midY - 7
        for (r, row) in Self.arrow.enumerated() {
            for (c, ch) in row.enumerated() where ch == "#" {
                NSRect(x: ax + CGFloat(c) * 2, y: ay + CGFloat(r) * 2, width: 2, height: 2).fill()
            }
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
        let ts = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: ax + 14 + 8, y: face.midY - ts.height / 2 - 1), withAttributes: attrs)
    }
}
