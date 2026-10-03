import Foundation

/// When a finished turn earns a "Done!" walk-on while the crew is inside (open question 1;
/// docs/product/sessions-and-states.md#done-announcement-rule). Roamers on the desktop and the
/// office cheer every turn whatever this says. The raw values are what the preference stores.
public enum DoneAnnouncement: String, CaseIterable, Sendable {
    case everyTurn = "every"
    /// Turns of at least `Timing.announceDoneMinTurn` (20 s). The default.
    case longTurns = "long"
    case never

    /// `duration` is nil when the turn's start wasn't seen (hooks installed mid-turn).
    public func announces(_ duration: TimeInterval?) -> Bool {
        switch self {
        case .everyTurn: true
        case .longTurns: (duration ?? 0) >= Timing.announceDoneMinTurn
        case .never: false
        }
    }
}
