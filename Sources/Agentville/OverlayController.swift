// The crew on the desktop: one borderless, transparent, shadowless window over the menu bar's
// display, with a SpriteKit scene that draws `CrewSim` (docs/architecture/app.md,
// docs/architecture/input-and-safety.md). It is click-through except while ⌥ is held over a
// character or a drag is in progress (non-negotiable #1); ⌥ and the cursor are polled each frame,
// never tapped, so no permission is needed. It's a non-activating panel, so grabbing someone
// doesn't take focus from the user's app.
// When the crew is home and the particles are gone, the scene pauses and the window leaves the
// screen (performance rule 1). More displays arrive in M8.
import AgentvilleCore
import AppKit
import SpriteKit

@MainActor
final class OverlayController {
    let sim: CrewSim
    private let window: NSPanel
    private let view: OverlayView
    private let scene: CrewScene
    private(set) var screenFrame: CGRect
    /// On screen and running (presentScene un-pauses the view, so don't trust `isPaused` for this).
    private var awake = false
    /// Gulp and similar, for the desk panel.
    var onEvent: ((CrewEvent) -> Void)?
    /// The store's sessions by id, read every frame.
    var sessions: () -> [String: Session] = { [:] }

    init() {
        let screen = NSScreen.screens.first ?? NSScreen.main!
        screenFrame = screen.frame
        sim = CrewSim(stage: Self.stage(for: screen))
        sim.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        window = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true // non-negotiable #1: the crew is glass
        // Below the menu bar, so the status item (the escape hatch) is always above the crew.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        // On every Space; not over full-screen apps (open question 6's default).
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.setFrame(screen.frame, display: false)

        view = OverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.isPaused = true
        scene = CrewScene(size: screen.frame.size)
        window.contentView = view
        scene.controller = self
        view.controller = self
        view.presentScene(scene)
        view.isPaused = true // presentScene un-pauses the view
    }

    /// The stage in the sim's top-left coordinates: the menu bar on top, the Dock at the bottom.
    static func stage(for screen: NSScreen) -> Stage {
        let f = screen.frame, v = screen.visibleFrame
        return Stage(width: f.width, height: f.height, top: f.maxY - v.maxY, bottom: f.height - (v.minY - f.minY))
    }

    /// Screen point (AppKit, y up) → sim point (top-left of the overlay's display, y down).
    func simPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - screenFrame.minX, y: screenFrame.maxY - p.y) }

    func release(_ sessions: [Session]) -> [CrewEvent] {
        let events = sim.release(sessions)
        wake()
        return events
    }

    func recall() {
        sim.recall()
        wake()
    }

    func sessionsChanged(_ sessions: [Session]) {
        guard !sim.members.isEmpty || sim.released else { return }
        sim.sessionsChanged(sessions)
        wake()
    }

    func close() {
        awake = false
        view.isPaused = true
        window.orderOut(nil)
        window.close()
    }

    private func wake() {
        guard !awake else { return }
        awake = true
        scene.resetClock()
        window.orderFrontRegardless()
        view.isPaused = false
    }

    // MARK: - Input (docs/architecture/input-and-safety.md)

    /// ⌥ is held (polled each frame).
    private(set) var optionHeld = false

    /// Port of the prototype's capture-phase listeners, with polling instead of events: read ⌥ and
    /// the cursor, feed the hover fade and grab mode, end a drag when ⌥ is let go, and take the mouse
    /// only while ⌥ is held over someone (or mid-drag). Polling `NSEvent` needs no permission.
    fileprivate func pollInput() {
        optionHeld = NSEvent.modifierFlags.contains(.option)
        let mouse = NSEvent.mouseLocation
        let p = simPoint(mouse)
        sim.grabMode = optionHeld
        sim.pointer = screenFrame.contains(mouse) ? (Double(p.x), Double(p.y)) : nil
        if !optionHeld, sim.dragging != nil { sim.endDrag(cancel: false) }
        let capture = sim.capturesMouse(optionHeld: optionHeld, x: p.x, y: p.y)
        if window.ignoresMouseEvents == capture { window.ignoresMouseEvents = !capture }
    }

    fileprivate func mouse(_ phase: OverlayView.Phase, _ event: NSEvent) {
        let p = simPoint(NSEvent.mouseLocation)
        switch phase {
        case .down:
            guard optionHeld, let id = sim.hitTest(x: p.x, y: p.y) else { return }
            sim.grab(id, x: p.x, y: p.y, at: event.timestamp)
        case .dragged:
            sim.dragTo(x: p.x, y: p.y, at: event.timestamp)
        case .up:
            sim.endDrag(cancel: false)
        }
    }

    /// Called by the scene once the crew is home and the particles are gone.
    fileprivate func sleep() {
        awake = false
        window.ignoresMouseEvents = true
        view.isPaused = true
        window.orderOut(nil)
        scene.clear()
    }
}

/// Never key or main: the user's app keeps focus while they play with the crew.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Turns presses into grabs. Only receives them while the overlay has stopped ignoring the mouse,
/// which is only while ⌥ is held over a character.
@MainActor
final class OverlayView: SKView {
    enum Phase { case down, dragged, up }
    weak var controller: OverlayController?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { controller?.mouse(.down, event) }
    override func mouseDragged(with event: NSEvent) { controller?.mouse(.dragged, event) }
    override func mouseUp(with event: NSEvent) { controller?.mouse(.up, event) }
}

/// Draws the sim each frame. Nodes are reused: one set per crew member, a pool for particles.
@MainActor
final class CrewScene: SKScene {
    weak var controller: OverlayController?
    private var last: TimeInterval?
    private var nodes: [String: MemberNodes] = [:]
    private var particleNodes: [SKSpriteNode] = []
    private let textures = TextureCache()

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func resetClock() { last = nil }

    func clear() {
        for n in nodes.values { n.remove() }
        nodes.removeAll()
        for p in particleNodes { p.isHidden = true }
    }

    override func update(_ currentTime: TimeInterval) {
        MainActor.assumeIsolated { step(currentTime) }
    }

    @MainActor
    private func step(_ now: TimeInterval) {
        guard let c = controller else { return }
        let dt = last.map { now - $0 } ?? 0
        last = now
        c.pollInput()
        for e in c.sim.update(dt: dt, sessions: c.sessions()) { c.onEvent?(e) }
        draw(c.sim)
        if c.sim.isIdle { c.sleep() }
    }

    // MARK: - Drawing (port of render, shadow, drawEnt, drawParts)

    private static let shadowColor = NSColor(srgbRed: 20 / 255, green: 14 / 255, blue: 48 / 255, alpha: 1)
    private static let shadowAlpha: CGFloat = 0.28

    @MainActor
    private func draw(_ sim: CrewSim) {
        let H = size.height
        var seen = Set<String>()
        for m in sim.members.values {
            seen.insert(m.id)
            let n = nodes[m.id] ?? {
                let n = MemberNodes(); n.add(to: self); nodes[m.id] = n; return n
            }()
            let sc = m.scale, lift = m.z + m.hop
            Self.shadow(n.shadow1, n.shadow2, x: m.x, y: m.y, sc: sc, z: lift, H: H)
            drawSidekick(m, n, H: H, sim: sim)

            let hl = sim.grabMode
            let tex = textures.sprite(m.look, m.drawPose, frame: m.frame, highlight: hl)
            if n.sprite.texture !== tex { n.sprite.texture = tex }
            let a = CGFloat(m.alpha)
            n.sprite.alpha = a; n.emote.alpha = a; n.side.alpha = a; n.badge.alpha = a
            n.bubble.alpha = max(0.15, a)
            for sh in [n.shadow1, n.shadow2, n.sideShadow1, n.sideShadow2] { sh.alpha = Self.shadowAlpha * a }
            drawDizzy(m, n, H: H)
            let st = m.stretch
            n.sprite.xScale = CGFloat(m.face * st.x * sc)
            n.sprite.yScale = CGFloat(st.y * sc)
            n.sprite.position = CGPoint(x: m.x.rounded(), y: H - (m.y - lift).rounded())
            n.sprite.zPosition = 2 + CGFloat(m.y) / 100_000

            if let e = m.emote {
                let s = max(1, sc - 1).rounded()
                let cx = m.x + m.face * 2 * sc, bottom = m.y - lift - 25 * sc
                n.emote.isHidden = false
                n.emote.texture = textures.emote(e)
                n.emote.setScale(CGFloat(s))
                n.emote.position = CGPoint(x: (cx - 4.5 * s).rounded(), y: H - (bottom - 10 * s).rounded())
            } else {
                n.emote.isHidden = true
            }

            if let b = m.bubble {
                let art = textures.bubble(b)
                if n.bubble.texture !== art.texture {
                    n.bubble.texture = art.texture
                    n.bubble.size = art.texture.size()
                    n.bubble.anchorPoint = art.anchor
                }
                n.bubble.isHidden = false
                let half = art.box.width / 2, boxH = art.box.height
                let x = min(max(m.x, half + 6), size.width - half - 6)
                let emoteH = m.emote == nil ? 0 : 11 * max(1, sc - 1)
                let y = max(sim.stage.top + boxH + 14, m.y - lift - 26 * sc - emoteH - 12)
                n.bubble.position = CGPoint(x: x.rounded(), y: H - y.rounded())
            } else {
                n.bubble.isHidden = true
            }
        }
        for (id, n) in nodes where !seen.contains(id) {
            n.remove()
            nodes[id] = nil
        }
        drawParticles(sim.particles, scale: sim.stage.scale, H: H)
        drawHud(sim, H: H)
    }

    /// Two yellow stars circling the head of a dizzy character (the `dizzy` part of `drawEnt`).
    @MainActor
    private func drawDizzy(_ m: CrewMember, _ n: MemberNodes, H: CGFloat) {
        let on = m.pose == .dizzy
        for (i, star) in n.stars.enumerated() {
            star.isHidden = !on
            guard on else { continue }
            let sc = m.scale, s = max(1, sc - 1), lift = m.z + m.hop
            let ang = m.t * 6 + Double(i) * .pi
            let x = (m.x + cos(ang) * 6 * sc - sc).rounded(), y = (m.y - lift - 25 * sc + sin(ang) * 1.5 * sc).rounded()
            star.texture = textures.plus
            star.color = Self.color(RGB(0xFFEC27))
            star.colorBlendFactor = 1
            star.size = CGSize(width: 3 * s, height: 3 * s)
            star.position = CGPoint(x: x, y: H - y)
            star.alpha = CGFloat(m.alpha)
        }
    }

    // MARK: - HUD (port of updateHud and `.hud`)

    private let hud = SKSpriteNode()
    private var hudMode: HudArt.Mode?

    @MainActor
    private func drawHud(_ sim: CrewSim, H: CGFloat) {
        let mode: HudArt.Mode? = sim.grabMode && !sim.members.isEmpty ? .grab : sim.released ? .out : nil
        if hud.parent == nil { hud.zPosition = 10; hud.anchorPoint = CGPoint(x: 0.5, y: 0); addChild(hud) }
        hud.isHidden = mode == nil
        guard let mode else { hudMode = nil; return }
        if mode != hudMode {
            hudMode = mode
            let t = HudArt.texture(mode)
            hud.texture = t
            hud.size = t.size()
        }
        hud.position = CGPoint(x: (size.width / 2).rounded(), y: H - sim.stage.bottom + 12)
    }

    /// Port of `shadow`: two stacked rows, narrower the higher it flies.
    private static func shadow(_ row1: SKSpriteNode, _ row2: SKSpriteNode, x: Double, y: Double, sc: Double, z: Double, H: CGFloat) {
        let k = min(1, max(0.35, 1 - z / 160)), w = (6 * sc * k).rounded()
        let rowH = max(1, sc.rounded())
        rect(row1, x: (x - w).rounded(), y: (y - sc * 0.5).rounded(), w: w * 2, h: rowH, H: H)
        rect(row2, x: (x - w + sc).rounded(), y: (y - sc * 1.3).rounded(), w: max(0, w * 2 - (2 * sc).rounded()), h: rowH, H: H)
    }

    /// The subagent mini-me (the sidekick part of `drawEnt`), one size smaller, behind its
    /// character, with a count badge when several subagents run (open question 12's default).
    @MainActor
    private func drawSidekick(_ m: CrewMember, _ n: MemberNodes, H: CGFloat, sim: CrewSim) {
        let parts = [n.sideShadow1, n.sideShadow2, n.side, n.badge]
        guard let side = m.side else { for p in parts { p.isHidden = true }; return }
        for p in parts { p.isHidden = false }
        let ss = max(1, m.scale - 1)
        Self.shadow(n.sideShadow1, n.sideShadow2, x: side.x, y: side.y, sc: ss, z: 0, H: H)
        let tex = textures.sprite(m.look, side.pose, frame: side.frame, highlight: sim.grabMode)
        if n.side.texture !== tex { n.side.texture = tex }
        n.side.xScale = CGFloat(side.face * ss)
        n.side.yScale = CGFloat(ss)
        n.side.position = CGPoint(x: side.x.rounded(), y: H - side.y.rounded())
        n.side.zPosition = 2 + CGFloat(min(side.y, m.y)) / 100_000 - 0.000_001
        if side.count > 1 {
            let t = textures.badge(side.count)
            if n.badge.texture !== t { n.badge.texture = t; n.badge.size = t.size() }
            n.badge.position = CGPoint(x: side.x.rounded(), y: H - (side.y - 24 * ss - 2).rounded())
        } else {
            n.badge.isHidden = true
        }
    }

    /// A top-left-anchored rect in sim coordinates.
    private static func rect(_ node: SKSpriteNode, x: Double, y: Double, w: Double, h: Double, H: CGFloat) {
        node.size = CGSize(width: w, height: h)
        node.position = CGPoint(x: x, y: H - y)
    }

    @MainActor
    private func drawParticles(_ ps: [Particle], scale S: Double, H: CGFloat) {
        while particleNodes.count < ps.count {
            let p = SKSpriteNode(color: .white, size: CGSize(width: 1, height: 1))
            p.anchorPoint = CGPoint(x: 0, y: 1)
            p.zPosition = 1
            addChild(p)
            particleNodes.append(p)
        }
        for (i, node) in particleNodes.enumerated() {
            guard i < ps.count else { node.isHidden = true; continue }
            let p = ps[i], t = p.life / p.max
            let x = p.x.rounded(), y = (p.y - p.z).rounded()
            node.isHidden = false
            switch p.kind {
            case .spark:
                // A plus: three cells of s×s, drawn as one 3×3 texture scaled by s.
                let s = max(1, (S * (1 - t * 0.5)).rounded())
                node.texture = textures.plus
                node.color = Self.color(p.color)
                node.colorBlendFactor = 1
                node.alpha = CGFloat(1 - t)
                node.size = CGSize(width: s * 3, height: s * 3)
                node.position = CGPoint(x: x - s, y: H - (y - s))
            case .dust:
                let s = (S * (1 + t * 2)).rounded()
                node.texture = nil
                node.color = Self.color(p.color)
                node.colorBlendFactor = 1
                node.alpha = CGFloat((1 - t) * 0.7)
                node.size = CGSize(width: s, height: s)
                node.position = CGPoint(x: (x - s / 2).rounded(.down), y: H - (y - s).rounded(.down))
            case .confetti:
                // A flake that flips between 1 and 2 cells wide as it flutters; fades in its last quarter.
                let w = abs(sin(p.life * 10 + p.phase)) > 0.5 ? 2.0 : 1.0
                node.texture = nil
                node.color = Self.color(p.color)
                node.colorBlendFactor = 1
                node.alpha = CGFloat(t > 0.75 ? (1 - t) * 4 : 1)
                node.size = CGSize(width: max(1, (w * S * 0.67).rounded(.down)), height: S)
                node.position = CGPoint(x: x, y: H - y)
            case .zzz:
                let s = max(1, S - 1)
                node.texture = textures.zee
                node.color = Self.color(p.color)
                node.colorBlendFactor = 1
                node.alpha = CGFloat(1 - t)
                node.size = CGSize(width: s * 3, height: s * 3)
                node.position = CGPoint(x: x, y: H - y)
            case .bit:
                node.texture = nil
                node.color = Self.color(p.color)
                node.colorBlendFactor = 1
                node.alpha = CGFloat(1 - t)
                node.size = CGSize(width: S * 2, height: S)
                node.position = CGPoint(x: x, y: H - y)
            }
        }
    }

    static func color(_ c: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// Shadows, the sprite, its sidekick, its emote and its speech bubble.
    @MainActor
    final class MemberNodes {
        let shadow1 = CrewScene.shadowNode(), shadow2 = CrewScene.shadowNode()
        let sprite = MemberNodes.spriteNode()
        let sideShadow1 = CrewScene.shadowNode(), sideShadow2 = CrewScene.shadowNode()
        let side = MemberNodes.spriteNode()
        let badge = SKSpriteNode()
        let stars = [SKSpriteNode(), SKSpriteNode()]
        let emote = SKSpriteNode()
        let bubble = SKSpriteNode()
        private var all: [SKSpriteNode] { [shadow1, shadow2, sideShadow1, sideShadow2, side, sprite, badge, emote, bubble] + stars }

        /// Feet at pixel (AX, AY) from the top-left (prototype drawImage(img, −AX, −AY)).
        static func spriteNode() -> SKSpriteNode {
            let node = SKSpriteNode()
            let a = SpriteRenderer.anchor, n = CGFloat(SpriteRenderer.size)
            node.size = CGSize(width: n, height: n)
            node.anchorPoint = CGPoint(x: CGFloat(a.x) / n, y: (n - CGFloat(a.y)) / n)
            return node
        }

        init() {
            emote.size = CGSize(width: 9, height: 10)
            emote.anchorPoint = CGPoint(x: 0, y: 1)
            emote.zPosition = 3
            badge.anchorPoint = CGPoint(x: 0.5, y: 0)
            badge.zPosition = 3
            bubble.zPosition = 4
            side.isHidden = true; badge.isHidden = true; sideShadow1.isHidden = true; sideShadow2.isHidden = true
            for s in stars { s.anchorPoint = CGPoint(x: 0, y: 1); s.zPosition = 3; s.isHidden = true }
        }

        func add(to scene: SKScene) { for n in all { scene.addChild(n) } }
        func remove() { for n in all { n.removeFromParent() } }
    }

    static func shadowNode() -> SKSpriteNode {
        let n = SKSpriteNode(color: shadowColor, size: .zero)
        n.alpha = shadowAlpha
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.zPosition = 0
        return n
    }
}

/// Nearest-neighbour textures for sprites and emotes, and speech bubble art. Bounded.
@MainActor
final class TextureCache {
    private struct Key: Hashable { let look: Look; let pose: Pose; let frame: Int; let highlight: Bool }
    private let sprites = SpriteCache()
    private var spriteTextures: [Key: SKTexture] = [:]
    private var emoteTextures: [Emote: SKTexture] = [:]
    private var bubbleTextures: [Bubble: BubbleArt.Art] = [:]
    private var badgeTextures: [Int: SKTexture] = [:]

    let plus: SKTexture = {
        var c = PixelCanvas(width: 3, height: 3)
        c.fill(0, 1, 3, 1, RGB(0xFFFFFF)); c.fill(1, 0, 1, 3, RGB(0xFFFFFF))
        return TextureCache.texture(c)
    }()

    /// Prototype `drawPattern(['##.', '.#.', '.##'])` for sleepers' z's.
    let zee: SKTexture = {
        var c = PixelCanvas(width: 3, height: 3)
        c.fill(0, 0, 2, 1, RGB(0xFFFFFF)); c.fill(1, 1, 1, 1, RGB(0xFFFFFF)); c.fill(1, 2, 2, 1, RGB(0xFFFFFF))
        return TextureCache.texture(c)
    }()

    static func texture(_ c: PixelCanvas) -> SKTexture {
        let t = SKTexture(cgImage: PixelImage.cgImage(c)!)
        t.filteringMode = .nearest
        return t
    }

    /// `highlight`: grab mode's light outline (prototype `sprite(…, hl)`).
    func sprite(_ look: Look, _ pose: Pose, frame: Int, highlight: Bool = false) -> SKTexture {
        let key = Key(look: look, pose: pose, frame: frame, highlight: highlight)
        if let t = spriteTextures[key] { return t }
        if spriteTextures.count >= Limits.spriteCache { spriteTextures.removeAll(keepingCapacity: true) }
        let t = Self.texture(sprites.sprite(look, pose, frame: frame, highlight: highlight))
        spriteTextures[key] = t
        return t
    }

    func emote(_ e: Emote) -> SKTexture {
        if let t = emoteTextures[e] { return t }
        let t = Self.texture(SpriteRenderer.emote(e))
        emoteTextures[e] = t
        return t
    }

    func bubble(_ b: Bubble) -> BubbleArt.Art {
        var key = b
        key.until = 0
        if let a = bubbleTextures[key] { return a }
        if bubbleTextures.count > 64 { bubbleTextures.removeAll() }
        let a = BubbleArt.make(b)
        bubbleTextures[key] = a
        return a
    }

    func badge(_ n: Int) -> SKTexture {
        if let t = badgeTextures[n] { return t }
        if badgeTextures.count > 32 { badgeTextures.removeAll() }
        let t = BubbleArt.badge(n)
        badgeTextures[n] = t
        return t
    }
}

/// The speech bubble (port of `.bub`): paper box, 2 pt ink ring, a drop shadow offset 3×4, and a
/// stepped tail. Text in the system font standing in for the prototype's pixel web font.
@MainActor
enum BubbleArt {
    struct Art {
        let texture: SKTexture
        /// The box's bottom centre, as a unit point of the texture (the tail hangs below it).
        let anchor: CGPoint
        let box: CGSize
    }

    /// Height below the box taken by the tail.
    static let tail: CGFloat = 10

    static func make(_ b: Bubble) -> Art {
        let (image, box, pad) = draw(b)
        let size = image.size
        return Art(texture: SKTexture(image: image),
                   anchor: CGPoint(x: (pad + box.width / 2) / size.width, y: (pad + tail) / size.height),
                   box: box)
    }

    /// Title colours of `.bub.done .t` and `.bub.wait .t`.
    static let doneInk = NSColor(srgbRed: 11 / 255, green: 122 / 255, blue: 62 / 255, alpha: 1)
    static let waitInk = NSColor(srgbRed: 208 / 255, green: 16 / 255, blue: 62 / 255, alpha: 1)

    private static func draw(_ b: Bubble) -> (NSImage, CGSize, CGFloat) {
        let text = b.text
        let ink: NSColor = switch b.kind { case .say: Theme.pixDark; case .done: doneInk; case .wait: waitInk }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .bold), .foregroundColor: ink]
        // `.bub .s`: 12 px at 80% opacity, under the title.
        let subAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                       .foregroundColor: Theme.pixDark.withAlphaComponent(0.8)]
        let ts = (text as NSString).size(withAttributes: attrs)
        let ss = b.sub.map { ($0 as NSString).size(withAttributes: subAttrs) } ?? .zero
        let box = CGSize(width: ceil(max(ts.width, ss.width)) + 18, height: ceil(ts.height) + ceil(ss.height) + 11)
        // Room for the ring (2) and the drop shadow (3 right, 4 down + 2 spread).
        let pad: CGFloat = 2, size = CGSize(width: box.width + pad * 2 + 5, height: box.height + pad * 2 + tail)
        let image = NSImage(size: size, flipped: true) { _ in
            let o = CGPoint(x: pad, y: pad)
            let boxRect = CGRect(origin: o, size: box)
            NSColor(srgbRed: 26 / 255, green: 19 / 255, blue: 48 / 255, alpha: 0.28).setFill()
            boxRect.offsetBy(dx: 3, dy: 4).insetBy(dx: -2, dy: -2).fill()
            Theme.pixDark.setFill()
            boxRect.insetBy(dx: -2, dy: -2).fill()
            Theme.pixPaper.setFill()
            boxRect.fill()
            // Tail: 8×4 paper with 2 pt ink sides, then a 4×2 ink tip.
            let cx = boxRect.midX
            Theme.pixDark.setFill()
            CGRect(x: cx - 4, y: boxRect.maxY + 2, width: 8, height: 4).fill()
            Theme.pixPaper.setFill()
            CGRect(x: cx - 2, y: boxRect.maxY, width: 4, height: 6).fill()
            Theme.pixDark.setFill()
            CGRect(x: cx - 2, y: boxRect.maxY + 6, width: 4, height: 2).fill()
            (text as NSString).draw(at: CGPoint(x: o.x + 9, y: o.y + 5), withAttributes: attrs)
            if let sub = b.sub {
                (sub as NSString).draw(at: CGPoint(x: o.x + 9, y: o.y + 5 + ceil(ts.height)), withAttributes: subAttrs)
            }
            return true
        }
        return (image, box, pad)
    }

    /// The sidekick's count badge: a small yellow tag with an ink ring and the number of subagents.
    static func badge(_ n: Int) -> SKTexture {
        let label = "\(n)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .heavy), .foregroundColor: Theme.pixDark]
        let ts = label.size(withAttributes: attrs)
        let box = CGSize(width: max(12, ceil(ts.width) + 6), height: ceil(ts.height) + 1)
        let image = NSImage(size: CGSize(width: box.width + 4, height: box.height + 4), flipped: true) { _ in
            let r = CGRect(x: 2, y: 2, width: box.width, height: box.height)
            Theme.pixDark.setFill()
            r.insetBy(dx: -2, dy: -2).fill()
            NSColor(srgbRed: 1, green: 236 / 255, blue: 39 / 255, alpha: 1).setFill()
            r.fill()
            label.draw(at: CGPoint(x: r.midX - ts.width / 2, y: r.minY), withAttributes: attrs)
            return true
        }
        return SKTexture(image: image)
    }
}

/// The HUD pill at the bottom of the screen (port of `.hud` and `updateHud`): a dark translucent
/// pill while the crew is out, an orange one in grab mode. Bold parts in the accent colour.
@MainActor
enum HudArt {
    enum Mode: Equatable { case out, grab }
    private static var cache: [Mode: SKTexture] = [:]

    static func texture(_ mode: Mode) -> SKTexture {
        if let t = cache[mode] { return t }
        let font = NSFont.systemFont(ofSize: 12.5, weight: .medium), bold = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let ink: NSColor = mode == .grab ? Theme.pixDark : .white
        let strong: NSColor = mode == .grab ? Theme.pixDark : Theme.accent
        let parts: [(String, Bool)] = mode == .grab
            ? [("Grab mode", true), ("  drag anyone, let go to throw", false)]
            : [("Clicks pass through · hold ", false), ("⌥", true), (" to grab · ", false), ("⌃⌥C", true), (" calls them back", false)]
        let text = NSMutableAttributedString()
        for (str, b) in parts {
            text.append(NSAttributedString(string: str, attributes: [.font: b ? bold : font, .foregroundColor: b ? strong : ink]))
        }
        let ts = text.size()
        let size = CGSize(width: ceil(ts.width) + 24, height: ceil(ts.height) + 14)
        let image = NSImage(size: size, flipped: true) { r in
            let fill = mode == .grab ? NSColor(srgbRed: 1, green: 163 / 255, blue: 0, alpha: 0.95)
                                     : NSColor(srgbRed: 20 / 255, green: 18 / 255, blue: 40 / 255, alpha: 0.72)
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
            text.draw(at: CGPoint(x: 12, y: 7))
            return true
        }
        let t = SKTexture(image: image)
        cache[mode] = t
        return t
    }
}
