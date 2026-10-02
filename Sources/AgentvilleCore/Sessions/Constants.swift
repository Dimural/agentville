import Foundation

/// Behaviour and limit constants. Values come from the prototype; see
/// docs/design/motion-and-behaviour.md and docs/product/sessions-and-states.md. Don't scatter copies.
public enum Limits {
    /// Max characters roaming the desktop (prototype `CAP`).
    public static let roamers = 12
    /// Max simultaneous walk-on notices.
    public static let walkOns = 3
    /// Max particles alive (prototype `parts.length > 520`).
    public static let particles = 520
    /// Max queued notices before folding into "+N more" (prototype: 24).
    public static let noticeQueue = 24
    /// Desks in the office.
    public static let desks = 6
    /// Max sessions tracked by the store; oldest idle sessions are evicted beyond this.
    public static let trackedSessions = 512
    /// Max concurrent subagents tracked per session.
    public static let subagentsPerSession = 32
    /// Diagnostics ring buffer (in-memory only).
    public static let diagnosticsLines = 200
    /// Max events the socket listener hands to the store at once; the rest follow in the next batch.
    public static let listenerBatch = 1024
    /// Rendered sprite frames kept in `SpriteCache` (LRU).
    public static let spriteCache = 2000
    /// Max rows the M1 debug window lists (the store itself is capped at `trackedSessions`).
    public static let debugListRows = 200
}

public enum Timing {
    /// UI list/summary refresh interval (4 Hz).
    public static let listRefresh: TimeInterval = 0.25
    /// Office redraw interval (≈12 fps).
    public static let officeFrame: TimeInterval = 1.0 / 12.0
    /// How often the app runs `SessionStore.tick` (finished → idle, staleness). Coarse on purpose.
    public static let storeTick: TimeInterval = 5
    /// Finished → idle after this long without another event (prototype: 6 s).
    public static let finishedHold: TimeInterval = 6
    /// Proposed default for announcing "done" walk-ons (open question 1).
    public static let announceDoneMinTurn: TimeInterval = 20
    /// Recall force-complete.
    public static let recallForceComplete: TimeInterval = 2.6

    /// Staleness: silence after which a session is removed, by what it was last doing.
    public enum Stale {
        public static let toolRunning: TimeInterval = 30 * 60
        public static let needsYou: TimeInterval = 60 * 60
        public static let working: TimeInterval = 15 * 60
        public static let idle: TimeInterval = 45 * 60
    }
}
