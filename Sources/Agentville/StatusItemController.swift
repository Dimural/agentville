// The menu bar item: pixel head, session count, red dot when anything needs you, and the menu
// (docs/product/user-experience.md#menu-bar-item). Port of the prototype's `.mb-crew` button.
// Release/recall (M3) and Settings (M7) join the menu in their milestones.
import AgentvilleCore
import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let toggleWindow = NSMenuItem(title: "Show Window", action: nil, keyEquivalent: "")
    private let dot = CALayer()
    private var needsYou = false
    private let onToggleWindow: () -> Void
    private let isWindowVisible: () -> Bool

    init(onToggleWindow: @escaping () -> Void, isWindowVisible: @escaping () -> Bool) {
        self.onToggleWindow = onToggleWindow
        self.isWindowVisible = isWindowVisible
        super.init()
        guard let button = item.button else { return }
        button.image = Self.headImage()
        button.imagePosition = .imageLeading
        button.toolTip = "Agentville"
        button.setAccessibilityLabel("Agentville")
        button.wantsLayer = true
        // `.mb-dot`: 7×7, warn colour, over the head's top-right corner.
        dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
        dot.cornerRadius = 3.5
        dot.isHidden = true
        button.layer?.addSublayer(dot)

        let menu = NSMenu()
        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        toggleWindow.target = self
        toggleWindow.action = #selector(toggle)
        menu.addItem(toggleWindow)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Agentville", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
    }

    func remove() { NSStatusBar.system.removeStatusItem(item) }

    /// The head as a template image (macOS tints it for the menu bar): 9×9 px at 2 pt per pixel,
    /// with exact 1× and 2× bitmaps so neither is resampled.
    private static func headImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        for scale in [2, 4] {
            guard let cg = PixelImage.cgImage(MenuBarIcon.head, scale: scale) else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = size
            image.addRepresentation(rep)
        }
        image.isTemplate = true
        return image
    }

    func update(_ s: SessionStore.Summary, listening: Bool) {
        guard let button = item.button else { return }
        button.attributedTitle = NSAttributedString(string: "\(s.active)", attributes: [.font: Theme.mono(12, .semibold)])
        needsYou = s.needYou > 0
        layoutDot()
        let head = NSMutableAttributedString(string: "Agentville", attributes: [.font: NSFont.menuFont(ofSize: 0).bold])
        let detail = listening ? DeskList.menuHeader(s) + (s.needYou > 0 ? " · \(s.needYou) need\(s.needYou == 1 ? "s" : "") you" : "")
                               : "not listening (socket unavailable)"
        head.append(NSAttributedString(string: "   " + detail, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        header.attributedTitle = head
        button.setAccessibilityValue(detail)
    }

    private func layoutDot() {
        guard let button = item.button else { return }
        dot.isHidden = !needsYou
        guard needsYou else { return }
        button.effectiveAppearance.performAsCurrentDrawingAppearance { dot.backgroundColor = Theme.warn.cgColor }
        let img = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? .zero
        // Prototype: dot at left 20, top 2 in a button whose 18 px head starts at 8, so it overlaps
        // the head's top-right by 6 px. The button layer isn't flipped: y grows upwards.
        let x = img.minX + 12, top = button.isFlipped ? img.minY - 2 : img.maxY + 2 - 7
        CATransaction.begin(); CATransaction.setDisableActions(true)
        dot.frame = CGRect(x: x, y: button.isFlipped ? top : top, width: 7, height: 7)
        CATransaction.commit()
    }

    func menuWillOpen(_ menu: NSMenu) {
        toggleWindow.title = isWindowVisible() ? "Hide Window" : "Show Window"
    }

    @objc private func toggle() { onToggleWindow() }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
