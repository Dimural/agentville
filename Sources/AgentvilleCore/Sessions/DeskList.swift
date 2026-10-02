import Foundation

/// What the desk window's list, summary line and menu bar header say. Port of the prototype's
/// `fmtDur`, `statusLabel` and `renderList` (docs/product/user-experience.md#desk-window-the-office).
/// Pure, so the app only lays it out.
public enum DeskList {
    /// Port of `fmtDur`: "45s", "4m 05s" (minutes keep counting past an hour, as in the prototype).
    public static func duration(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.isFinite ? t : 0))
        let m = s / 60
        return m > 0 ? "\(m)m \(String(format: "%02d", s % 60))s" : "\(s)s"
    }

    /// One list row.
    public struct Row: Equatable, Sendable {
        /// Chip colour classes, as the prototype's `.chip.working/.waiting/.done/.idle` plus Error.
        public enum Chip: Equatable, Sendable { case working, needsYou, finished, idle, error }

        public let id: String
        public let name: String
        /// Twin number badge (2, 3…) for later sessions in the same folder (open question 14).
        public let twin: Int?
        /// Small mono text after the name: the current tool and subagents, while working.
        public let detail: String
        public let chip: Chip
        public let label: String
        /// Current turn's elapsed time, or the last turn's duration when finished.
        public let elapsed: String
        /// Replaces the prototype's "Answer" button (open question 11).
        public let tooltip: String?

        public init(_ s: Session, now: TimeInterval) {
            id = s.id
            name = s.project
            twin = s.twinIndex > 1 ? s.twinIndex : nil
            label = s.status.label
            switch s.status {
            case .working: chip = .working
            case .needsYou: chip = .needsYou
            case .finished: chip = .finished
            case .idle: chip = .idle
            case .error: chip = .error
            }
            if s.isWorking {
                let subs = s.subagents.count
                let sub = subs == 0 ? "" : subs == 1 ? "+ subagent" : "+ \(subs) subagents"
                detail = [s.tool ?? "", sub].filter { !$0.isEmpty }.joined(separator: " ")
            } else {
                detail = ""
            }
            switch s.status {
            case .working, .needsYou: elapsed = s.turnStartedAt.map { DeskList.duration(now - $0) } ?? ""
            case .finished: elapsed = s.lastTurnDuration.map(DeskList.duration) ?? ""
            case .idle, .error: elapsed = ""
            }
            tooltip = s.status == .needsYou ? "Answer it in your terminal" : nil
        }
    }

    /// A piece of the summary line; `count` is drawn bold, the tone colours the whole piece.
    public struct Segment: Equatable, Sendable {
        public enum Tone: Equatable, Sendable { case plain, warn, ok }
        public let count: String?
        public let text: String
        public let tone: Tone
    }

    /// "7 active · 2 need you · 1 just finished", or the empty-state sentence. Join with " · ".
    public static func summary(_ s: SessionStore.Summary) -> [Segment] {
        guard s.active > 0 else {
            return [Segment(count: nil, text: "No sessions yet. Start Claude Code in any terminal.", tone: .plain)]
        }
        var out = [Segment(count: "\(s.active)", text: "\(s.active) active", tone: .plain)]
        if s.needYou > 0 {
            out.append(Segment(count: "\(s.needYou)", text: "\(s.needYou) need\(s.needYou == 1 ? "s" : "") you", tone: .warn))
        }
        if s.justFinished > 0 {
            out.append(Segment(count: "\(s.justFinished)", text: "\(s.justFinished) just finished", tone: .ok))
        }
        return out
    }

    /// The status item menu's header ("N sessions").
    public static func menuHeader(_ s: SessionStore.Summary) -> String {
        "\(s.active) session\(s.active == 1 ? "" : "s")"
    }
}
