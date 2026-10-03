import Foundation

/// Keeps a stalled overlay off the screen (bug 0001, docs/bugs/0001-grey-screen-overlay.md).
///
/// The overlay is a full-screen window. If its scene stops delivering frames while it's up, a lost
/// or unpresented surface could cover the whole screen. So while the overlay is awake the app
/// reports every frame and checks about once a second. After `Timing.overlayStall` without a frame
/// the window is taken off screen (`.hide`). It is tried again (`.show`) after a backoff that doubles
/// from `Timing.overlayRetryFirst` up to `Timing.overlayRetryMax`, or at once when a frame arrives.
/// Pure, so it is tested without a window.
public struct OverlayWatchdog: Sendable {
    public enum Action: Equatable, Sendable { case hide, show }

    /// The overlay is meant to be on screen (between `awake` and `asleep`).
    public private(set) var active = false
    /// On screen as far as the watchdog is concerned (false while it's hiding a stalled overlay).
    public private(set) var visible = false
    /// Stalls in a row without a frame in between.
    public private(set) var stalls = 0
    private var lastFrame = 0.0
    private var retryAt = 0.0

    public init() {}

    /// The overlay woke and went on screen. Counts as a frame, so a fresh window gets the full
    /// stall time to draw its first one.
    public mutating func awake(at now: TimeInterval) {
        active = true
        visible = true
        stalls = 0
        lastFrame = now
    }

    /// The overlay went to sleep on purpose (crew home) or closed.
    public mutating func asleep() {
        active = false
        visible = false
        stalls = 0
    }

    /// A frame was drawn. Brings a hidden overlay back.
    public mutating func frame(at now: TimeInterval) -> Action? {
        guard active else { return nil }
        lastFrame = now
        if !visible {
            visible = true
            stalls = 0
            return .show
        }
        stalls = 0
        return nil
    }

    /// Called about once a second while active.
    public mutating func check(at now: TimeInterval) -> Action? {
        guard active else { return nil }
        if visible {
            guard now - lastFrame > Timing.overlayStall else { return nil }
            visible = false
            stalls += 1
            let wait = min(Timing.overlayRetryMax, Timing.overlayRetryFirst * pow(2, Double(stalls - 1)))
            retryAt = now + wait
            return .hide
        }
        guard now >= retryAt else { return nil }
        // Try again; it gets the full stall time to draw before it's hidden again.
        visible = true
        lastFrame = now
        return .show
    }
}
