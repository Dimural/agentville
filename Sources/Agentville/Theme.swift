// Colours and fonts for the desk window and menu bar, copied from the prototype's CSS tokens
// (`--win`, `--win-ink`, `--warn`, … light and dark). The prototype wins on look (AGENTS.md).
import AgentvilleCore
import AppKit

@MainActor
enum Theme {
    private static func dynamic(_ light: String, _ dark: String, alpha: CGFloat = 1, darkAlpha: CGFloat? = nil) -> NSColor {
        NSColor(name: nil) { ap in
            let isDark = ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return color(isDark ? dark : light, alpha: isDark ? (darkAlpha ?? alpha) : alpha)
        }
    }

    static func color(_ hex: String, alpha: CGFloat = 1) -> NSColor {
        let c = RGB(hex)
        return NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: alpha)
    }

    static let win = dynamic("#F6F6FA", "#22253F")
    static let ink = dynamic("#23263F", "#ECEAF7")
    static let muted = dynamic("#6A6E8E", "#A3A2C4")
    static let line = dynamic("#1C2040", "#FFFFFF", alpha: 0.14, darkAlpha: 0.1)
    static let warn = dynamic("#E0164A", "#FF4D76")
    static let ok = dynamic("#0E8F50", "#3DDC84")
    static let info = dynamic("#2B7BD6", "#6CB2FF")
    /// `.chip` background: rgba(127,127,160,.16) in both themes.
    static let chipFill = NSColor(srgbRed: 127 / 255, green: 127 / 255, blue: 160 / 255, alpha: 0.16)
    static let accent = color("#FFA300")
    static let pixDark = color("#1A1330")
    static let pixPaper = color("#FFF8EC")

    static func isDark(_ view: NSView) -> Bool {
        view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Stand-ins for the prototype's web fonts (no third-party fonts without an ADR).
    static func body(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size, weight: weight) }
    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight) }
    static func digits(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .monospacedDigitSystemFont(ofSize: size, weight: weight) }
}

/// Shows a pixel `CGImage` stretched to its bounds with nearest-neighbour filtering. Callers size it
/// to an integer multiple of the image (docs/architecture/app.md#rendering).
final class PixelView: NSView {
    var image: CGImage? {
        didSet { layer?.contents = image }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
        layer?.contentsGravity = .resize
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }
}
