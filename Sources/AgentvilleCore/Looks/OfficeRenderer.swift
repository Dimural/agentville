import Foundation

/// What the office shows: up to 6 desks, the theme and the wall clock (docs/design/office.md).
public struct OfficeScene: Sendable {
    /// The prototype's activity names, which pick the office pose and monitor screen.
    /// `other` is the prototype's fallback branch (desk typing, "…" screen). `plan` and `tinker`
    /// are Agentville's own (open question 12).
    public enum Act: String, CaseIterable, Sendable { case edit, read, bash, search, web, think, plan, tinker, other }

    public enum DeskState: Equatable, Sendable {
        case idle, needsYou, finished
        /// The last turn failed (Agentville's own, open question 12).
        case error
        case working(Act)

        /// Core status → office state. Unknown tools fall back to plain desk typing.
        public init(_ status: SessionStatus) {
            switch status {
            case .idle: self = .idle
            case .needsYou: self = .needsYou
            case .finished: self = .finished
            case .error: self = .error
            case .working(let a):
                switch a {
                case .editing: self = .working(.edit)
                case .reading: self = .working(.read)
                case .running: self = .working(.bash)
                case .searching: self = .working(.search)
                case .web: self = .working(.web)
                case .thinking: self = .working(.think)
                case .planning: self = .working(.plan)
                case .tinkering: self = .working(.tinker)
                case .working: self = .working(.other)
                }
            }
        }
    }

    public struct Desk: Equatable, Sendable {
        public var look: Look
        public var state: DeskState
        /// Seeds the editing screen's line lengths (prototype: `rng(s.id * 97)`).
        public var seed: UInt32
        /// A subagent is running: a mini-me sits on the monitor.
        public var subagent: Bool
        /// The character is out on the desktop: empty chair, monitor keeps working.
        public var away: Bool

        public init(look: Look, state: DeskState, seed: UInt32, subagent: Bool = false, away: Bool = false) {
            self.look = look; self.state = state; self.seed = seed; self.subagent = subagent; self.away = away
        }
    }

    /// Desk i holds `desks[i]`; nil or missing entries are empty desks. At most `Limits.desks` are drawn.
    public var desks: [Desk?] = []
    /// Sessions beyond the desks ("+N more below").
    public var moreBelow = 0
    public var night: Bool
    /// The clock on the wall (the app passes the real time).
    public var clock: (hour: Int, minute: Int)

    public init(night: Bool, clock: (hour: Int, minute: Int)) {
        self.night = night
        self.clock = clock
    }

    /// Sessions in store order take the desks; the rest are counted.
    public init(sessions: [Session], awayIDs: Set<String> = [], night: Bool, clock: (hour: Int, minute: Int)) {
        self.init(night: night, clock: clock)
        desks = sessions.prefix(Limits.desks).map {
            Desk(look: $0.look, state: DeskState($0.status), seed: LookHash.fnv1a($0.id),
                 subagent: !$0.subagents.isEmpty, away: awayIDs.contains($0.id))
        }
        moreBelow = max(0, sessions.count - Limits.desks)
    }
}

/// The office room, ported from the prototype's `drawOffice`, `screenFor` and `deskUnits`.
/// Pure: the same scene and `t` always give the same pixels. Golden-tested against frames exported
/// from the prototype (Tests/AgentvilleCoreTests/Fixtures/office-vectors.json).
public enum OfficeRenderer {
    /// Room size in units; the prototype draws 2 px per unit.
    public static let units = (width: 216, height: 136)
    public static let pixelSize = (width: 432, height: 272)

    /// Port of `deskUnits(i)`: desk origin and the feet anchor, in units.
    public static func deskUnits(_ i: Int) -> (gx: Int, top: Int, fx: Int, fy: Int) {
        let row = i / 3, col = i % 3
        let gx = 4 + col * 70, top = row != 0 ? 118 : 72
        return (gx, top, gx + 22, top + 8)
    }

    /// Port of `CONF` (confetti colours; the screensaver pixel cycles through them).
    static let conf = [0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436, 0x29ADFF, 0xFF77A8, 0x83769C, 0xFFF1E8].map { RGB($0) }

    // MARK: - Helpers (ports of `U` and `drawPatternU`)

    /// `U(x, y, w, h, c)`: a rectangle in room units.
    @inline(__always) static func U(_ g: inout PixelCanvas, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB) {
        g.fill(x * 2, y * 2, w * 2, h * 2, c)
    }

    static func pattern(_ g: inout PixelCanvas, _ p: [String], _ x: Int, _ y: Int, _ c: RGB) {
        for (r, row) in p.enumerated() {
            for (q, ch) in row.enumerated() where ch == "#" { U(&g, x + q, y + r, 1, 1, c) }
        }
    }

    /// JS `Math.round`: nearest integer, halves toward +∞.
    @inline(__always) static func jsRound(_ x: Double) -> Int {
        let f = x.rounded(.down)
        return Int(x - f >= 0.5 ? f + 1 : f)
    }

    /// JS `%` on numbers (sign of the dividend).
    @inline(__always) static func mod(_ a: Double, _ b: Double) -> Double { a.truncatingRemainder(dividingBy: b) }

    // MARK: - Screens

    /// Port of `screenFor(s, gx, top, t)`, with the screen's top-left at (sx, sy) in units
    /// (the office uses sx = gx + 39, sy = top − 14). `desk` nil is an empty desk.
    public static func drawScreen(_ g: inout PixelCanvas, desk: OfficeScene.Desk?, sx: Int, sy: Int, t: Double) {
        let w = 16, h = 10
        var r = XorShift32(seed: desk?.seed ?? 7 &* 97)
        let tick = Int(floor(t * 4))
        let state = desk?.state

        switch state {
        case .needsYou:
            U(&g, sx, sy, w, h, RGB(tick % 2 != 0 ? 0xFF004D : 0x7E2553))
            U(&g, sx + 7, sy + 2, 2, 4, RGB(0xFFF1E8)); U(&g, sx + 7, sy + 7, 2, 1, RGB(0xFFF1E8))
            return
        case .finished:
            U(&g, sx, sy, w, h, RGB(0x0F7A43))
            pattern(&g, ["....#", "...#.", "#.#..", ".#..."], sx + 5, sy + 3, RGB(0xFFF1E8))
            return
        case .error:
            // Agentville's own: a steady red cross (not blinking, unlike Needs you).
            U(&g, sx, sy, w, h, RGB(0x2A1520))
            pattern(&g, ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"], sx + 5, sy + 2, RGB(0xFF004D))
            return
        case .idle, .none:
            U(&g, sx, sy, w, h, RGB(0x15172C))
            let px = Int(abs(mod(t * 5, 28) - 14)), py = Int(abs(mod(t * 3.3, 16) - 8))
            U(&g, sx + min(max(px, 0), 15), sy + min(max(py, 0), 9), 1, 1, conf[Int(floor(t)) % 7])
            return
        case .working(let act):
            switch act {
            case .edit:
                U(&g, sx, sy, w, h, RGB(0x1B1E34))
                let colors = [0xFF77A8, 0x29ADFF, 0xFFEC27, 0x00E436].map { RGB($0) }
                for i in 0..<4 {
                    let ww = 3 + Int(floor(r.next() * 10))
                    let shown = i < tick % 5 ? ww : 0
                    U(&g, sx + 1 + i % 2, sy + 1 + i * 2, min(shown, 13), 1, colors[i])
                }
                if tick % 2 != 0 { U(&g, sx + 2 + tick % 9, sy + 8, 1, 1, RGB(0xFFF1E8)) }
            case .read:
                U(&g, sx, sy, w, h, RGB(0xECEAF4))
                let off = tick % 3
                for i in 0..<4 { U(&g, sx + 2, sy + 1 + (i * 2 + off) % 9, 8 + (i * 5) % 5, 1, RGB(0x9A95B5)) }
            case .bash:
                let green = RGB(0x3CFF7A)
                U(&g, sx, sy, w, h, RGB(0x0B1A12))
                let n = tick % 6
                for i in 0..<min(n, 4) {
                    U(&g, sx + 1, sy + 1 + i * 2, 1, 1, green)
                    U(&g, sx + 3, sy + 1 + i * 2, 3 + (i * 7 + tick) % 8, 1, green)
                }
                if tick % 2 != 0 { U(&g, sx + 1, sy + 8, 2, 1, green) }
            case .search:
                U(&g, sx, sy, w, h, RGB(0x1B1E34))
                for i in 0..<5 { U(&g, sx + 1, sy + 1 + i * 2, 6 + (i * 3) % 7, 1, RGB(0x5E6390)) }
                let hi = tick % 5
                g.blend(sx * 2, (sy + hi * 2) * 2, w * 2, 2 * 2, RGB(r: 255, g: 236, b: 39), alpha: 0.45)
            case .web:
                let sea = RGB(0x29ADFF), land = RGB(0x00E436)
                U(&g, sx, sy, w, h, RGB(0x2B6CB0))
                U(&g, sx + 5, sy + 2, 6, 6, sea); U(&g, sx + 4, sy + 3, 8, 4, sea)
                let o = tick % 8
                U(&g, sx + 4 + o % 6, sy + 3, 2, 2, land); U(&g, sx + 5 + (o + 3) % 5, sy + 6, 2, 1, land)
            case .plan:
                // Agentville's own: a checklist ticking itself off, row by row.
                U(&g, sx, sy, w, h, RGB(0xECEAF4))
                let done = tick % 5
                for i in 0..<4 {
                    U(&g, sx + 2, sy + 1 + i * 2, 1, 1, i < done ? RGB(0x0B9A4B) : RGB(0x9A95B5))
                    U(&g, sx + 4, sy + 1 + i * 2, 5 + (i * 3) % 6, 1, RGB(0x9A95B5))
                }
            case .tinker:
                // Agentville's own: a plug and a progress bar filling up.
                U(&g, sx, sy, w, h, RGB(0x1B1E34))
                U(&g, sx + 6, sy + 1, 1, 2, RGB(0xA5ADC2)); U(&g, sx + 9, sy + 1, 1, 2, RGB(0xA5ADC2))
                U(&g, sx + 5, sy + 3, 6, 2, RGB(0xA5ADC2))
                U(&g, sx + 2, sy + 7, 12, 1, RGB(0x2E3156))
                U(&g, sx + 2, sy + 7, tick % 13, 1, RGB(0x29ADFF))
            case .think, .other:
                U(&g, sx, sy, w, h, RGB(0x1B1E34))
                let n = tick % 4
                for i in 0..<n { U(&g, sx + 4 + i * 3, sy + 5, 2, 1, RGB(0xC2C3E0)) }
            }
        }
    }

    // MARK: - The room

    /// Office pose, lift, frame rate and emote for a desk (from `drawOffice`; table in docs/design/office.md).
    static func pose(for state: OfficeScene.DeskState, t: Double) -> (pose: Pose, raise: Int, fps: Double, emote: Emote?) {
        switch state {
        case .needsYou: return (.wave, 5 + jsRound(abs(sin(t * 6)) * 2), 5, .icon(.bang))
        case .finished: return (.cheer, 4 + jsRound(abs(sin(t * 8)) * 3), 5, .icon(.check))
        case .idle: return (.nap, 0, 1, nil)
        case .error: return (.error, 0, 2, .icon(.storm))
        case .working(let act):
            switch act {
            case .read: return (.read, 0, 1.2, nil)
            case .search: return (.search, 0, 3, nil)
            case .web: return (.web, 0, 1.6, nil)
            case .think: return (.think, 0, 2, .dots(Int(floor(t * 3)) % 4))
            case .bash: return (.deskType, 0, 11, nil)
            case .plan: return (.plan, 0, CrewSim.fps[.plan] ?? 1.5, nil)
            case .tinker: return (.tinker, 0, CrewSim.fps[.tinker] ?? 4, nil)
            case .edit, .other: return (.deskType, 0, 6, nil)
            }
        }
    }

    /// Port of `drawOffice(t)`: one 432×272 px frame.
    public static func render(_ scene: OfficeScene, t: Double, cache: SpriteCache? = nil) -> PixelCanvas {
        var g = PixelCanvas(width: pixelSize.width, height: pixelSize.height)
        let night = scene.night
        func C(_ day: UInt32, _ dark: UInt32) -> RGB { RGB(night ? dark : day) }

        // wall
        U(&g, 0, 0, 216, 46, C(0x3B4078, 0x262A56))
        for x in stride(from: 6, to: 216, by: 12) { U(&g, x, 0, 1, 44, C(0x434985, 0x2C3060)) }
        U(&g, 0, 43, 216, 3, C(0x2A2D5A, 0x1B1E40))
        // window on the wall
        U(&g, 10, 7, 42, 28, RGB(0x5B4A6B))
        U(&g, 12, 9, 38, 24, C(0x8FD3FF, 0x131B45))
        if night {
            U(&g, 40, 12, 4, 4, RGB(0xFFF1C9)); U(&g, 41, 12, 3, 1, RGB(0x131B45))
            let stars = [(16, 12), (24, 20), (31, 11), (19, 27), (45, 24), (28, 26)]
            for (i, s) in stars.enumerated() where (Int(floor(t * 1.5)) + i) % 4 != 0 { U(&g, s.0, s.1, 1, 1, RGB(0xFFF1E8)) }
        } else {
            U(&g, 15, 20, 12, 3, RGB(0xFFFFFF)); U(&g, 18, 18, 6, 2, RGB(0xFFFFFF))
            // The prototype lets this cloud sit between pixels (anti-aliased); we snap it to whole pixels.
            let cx = 30 + mod(t * 1.2, 30)
            g.fill(Int(floor((12 + mod(cx, 34)) * 2)), 13 * 2, 8 * 2, 2 * 2, RGB(0xE8F6FF))
            U(&g, 40, 11, 5, 5, RGB(0xFFE27A))
        }
        U(&g, 30, 9, 1, 24, RGB(0x5B4A6B)); U(&g, 12, 20, 38, 1, RGB(0x5B4A6B))
        U(&g, 9, 34, 44, 2, RGB(0x7A6690))
        // pinboard with notes
        U(&g, 128, 9, 42, 24, RGB(0xB98556)); U(&g, 129, 10, 40, 22, RGB(0xD9A86C))
        let notes: [(Int, Int, UInt32)] = [(132, 12, 0xFFEC27), (141, 14, 0xFF77A8), (151, 11, 0x29ADFF), (160, 15, 0x00E436),
                                           (135, 22, 0xFFA300), (148, 22, 0xFFF1E8), (158, 24, 0xFF77A8)]
        for (x, y, c) in notes { U(&g, x, y, 7, 6, RGB(c)); U(&g, x + 3, y, 1, 1, RGB(0xFF004D)) }
        // clock
        let hour = Double(scene.clock.hour % 12), minute = Double(scene.clock.minute)
        let hr = (hour + minute / 60) / 12 * Double.pi * 2, mn = minute / 60 * Double.pi * 2
        U(&g, 186, 9, 14, 14, RGB(0x1D1A2F)); U(&g, 187, 10, 12, 12, RGB(0xFFF1E8))
        for i in 0..<5 {
            let d = Double(i)
            U(&g, 193 + jsRound(sin(mn) * d), 16 - jsRound(cos(mn) * d), 1, 1, RGB(0x1D1A2F))
            if i < 4 { U(&g, 193 + jsRound(sin(hr) * d * 0.8), 16 - jsRound(cos(hr) * d * 0.8), 1, 1, RGB(0xFF004D)) }
        }
        // plant
        U(&g, 204, 36, 9, 8, RGB(0xAB5236)); U(&g, 203, 35, 11, 2, RGB(0xC8693F)); U(&g, 206, 26, 2, 10, RGB(0x008751))
        U(&g, 203, 28, 4, 3, RGB(0x00B34A)); U(&g, 208, 24, 4, 3, RGB(0x00B34A)); U(&g, 209, 30, 4, 3, RGB(0x008751))
        // floor
        let seam = C(0x9C6A43, 0x744E33)
        U(&g, 0, 46, 216, 90, C(0xB07A4F, 0x8A5E3F))
        for (row, y) in stride(from: 46, to: 136, by: 9).enumerated() {
            U(&g, 0, y, 216, 1, seam)
            for x in stride(from: (row % 2) * 17, to: 216, by: 34) { U(&g, x, y, 1, 9, seam) }
        }
        // rug
        U(&g, 6, 93, 204, 22, C(0x7E2553, 0x4A1D3F)); U(&g, 8, 95, 200, 18, C(0x963363, 0x5E2750))
        for x in stride(from: 12, to: 206, by: 8) { U(&g, x, 103, 4, 2, C(0xB04477, 0x6E3060)) }

        func sprite(_ L: Look, _ p: Pose, _ f: Int) -> PixelCanvas {
            cache?.sprite(L, p, frame: f, highlight: false) ?? SpriteRenderer.render(L, p, frame: f)
        }

        for i in 0..<Limits.desks {
            let s = i < scene.desks.count ? scene.desks[i] : nil
            let (gx, top, _, _) = deskUnits(i)
            let away = s?.away ?? false
            // chair
            U(&g, gx + 13, top - 13, 7, 13, RGB(0x2D3150)); U(&g, gx + 14, top - 12, 5, 1, RGB(0x454A73))
            U(&g, gx + 16, top, 2, 10, RGB(0x2D3150))
            // character
            if let s, !away {
                let p = pose(for: s.state, t: t)
                let f = Int(floor((t + Double(i) * 0.3) * p.fps)) % 2
                let fx = (gx + 22) * 2, fy = (top + 8 - p.raise) * 2
                g.draw(sprite(s.look, p.pose, f), x: fx - SpriteRenderer.anchor.x * 2, y: fy - SpriteRenderer.anchor.y * 2, scale: 2)
                if let e = p.emote {
                    // `officeEmote` → `drawEmote(og, cx*2, bottom*2, 2, …)`: left = cx − 9, top = bottom − 20 (px).
                    g.draw(SpriteRenderer.emote(e), x: (gx + 25) * 2 - 9, y: (top - 16 - p.raise) * 2 - 20, scale: 2)
                }
                if s.state == .idle, Int(floor(t * 1.2 + Double(i))) % 3 == 0 {
                    pattern(&g, ["##.", ".#.", ".##"], gx + 28, top - 16 - Int(floor(mod(t * 4, 4))), RGB(0xFFF1E8))
                }
            }
            // desk
            g.blend((gx + 10) * 2, (top + 12) * 2, 50 * 2, 2 * 2, RGB(r: 20, g: 10, b: 30), alpha: 0.25)
            U(&g, gx + 10, top, 50, 3, RGB(0xE0B084)); U(&g, gx + 11, top + 3, 48, 9, RGB(0xB98556))
            U(&g, gx + 11, top + 3, 48, 1, RGB(0x9A6A42))
            U(&g, gx + 48, top + 6, 4, 1, RGB(0x6E4A2E))
            if let s { U(&g, gx + 16, top + 6, 11, 3, s.look.shirt); U(&g, gx + 17, top + 7, 9, 1, s.look.shirt.shade(0.45)) }
            // keyboard, monitor, desk item
            U(&g, gx + 28, top - 1, 9, 1, RGB(0xC9CEDF))
            U(&g, gx + 38, top - 15, 18, 12, RGB(0x20233D))
            drawScreen(&g, desk: s, sx: gx + 39, sy: top - 14, t: t + Double(i))
            U(&g, gx + 46, top - 3, 3, 3, RGB(0x20233D)); U(&g, gx + 43, top - 1, 9, 1, RGB(0x20233D))
            switch s?.look.desk {
            case .mug: U(&g, gx + 57, top - 3, 3, 3, RGB(0xF4F0E8)); U(&g, gx + 57, top - 3, 3, 1, RGB(0x6B3B24))
            case .plant:
                U(&g, gx + 57, top - 3, 3, 3, RGB(0xAB5236)); U(&g, gx + 56, top - 6, 2, 3, RGB(0x00B34A)); U(&g, gx + 58, top - 7, 2, 4, RGB(0x008751))
            case .duck:
                U(&g, gx + 56, top - 3, 4, 3, RGB(0xFFEC27)); U(&g, gx + 58, top - 5, 2, 2, RGB(0xFFEC27)); U(&g, gx + 60, top - 4, 1, 1, RGB(0xFFA300))
            case .stack: U(&g, gx + 55, top - 2, 5, 2, RGB(0x29ADFF)); U(&g, gx + 56, top - 4, 5, 2, RGB(0xFF004D))
            case nil: break
            }
            // subagent: a mini-me sits on the monitor (1×, in pixels)
            if let s, !away, s.subagent {
                let f = Int(floor(t * 6)) % 2
                g.draw(sprite(s.look, .type, f), x: (gx + 47) * 2 - SpriteRenderer.anchor.x,
                       y: (top - 15) * 2 - SpriteRenderer.anchor.y + 2)
            }
            // empty chair note
            if away { U(&g, gx + 14, top - 6, 5, 1, RGB(0x454A73)) }
        }
        return g
    }
}
