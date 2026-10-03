import Foundation

/// In-memory session state machine. Pure: time is injected, nothing touches the system clock,
/// disk or UI. Spec: docs/product/sessions-and-states.md. Every transition has a test.
public final class SessionStore {
    public struct Summary: Equatable, Sendable {
        public var active = 0, needYou = 0, justFinished = 0
    }

    /// Which finished turns get a "Done!" walk-on (open question 1); the app sets it from preferences.
    public var announceDone = DoneAnnouncement.longTurns

    public private(set) var sessions: [String: Session] = [:]
    /// Insertion order: desk assignment and list order.
    public private(set) var order: [String] = []
    /// Bumped on every change; the UI redraws at 4 Hz only when this moved.
    public private(set) var revision = 0

    /// Twin badge indices in use per project folder (O(1) twin assignment).
    private var twinsByProject: [String: Set<Int>] = [:]

    /// Recently ended ids, so late events can't resurrect them (except SessionStart).
    private var tombstones: [String] = []
    private var tombstoneSet: Set<String> = []
    private static let tombstoneCap = 256

    public init() {}

    public var ordered: [Session] { order.compactMap { sessions[$0] } }

    public var summary: Summary {
        var s = Summary()
        for x in sessions.values {
            s.active += 1
            if x.status == .needsYou { s.needYou += 1 }
            if x.status == .finished { s.justFinished += 1 }
        }
        return s
    }

    // MARK: - Events

    @discardableResult
    public func apply(_ e: WireEvent, now: TimeInterval) -> [StoreEffect] {
        var fx: [StoreEffect] = []
        let id = e.session

        if e.event == .sessionEnd {
            if sessions[id] != nil { remove(id, reason: .ended, into: &fx) }
            bury(id)
            return fx
        }
        if tombstoneSet.contains(id) {
            guard e.event == .sessionStart else { return fx }
            unbury(id)
        }

        var s: Session
        if let existing = sessions[id] {
            s = existing
        } else {
            s = makeSession(id: id, project: e.project, now: now, kind: e.event)
            evictIfFull(into: &fx)
            sessions[id] = s
            order.append(id)
            fx.append(.added(id: id))
        }
        let wasNeedsYou = s.status == .needsYou

        switch e.event {
        case .sessionStart:
            // Compaction can happen mid-turn: don't interrupt work. Other sources start fresh.
            if e.source != "compact" { s.status = .idle; s.tool = nil; s.turnStartedAt = nil }

        case .userPromptSubmit:
            s.status = .working(.thinking); s.tool = nil
            s.turnStartedAt = now; s.finishedAt = nil

        case .preToolUse:
            beginTurnIfNeeded(&s, now: now)
            if let a = ActivityMapping.activity(forTool: e.tool) {
                s.status = .working(a); s.tool = e.tool
            } else if !s.isWorking {
                s.status = .working(.thinking) // a subagent launcher; the mini-me shows it
            }

        case .postToolUse, .postToolUseFailure:
            beginTurnIfNeeded(&s, now: now)
            s.status = .working(.thinking); s.tool = nil

        case .permissionRequest:
            beginTurnIfNeeded(&s, now: now)
            s.status = .needsYou; s.tool = e.tool

        case .notification:
            switch e.notification {
            case "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
                s.status = .needsYou
            case "idle_prompt":
                if s.status != .needsYou { s.status = .idle; s.tool = nil }
            default:
                break // auth_success, elicitation_complete…: no visible change
            }

        case .stop:
            let duration = s.turnStartedAt.map { max(0, now - $0) }
            s.status = .finished; s.tool = nil; s.subagents.removeAll()
            s.lastTurnDuration = duration; s.finishedAt = now; s.turnStartedAt = nil
            fx.append(.finished(id: id, duration: duration, announce: announceDone.announces(duration)))

        case .stopFailure:
            s.status = .error; s.tool = nil; s.subagents.removeAll(); s.turnStartedAt = nil
            fx.append(.failed(id: id))

        case .subagentStart:
            let agent = e.agentId ?? "anonymous"
            if !s.subagents.contains(agent), s.subagents.count < Limits.subagentsPerSession {
                s.subagents.append(agent)
                fx.append(.subagentStarted(id: id, agent: agent))
            }

        case .subagentStop:
            let agent = e.agentId ?? "anonymous"
            if let i = s.subagents.firstIndex(of: agent) {
                s.subagents.remove(at: i)
                fx.append(.subagentStopped(id: id, agent: agent))
            }

        case .sessionEnd:
            break // handled above
        }

        if wasNeedsYou && s.status != .needsYou { fx.append(.resolved(id: id)) }
        if !wasNeedsYou && s.status == .needsYou { fx.append(.needsYou(id: id)) }

        s.lastEventAt = now
        s.lastEvent = e.event
        sessions[id] = s
        revision &+= 1
        return fx
    }

    // MARK: - Time

    /// Call about every 1–10 s: finished → idle after the hold, and removes stale sessions.
    @discardableResult
    public func tick(now: TimeInterval) -> [StoreEffect] {
        var fx: [StoreEffect] = []
        var changed = false
        for id in order {
            guard var s = sessions[id] else { continue }
            if s.status == .finished, let f = s.finishedAt, now - f >= Timing.finishedHold {
                s.status = .idle
                sessions[id] = s
                changed = true
            }
            if now - s.lastEventAt >= staleLimit(for: s) {
                remove(id, reason: .stale, into: &fx)
                bury(id)
            }
        }
        if changed { revision &+= 1 }
        return fx
    }

    /// Silence allowed before a session is considered gone (docs/product/sessions-and-states.md#staleness).
    public func staleLimit(for s: Session) -> TimeInterval {
        if s.status == .needsYou { return Timing.Stale.needsYou }
        if s.lastEvent == .preToolUse { return Timing.Stale.toolRunning }
        switch s.status {
        case .working: return Timing.Stale.working
        default: return Timing.Stale.idle
        }
    }

    // MARK: - Helpers

    private func makeSession(id: String, project: String, now: TimeInterval, kind: WireEvent.Kind) -> Session {
        let used = twinsByProject[project, default: []]
        var twin = 1
        while used.contains(twin) { twin += 1 }
        twinsByProject[project, default: []].insert(twin)
        return Session(id: id, project: project, look: LookGenerator.look(for: project), twinIndex: twin,
                       createdAt: now, lastEventAt: now, lastEvent: kind)
    }

    private func beginTurnIfNeeded(_ s: inout Session, now: TimeInterval) {
        // Hooks may be installed mid-turn: the first sign of work starts the clock.
        if s.turnStartedAt == nil { s.turnStartedAt = now; s.finishedAt = nil }
    }

    private func evictIfFull(into fx: inout [StoreEffect]) {
        guard sessions.count >= Limits.trackedSessions else { return }
        // Prefer the longest-quiet idle session; otherwise the longest-quiet session of any kind.
        var idleVictim: (id: String, at: TimeInterval)?
        var anyVictim: (id: String, at: TimeInterval)?
        for (id, s) in sessions {
            if anyVictim == nil || s.lastEventAt < anyVictim!.at { anyVictim = (id, s.lastEventAt) }
            if s.status == .idle, idleVictim == nil || s.lastEventAt < idleVictim!.at { idleVictim = (id, s.lastEventAt) }
        }
        if let v = idleVictim ?? anyVictim { remove(v.id, reason: .evicted, into: &fx); bury(v.id) }
    }

    private func remove(_ id: String, reason: StoreEffect.RemovalReason, into fx: inout [StoreEffect]) {
        guard let gone = sessions.removeValue(forKey: id) else { return }
        twinsByProject[gone.project]?.remove(gone.twinIndex)
        if twinsByProject[gone.project]?.isEmpty == true { twinsByProject[gone.project] = nil }
        if let i = order.firstIndex(of: id) { order.remove(at: i) }
        fx.append(.removed(id: id, reason: reason))
        revision &+= 1
    }

    private func bury(_ id: String) {
        guard tombstoneSet.insert(id).inserted else { return }
        tombstones.append(id)
        if tombstones.count > Self.tombstoneCap { tombstoneSet.remove(tombstones.removeFirst()) }
    }

    private func unbury(_ id: String) {
        tombstoneSet.remove(id)
        if let i = tombstones.firstIndex(of: id) { tombstones.remove(at: i) }
    }
}
