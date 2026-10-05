// The menu bar item: pixel head, session count, red dot when anything needs you
// (docs/product/user-experience.md#menu-bar-item). Port of the prototype's `.mb-crew` button.
// Left click drops the desk panel down; right click (or ⌃-click) opens the menu
// (docs/decisions/0009-desk-panel-dropdown.md). Settings (M7) joins later; until then the done
// announcement rule (open question 1) is a submenu here.
import AgentvilleCore
import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let keepOpen = NSMenuItem(title: "Keep Panel Open", action: nil, keyEquivalent: "")
    private let crewItem = NSMenuItem(title: "Release the crew", action: nil, keyEquivalent: "")
    /// Settings… (⌘,): the done rule, hide names, Connect/Disconnect and Diagnostics live there.
    var onSettings: (() -> Void)?
    /// Release / call back, and whether the crew is out (for the item's title).
    var onToggleCrew: (() -> Void)?
    var isReleased: () -> Bool = { false }
    private let dot = CALayer()
    private var needsYou = false
    private let onTogglePanel: () -> Void
    private let isPinned: () -> Bool
    private let onTogglePin: () -> Void

    init(onTogglePanel: @escaping () -> Void, isPinned: @escaping () -> Bool, onTogglePin: @escaping () -> Void) {
        self.onTogglePanel = onTogglePanel
        self.isPinned = isPinned
        self.onTogglePin = onTogglePin
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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

        menu.delegate = self
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        crewItem.target = self
        crewItem.action = #selector(toggleCrew)
        // Shown for discoverability; the global shortcut itself is `HotKey`.
        crewItem.keyEquivalent = "c"
        crewItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(crewItem)
        keepOpen.target = self
        keepOpen.action = #selector(togglePin)
        menu.addItem(keepOpen)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem(title: "Quit Agentville", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// The same menu, for the panel's "⋯" button.
    var moreMenu: NSMenu { menu }

    /// The icon's rect on screen and that screen's visible frame, for placing the panel under it.
    var anchor: (icon: CGRect, screen: CGRect)? {
        guard let button = item.button, let w = button.window, let screen = w.screen else { return nil }
        return (w.convertToScreen(button.convert(button.bounds, to: nil)), screen.visibleFrame)
    }

    /// Pressed look while the panel is open, like a status item whose menu is showing.
    func setPanelOpen(_ open: Bool) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.item.button?.highlight(open) }
        }
    }

    @objc private func clicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true {
            // Attach the menu just for this click so a left click stays free for the panel.
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            onTogglePanel()
        }
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
        keepOpen.state = isPinned() ? .on : .off
        crewItem.title = isReleased() ? "Call the crew back" : "Release the crew"
    }

    @objc private func openSettings() { onSettings?() }

    @objc private func toggleCrew() { onToggleCrew?() }

    /// Where the crew flies when the desk panel is closed: just under the icon (prototype `menuIconPos`).
    var iconHome: CGPoint? {
        guard let a = anchor else { return nil }
        return CGPoint(x: a.icon.minX + 14, y: a.icon.minY)
    }

    @objc private func togglePin() { onTogglePin() }
}

private extension NSFont {
    var bold: NSFont { NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask) }
}
