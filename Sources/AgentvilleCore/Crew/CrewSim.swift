import Foundation

/// The desktop the crew stands on, in points with a top-left origin (y grows downwards), like the
/// prototype's stage. `top` is the menu bar's height; `bottom` is where the usable area ends
/// (above the Dock).
public struct Stage: Equatable, Sendable {
    public var width, height, top, bottom: Double

    public init(width: Double, height: Double, top: Double, bottom: Double) {
        self.width = width; self.height = height; self.top = top; self.bottom = bottom
    }

    /// Points per sprite pixel on the desktop (prototype `S`: 2 on narrow stages).
    public var scale: Double { width < 700 ? 2 : 3 }
    /// Highest feet position (prototype `minY`): a character's head stays below the menu bar.
    public var minY: Double { top + 26 * scale + 6 }
}

/// Where a character's desk is: its feet, and how many points per pixel it is drawn at there.
/// The menu bar icon is a home too, when the desk panel is closed.
public struct Home: Equatable, Sendable {
    public var x, y, scale: Double
    public init(x: Double, y: Double, scale: Double) { self.x = x; self.y = y; self.scale = scale }
}

public struct Particle: Equatable, Sendable {
    /// Prototype `k`: `spark`, `dust`, `conf`, `z`, `bit`.
    public enum Kind: Equatable, Sendable { case spark, dust, confetti, zzz, bit }
    public var kind: Kind
    public var x, y, z, vx, vy, vz: Double
    public var life = 0.0, max: Double
    public var color: RGB
    /// Confetti flutter phase (prototype `ph`).
    public var phase = 0.0
}

public struct Bubble: Hashable, Sendable {
    /// Prototype bubble classes: `say`, `done` (green title), `wait` (red title).
    public enum Kind: Hashable, Sendable { case say, done, wait }
    public var text: String
    public var kind = Kind.say
    /// Second, smaller line (prototype `sub`): the session's name, and the turn time when done.
    public var sub: String?
    /// Sim time after which it disappears.
    public var until: Double
}

/// A subagent's mini-me, following its character around (prototype `e.side`).
public struct Sidekick: Equatable, Sendable {
    public var x, y: Double
    public var face: Double
    public var moving = false
    /// Subagents running; more than one shows a count badge (open question 12's default).
    public var count: Int
    public var frame = 0
    /// Walks while catching up, types while still.
    public var pose: Pose { moving ? .walk : .type }
}

public struct Flight: Equatable, Sendable {
    public var t = 0.0, duration: Double
    public var from: (x: Double, y: Double), to: (x: Double, y: Double)
    public var scaleFrom, scaleTo: Double
    /// Lands on the desktop, or arrives home and leaves the overlay.
    public var homeward: Bool

    public static func == (a: Flight, b: Flight) -> Bool {
        a.t == b.t && a.duration == b.duration && a.from == b.from && a.to == b.to
            && a.scaleFrom == b.scaleFrom && a.scaleTo == b.scaleTo && a.homeward == b.homeward
    }
}

/// One character out on the desktop (prototype `Ent`).
public struct CrewMember: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case fly(Flight)
        /// Recalled, waiting for its turn to fly home (under a `!`).
        case wait
        /// A new session while the crew is out: falls in from above.
        case drop
        /// Its session ended: waves "Bye!" then poofs.
        case leave
        /// On the desktop: acting out its session, wandering between acts (prototype `roam`).
        case rest
        /// Held by the user (⌥ + press): dangles at the cursor.
        case drag
        /// Let go with some speed: flies, bounces and slides (prototype `thrown`).
        case thrown(vx: Double, vy: Double, hard: Bool)
    }

    public let id: String
    public var look: Look
    public var x, y: Double
    public var z = 0.0, vz = 0.0
    /// Extra lift from hopping (needs you, cheering).
    public var hop = 0.0
    public var face: Double
    public var scale: Double
    public var squash = 0.0
    public var mode: Mode
    public var pose: Pose = .idle
    public var frame = 0
    public var emote: Emote?
    public var bubble: Bubble?
    public var side: Sidekick?
    /// Hover fade: eases to `Motion.hoverAlpha` while the cursor is over it.
    public var alpha = 1.0
    /// Seconds of seeing stars left after a hard throw.
    var dizzy = 0.0
    var anim: Double
    /// Seconds since it came out (drives hops and the dizzy stars).
    public internal(set) var t = 0.0
    var blinkT: Double
    var timer = 0.0
    /// Roaming: acting in place, or walking to (tx, ty).
    enum Phase: Equatable, Sendable { case act, walk, meet }
    var phase = Phase.act
    var tx = 0.0, ty = 0.0
    /// Running to the bottom of the screen because the session needs the user.
    var alert = false
    var cheerT = 0.0
    var lastStatus: SessionStatus?
    /// Meetings: seconds until it may meet someone again, and the emote it shows while meeting.
    var meetCd: Double
    var meetEmote: Emote?
    /// Last Bash frame, so sparks fly once per hammer strike.
    var lastFrame = 0

    /// Horizontal and vertical stretch, as `drawEnt` applies it.
    public var stretch: (x: Double, y: Double) {
        if case .fly = mode { return Motion.flightStretch }
        guard squash > 0 else { return (1, 1) }
        return (1 + squash * Motion.squashAmount, 1 - squash * Motion.squashAmount)
    }

    /// The pose to draw: blinking replaces `idle` for a moment.
    public var drawPose: Pose { pose == .idle && blinkT < 0 ? .blink : pose }

    public static func == (a: CrewMember, b: CrewMember) -> Bool {
        a.id == b.id && a.x == b.x && a.y == b.y && a.z == b.z && a.mode == b.mode && a.pose == b.pose && a.frame == b.frame
            && a.side == b.side
    }
}

public enum CrewEvent: Equatable, Sendable {
    /// The desk panel squashes and stretches as the crew pours out.
    case burp
    /// The last one is home.
    case gulp
}

/// The crew on the desktop: release, recall and roaming, ported from the prototype's `release`,
/// `recall`, `spawnFromHome`, `sendHome`, `Ent.launch`/`land`, `updateEnt` and `roam`. Pure and seeded, so tests drive
/// it with a fixed clock. The app renders `members` and `particles` and supplies `home`.
public final class CrewSim {
    public var stage: Stage
    /// Where each session's character goes home to (its desk, or the menu bar icon).
    public var home: (String) -> Home = { _ in Home(x: 0, y: 0, scale: 2) }
    /// Cut confetti and similar (not used until M4's confetti).
    public var reduceMotion = false

    public private(set) var released = false
    public private(set) var members: [String: CrewMember] = [:]
    public private(set) var particles: [Particle] = []
    /// Seconds since the sim was created.
    public private(set) var time = 0.0

    private enum Action { case spawn(String), sendHome(String), forceHome(Int) }
    private var pending: [(at: Double, action: Action)] = []
    /// Bumped by every release and recall, so stale scheduled actions do nothing (prototype `token`).
    private var token = 0
    private var looks: [String: Look] = [:]
    /// Meetings are checked every `Motion.meetCheck` seconds (prototype `meetClock`).
    private var meetClock = 0.0
    private var rng: SplitMix64

    public init(stage: Stage, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.stage = stage
        rng = SplitMix64(seed: seed)
    }

    /// Nobody out, nothing scheduled, no particles: the overlay can pause and hide.
    public var isIdle: Bool { !released && members.isEmpty && particles.isEmpty && pending.isEmpty }

    /// Sessions whose desks are empty because their character is out.
    public var awayIDs: Set<String> { Set(members.keys) }

    /// ⌥ is held: everyone gets an outline and the hover fade is off.
    public var grabMode = false
    /// The cursor, in stage coordinates, while it's over the overlay's display (for the hover fade).
    public var pointer: (x: Double, y: Double)?
    /// The character being held, if any.
    public var dragging: String? { drag?.id }
    private struct Drag {
        let id: String
        let ox, oy: Double
        var samples: [(x: Double, y: Double, t: Double)]
        var moved = 0.0
    }
    private var drag: Drag?

    /// Tests only: put a character somewhere particular (`@testable`).
    func modify(_ id: String, _ body: (inout CrewMember) -> Void) {
        guard var m = members[id] else { return }
        body(&m)
        members[id] = m
    }

    // MARK: - Grabbing (ports of hitBox, hitTest, the pointer handlers, endDrag, settle)

    /// Port of `hitBox`: feet at (x, y), `8·S` either side, `24·S` tall above the lift.
    func hit(_ m: CrewMember, x px: Double, y py: Double, pad: Double) -> Bool {
        let sc = m.scale, top = m.y - m.z - m.hop - 24 * sc, w = 8 * sc
        return px > m.x - w - pad && px < m.x + w + pad && py > top - pad && py < m.y + pad
    }

    /// Port of `hitTest`: the front-most (lowest on screen) grabbable character under the point.
    public func hitTest(x: Double, y: Double) -> String? {
        members.values
            .filter { m in
                switch m.mode {
                case .rest, .thrown, .drop: true
                case .fly, .wait, .leave, .drag: false
                }
            }
            .sorted { $0.y > $1.y || ($0.y == $1.y && $0.id < $1.id) }
            .first { hit($0, x: x, y: y, pad: Grab.pad) }?.id
    }

    /// Non-negotiable #1: the overlay takes the mouse only while ⌥ is held over a character, or
    /// while a drag is in progress. Everything else goes to the apps underneath.
    public func capturesMouse(optionHeld: Bool, x: Double, y: Double) -> Bool {
        drag != nil || (optionHeld && hitTest(x: x, y: y) != nil)
    }

    /// Press on a character (prototype `pointerdown`): it's lifted and dangles.
    public func grab(_ id: String, x: Double, y: Double, at t: Double) {
        guard drag == nil, var m = members[id] else { return }
        drag = Drag(id: id, ox: m.x - x, oy: m.y - y, samples: [(x, y, t)])
        m.mode = .drag
        m.z = Grab.lift
        m.vz = 0
        m.bubble = nil
        members[id] = m
    }

    /// Cursor moved while holding (prototype `pointermove`).
    public func dragTo(x: Double, y: Double, at t: Double) {
        guard var d = drag, var m = members[d.id] else { return }
        d.moved += hypot(x + d.ox - m.x, y + d.oy - m.y)
        m.x = clamp(x + d.ox, 20, stage.width - 20)
        m.y = clamp(y + d.oy + Grab.lift, stage.minY, stage.bottom - 8)
        m.z = Grab.lift
        if m.x < x + d.ox - 1 { m.face = 1 } else if m.x > x + d.ox + 1 { m.face = -1 }
        d.samples.append((x, y, t))
        if d.samples.count > Grab.samples { d.samples.removeFirst() }
        members[d.id] = m
        drag = d
    }

    /// Let go (prototype `endDrag`): a tap hops, anything else is a throw. `cancel` just sets it down.
    public func endDrag(cancel: Bool) {
        guard let d = drag else { return }
        drag = nil
        guard var m = members[d.id] else { return }
        defer { members[d.id] = m }
        if cancel {
            m.z = 0
            settle(&m)
            return
        }
        if d.moved < Grab.tapDistance {
            m.z = 0
            settle(&m)
            m.cheerT = Grab.tapCheer
            m.bubble = Bubble(text: pick(Phrases.tap), until: time + 1)
            sparkle(x: m.x, y: m.y - 40, count: 4, color: RGB(0xFF77A8))
            return
        }
        let a = d.samples[0], b = d.samples[d.samples.count - 1]
        let span = max(Grab.minSampleSpan, b.t - a.t)
        var vx = (b.x - a.x) / span, vy = (b.y - a.y) / span
        let speed = hypot(vx, vy)
        if speed > Grab.maxSpeed { vx *= Grab.maxSpeed / speed; vy *= Grab.maxSpeed / speed }
        m.vz = clamp(speed * Grab.liftFactor, Grab.minLift, Grab.maxLift)
        m.mode = .thrown(vx: vx, vy: vy * Grab.verticalDamping, hard: speed > Grab.dizzySpeed)
        if speed > Grab.shoutSpeed { m.bubble = Bubble(text: pick(Phrases.throwShout), until: time + 0.9) }
    }

    /// Port of `settle`: back to roaming where it landed.
    private func settle(_ m: inout CrewMember) {
        m.mode = .rest
        m.phase = .act
        m.tx = m.x; m.ty = m.y
    }

    // MARK: - Release and recall

    /// Port of `release`: the first `Limits.roamers` sessions leap out, staggered.
    @discardableResult
    public func release(_ sessions: [Session]) -> [CrewEvent] {
        guard !released else { return [] }
        released = true
        token += 1
        for (i, s) in sessions.prefix(Limits.roamers).enumerated() {
            looks[s.id] = s.look
            schedule(Motion.releaseFirst + Double(i) * Motion.releaseStagger, .spawn(s.id))
        }
        return [.burp]
    }

    /// Port of `recall`: everyone stops under a `!`, then flies home bottom-most first. Anything
    /// still out after `Timing.recallForceComplete` is removed (non-negotiable #2).
    public func recall() {
        guard released else { return }
        endDrag(cancel: true)
        released = false
        token += 1
        pending.removeAll { if case .spawn = $0.action { true } else { false } }
        for (i, m) in members.values.sorted(by: { $0.y > $1.y || ($0.y == $1.y && $0.id < $1.id) }).enumerated() {
            var m = m
            m.emote = .icon(.bang)
            m.bubble = nil
            if chance(Motion.recallShoutChance) { m.bubble = Bubble(text: pick(Phrases.recall), until: time + 0.9) }
            m.mode = .wait
            m.hop = 0
            members[m.id] = m
            schedule(Motion.recallFirst + Double(i) * Motion.recallStagger, .sendHome(m.id))
        }
        schedule(Timing.recallForceComplete, .forceHome(token))
    }

    /// Port of `syncRoamers`/`onAdded`/`onEnded`: call when the store changes. While the crew is
    /// out, new sessions (within the cap) drop in and ended ones wave goodbye.
    public func sessionsChanged(_ sessions: [Session]) {
        let live = Set(sessions.map(\.id))
        for (id, m) in members where !live.contains(id) && m.mode != .leave {
            var m = m
            m.mode = .leave
            m.timer = Motion.leaveTime
            m.bubble = Bubble(text: Phrases.bye, until: time + Motion.leaveTime)
            m.emote = nil
            members[id] = m
        }
        guard released else { return }
        let scheduled = Set(pending.compactMap { if case .spawn(let id) = $0.action { id } else { nil } })
        for s in sessions.prefix(Limits.roamers) {
            looks[s.id] = s.look
            guard members[s.id] == nil, !scheduled.contains(s.id) else { continue }
            let to = randomSpot()
            var m = newMember(s.id, look: s.look, x: to.x, y: to.y, scale: stage.scale)
            m.z = stage.height * Motion.dropHeight
            m.mode = .drop
            members[s.id] = m
        }
    }

    // MARK: - Time

    /// Advance by `dt` seconds (the app passes display-rate steps, capped like the prototype's 50 ms).
    public func update(dt: Double, sessions: [String: Session]) -> [CrewEvent] {
        let dt = min(dt, 0.05)
        time += dt
        var events: [CrewEvent] = []
        runPending(&events)
        for id in members.keys.sorted() { step(id, dt: dt, sessions: sessions, events: &events) }
        checkMeetings(dt)
        stepParticles(dt)
        return events
    }

    private func schedule(_ delay: Double, _ a: Action) { pending.append((time + delay, a)) }

    private func runPending(_ events: inout [CrewEvent]) {
        guard pending.contains(where: { $0.at <= time }) else { return }
        let due = pending.enumerated().filter { $0.element.at <= time }.sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
        pending.removeAll { $0.at <= time }
        for (_, p) in due {
            switch p.action {
            case .spawn(let id): spawnFromHome(id)
            case .sendHome(let id): sendHome(id)
            case .forceHome(let t):
                guard t == token, !released else { continue }
                for (id, m) in members {
                    switch m.mode {
                    case .fly, .wait, .drop, .drag, .thrown: members[id] = nil
                    case .leave, .rest: break
                    }
                }
                // `rest` can't happen after a recall, and `leave` ends on its own within 1.1 s.
            }
        }
    }

    /// Port of `spawnFromHome`.
    private func spawnFromHome(_ id: String) {
        guard released, let look = looks[id] else { return }
        if var m = members[id] {
            // Still out from before (flying home or waiting): turn around.
            if m.mode == .wait || { if case .fly(let f) = m.mode { f.homeward } else { false } }() {
                let to = randomSpot()
                m.bubble = nil; m.emote = nil
                launch(&m, to: to, duration: rand(Motion.releaseFlight), homeward: false, scaleTo: stage.scale)
                members[id] = m
            }
            return
        }
        let h = home(id)
        var m = newMember(id, look: look, x: h.x, y: h.y, scale: h.scale)
        launch(&m, to: randomSpot(), duration: rand(Motion.releaseFlight), homeward: false, scaleTo: stage.scale)
        sparkle(x: h.x, y: h.y, count: 4)
        if chance(Motion.releaseShoutChance) { m.bubble = Bubble(text: pick(Phrases.release), until: time + 1.2) }
        members[id] = m
    }

    /// Port of `sendHome`.
    private func sendHome(_ id: String) {
        guard !released, var m = members[id], m.mode == .wait else { return }
        let h = home(id)
        launch(&m, to: (h.x, h.y), duration: rand(Motion.recallFlight), homeward: true, scaleTo: h.scale)
        members[id] = m
    }

    /// Port of `Ent.launch`.
    private func launch(_ m: inout CrewMember, to: (x: Double, y: Double), duration: Double, homeward: Bool, scaleTo: Double) {
        m.mode = .fly(Flight(duration: duration, from: (m.x, m.y), to: to, scaleFrom: m.scale, scaleTo: scaleTo, homeward: homeward))
        m.vz = Motion.gravity * duration / 2
        m.z = 0
        m.face = to.x >= m.x ? 1 : -1
    }

    /// Port of `Ent.land`.
    private func land(_ m: inout CrewMember) {
        m.z = 0
        m.squash = 1
        dust(x: m.x, y: m.y, count: 5)
    }

    private func newMember(_ id: String, look: Look, x: Double, y: Double, scale: Double) -> CrewMember {
        CrewMember(id: id, look: look, x: x, y: y, face: chance(0.5) ? 1 : -1, scale: scale, mode: .rest,
                   anim: rand(0...10), blinkT: rand(2...5), meetCd: rand(Motion.meetFirstCooldown))
    }

    /// Port of the `fly`/`wait`/`drop`/`leave` branches of `updateEnt`, plus M3's in-place acting.
    private func step(_ id: String, dt: Double, sessions: [String: Session], events: inout [CrewEvent]) {
        guard var m = members[id] else { return }
        m.t += dt
        m.anim += dt
        m.squash = max(0, m.squash - dt * Motion.squashDecay)
        m.emote = nil
        if let b = m.bubble, time > b.until { m.bubble = nil }
        var pose = Pose.idle

        switch m.mode {
        case .fly(var f):
            f.t += dt
            let k = min(1, f.t / f.duration)
            m.x = f.from.x + (f.to.x - f.from.x) * k
            m.y = f.from.y + (f.to.y - f.from.y) * k
            m.z = max(0, (Motion.gravity * f.duration / 2) * f.t - Motion.gravity * f.t * f.t / 2)
            m.scale = f.scaleFrom + (f.scaleTo - f.scaleFrom) * k
            pose = f.homeward ? .dangle : .cheer
            if chance(dt * 20) {
                add(Particle(kind: .spark, x: m.x, y: m.y, z: m.z + 20, vx: 0, vy: 0, vz: 0, max: 0.35,
                             color: pick([RGB(0xFFEC27), RGB(0xFFF1E8)])))
            }
            if k >= 1 {
                if f.homeward {
                    sparkle(x: m.x, y: m.y - 8, count: 3)
                    members[id] = nil
                    if members.isEmpty, !released { events.append(.gulp) }
                    return
                }
                m.scale = f.scaleTo
                m.x = f.to.x; m.y = f.to.y
                land(&m)
                m.mode = .rest
                m.phase = .act
                m.timer = rand(Motion.actAfterLanding)
            } else {
                m.mode = .fly(f)
            }
        case .wait:
            pose = .idle
            m.emote = .icon(.bang)
        case .drop:
            m.vz -= Motion.gravity * dt
            m.z += m.vz * dt
            pose = .dangle
            if m.z <= 0 {
                land(&m)
                m.mode = .rest
                m.phase = .act
                m.timer = 1
                m.bubble = Bubble(text: Phrases.hello, until: time + 1.2)
            }
        case .leave:
            m.timer -= dt
            pose = .wave
            if m.timer <= 0 {
                sparkle(x: m.x, y: m.y - 20, count: 10)
                dust(x: m.x, y: m.y, count: 6)
                members[id] = nil
                return
            }
        case .rest:
            pose = roam(&m, dt: dt, session: sessions[id])
        case .drag:
            pose = .dangle
            m.z = Grab.lift
        case .thrown(var vx, var vy, let hard):
            // Port of the `thrown` branch of `updateEnt`.
            m.x += vx * dt
            m.y += vy * dt
            if m.x < 24 { m.x = 24; vx = abs(vx) * Grab.wallBounce; m.squash = Grab.wallSquash }
            if m.x > stage.width - 24 { m.x = stage.width - 24; vx = -abs(vx) * Grab.wallBounce; m.squash = Grab.wallSquash }
            if m.y < stage.minY { m.y = stage.minY; vy = abs(vy) * Grab.wallBounce }
            if m.y > stage.bottom - 10 { m.y = stage.bottom - 10; vy = -abs(vy) * Grab.wallBounce }
            m.mode = .thrown(vx: vx, vy: vy, hard: hard)
            if m.z > 0 || m.vz > 0 {
                m.vz -= Motion.gravity * dt
                m.z += m.vz * dt
                pose = .dangle
                if m.z <= 0 {
                    m.z = 0
                    if m.vz < -Grab.groundBounceSpeed {
                        m.vz = -m.vz * Grab.groundBounce
                        m.mode = .thrown(vx: vx * Grab.bounceDamping, vy: vy * Grab.bounceDamping, hard: hard)
                        m.squash = 1
                        dust(x: m.x, y: m.y, count: 4)
                    } else {
                        m.vz = 0
                        land(&m)
                    }
                }
            } else {
                let f = exp(-Grab.friction * dt)
                vx *= f; vy *= f
                m.mode = .thrown(vx: vx, vy: vy, hard: hard)
                pose = .idle
                if chance(dt * 12), hypot(vx, vy) > 60 { dust(x: m.x, y: m.y, count: 1) }
                if hypot(vx, vy) < Grab.settleSpeed {
                    settle(&m)
                    m.timer = rand(1...2)
                    if hard { m.dizzy = Grab.dizzyTime }
                }
            }
        }
        if m.mode != .rest { m.hop = 0 }
        followWithSidekick(&m, dt: dt, session: sessions[id])

        // Blink (prototype: every 2.5–5 s for 0.12 s, idle pose only).
        m.blinkT -= dt
        if m.blinkT < -0.12 { m.blinkT = rand(2.5...5) }
        if pose != m.pose { m.pose = pose; m.anim = 0 }
        m.frame = Int(m.anim * (Self.fps[pose] ?? 2)) % pose.frameCount

        // Hover fade: whoever is under the cursor turns see-through (not in grab mode).
        var target = 1.0
        if let p = pointer, !grabMode, hit(m, x: p.x, y: p.y, pad: Grab.hoverPad) { target = Motion.hoverAlpha }
        m.alpha += (target - m.alpha) * min(1, dt * Motion.hoverEase)
        members[id] = m
    }

    /// The name bubbles use: the project, with the twin number for later sessions in one folder.
    static func name(_ s: Session) -> String { s.twinIndex > 1 ? "\(s.project) \(s.twinIndex)" : s.project }

    /// Port of `roam`: act out the session for a while, then walk somewhere nearby. Needing the
    /// user means running to the bottom of the screen to wave; a finished turn means a cheer first.
    private func roam(_ m: inout CrewMember, dt: Double, session: Session?) -> Pose {
        guard let s = session else { m.hop = 0; return .idle }
        m.look = s.look
        if m.dizzy > 0 { m.dizzy -= dt; m.hop = 0; return .dizzy }
        // A turn just finished (port of `onDone`): cheer, say Done! with the turn time, confetti.
        if s.status == .finished, m.lastStatus != nil, m.lastStatus != .finished {
            m.cheerT = Motion.cheer
            let sub = s.lastTurnDuration.map { "\(Self.name(s)) · \(DeskList.duration($0))" } ?? Self.name(s)
            m.bubble = Bubble(text: Phrases.done, kind: .done, sub: sub, until: time + Motion.doneBubble)
            confetti(x: m.x, y: m.y - 30, count: Motion.doneConfetti)
        }
        m.lastStatus = s.status
        if m.cheerT > 0 {
            m.cheerT -= dt
            m.hop = abs(sin(m.t * 9)) * 12
            m.emote = .icon(.check)
            if chance(dt * 6) { confetti(x: m.x, y: m.y - 40, count: 2) }
            return .cheer
        }
        m.hop = 0

        if s.status == .needsYou {
            if !m.alert {
                m.alert = true
                m.tx = clamp(m.x, 60, stage.width - 60)
                m.ty = stage.bottom - 26
                m.phase = .walk
            }
            m.bubble = Bubble(text: Phrases.needsYou, kind: .wait, sub: Self.name(s), until: time + 0.3)
            m.emote = .icon(.bang)
            if m.phase == .walk {
                if walk(&m, dt: dt, speed: Motion.needsYouRun) { m.phase = .act } else { return .walk }
            }
            m.hop = abs(sin(m.t * 7)) * 9
            return .wave
        }
        if m.alert { m.alert = false; m.bubble = nil; m.phase = .act; m.timer = 0.3 }
        if m.phase == .meet {
            m.timer -= dt
            if m.timer <= 0 { m.phase = .act; m.timer = 0.2 }
            m.emote = m.meetEmote
            return m.timer > Motion.meet - Motion.meetCheer ? .cheer : .idle
        }

        let idle = s.status == .idle || s.status == .finished
        let work = OfficeScene.DeskState(s.status)
        let searching = !idle && work == .working(.search)
        if m.phase == .walk {
            let speed = idle ? Motion.idleStroll : searching ? Motion.searchCreep : Motion.walk
            if walk(&m, dt: dt, speed: speed) {
                m.phase = .act
                m.timer = rand(idle ? Motion.actIdle : Motion.actWorking)
            }
            return searching ? .search : .walk
        }

        m.timer -= dt
        if m.timer <= 0 {
            let r = idle ? Motion.wanderIdle : Motion.wanderWorking
            m.tx = clamp(m.x + rand(-r...r), 36, stage.width - 36)
            m.ty = clamp(m.y + rand(-r * 0.6...r * 0.6), stage.minY + 6, stage.bottom - 16)
            m.phase = .walk
            return .walk
        }
        let S = stage.scale
        if idle {
            guard s.look.rest == .sleep else { return .coffee }
            if chance(dt * 0.9) { zzz(x: m.x + m.face * 4 * S, y: m.y - 22 * S) }
            return .sleep
        }
        switch work {
        case .working(.edit):
            if chance(dt * 3) { bit(x: m.x + m.face * 7 * S, y: m.y - 10 * S) }
            return .type
        case .working(.read): return .read
        case .working(.bash):
            // A shower of sparks on each strike (frame 0 → 1).
            let f = Int(floor(m.anim * (Self.fps[.bash] ?? 3))) % 2
            if f == 1, m.lastFrame == 0 {
                for _ in 0..<4 {
                    add(Particle(kind: .spark, x: m.x + m.face * 9 * S, y: m.y, z: 12 * S, vx: rand(-80...80),
                                 vy: rand(-20...20), vz: rand(40...160), max: 0.35, color: pick(Self.bashColors)))
                }
            }
            m.lastFrame = f
            return .bash
        case .working(.search): return .search
        case .working(.web):
            if chance(dt * 1.5) {
                add(Particle(kind: .spark, x: m.x + m.face * (10 * S + rand(0...20)), y: m.y, z: 26 * S + rand(0...24),
                             vx: 0, vy: 0, vz: 0, max: 0.7, color: RGB(0xFFEC27)))
            }
            return .web
        case .working(.think):
            m.emote = .dots(Int(floor(m.t * 3)) % 4)
            return .think
        case .working(.plan): return .plan
        case .working(.tinker):
            // A small fizz from the gadget each time the wrench turns.
            let f = Int(floor(m.anim * (Self.fps[.tinker] ?? 4))) % 2
            if f == 1, m.lastFrame == 0 {
                for _ in 0..<2 {
                    add(Particle(kind: .spark, x: m.x + m.face * 8 * S, y: m.y, z: 12 * S, vx: rand(-40...40),
                                 vy: rand(-10...10), vz: rand(30...90), max: 0.3, color: pick(Self.tinkerColors)))
                }
            }
            m.lastFrame = f
            return .tinker
        case .error:
            m.emote = .icon(.storm)
            return .error
        default: return .idle
        }
    }

    /// Port of `checkMeetings`: two working characters who pass within 44 pt stop to say hi.
    private func checkMeetings(_ dt: Double) {
        meetClock -= dt
        guard meetClock <= 0 else { return }
        meetClock = Motion.meetCheck
        let ids = members.keys.sorted().filter {
            guard let m = members[$0], m.mode == .rest, m.phase == .walk else { return false }
            return m.lastStatus.map { if case .working = $0 { true } else { false } } ?? false
        }
        for id in ids { members[id]?.meetCd -= Motion.meetCheck }
        for (i, ia) in ids.enumerated() {
            for ib in ids[(i + 1)...] {
                guard var a = members[ia], var b = members[ib], a.meetCd <= 0, b.meetCd <= 0,
                      hypot(a.x - b.x, a.y - b.y) < Motion.meetDistance else { continue }
                let em: Emote = pick([.icon(.heart), .icon(.heart), .icon(.quest)])
                meet(&a, facing: b, emote: em)
                meet(&b, facing: a, emote: nil)
                if chance(0.5) { a.bubble = Bubble(text: pick(Phrases.meet), until: time + 1.3) }
                members[ia] = a
                members[ib] = b
                sparkle(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 30, count: 5, color: RGB(0xFF77A8))
                return
            }
        }
    }

    private func meet(_ m: inout CrewMember, facing other: CrewMember, emote: Emote?) {
        m.phase = .meet
        m.timer = Motion.meet
        m.face = other.x > m.x ? 1 : -1
        m.meetCd = rand(Motion.meetCooldown)
        m.meetEmote = emote
    }

    /// Port of the sidekick block of `updateEnt`: while the session has subagents, a mini-me pops in
    /// with yellow sparkles and follows a step behind; it poofs when they're done or the crew leaves.
    private func followWithSidekick(_ m: inout CrewMember, dt: Double, session: Session?) {
        guard let s = session, !s.subagents.isEmpty, m.mode == .rest else {
            if let side = m.side { sparkle(x: side.x, y: side.y - 8, count: 5); m.side = nil }
            return
        }
        if m.side == nil {
            m.side = Sidekick(x: m.x - 18 * m.face, y: m.y + 4, face: m.face, count: 0)
            sparkle(x: m.x - 18 * m.face, y: m.y + 4 - 10, count: 6, color: RGB(0xFFEC27))
        }
        guard var side = m.side else { return }
        side.count = s.subagents.count
        let tx = m.x - m.face * 11 * stage.scale, ty = m.y + 3
        let d = hypot(tx - side.x, ty - side.y)
        side.moving = d > 3
        if side.moving {
            let step = min(d, Motion.sidekickFollow * dt)
            side.x += (tx - side.x) / d * step
            side.y += (ty - side.y) / d * step
            side.face = tx > side.x ? 1 : -1
        } else {
            side.face = m.face
        }
        side.frame = Int(m.anim * (Self.fps[side.pose] ?? 2)) % side.pose.frameCount
        m.side = side
    }

    /// Port of `walkTo`: true when it has arrived.
    private func walk(_ m: inout CrewMember, dt: Double, speed: Double) -> Bool {
        let dx = m.tx - m.x, dy = m.ty - m.y, d = hypot(dx, dy)
        if d < 2 { m.x = m.tx; m.y = m.ty; return true }
        let step = min(d, speed * dt)
        m.x += dx / d * step
        m.y += dy / d * step
        if abs(dx) > 1 { m.face = dx > 0 ? 1 : -1 }
        return false
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

    /// Prototype `FPS`.
    static let fps: [Pose: Double] = [
        .walk: 8, .type: 6, .bash: 3, .read: 1.2, .search: 3, .web: 1.6, .think: 2, .wave: 5, .cheer: 5,
        .coffee: 0.7, .sleep: 1, .dangle: 7, .idle: 1.2, .dizzy: 4, .deskType: 6, .nap: 1,
        // Agentville's own.
        .plan: 1.5, .tinker: 4, .error: 2,
    ]

    // MARK: - Particles (port of addP, sparkle, dust, stepParts)

    private func add(_ p: Particle) {
        if particles.count >= Limits.particles { particles.removeFirst(particles.count - Limits.particles + 1) }
        particles.append(p)
    }

    static let sparkColors = [RGB(0xFFEC27), RGB(0xFFF1E8), RGB(0x29ADFF)]
    static let bashColors = [RGB(0xFFEC27), RGB(0xFFA300), RGB(0xFFF1E8)]
    static let tinkerColors = [RGB(0x29ADFF), RGB(0xFFF1E8)]
    static let bitColors = [RGB(0xFF77A8), RGB(0x29ADFF), RGB(0xFFEC27), RGB(0x00E436)]
    /// Prototype `CONF`.
    static let confettiColors = [RGB(0xFF004D), RGB(0xFFA300), RGB(0xFFEC27), RGB(0x00E436), RGB(0x29ADFF),
                                 RGB(0xFF77A8), RGB(0x83769C), RGB(0xFFF1E8)]

    /// Port of `confetti`: a quarter as many with reduced motion.
    public func confetti(x: Double, y: Double, count: Int) {
        let n = reduceMotion ? (count + 3) / 4 : count
        for _ in 0..<n {
            add(Particle(kind: .confetti, x: x, y: y, z: rand(20...50), vx: rand(-160...160), vy: rand(-50...50),
                         vz: rand(250...560), max: rand(1.3...2.2), color: pick(Self.confettiColors), phase: rand(0...6)))
        }
    }

    /// Port of `zzz`.
    func zzz(x: Double, y: Double) {
        add(Particle(kind: .zzz, x: x, y: y, z: 0, vx: rand(8...18), vy: 0, vz: 22, max: 1.8, color: RGB(0xFFF1E8)))
    }

    /// Port of `bits`.
    func bit(x: Double, y: Double) {
        add(Particle(kind: .bit, x: x + rand(-4...4), y: y, z: 0, vx: rand(-10...10), vy: 0, vz: rand(30...50),
                     max: rand(0.8...1.3), color: pick(Self.bitColors)))
    }

    public func sparkle(x: Double, y: Double, count: Int, color: RGB? = nil) {
        for _ in 0..<count {
            add(Particle(kind: .spark, x: x + rand(-14...14), y: y + rand(-6...6), z: rand(0...40),
                         vx: rand(-40...40), vy: rand(-10...10), vz: rand(-30...80), max: rand(0.4...0.9),
                         color: color ?? pick(Self.sparkColors)))
        }
    }

    public func dust(x: Double, y: Double, count: Int) {
        for _ in 0..<count {
            add(Particle(kind: .dust, x: x + rand(-8...8), y: y + rand(-2...2), z: 0, vx: rand(-70...70),
                         vy: rand(-12...12), vz: rand(10...60), max: rand(0.35...0.6), color: RGB(0xE8E4F2)))
        }
    }

    private func stepParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        particles = particles.compactMap { p in
            var p = p
            p.life += dt
            guard p.life < p.max else { return nil }
            if p.kind == .confetti {
                // Falls at 0.55 G, flutters sideways, and settles on the ground.
                p.vz -= Motion.gravity * 0.55 * dt
                p.vx += sin(p.life * 9 + p.phase) * 140 * dt
                p.z += p.vz * dt
                if p.z < 0 { p.z = 0; p.vz = 0; p.vx *= 0.8; p.vy *= 0.8 }
                p.x += p.vx * dt
                p.y += p.vy * dt
                return p
            }
            p.z += p.vz * dt
            p.x += p.vx * dt
            p.y += p.vy * dt
            return p
        }
    }

    // MARK: - Randomness (seeded)

    private func randomSpot() -> (x: Double, y: Double) {
        (rand(40...max(40, stage.width - 40)), rand((stage.minY + 10)...max(stage.minY + 10, stage.bottom - 18)))
    }

    private func rand(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + Double(rng.next() >> 11) / Double(1 << 53) * (r.upperBound - r.lowerBound)
    }

    private func chance(_ p: Double) -> Bool { rand(0...1) < p }

    private func pick<T>(_ a: [T]) -> T { a[Int(rng.next() % UInt64(a.count))] }
}

/// Small seeded generator for the crew's randomness (SplitMix64).
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
