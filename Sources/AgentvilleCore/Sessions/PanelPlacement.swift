import CoreGraphics

/// Where the desk panel drops down under the menu bar icon (docs/decisions/0009-desk-panel-dropdown.md).
/// Like a status item's menu: left edge on the icon's left edge, just under the menu bar, shifted to
/// stay inside the screen's visible frame. AppKit screen coordinates (y grows upwards). Whole points.
public enum PanelPlacement {
    /// Space between the menu bar and the panel's top edge.
    public static let gap: CGFloat = 6
    /// Minimum distance from the screen's sides and bottom.
    public static let margin: CGFloat = 8

    public static func frame(size: CGSize, under icon: CGRect, screen: CGRect) -> CGRect {
        // At launch the status item may not be on the menu bar yet (it sits at y < 0). The menu bar
        // is above the visible frame, so an icon below its top isn't placed: use the top-right corner.
        let icon = icon.minY >= screen.maxY - 1 ? icon : CGRect(x: screen.maxX, y: screen.maxY, width: 0, height: 0)
        let top = (icon.minY - gap).rounded(.down)
        let height = min(size.height, top - screen.minY - margin)
        let maxX = screen.maxX - margin - size.width
        let x = max(screen.minX + margin, min(icon.minX, maxX)).rounded(.down)
        return CGRect(x: x, y: top - height, width: size.width, height: height)
    }
}
