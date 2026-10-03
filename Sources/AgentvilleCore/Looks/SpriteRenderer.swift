/// Character poses (docs/design/sprites-and-poses.md#poses). Raw values are the prototype's pose names.
public enum Pose: String, CaseIterable, Sendable {
    case idle, walk, type, deskType, read, bash, search, web, think, wave, cheer, coffee, sleep, nap, dangle, dizzy, blink
    /// Agentville's own poses, for states the prototype never drew (open question 12): a checklist
    /// on a clipboard (planning), a gadget and a wrench (MCP tools), and a head-scratching slump
    /// under a storm cloud (a failed turn).
    case plan, tinker, error

    /// The poses ported from the prototype (golden-tested against its exports).
    public static let prototypePoses = allCases.filter { !agentvillePoses.contains($0) }
    /// Poses drawn for Agentville (docs/design/sprites-and-poses.md#agentvilles-own-poses).
    public static let agentvillePoses: [Pose] = [.plan, .tinker, .error]

    /// Port of `frameCount(p)`.
    public var frameCount: Int { self == .walk ? 4 : 2 }
}

/// Emote bubbles (port of `ICON` + `drawEmote`).
public enum Emote: Equatable, Hashable, Sendable {
    /// `storm` is Agentville's own (a failed turn); the rest are the prototype's `ICON`.
    public enum Icon: String, CaseIterable, Sendable { case bang, check, heart, quest, storm }
    case icon(Icon)
    /// The animated "…" bubble with 0–3 dots (the prototype shows `floor(t*3) % 4`).
    case dots(Int)

    public static func icon(rawValue: String) -> Emote? { Icon(rawValue: rawValue).map { .icon($0) } }
}

/// Procedural pixel sprites, ported line for line from the prototype's `sprite`, `drawChar`,
/// `outline`, `avatar` and `drawEmote`. Golden-tested against frames exported from the prototype
/// (Tests/AgentvilleCoreTests/Fixtures/sprite-vectors.json).
public enum SpriteRenderer {
    /// Frame size, pixels (prototype `SPW`).
    public static let size = 28
    /// Feet anchor inside the frame (prototype `AX`, `AY`).
    public static let anchor = (x: 12, y: 26)
    /// List avatar: this crop of `idle` frame 0 (port of `avatar`; the app draws it at 2×).
    public static let avatarCrop = (x: 5, y: 1, w: 13, h: 14)

    static let eye = RGB(0x1A1330)
    static let wood = RGB(0x8B5A2B), metal = RGB(0xA5ADC2)

    /// Port of `sprite(L, pose, f, hl)`: draw, outline, and a second highlight outline when grabbable.
    public static func render(_ L: Look, _ pose: Pose, frame: Int, highlight: Bool = false) -> PixelCanvas {
        let n = pose.frameCount
        var c = PixelCanvas(width: size, height: size)
        drawChar(&c, L, pose, ((frame % n) + n) % n)
        c.origin = (0, 0)
        c.outline(Palette.outline)
        if highlight { c.outline(Palette.highlight) }
        return c
    }

    /// Port of `avatar(L)`: the head crop of `idle` frame 0, unscaled.
    public static func avatar(_ L: Look) -> PixelCanvas {
        render(L, .idle, frame: 0).cropped(avatarCrop.x, avatarCrop.y, avatarCrop.w, avatarCrop.h)
    }

    // MARK: - drawChar

    private enum Legs { case stand, walk0, walk1, walk2, walk3, kickA, kickB }
    private enum Arms {
        case down, swingA, swingB, typeA, typeB, lapA, lapB, book, hammerUp, hammerDown, magnifier
        case telescope, chin, waveA, waveB, up, upMid, mug, sip, rest
        case clipboard, gadgetA, gadgetB, scratchA, scratchB
    }
    private enum Eyes { case open, down, up, closed, happy, wide, x }
    private enum Mouth { case closed, open, frown }
    private enum Prop { case none, crt, laptop, book, lens, telescope }

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private static func drawChar(_ g: inout PixelCanvas, _ L: Look, _ pose: Pose, _ f: Int) {
        g.origin = (2, 2)
        func R(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB) { g.fill(x, y, w, h, c) }
        func P(_ x: Int, _ y: Int, _ c: RGB) { g.dot(x, y, c) }
        func clear(_ x: Int, _ y: Int) { g.clear(x, y, 1, 1) }

        var dy = 0, legs = Legs.stand, arms = Arms.down, eyes = Eyes.open
        var mouthOpen = false, prop = Prop.none, sit = false, frown = false
        switch pose {
        case .idle: dy = f != 0 ? 1 : 0
        case .walk:
            legs = [.walk0, .walk1, .walk2, .walk3][f]
            dy = f % 2 == 0 ? 1 : 0
            arms = f == 0 ? .swingA : f == 2 ? .swingB : .down
        case .type: sit = true; arms = f != 0 ? .lapB : .lapA; prop = .laptop; eyes = .down
        case .deskType: arms = f != 0 ? .typeB : .typeA; eyes = .down
        case .read: arms = .book; prop = .book; eyes = .down
        case .bash: arms = f != 0 ? .hammerDown : .hammerUp; prop = .crt; mouthOpen = f != 0
        case .search: arms = .magnifier; dy = f; prop = .lens
        case .web: arms = .telescope; prop = .telescope; dy = f != 0 ? 1 : 0
        case .think: arms = .chin; eyes = .up; dy = f != 0 ? 1 : 0
        case .wave: arms = f != 0 ? .waveB : .waveA; mouthOpen = true
        case .cheer: arms = f != 0 ? .up : .upMid; eyes = .happy; mouthOpen = true
        case .coffee: sit = true; arms = f != 0 ? .sip : .mug; eyes = f != 0 ? .closed : .open
        case .sleep: sit = true; eyes = .closed; dy = f != 0 ? 1 : 0; arms = .rest
        case .nap: eyes = .closed; dy = 3 + (f != 0 ? 1 : 0); arms = .typeA
        case .dangle: legs = f != 0 ? .kickB : .kickA; arms = .up; eyes = .wide; mouthOpen = true
        case .dizzy: eyes = .x; mouthOpen = true; dy = f != 0 ? 1 : 0
        case .blink: eyes = .closed
        // Agentville's own poses (not in the prototype).
        case .plan: arms = .clipboard; eyes = .down; dy = f != 0 ? 1 : 0
        case .tinker: arms = f != 0 ? .gadgetB : .gadgetA; eyes = .down
        case .error: arms = f != 0 ? .scratchB : .scratchA; eyes = .down; dy = 1; frown = true
        }
        if sit { dy += 3 }
        let S1 = L.shirt, S2 = L.shirtD, SK = L.skin, PN = L.pants, PD = L.pantsD, SH = L.shoe

        // long hair behind body
        if L.style == .long { R(4, 4 + dy, 3, 10, L.hairD) }
        if prop == .crt {
            R(17, 15, 7, 8, RGB(0xD9CFB8)); R(18, 16, 5, 4, RGB(0x0E2A1A)); P(19, 17, RGB(0x3CFF7A))
            R(19, 18, f != 0 ? 3 : 2, 1, RGB(0x3CFF7A)); R(17, 22, 7, 1, RGB(0xB3A68B))
        }

        // legs
        if sit { R(7, 21, 7, 1, PN); R(8, 22, 8, 2, PN); R(16, 21, 2, 3, SH) } else {
            switch legs {
            case .stand: R(7, 18, 6, 1, PN); R(7, 19, 2, 3, PD); R(11, 19, 2, 3, PN); R(7, 22, 3, 2, SH); R(11, 22, 3, 2, SH)
            case .walk0: R(7, 18, 6, 1, PN); R(6, 19, 2, 3, PD); R(12, 19, 2, 3, PN); R(5, 22, 3, 2, SH); R(12, 22, 3, 2, SH)
            case .walk2: R(7, 18, 6, 1, PN); R(12, 19, 2, 3, PD); R(6, 19, 2, 3, PN); R(13, 22, 3, 2, SH.shade(-0.2)); R(5, 22, 3, 2, SH)
            case .walk1, .walk3: R(7, 18, 6, 1, PN); R(8, 19, 2, 3, PD); R(10, 19, 2, 2, PN); R(8, 22, 3, 2, SH); R(10, 21, 3, 2, SH)
            case .kickA: R(7, 18, 6, 1, PN); R(7, 19, 2, 3, PD); R(11, 19, 2, 2, PN); R(7, 22, 2, 2, SH); R(11, 21, 3, 2, SH)
            case .kickB: R(7, 18, 6, 1, PN); R(7, 19, 2, 2, PD); R(11, 19, 2, 3, PN); R(6, 21, 3, 2, SH); R(11, 22, 2, 2, SH)
            }
        }

        // torso
        R(6, 12 + dy, 8, 6, S1); R(6, 17 + dy, 8, 1, S2)
        switch L.pattern {
        case .stripe: R(6, 14 + dy, 8, 1, L.shirtL)
        case .pocket: R(11, 13 + dy, 2, 2, S2)
        case .hood: R(5, 12 + dy, 3, 2, S2); P(10, 13 + dy, L.shirtL); P(10, 14 + dy, L.shirtL)
        case .plain: break
        }

        // head
        R(5, 3 + dy, 10, 9, SK); R(6, 11 + dy, 8, 1, L.skinD)
        clear(5, 3 + dy); clear(14, 3 + dy); clear(5, 11 + dy); clear(14, 11 + dy)
        P(6, 8 + dy, L.skinD)

        // hair
        let H = L.hair, y0 = dy
        func topHair() {
            R(5, 2 + y0, 10, 3, H); R(5, 5 + y0, 2, 3, H); R(12, 5 + y0, 3, 1, H)
            clear(5, 2 + y0); clear(14, 2 + y0); P(8, 2 + y0, L.hairL); P(9, 2 + y0, L.hairL)
        }
        switch L.style {
        case .short: topHair()
        case .spiky:
            topHair(); P(6, 1 + y0, H); P(8, 1 + y0, H); P(8, 0 + y0, H); P(11, 1 + y0, H); P(12, 0 + y0, H); P(13, 1 + y0, H)
        case .cap:
            R(6, 1 + y0, 8, 1, L.cap); R(5, 2 + y0, 10, 3, L.cap); clear(5, 2 + y0); R(13, 4 + y0, 4, 1, L.capD)
            R(5, 5 + y0, 2, 2, H); P(9, 1 + y0, L.capL)
        case .beanie:
            R(5, 1 + y0, 10, 4, L.cap); R(5, 4 + y0, 10, 1, L.capL); R(9, 0 + y0, 2, 1, L.capL)
            clear(5, 1 + y0); clear(14, 1 + y0); R(5, 5 + y0, 1, 2, H)
        case .long: topHair(); R(13, 5 + y0, 2, 2, H)
        case .bun: topHair(); R(4, 0 + y0, 3, 3, H); P(5, 0 + y0, L.hairL)
        case .curly:
            R(5, 2 + y0, 10, 3, H); P(5, 1 + y0, H); P(7, 1 + y0, H); P(9, 1 + y0, H); P(11, 1 + y0, H); P(13, 1 + y0, H)
            R(4, 4 + y0, 2, 5, H); R(12, 5 + y0, 3, 1, H); P(8, 2 + y0, L.hairL)
        }

        // face
        let ey = 7 + dy, E = eye
        switch eyes {
        case .open: R(10, ey, 1, 2, E); R(13, ey, 1, 2, E)
        case .down: R(10, ey + 1, 1, 2, E); R(13, ey + 1, 1, 2, E)
        case .up: R(10, ey - 1, 1, 2, E); R(13, ey - 1, 1, 2, E)
        case .closed: R(9, ey + 1, 2, 1, E); R(12, ey + 1, 2, 1, E)
        case .happy: P(10, ey, E); P(9, ey + 1, E); P(11, ey + 1, E); P(13, ey, E); P(12, ey + 1, E); P(14, ey + 1, E)
        case .wide: R(10, ey - 1, 1, 3, E); R(13, ey - 1, 1, 3, E)
        case .x:
            P(9, ey, E); P(11, ey, E); P(10, ey + 1, E); P(9, ey + 2, E); P(11, ey + 2, E)
            P(12, ey, E); P(14, ey, E); P(13, ey + 1, E); P(12, ey + 2, E); P(14, ey + 2, E)
        }
        P(9, 9 + dy, L.blush); P(14, 9 + dy, L.blush)
        if mouthOpen { R(11, 10 + dy, 2, 1, RGB(0x7A1F35)) }
        if frown { R(11, 10 + dy, 2, 1, RGB(0x7A1F35)); P(10, 11 + dy, RGB(0x7A1F35)); P(13, 11 + dy, RGB(0x7A1F35)) }
        if L.acc == .shades && eyes != .x { R(9, ey, 6, 2, RGB(0x1A1330)); P(10, ey, RGB(0x8FD3FF)); P(13, ey, RGB(0x8FD3FF)) }
        if L.acc == .headphones { R(6, 1 + dy, 8, 1, RGB(0x3A3F5C)); R(6, 5 + dy, 2, 3, RGB(0x3A3F5C)); P(6, 6 + dy, L.cap) }

        // props behind arms
        if prop == .laptop { R(13, 21, 7, 1, metal); R(19, 15, 1, 6, RGB(0xC2C8D8)); R(18, 16, 1, 4, RGB(0x8FE3FF)) }

        // arms
        switch arms {
        case .down: R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); R(14, 13 + dy, 1, 4, S1); P(14, 17 + dy, SK)
        case .swingA: R(5, 13 + dy, 1, 3, S2); P(4, 16 + dy, SK); R(14, 13 + dy, 1, 3, S1); P(15, 16 + dy, SK)
        case .swingB: R(5, 13 + dy, 1, 3, S2); P(6, 16 + dy, SK); R(14, 13 + dy, 1, 3, S1); P(13, 16 + dy, SK)
        case .typeA: R(5, 13 + dy, 1, 3, S2); R(14, 14 + dy, 3, 1, S1); P(17, 14 + dy, SK); P(18, 15 + dy, SK)
        case .typeB: R(5, 13 + dy, 1, 3, S2); R(14, 14 + dy, 3, 1, S1); P(17, 15 + dy, SK); P(18, 14 + dy, SK)
        case .lapA: R(5, 16, 1, 3, S2); R(14, 16, 1, 3, S1); P(15, 19, S1); P(16, 20, SK); P(18, 19, SK)
        case .lapB: R(5, 16, 1, 3, S2); R(14, 16, 1, 3, S1); P(15, 19, S1); P(16, 19, SK); P(18, 20, SK)
        case .book:
            let page = RGB(0xFFF4E6), ink = RGB(0x9A8F9F)
            R(5, 13 + dy, 1, 3, S2); R(14, 13 + dy, 1, 2, S1)
            R(13, 11 + dy, 3, 5, page); R(16, 11 + dy, 3, 5, RGB(0xF0DCC4)); R(16, 11 + dy, 1, 5, RGB(0xC94F4F))
            if f != 0 { R(13, 13 + dy, 2, 1, ink); R(17, 13 + dy, 2, 1, ink); R(13, 15 + dy, 2, 1, ink); R(16, 10 + dy, 2, 1, page) }
            else { R(13, 12 + dy, 2, 1, ink); R(17, 12 + dy, 2, 1, ink); R(13, 14 + dy, 2, 1, ink); R(17, 14 + dy, 2, 1, ink) }
            P(13, 16 + dy, SK); P(18, 16 + dy, SK)
        case .hammerUp:
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); P(14, 12 + dy, S1); R(15, 8 + dy, 1, 4, S1); P(15, 7 + dy, SK)
            R(15, 3 + dy, 1, 4, wood); R(14, 1 + dy, 3, 2, metal)
        case .hammerDown:
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); R(14, 13 + dy, 3, 1, S1); P(17, 13 + dy, SK)
            R(18, 13 + dy, 2, 1, wood); R(20, 12 + dy, 2, 3, metal)
        case .magnifier:
            let rim = RGB(0x6E7690)
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); R(14, 12 + dy, 1, 2, S1); P(15, 11 + dy, S1); P(16, 10 + dy, SK); P(17, 9 + dy, wood)
            R(18, 5 + dy, 3, 1, rim); R(18, 9 + dy, 3, 1, rim); R(17, 6 + dy, 1, 3, rim); R(21, 6 + dy, 1, 3, rim)
            R(18, 6 + dy, 3, 3, RGB(0xBFE9FF)); P(18, 6 + dy, RGB(0xFFFFFF))
        case .telescope:
            R(5, 13 + dy, 1, 3, S2); R(14, 11 + dy, 1, 2, S1); P(15, 10 + dy, SK)
            for i in 0..<9 {
                // JS Math.round(i * .6); no value here sits exactly on .5, so .rounded() agrees.
                R(14 + i, 7 + dy - Int((Double(i) * 0.6).rounded()), 1, 2, i < 3 ? RGB(0x6B4A2B) : RGB(0xD4A24C))
            }
            R(22, 1 + dy, 1, 3, RGB(0x8FD3FF)); P(18, 7 + dy, SK)
        case .chin: R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); R(14, 12 + dy, 1, 3, S1); P(14, 11 + dy, SK)
        case .waveA: R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); P(14, 12 + dy, S1); R(15, 8 + dy, 1, 4, S1); P(15, 7 + dy, SK)
        case .waveB:
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); P(14, 12 + dy, S1); R(15, 10 + dy, 1, 2, S1); P(16, 9 + dy, S1); P(17, 8 + dy, SK)
        case .up: P(5, 12 + dy, S2); R(4, 8 + dy, 1, 4, S2); P(4, 7 + dy, SK); P(14, 12 + dy, S1); R(15, 8 + dy, 1, 4, S1); P(15, 7 + dy, SK)
        case .upMid: R(4, 10 + dy, 1, 3, S2); P(3, 9 + dy, SK); R(15, 10 + dy, 1, 3, S1); P(16, 9 + dy, SK)
        case .mug:
            R(5, 16, 1, 3, S2); R(14, 16, 1, 2, S1); P(15, 17, SK)
            R(15, 14, 3, 3, RGB(0xF4F0E8)); R(15, 14, 3, 1, RGB(0x6B3B24)); P(18, 15, RGB(0xF4F0E8))
        case .sip: R(5, 16, 1, 3, S2); R(14, 15, 1, 2, S1); P(14, 14, SK); R(13, 11, 3, 3, RGB(0xF4F0E8)); P(16, 12, RGB(0xF4F0E8))
        case .rest: R(5, 13 + dy, 1, 3, S2); P(5, 16 + dy, SK); R(14, 13 + dy, 1, 3, S1); P(14, 16 + dy, SK)

        // Agentville's own arms and props (not in the prototype).
        case .clipboard:
            // A clipboard held up in front: board, metal clip, paper with two lines; a tick lands on the second.
            let board = RGB(0xB07A45), page = RGB(0xFFF4E6), ink = RGB(0x9A8F9F), tick = RGB(0x0B9A4B)
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); R(14, 13 + dy, 1, 3, S1)
            R(15, 9 + dy, 5, 8, board); R(16, 10 + dy, 3, 6, page); R(16, 9 + dy, 3, 1, metal)
            R(16, 11 + dy, 2, 1, ink); R(16, 13 + dy, 2, 1, ink); P(18, 11 + dy, tick)
            if f != 0 { P(18, 13 + dy, tick) } else { R(16, 15 + dy, 1, 1, ink) }
            P(15, 16 + dy, SK)
        case .gadgetA, .gadgetB:
            // A little box with an antenna and a blinking light, turned with a wrench on its right.
            let box = RGB(0x3A3F5C), led = arms == .gadgetA ? RGB(0xFF004D) : RGB(0x00E436)
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); R(14, 14 + dy, 1, 2, S1); P(15, 16 + dy, SK)
            R(15, 12 + dy, 4, 4, box); R(16, 13 + dy, 1, 1, RGB(0x5E6390)); P(17, 13 + dy, led)
            R(16, 9 + dy, 1, 3, metal); P(16, 8 + dy, RGB(0xFFEC27))
            // The wrench: a handle and an open-ended head, rocking up a row as it turns.
            let wy = (arms == .gadgetA ? 14 : 13) + dy
            R(19, wy, 3, 1, metal); R(22, wy - 1, 2, 1, metal); P(22, wy, metal); R(22, wy + 1, 2, 1, metal)
        case .scratchA, .scratchB:
            // Hand at the side of the head, scratching; a sweat drop slides down.
            let up = arms == .scratchA ? 0 : 1, drop = RGB(0x8FD3FF)
            R(5, 13 + dy, 1, 4, S2); P(5, 17 + dy, SK); P(14, 12 + dy, S1); R(15, 7 + up + dy, 1, 5 - up, S1)
            P(15, 6 + up + dy, SK)
            P(4, 5 + up * 2 + dy, drop); P(4, 6 + up * 2 + dy, drop)
        }
    }

    // MARK: - Emotes

    /// Port of `ICON`: 5×5 patterns and their colours.
    static let icons: [Emote.Icon: (color: RGB, pattern: [String])] = [
        .bang: (RGB(0xE0103F), ["..#..", "..#..", "..#..", ".....", "..#.."]),
        .check: (RGB(0x0B9A4B), ["....#", "...##", "#.##.", "###..", ".#..."]),
        .heart: (RGB(0xFF3F7F), [".#.#.", "#####", "#####", ".###.", "..#.."]),
        .quest: (RGB(0x2B7BD6), [".###.", "....#", "..##.", ".....", "..#.."]),
        // Agentville's own: a grey cloud; `*` cells take the bolt colour below.
        .storm: (RGB(0x6E7690), [".###.", "#####", "..**.", ".**..", ".*..."]),
    ]
    /// Second colour for `*` cells.
    static let iconAccent: [Emote.Icon: RGB] = [.storm: RGB(0xFFA300)]

    /// Port of `drawEmote` at scale 1: a 9×10 bubble (9×9 plus a 1 px tail). The app scales it up.
    public static func emote(_ kind: Emote) -> PixelCanvas {
        var c = PixelCanvas(width: 9, height: 10)
        c.fill(1, 0, 7, 9, Palette.outline); c.fill(0, 1, 9, 7, Palette.outline); c.fill(4, 9, 1, 1, Palette.outline)
        c.fill(1, 1, 7, 7, RGB(0xFFF8EC))
        switch kind {
        case .dots(let n):
            for i in 0..<max(0, min(3, n)) { c.fill(2 + i * 2, 4, 1, 1, RGB(0x5B5578)) }
        case .icon(let icon):
            let (color, pattern) = icons[icon]!
            for (r, row) in pattern.enumerated() {
                for (col, ch) in row.enumerated() where ch != "." {
                    c.fill(2 + col, 2 + r, 1, 1, ch == "*" ? iconAccent[icon] ?? color : color)
                }
            }
        }
        return c
    }
}
