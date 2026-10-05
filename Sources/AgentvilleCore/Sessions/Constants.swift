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
    /// Bug 0001: an awake overlay without a frame for this long is taken off screen (`OverlayWatchdog`).
    public static let overlayStall: TimeInterval = 2
    /// …and tried again after this, doubling each time it stalls again, up to `overlayRetryMax`.
    public static let overlayRetryFirst: TimeInterval = 1
    public static let overlayRetryMax: TimeInterval = 30
    /// The overlay goes on screen transparent and is revealed after this many frames (bug 0001).
    public static let overlayRevealFrames = 2
    /// A longer gap between overlay frames is logged to `Diagnostics` as a hitch.
    public static let overlayFrameGap: TimeInterval = 0.25
    /// How often the app asks the watchdog while the overlay is awake.
    public static let overlayCheck: TimeInterval = 1

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
    /// Hover fade: a character under the cursor eases to this opacity, at `min(1, dt·hoverEase)`.
    public static let hoverAlpha = 0.16, hoverEase = 14.0
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

    /// Walk-ons (prototype `notify-in`/`notify-hold`/`notify-out`): in from the right edge at 95 pt/s,
    /// off again at 110. A Done! walk-on holds 6.5 s (cheering for the first 2.4, 30 confetti); a
    /// Needs-you one up to 16 s, or until it's answered. Slot k stands `walkOnSpacing·k` further left
    /// and `walkOnStep·k` higher, from `walkOnRight` and `walkOnBottom` in from the edges.
    public static let walkOnIn = 95.0, walkOnOut = 110.0
    public static let walkOnDoneHold = 6.5, walkOnNeedsYouHold = 16.0, walkOnCheer = 2.4, walkOnConfetti = 30
    public static let walkOnRight = 80.0, walkOnSpacing = 130.0, walkOnBottom = 22.0, walkOnStep = 6.0
    /// Screen widths below which only 2, then 1, walk-on slots fit (prototype `slotsMax`).
    public static let walkOnTwoSlotsBelow = 900.0, walkOnOneSlotBelow = 560.0

    /// The crowd (prototype `spawnCrowd`, `roamCrowd`): leaps out 60 ms after the last roamer in a
    /// 1.1 s flight; wanders at 22 pt/s for up to 160 pt, resting 3–6 s between walks. A member's
    /// finished turn: "name finished" for 2.4 s and 12 confetti.
    public static let crowdAfterRoamers = 0.06, crowdFlight = 1.1
    public static let crowdWander = 22.0, crowdWanderRadius = 160.0, crowdAct = 3.0...6.0
    public static let crowdFinishedBubble = 2.4, crowdConfetti = 12
    /// Stepping out of the crowd (prototype `syncRoamers`): a 0.7 s hop to within 140 pt of it.
    public static let stepOutFlight = 0.7, stepOutRadius = 140.0
    /// How often the roamers are re-synced with the sessions (prototype: every 0.25 s).
    public static let rosterSync = 0.25
}

/// What the crew says (docs/design/motion-and-behaviour.md#phrases).
/// Grabbing, dragging and throwing (docs/design/motion-and-behaviour.md#throwing,
/// docs/architecture/input-and-safety.md).
public enum Grab {
    /// Hit-box padding for grabbing and for the hover fade.
    public static let pad = 4.0, hoverPad = 6.0
    /// Less movement than this between press and release is a tap.
    public static let tapDistance = 5.0
    /// Held characters float this high.
    public static let lift = 10.0
    /// Throw samples kept, and the shortest time span they count over.
    public static let samples = 6, minSampleSpan = 0.016
    public static let maxSpeed = 1500.0, dizzySpeed = 900.0, shoutSpeed = 700.0
    public static let verticalDamping = 0.6
    public static let liftFactor = 0.35, minLift = 80.0, maxLift = 460.0
    public static let wallBounce = 0.6, wallSquash = 0.8
    public static let groundBounceSpeed = 260.0, groundBounce = 0.42, bounceDamping = 0.65
    public static let friction = 7.0, settleSpeed = 18.0
    public static let dizzyTime = 1.8
    /// A tapped character hops (cheers) this long.
    public static let tapCheer = 0.7
}

public enum Phrases {
    public static let tap = ["hey!", "boop", "hi there", "*giggle*"]
    public static let throwShout = ["waaah!", "whoa!", "aaa!"]
    public static let release = ["Wheee!", "Freedom!", "Hi!", "Let's go!", "Stretch time"]
    public static let recall = ["Coming!", "Okay!", "Back to work!", "On my way"]
    public static let meet = ["hi!", "nice commit", "lunch?", "high five!"]
    public static let hello = "Hello!", bye = "Bye!", done = "Done!", needsYou = "Needs you", myTurn = "My turn!"
    /// Walk-on subtitle while a session waits (prototype: "name is waiting for permission").
    public static func waiting(_ name: String) -> String { "\(name) is waiting for permission" }
    /// The crowd announcing a member's finished turn.
    public static func finished(_ name: String) -> String { "\(name) finished" }
    /// The crowd's count bubble: "+N", and "N need you" under it.
    public static func crowdCount(_ n: Int) -> String { "+\(n)" }
    public static func needYou(_ n: Int) -> String { "\(n) need you" }
}
