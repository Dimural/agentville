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

/// How the crew moves on the desktop. Values from the prototype; table in
/// docs/design/motion-and-behaviour.md. Points and seconds.
public enum Motion {
    /// Prototype `G`.
    public static let gravity = 1500.0
    /// Release: first leap after 120 ms, then one every 85 ms.
    public static let releaseFirst = 0.12, releaseStagger = 0.085
    /// Release flight duration range.
    public static let releaseFlight = 0.8...1.1
    /// Recall: first one leaves after 60 ms, then one every 55 ms, bottom-most first.
    public static let recallFirst = 0.06, recallStagger = 0.055
    /// Recall flight duration range.
    public static let recallFlight = 0.5...0.7
    /// Stretched while flying (`sx .92, sy 1.1`).
    public static let flightStretch = (x: 0.92, y: 1.1)
    /// Landing squash: decays at 6/s; `sx = 1 + .22·squash`, `sy = 1 − .22·squash`.
    public static let squashDecay = 6.0, squashAmount = 0.22
    /// A new session while the crew is out drops in from 70% of the screen height.
    public static let dropHeight = 0.7
    /// "Bye!" wave before an ended session's character poofs.
    public static let leaveTime = 1.1
    /// Walking speeds, pt/s: working, searching (creeping with the magnifier), idle stroll, the
    /// "needs you" run to the bottom of the screen.
    public static let walk = 48.0, searchCreep = 26.0, idleStroll = 32.0, needsYouRun = 120.0
    /// How long a character acts before wandering on: working, idle.
    public static let actWorking = 3.0...7.0, actIdle = 6.0...12.0
    /// How far it wanders (y range × 0.6): working, idle.
    public static let wanderWorking = 220.0, wanderIdle = 120.0
    /// First act after landing.
    public static let actAfterLanding = 0.6...1.6
    /// Cheer after a turn finishes.
    public static let cheer = 2.6
    /// Chance of a shout on release / recall.
    public static let releaseShoutChance = 0.35, recallShoutChance = 0.3
    /// Done!: the bubble stays 5 s; 26 confetti (a quarter with reduced motion).
    public static let doneBubble = 5.0, doneConfetti = 26
    /// Meetings (`checkMeetings`): checked every 0.35 s; within 44 pt; stop for 1.6 s, cheering for
    /// the first 0.8 s; then 18–30 s before meeting again (6–16 s at first).
    public static let meetCheck = 0.35, meetDistance = 44.0, meet = 1.6, meetCheer = 0.8
    public static let meetCooldown = 18.0...30.0, meetFirstCooldown = 6.0...16.0
    /// A sidekick catches up at up to 140 pt/s.
    public static let sidekickFollow = 140.0
}

/// What the crew says (docs/design/motion-and-behaviour.md#phrases).
public enum Phrases {
    public static let release = ["Wheee!", "Freedom!", "Hi!", "Let's go!", "Stretch time"]
    public static let recall = ["Coming!", "Okay!", "Back to work!", "On my way"]
    public static let meet = ["hi!", "nice commit", "lunch?", "high five!"]
    public static let hello = "Hello!", bye = "Bye!", done = "Done!", needsYou = "Needs you"
}
