# 0009: The desk is a dropdown panel under the menu bar icon
Status: Accepted
Date: 2026-10-02

## Context
M2 shipped the office and session list in an ordinary titled window opened from the status item's menu. The owner reviewed it and asked for it to behave like the system's menu bar extras (Wi-Fi, Control Center, Battery): click the icon and the content drops down below it, click again or elsewhere and it folds away. A separate window felt like one more thing to manage.

## Decision
- The desk is a **borderless, non-activating panel** (`DeskPanelController`) that drops down under the status item: left edge on the icon, 6 pt under the menu bar, kept 8 pt inside the screen (`PanelPlacement`, Core, `PanelPlacementTests`). Rounded corners (10 pt), a hairline border, the window shadow; no title bar and no arrow.
- **Left click** on the icon toggles it. **Right click** (or ⌃-click) opens the menu (header, Keep Panel Open, Quit). The panel's footer has a pin and a "⋯" button that opens the same menu.
- It folds away on a second click of the icon, a click in any other app, or Esc. Outside clicks come from a global mouse monitor, which needs no permission (only key monitors do; non-negotiable #9), and exists only while an unpinned panel is open.
- **Pinned** ("Keep open"): it stays open, floats above normal windows and can be dragged anywhere, for side-by-side reviews. Unpinning snaps it back under the icon. `Agentville --show-desk` opens it pinned.
- Contents are unchanged from the M2 window: office, summary line, session list (4 rows visible, the rest scroll). The Release button joins the footer in M3.

## Consequences
- Docs that say "desk window" now mean this panel. M3's release/recall effects (burp, gulp) play on the panel when it's open; when it's closed, the crew flies into the menu bar icon, as [user-experience.md](../product/user-experience.md) already specifies.
- The panel is not a normal window: it has no Dock or ⌘` presence and no minimise. Timers still stop whenever it's hidden or covered.
- Clicking elsewhere closes it, so anything that must stay visible while the user works (walk-on notices, the crew) belongs in the overlay, not the panel.
