import Foundation

/// What a session is doing right now. Spec: docs/product/sessions-and-states.md#states.
public enum SessionStatus: Equatable, Sendable {
    case idle
    case working(Activity)
    case needsYou
    case finished
    case error

    /// Status chip label for the desk panel list.
    public var label: String {
        switch self {
        case .idle: "Idle"
        case .working(let a): a.label
        case .needsYou: "Needs you"
        case .finished: "Finished"
        case .error: "Error"
        }
    }
}

/// One Claude Code session as the app knows it. Only allowlisted data lives here.
public struct Session: Equatable, Sendable {
    public let id: String
    public let project: String
    public let look: Look
    /// 1 for the first session in a folder; 2, 3… for later twins (badge in the UI).
    public let twinIndex: Int
    public let createdAt: TimeInterval

    public internal(set) var status: SessionStatus = .idle
    /// Last tool name seen (for the list's small mono text). Nil while idle or thinking.
    public internal(set) var tool: String?
    /// Active subagent ids, in start order (capped at `Limits.subagentsPerSession`).
    public internal(set) var subagents: [String] = []
    public internal(set) var turnStartedAt: TimeInterval?
    public internal(set) var lastTurnDuration: TimeInterval?
    public internal(set) var finishedAt: TimeInterval?
    public internal(set) var lastEventAt: TimeInterval
    public internal(set) var lastEvent: WireEvent.Kind

    public var isWorking: Bool { if case .working = status { true } else { false } }
    public var activity: Activity? { if case .working(let a) = status { a } else { nil } }
}

/// Things the UI should react to, returned by `SessionStore.apply` / `tick`.
public enum StoreEffect: Equatable, Sendable {
    public enum RemovalReason: Equatable, Sendable { case ended, stale, evicted }

    case added(id: String)
    case removed(id: String, reason: RemovalReason)
    case finished(id: String, duration: TimeInterval?, announce: Bool)
    case needsYou(id: String)
    case resolved(id: String)
    case failed(id: String)
    case subagentStarted(id: String, agent: String)
    case subagentStopped(id: String, agent: String)
}
