import CoreGraphics
import Testing
@testable import AgentvilleCore

/// Where the desk panel drops down (docs/decisions/0009-desk-panel-dropdown.md). AppKit screen
/// coordinates: origin bottom-left, y grows upwards; the menu bar is at the top of `screen`.
@Suite("Desk panel placement")
struct PanelPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)   // visible frame, below the menu bar
    let size = CGSize(width: 432, height: 500)

    @Test("Left edge lines up with the icon, top just under the menu bar")
    func underTheIcon() {
        let icon = CGRect(x: 900, y: 878, width: 40, height: 22)
        let f = PanelPlacement.frame(size: size, under: icon, screen: screen)
        #expect(f.minX == 900)
        #expect(f.maxY == 878 - PanelPlacement.gap)
        #expect(f.size == size)
    }

    @Test("Shifted left to stay on screen near the right edge")
    func rightEdge() {
        let icon = CGRect(x: 1300, y: 878, width: 40, height: 22)
        let f = PanelPlacement.frame(size: size, under: icon, screen: screen)
        #expect(f.maxX == 1440 - PanelPlacement.margin)
    }

    @Test("Never off the left edge, and never taller than the screen")
    func clamps() {
        let icon = CGRect(x: -20, y: 878, width: 40, height: 22)
        let tall = PanelPlacement.frame(size: CGSize(width: 432, height: 2000), under: icon, screen: screen)
        #expect(tall.minX == PanelPlacement.margin)
        #expect(tall.minY >= screen.minY + PanelPlacement.margin)
        #expect(tall.maxY == 878 - PanelPlacement.gap)
    }

    @Test("Coordinates are whole points")
    func whole() {
        let icon = CGRect(x: 900.4, y: 878.6, width: 40, height: 22)
        let f = PanelPlacement.frame(size: size, under: icon, screen: screen)
        #expect(f.minX == f.minX.rounded() && f.minY == f.minY.rounded())
    }

    @Test("An icon not yet on the menu bar (at launch) falls back to the top-right corner")
    func unplacedIcon() {
        let icon = CGRect(x: 0, y: -11, width: 48, height: 22)
        let f = PanelPlacement.frame(size: size, under: icon, screen: screen)
        #expect(f.maxX == 1440 - PanelPlacement.margin)
        #expect(f.maxY == 875 - PanelPlacement.gap)
        #expect(f.size == size)
    }
}
