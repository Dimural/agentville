import Foundation

/// The crowd: sessions beyond the first `Limits.roamers` gather into one wandering group of three
/// half-size characters with a "+N" count. Ports of the prototype's `spawnCrowd`, `roamCrowd`,
/// `crowdMembers` and the crowd part of `drawEnt` (docs/product/user-experience.md#limits-the-user-can-notice).
extension CrewSim {
    /// Port of `spawnCrowd`: it leaps out of its home (the session list's, or the menu bar icon).
    func spawnCrowd() {
        guard released, roster.count > Limits.roamers else { return }
        if var c = members[Self.crowdID] {
            // Still out from before (flying home or waiting): turn around.
            if c.mode == .wait || { if case .fly(let f) = c.mode { f.homeward } else { false } }() {
                c.bubble = nil; c.emote = nil
                launch(&c, to: randomSpot(), duration: Motion.crowdFlight, homeward: false, scaleTo: stage.scale)
                members[Self.crowdID] = c
            }
            return
        }
        let h = home(Self.crowdID)
        var c = newMember(Self.crowdID, look: roster[Limits.roamers].look, x: h.x, y: h.y, scale: h.scale)
        launch(&c, to: randomSpot(), duration: Motion.crowdFlight, homeward: false, scaleTo: stage.scale)
        members[Self.crowdID] = c
    }

    /// The sessions the crowd stands for, as they are now.
    private func crowdSessions(_ sessions: [String: Session]) -> [Session] {
        roster.dropFirst(Limits.roamers).compactMap { sessions[$0.id] }
    }

    /// Port of `roamCrowd`: a slow wander, the count bubble (unless it's saying something else),
    /// `!` while any member needs the user. Nil once nobody is left in it: it poofs.
    func roamCrowd(_ m: inout CrewMember, dt: Double, sessions: [String: Session]) -> Pose? {
        if m.phase == .walk {
            if walk(&m, dt: dt, speed: Motion.crowdWander) { m.phase = .act; m.timer = rand(Motion.crowdAct) }
        } else {
            m.timer -= dt
            if m.timer <= 0 {
                let r = Motion.crowdWanderRadius
                m.tx = clamp(m.x + rand(-r...r), 36, stage.width - 36)
                m.ty = clamp(m.y + rand(-r * 0.6...r * 0.6), stage.minY + 6, stage.bottom - 16)
                m.phase = .walk
            }
        }
        let mem = crowdSessions(sessions)
        guard !mem.isEmpty else {
            sparkle(x: m.x, y: m.y - 20, count: 10)
            return nil
        }
        let waiting = mem.filter { $0.status == .needsYou }.count
        if m.bubble == nil || m.bubble?.kind == .count {
            m.bubble = Bubble(text: Phrases.crowdCount(mem.count), kind: .count,
                              sub: waiting > 0 ? Phrases.needYou(waiting) : nil, until: time + 0.4)
        }
        if waiting > 0 { m.emote = .icon(.bang) }
        return m.phase == .walk ? .walk : .idle
    }

    /// What the overlay draws for the crowd: its first three members, walking or standing, each a
    /// little out of step with the others (the crowd part of `drawEnt`).
    func updateCrowd(_ m: inout CrewMember, sessions: [String: Session]) {
        let mem = crowdSessions(sessions)
        let walking = m.mode == .rest && m.phase == .walk
        let pose: Pose = walking ? .walk : .idle
        let shown = mem.prefix(Crowd.offsets.count)
        let frames = shown.indices.map { i in
            Int(floor((m.anim + Double(i - shown.startIndex) * 0.37) * (walking ? 8 : 1.2))) % pose.frameCount
        }
        m.crowd = Crowd(looks: shown.map(\.look), frames: frames, pose: pose, count: mem.count,
                        waiting: mem.filter { $0.status == .needsYou }.count)
    }
}
