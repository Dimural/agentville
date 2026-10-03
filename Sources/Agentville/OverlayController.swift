// The crew on the desktop: one borderless, transparent, shadowless window over the menu bar's
// display, with a SpriteKit scene that draws `CrewSim` (docs/architecture/app.md,
// docs/architecture/input-and-safety.md). It is click-through except while ⌥ is held over a
// character or a drag is in progress (non-negotiable #1); ⌥ and the cursor are polled each frame,
// never tapped, so no permission is needed. It's a non-activating panel, so grabbing someone
// doesn't take focus from the user's app.
// When the crew is home and the particles are gone, the scene pauses and the window leaves the
// screen (performance rule 1). More displays arrive in M8.
// Bug 0001 (docs/bugs/0001-grey-screen-overlay.md): the layers are explicitly clear, an
// `OverlayWatchdog` takes the window off screen if frames stop, the window follows display changes
// and leaves the screen while the display sleeps, and all of it is logged to `Diagnostics`.
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
    /// Diagnostics (in memory only).
    var log: (String) -> Void = { _ in }
    private var watchdog = OverlayWatchdog()
    private var watchTimer: Timer?
    /// Uptime of the last wake, until its first frame is logged.
    private var wokeAt: TimeInterval?
    private var lastFrameAt: TimeInterval?
    private var displayAsleep = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

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
        // Never animated in or out: it's glass, not a window the user opened.
        window.animationBehavior = .none
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
        // Never let a frame show anything but the crew (bug 0001, hypothesis 2).
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        scene.controller = self
        view.controller = self
        view.presentScene(scene)
        view.isPaused = true // presentScene un-pauses the view
        observe()
    }

    private func observe() {
        let app = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        func on(_ c: NotificationCenter, _ name: Notification.Name, _ f: @escaping @MainActor (OverlayController) -> Void) {
            let token = c.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self { f(self) } }
            }
            observers.append((c, token))
        }
        on(app, NSApplication.didChangeScreenParametersNotification) { $0.screensChanged() }
        on(ws, NSWorkspace.screensDidSleepNotification) { $0.displaySleep(true) }
        on(ws, NSWorkspace.screensDidWakeNotification) { $0.displaySleep(false) }
    }

    private static func size(_ r: CGRect) -> String { "\(Int(r.width))×\(Int(r.height)) at \(Int(r.minX)),\(Int(r.minY))" }

    /// For diagnostics.
    var stateDescription: String {
        let state = awake ? (displayAsleep ? "awake, display asleep" : watchdog.visible ? "awake" : "awake, hidden by watchdog") : "asleep"
        return "\(state), on screen: \(window.isVisible), frame \(Int(screenFrame.width))×\(Int(screenFrame.height))"
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
        wake("release")
        return events
    }

    func recall() {
        sim.recall()
        wake("recall")
    }

    /// Always passed on: the sim needs the order for the crowd and the names for walk-ons. It only
    /// wakes the overlay when someone is out (or about to be).
    func sessionsChanged(_ sessions: [Session]) {
        sim.sessionsChanged(sessions)
        if !sim.isIdle { wake("sessions changed") }
    }

    /// Store effects: finished turns and sessions that need you may walk on (crew inside).
    func notify(_ effects: [StoreEffect]) {
        sim.notify(effects)
        if !sim.isIdle { wake("walk-on") }
    }

    func close() {
        awake = false
        stopWatching()
        for (c, t) in observers { c.removeObserver(t) }
        observers.removeAll()
        view.isPaused = true
        window.orderOut(nil)
        window.close()
    }

    private func wake(_ reason: String) {
        guard !awake else { return }
        awake = true
        log("overlay wake (\(reason))")
        guard !displayAsleep else { return } // shown when the display wakes
        present()
    }

    /// On screen and running, watched.
    private func present() {
        scene.resetClock()
        window.orderFrontRegardless()
        view.isPaused = false
        if window.frame != screenFrame {
            log("overlay frame \(Self.size(window.frame)) differs from the display's \(Self.size(screenFrame)); fixing")
            window.setFrame(screenFrame, display: false)
        }
        wokeAt = AppDelegate.now()
        lastFrameAt = nil
        watchdog.awake(at: AppDelegate.now())
        startWatching()
    }

    // MARK: - Watchdog, displays (bug 0001)

    private func startWatching() {
        guard watchTimer == nil else { return }
        let t = Timer(timeInterval: Timing.overlayCheck, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFrames() }
        }
        t.tolerance = Timing.overlayCheck / 4
        RunLoop.main.add(t, forMode: .common)
        watchTimer = t
    }

    private func stopWatching() {
        watchTimer?.invalidate()
        watchTimer = nil
        watchdog.asleep()
    }

    /// Each frame, from the scene.
    fileprivate func frameDrawn() {
        let now = AppDelegate.now()
        if let w = wokeAt {
            wokeAt = nil
            log(String(format: "overlay first frame after %.0f ms", (now - w) * 1000))
        } else if let last = lastFrameAt, now - last > Timing.overlayFrameGap {
            // A hitch: the main thread was busy, or SpriteKit waited for a drawable (bug 0001).
            log(String(format: "overlay frame gap %.0f ms", (now - last) * 1000))
        }
        lastFrameAt = now
        if let a = watchdog.frame(at: now) { apply(a, because: "frames resumed") }
    }

    private func checkFrames() {
        let now = AppDelegate.now()
        // Hidden behind a full-screen app's Space, frames may stop on purpose: not a stall.
        if watchdog.visible, !window.occlusionState.contains(.visible) {
            _ = watchdog.frame(at: now)
            return
        }
        guard let a = watchdog.check(at: now) else { return }
        apply(a, because: a == .hide ? "no frame for \(Int(Timing.overlayStall)) s (stall \(watchdog.stalls))" : "retrying")
    }

    private func apply(_ action: OverlayWatchdog.Action, because why: String) {
        switch action {
        case .hide:
            log("overlay off screen: \(why)")
            window.orderOut(nil)
        case .show:
            log("overlay back on screen: \(why)")
            window.orderFrontRegardless()
            view.isPaused = false
        }
    }

    /// The display's size, the menu bar or the Dock changed: follow it.
    private func screensChanged() {
        guard let screen = NSScreen.screens.first else { return }
        let stage = Self.stage(for: screen)
        guard screen.frame != screenFrame || stage != sim.stage else { return }
        log("display changed: \(Int(screen.frame.width))×\(Int(screen.frame.height)), menu bar \(Int(stage.top)) pt, usable to \(Int(stage.bottom)) pt")
        screenFrame = screen.frame
        sim.stage = stage
        window.setFrame(screen.frame, display: false)
        view.frame = CGRect(origin: .zero, size: screen.frame.size)
        scene.size = screen.frame.size
    }

    /// Off screen while the display sleeps; back, with a fresh clock, when it wakes.
    private func displaySleep(_ asleep: Bool) {
        guard asleep != displayAsleep else { return }
        displayAsleep = asleep
        log(asleep ? "display asleep" : "display awake")
        guard awake else { return }
        if asleep {
            stopWatching()
            view.isPaused = true
            window.orderOut(nil)
        } else {
            present()
        }
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
        log("overlay sleep")
        stopWatching()
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
        c.frameDrawn()
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
            let a = CGFloat(m.alpha)
            if let crowd = m.crowd {
                n.sprite.isHidden = true
                drawCrowd(m, crowd, n, H: H, highlight: hl)
            } else {
                let tex = textures.sprite(m.look, m.drawPose, frame: m.frame, highlight: hl)
                if n.sprite.texture !== tex { n.sprite.texture = tex }
            }
            n.sprite.alpha = a; n.emote.alpha = a; n.side.alpha = a; n.badge.alpha = a
            for c in n.crowd { c.alpha = a }
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
                let cx = m.x + (m.crowd == nil ? m.face * 2 * sc : 0), bottom = m.y - lift - 25 * sc
                n.emote.isHidden = false
                n.emote.texture = textures.emote(e)
                n.emote.setScale(CGFloat(s))
                n.emote.position = CGPoint(x: (cx - 4.5 * s).rounded(), y: H - (bottom - 10 * s).rounded())
            } else {
                n.emote.isHidden = true
            }

            if let b = m.bubble {
                // Look the art up only when the bubble changes, not every frame.
                var key = b
                key.until = 0
                let art: BubbleArt.Art
                if let shown = n.bubbleArt, n.bubbleKey == key {
                    art = shown
                } else {
                    art = textures.bubble(key)
                    n.bubbleKey = key
                    n.bubbleArt = art
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

    /// The crowd (its part of `drawEnt`): its first three members at one size smaller, overlapping,
    /// alternately facing each way, walking or standing together.
    @MainActor
    private func drawCrowd(_ m: CrewMember, _ crowd: Crowd, _ n: MemberNodes, H: CGFloat, highlight: Bool) {
        let cs = max(1, m.scale - 1), lift = m.z + m.hop
        for (i, node) in n.crowd.enumerated() {
            guard i < crowd.looks.count else { node.isHidden = true; continue }
            node.isHidden = false
            let tex = textures.sprite(crowd.looks[i], crowd.pose, frame: crowd.frames[i], highlight: highlight)
            if node.texture !== tex { node.texture = tex }
            let off = Crowd.offsets[i]
            node.xScale = CGFloat((i % 2 == 1 ? -m.face : m.face) * cs)
            node.yScale = CGFloat(cs)
            node.position = CGPoint(x: (m.x + off.x * cs).rounded(), y: H - (m.y - lift + off.y * cs).rounded())
            // Drawn in order, like the prototype: the third (centre, highest) member last.
            node.zPosition = 2 + CGFloat(m.y) / 100_000 + CGFloat(i) / 10_000_000
        }
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
            let tex = textures.tinted(.plus, RGB(0xFFEC27))
            if star.texture !== tex { star.texture = tex }
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

    /// Particles use textures tinted ahead of time (`TextureCache.tinted`), never `color`: setting a
    /// node's colour makes AppKit colour-match it, and doing that for every particle each frame was
    /// the app's biggest cost in an event storm (docs/quality/performance-budget.md).
    @MainActor
    private func drawParticles(_ ps: [Particle], scale S: Double, H: CGFloat) {
        while particleNodes.count < ps.count {
            let p = SKSpriteNode(texture: nil, size: CGSize(width: 1, height: 1))
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
            let shape: TextureCache.Shape
            switch p.kind {
            case .spark:
                // A plus: three cells of s×s, drawn as one 3×3 texture scaled by s.
                let s = max(1, (S * (1 - t * 0.5)).rounded())
                shape = .plus
                node.alpha = CGFloat(1 - t)
                node.size = CGSize(width: s * 3, height: s * 3)
                node.position = CGPoint(x: x - s, y: H - (y - s))
            case .dust:
                let s = (S * (1 + t * 2)).rounded()
                shape = .solid
                node.alpha = CGFloat((1 - t) * 0.7)
                node.size = CGSize(width: s, height: s)
                node.position = CGPoint(x: (x - s / 2).rounded(.down), y: H - (y - s).rounded(.down))
            case .confetti:
                // A flake that flips between 1 and 2 cells wide as it flutters; fades in its last quarter.
                let w = abs(sin(p.life * 10 + p.phase)) > 0.5 ? 2.0 : 1.0
                shape = .solid
                node.alpha = CGFloat(t > 0.75 ? (1 - t) * 4 : 1)
                node.size = CGSize(width: max(1, (w * S * 0.67).rounded(.down)), height: S)
                node.position = CGPoint(x: x, y: H - y)
            case .zzz:
                let s = max(1, S - 1)
                shape = .zee
                node.alpha = CGFloat(1 - t)
                node.size = CGSize(width: s * 3, height: s * 3)
                node.position = CGPoint(x: x, y: H - y)
            case .bit:
                shape = .solid
                node.alpha = CGFloat(1 - t)
                node.size = CGSize(width: S * 2, height: S)
                node.position = CGPoint(x: x, y: H - y)
            }
            let tex = textures.tinted(shape, p.color)
            if node.texture !== tex { node.texture = tex }
        }
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
        /// What `bubble` shows (its `until` zeroed), so unchanged bubbles skip the texture cache.
        var bubbleKey: Bubble?
        var bubbleArt: BubbleArt.Art?
        /// The crowd's three members (hidden for everyone else).
        let crowd = (0..<Crowd.offsets.count).map { _ in MemberNodes.spriteNode() }
        private var all: [SKSpriteNode] { [shadow1, shadow2, sideShadow1, sideShadow2, side, sprite, badge, emote, bubble] + stars + crowd }

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
            for c in crowd { c.isHidden = true }
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

    /// Particle shapes: a filled cell, a plus (sparks, dizzy stars) and a z
    /// (prototype `drawPattern(['##.', '.#.', '.##'])` for sleepers).
    enum Shape: Hashable { case solid, plus, zee }
    private struct TintKey: Hashable { let shape: Shape; let color: RGB }
    private var tintedTextures: [TintKey: SKTexture] = [:]

    /// A shape already in its colour. The particle palette is small and fixed, so this stays tiny;
    /// the cap is a backstop.
    func tinted(_ shape: Shape, _ color: RGB) -> SKTexture {
        let key = TintKey(shape: shape, color: color)
        if let t = tintedTextures[key] { return t }
        if tintedTextures.count >= 256 { tintedTextures.removeAll() }
        var c: PixelCanvas
        switch shape {
        case .solid:
            c = PixelCanvas(width: 1, height: 1); c.fill(0, 0, 1, 1, color)
        case .plus:
            c = PixelCanvas(width: 3, height: 3); c.fill(0, 1, 3, 1, color); c.fill(1, 0, 1, 3, color)
        case .zee:
            c = PixelCanvas(width: 3, height: 3)
            c.fill(0, 0, 2, 1, color); c.fill(1, 1, 1, 1, color); c.fill(1, 2, 2, 1, color)
        }
        let t = Self.texture(c)
        tintedTextures[key] = t
        return t
    }

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
        let ink: NSColor = switch b.kind { case .say, .count: Theme.pixDark; case .done: doneInk; case .wait: waitInk }
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
            // `.bub.count`: the crowd's bubble is orange, tail and all.
            let paper = b.kind == .count ? Theme.accent : Theme.pixPaper
            Theme.pixDark.setFill()
            boxRect.insetBy(dx: -2, dy: -2).fill()
            paper.setFill()
            boxRect.fill()
            // Tail: 8×4 paper with 2 pt ink sides, then a 4×2 ink tip.
            let cx = boxRect.midX
            Theme.pixDark.setFill()
            CGRect(x: cx - 4, y: boxRect.maxY + 2, width: 8, height: 4).fill()
            paper.setFill()
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
