import Foundation

/// Walk-on notices: while the crew is inside, a finished turn or a session that needs the user
/// sends its character walking in from the right edge of the screen. Ports of the prototype's
/// `onDone`, `onWaiting`, `queueNotice`, `activeNotifiers`, `slotsMax`, `processNotices` and the
/// `notify-in`/`notify-hold`/`notify-out` modes of `updateEnt`
/// (docs/design/motion-and-behaviour.md#notices-walk-ons-while-the-crew-is-inside).
extension CrewSim {
    /// The store's effects, after `sessionsChanged` for the same batch.
    public func notify(_ effects: [StoreEffect]) {
        for fx in effects {
            switch fx {
            case .finished(let id, _, let announce): onDone(id, announce: announce)
            case .needsYou(let id): onWaiting(id)
            default: break
            }
        }
    }

    private func isRoamer(_ id: String) -> Bool { (rosterIndex[id] ?? Int.max) < Limits.roamers }

    /// Port of `onDone`. A roamer cheers where it stands (`roam` sees the status change); a crowd
    /// member's turn is announced by the crowd; otherwise a Done! walk-on, if the rule says so.
    private func onDone(_ id: String, announce: Bool) {
        if members[id]?.mode == .rest { return }
        if released, !isRoamer(id), rosterIndex[id] != nil, var c = members[Self.crowdID] {
            c.bubble = Bubble(text: Phrases.finished(name(id) ?? ""), until: time + Motion.crowdFinishedBubble)
            members[Self.crowdID] = c
            confetti(x: c.x, y: c.y - 30, count: Motion.crowdConfetti)
            return
        }
        if announce { queueNotice(id, .done) }
    }

    /// Port of `onWaiting`. Roamers run to the bottom of the screen by themselves; the crowd counts
    /// its own.
    private func onWaiting(_ id: String) {
        if let m = members[id], m.mode == .rest || m.mode.isWalkOn { return }
        if released, !isRoamer(id) { return }
        queueNotice(id, .needsYou)
    }

    /// Port of `queueNotice`: once per session and kind; the oldest is pushed out past the cap.
    private func queueNotice(_ id: String, _ kind: WalkOn.Kind) {
        let n = Notice(id: id, kind: kind)
        guard !noticeQueue.contains(n) else { return }
        noticeQueue.append(n)
        if noticeQueue.count > Limits.noticeQueue {
            noticeQueue.removeFirst()
            overflowDone += 1
        }
    }

    /// Port of `slotsMax`: 3 walk-ons side by side, fewer on narrow screens.
    var walkOnSlots: Int {
        stage.width < Motion.walkOnOneSlotBelow ? 1 : stage.width < Motion.walkOnTwoSlotsBelow ? 2 : Limits.walkOns
    }

    /// Port of `processNotices`: fill free slots from the queue. A needs-you that was answered while
    /// it waited, a session that's gone, or one whose character is already out is skipped. A Done!
    /// with 2 or more others pending takes them all along as "+N more".
    func processNotices(_ sessions: [String: Session]) {
        guard !noticeQueue.isEmpty else { return }
        var used = Set(members.values.filter { $0.mode.isWalkOn }.compactMap { $0.walkOn?.slot })
        var active = members.values.filter { $0.mode.isWalkOn }.count
        while !noticeQueue.isEmpty, active < walkOnSlots {
            let n = noticeQueue.removeFirst()
            guard let s = sessions[n.id], members[n.id] == nil else { continue }
            if n.kind == .needsYou, s.status != .needsYou { continue }
            var slot = 0
            while used.contains(slot) { slot += 1 }
            var more = 0
            if n.kind == .done {
                let pending = noticeQueue.filter { $0.kind == .done }.count + overflowDone
                if pending >= 2 {
                    more = pending
                    noticeQueue.removeAll { $0.kind == .done }
                    overflowDone = 0
                }
            }
            let k = Double(slot)
            var m = newMember(n.id, look: s.look, x: stage.width + 30, y: stage.bottom - Motion.walkOnBottom - k * Motion.walkOnStep,
                              scale: stage.scale)
            m.face = -1
            m.mode = .walkIn
            m.walkOn = WalkOn(slot: slot, kind: n.kind, more: more)
            m.tx = stage.width - Motion.walkOnRight - k * Motion.walkOnSpacing
            m.ty = m.y
            members[n.id] = m
            used.insert(slot)
            active += 1
        }
    }

    /// Heads back off the right edge (prototype: `mode = 'notify-out'; tx = W + 40`).
    func walkOff(_ m: inout CrewMember) {
        m.mode = .walkOff
        m.tx = stage.width + 40
        m.ty = m.y
        m.bubble = nil
        m.hop = 0
    }

    /// The `notify-*` branches of `updateEnt`. Returns the pose, or nil once it has walked off.
    func stepWalkOn(_ m: inout CrewMember, dt: Double, session: Session?) -> Pose? {
        switch m.mode {
        case .walkIn:
            guard walk(&m, dt: dt, speed: Motion.walkOnIn) else { return .walk }
            m.mode = .hold
            m.face = -1
            guard let w = m.walkOn, w.kind == .done else {
                m.timer = Motion.walkOnNeedsYouHold
                return .walk
            }
            m.timer = Motion.walkOnDoneHold
            m.cheerT = Motion.walkOnCheer
            confetti(x: m.x, y: m.y - 30, count: Motion.walkOnConfetti)
            var sub = session.map { s in s.lastTurnDuration.map { "\(Self.name(s)) · \(DeskList.duration($0))" } ?? Self.name(s) } ?? ""
            if w.more > 0 { sub += " · +\(w.more) more" }
            m.bubble = Bubble(text: Phrases.done, kind: .done, sub: sub, until: time + Motion.walkOnDoneHold)
            return .walk
        case .hold:
            m.timer -= dt
            var pose = Pose.idle
            if m.walkOn?.kind == .needsYou {
                pose = .wave
                m.emote = .icon(.bang)
                m.hop = abs(sin(m.t * 7)) * 8
                if let s = session, s.status == .needsYou {
                    m.bubble = Bubble(text: Phrases.needsYou, kind: .wait, sub: Phrases.waiting(Self.name(s)), until: time + 0.3)
                } else {
                    m.timer = 0
                }
            } else if m.cheerT > 0 {
                m.cheerT -= dt
                pose = .cheer
                m.hop = abs(sin(m.t * 9)) * 10
                m.emote = .icon(.check)
            } else {
                m.hop = 0
            }
            if m.timer <= 0 {
                walkOff(&m)
                // The crew came out meanwhile and this one's a roamer: it stays out.
                if released, let s = session, isRoamer(s.id) {
                    m.mode = .rest; m.phase = .act; m.timer = 0.5; m.walkOn = nil
                }
            }
            return pose
        case .walkOff:
            m.ty = m.y
            return walk(&m, dt: dt, speed: Motion.walkOnOut) ? nil : .walk
        default:
            return .idle
        }
    }
}
