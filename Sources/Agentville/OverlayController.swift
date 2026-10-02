// The crew on the desktop: one borderless, transparent, shadowless, click-through window over the
// menu bar's display, with a SpriteKit scene that draws `CrewSim` (docs/architecture/app.md,
// docs/architecture/input-and-safety.md). In M3 it never takes a click: grabbing arrives in M5.
// When the crew is home and the particles are gone, the scene pauses and the window leaves the
// screen (performance rule 1). More displays arrive in M8.
import AgentvilleCore
import AppKit
import SpriteKit

@MainActor
final class OverlayController {
    let sim: CrewSim
    private let window: NSWindow
    private let view: SKView
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

        window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: true)
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

        view = SKView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.isPaused = true
        scene = CrewScene(size: screen.frame.size)
        window.contentView = view
        scene.controller = self
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

    /// Called by the scene once the crew is home and the particles are gone.
    fileprivate func sleep() {
        awake = false
        view.isPaused = true
        window.orderOut(nil)
        scene.clear()
    }
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
            // Shadow: two stacked rows, narrower the higher it flies.
            let k = min(1, max(0.35, 1 - (m.z + m.hop) / 160)), w = (6 * sc * k).rounded()
            let rowH = max(1, sc.rounded())
            Self.rect(n.shadow1, x: (m.x - w).rounded(), y: (m.y - sc * 0.5).rounded(), w: w * 2, h: rowH, H: H)
            Self.rect(n.shadow2, x: (m.x - w + sc).rounded(), y: (m.y - sc * 1.3).rounded(), w: max(0, w * 2 - (2 * sc).rounded()), h: rowH, H: H)

            let tex = textures.sprite(m.look, m.drawPose, frame: m.frame)
            if n.sprite.texture !== tex { n.sprite.texture = tex }
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
                let art = textures.bubble(b.text)
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
            }
        }
    }

    static func color(_ c: RGB) -> NSColor {
        NSColor(srgbRed: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// Shadows, the sprite, its emote and its speech bubble.
    @MainActor
    final class MemberNodes {
        let shadow1 = CrewScene.shadowNode(), shadow2 = CrewScene.shadowNode()
        let sprite = SKSpriteNode()
        let emote = SKSpriteNode()
        let bubble = SKSpriteNode()

        init() {
            let a = SpriteRenderer.anchor, n = CGFloat(SpriteRenderer.size)
            sprite.size = CGSize(width: n, height: n)
            // Feet at pixel (AX, AY) from the top-left (prototype drawImage(img, −AX, −AY)).
            sprite.anchorPoint = CGPoint(x: CGFloat(a.x) / n, y: (n - CGFloat(a.y)) / n)
            emote.size = CGSize(width: 9, height: 10)
            emote.anchorPoint = CGPoint(x: 0, y: 1)
            emote.zPosition = 3
            bubble.zPosition = 4
        }

        func add(to scene: SKScene) { for n in [shadow1, shadow2, sprite, emote, bubble] { scene.addChild(n) } }
        func remove() { for n in [shadow1, shadow2, sprite, emote, bubble] { n.removeFromParent() } }
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
    private struct Key: Hashable { let look: Look; let pose: Pose; let frame: Int }
    private let sprites = SpriteCache()
    private var spriteTextures: [Key: SKTexture] = [:]
    private var emoteTextures: [Emote: SKTexture] = [:]
    private var bubbleTextures: [String: BubbleArt.Art] = [:]

    let plus: SKTexture = {
        var c = PixelCanvas(width: 3, height: 3)
        c.fill(0, 1, 3, 1, RGB(0xFFFFFF)); c.fill(1, 0, 1, 3, RGB(0xFFFFFF))
        return TextureCache.texture(c)
    }()

    static func texture(_ c: PixelCanvas) -> SKTexture {
        let t = SKTexture(cgImage: PixelImage.cgImage(c)!)
        t.filteringMode = .nearest
        return t
    }

    func sprite(_ look: Look, _ pose: Pose, frame: Int) -> SKTexture {
        let key = Key(look: look, pose: pose, frame: frame)
        if let t = spriteTextures[key] { return t }
        if spriteTextures.count >= Limits.spriteCache { spriteTextures.removeAll(keepingCapacity: true) }
        let t = Self.texture(sprites.sprite(look, pose, frame: frame, highlight: false))
        spriteTextures[key] = t
        return t
    }

    func emote(_ e: Emote) -> SKTexture {
        if let t = emoteTextures[e] { return t }
        let t = Self.texture(SpriteRenderer.emote(e))
        emoteTextures[e] = t
        return t
    }

    func bubble(_ text: String) -> BubbleArt.Art {
        if let a = bubbleTextures[text] { return a }
        if bubbleTextures.count > 64 { bubbleTextures.removeAll() }
        let a = BubbleArt.make(text)
        bubbleTextures[text] = a
        return a
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

    static func make(_ text: String) -> Art {
        let (image, box, pad) = draw(text)
        let size = image.size
        return Art(texture: SKTexture(image: image),
                   anchor: CGPoint(x: (pad + box.width / 2) / size.width, y: (pad + tail) / size.height),
                   box: box)
    }

    private static func draw(_ text: String) -> (NSImage, CGSize, CGFloat) {
        let font = NSFont.systemFont(ofSize: 14, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Theme.pixDark]
        let ts = (text as NSString).size(withAttributes: attrs)
        let box = CGSize(width: ceil(ts.width) + 18, height: ceil(ts.height) + 11)
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
            return true
        }
        return (image, box, pad)
    }
}
