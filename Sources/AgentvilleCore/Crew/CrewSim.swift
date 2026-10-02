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
    public enum Kind: Equatable, Sendable { case spark, dust }
    public var kind: Kind
    public var x, y, z, vx, vy, vz: Double
    public var life = 0.0, max: Double
    public var color: RGB
}

public struct Bubble: Equatable, Sendable {
    public var text: String
    /// Sim time after which it disappears.
    public var until: Double
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
        /// On the desktop playing its session's pose (walking around arrives in M4).
        case rest
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
    var anim: Double
    var t = 0.0
    var blinkT: Double
    var timer = 0.0

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
    }
}

public enum CrewEvent: Equatable, Sendable {
    /// The desk panel squashes and stretches as the crew pours out.
    case burp
    /// The last one is home.
    case gulp
}

/// The crew on the desktop: release and recall, ported from the prototype's `release`, `recall`,
/// `spawnFromHome`, `sendHome`, `Ent.launch`/`land` and `updateEnt`. Pure and seeded, so tests drive
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
    private var rng: SplitMix64

    public init(stage: Stage, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.stage = stage
        rng = SplitMix64(seed: seed)
    }

    /// Nobody out, nothing scheduled, no particles: the overlay can pause and hide.
    public var isIdle: Bool { !released && members.isEmpty && particles.isEmpty && pending.isEmpty }

    /// Sessions whose desks are empty because their character is out.
    public var awayIDs: Set<String> { Set(members.keys) }

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
                    case .fly, .wait, .drop: members[id] = nil
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
                   anim: rand(0...10), blinkT: rand(2...5))
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
            pose = act(&m, session: sessions[id])
        }
        if m.mode != .rest { m.hop = 0 }

        // Blink (prototype: every 2.5–5 s for 0.12 s, idle pose only).
        m.blinkT -= dt
        if m.blinkT < -0.12 { m.blinkT = rand(2.5...5) }
        if pose != m.pose { m.pose = pose; m.anim = 0 }
        m.frame = Int(m.anim * (Self.fps[pose] ?? 2)) % pose.frameCount
        members[id] = m
    }

    /// In place, the pose `roam` would act out (no walking until M4).
    private func act(_ m: inout CrewMember, session: Session?) -> Pose {
        guard let s = session else { m.hop = 0; return .idle }
        m.look = s.look
        switch s.status {
        case .needsYou:
            m.emote = .icon(.bang)
            m.hop = abs(sin(m.t * 7)) * 9
            return .wave
        case .finished:
            m.emote = .icon(.check)
            m.hop = abs(sin(m.t * 9)) * 12
            return .cheer
        case .idle:
            m.hop = 0
            return s.look.rest == .sleep ? .sleep : .coffee
        case .error, .working:
            m.hop = 0
            switch OfficeScene.DeskState(s.status) {
            case .working(.edit): return .type
            case .working(.read): return .read
            case .working(.bash): return .bash
            case .working(.search): return .search
            case .working(.web): return .web
            case .working(.think):
                m.emote = .dots(Int(floor(m.t * 3)) % 4)
                return .think
            default: return .idle
            }
        }
    }

    /// Prototype `FPS`.
    static let fps: [Pose: Double] = [
        .walk: 8, .type: 6, .bash: 3, .read: 1.2, .search: 3, .web: 1.6, .think: 2, .wave: 5, .cheer: 5,
        .coffee: 0.7, .sleep: 1, .dangle: 7, .idle: 1.2, .dizzy: 4, .deskType: 6, .nap: 1,
    ]

    // MARK: - Particles (port of addP, sparkle, dust, stepParts)

    private func add(_ p: Particle) {
        if particles.count >= Limits.particles { particles.removeFirst(particles.count - Limits.particles + 1) }
        particles.append(p)
    }

    static let sparkColors = [RGB(0xFFEC27), RGB(0xFFF1E8), RGB(0x29ADFF)]

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
