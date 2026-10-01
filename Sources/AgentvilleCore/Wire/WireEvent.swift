import Foundation

/// The only data that ever leaves `agentville-hook`. Schema v1.
/// Spec: docs/architecture/data-contract.md. Changing this changes the privacy boundary.
public struct WireEvent: Codable, Equatable, Sendable {
    public static let version = 1

    /// Registered hook events. Must match `Plugin/agentville/hooks/hooks.json` exactly.
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case stopFailure = "StopFailure"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"

        /// Events whose payload carries a `tool_name` we forward.
        public var carriesTool: Bool {
            switch self {
            case .preToolUse, .postToolUse, .postToolUseFailure, .permissionRequest: true
            default: false
            }
        }
    }

    public var v: Int
    public var event: Kind
    public var session: String
    public var project: String
    public var tool: String?
    public var notification: String?
    public var agentId: String?
    public var agentType: String?
    public var source: String?
    public var reason: String?
    public var error: String?
    /// Unix time in milliseconds, from the hook's clock.
    public var ts: Int64

    enum CodingKeys: String, CodingKey {
        case v, event, session, project, tool, notification
        case agentId = "agent_id"
        case agentType = "agent_type"
        case source, reason, error, ts
    }

    public init(
        event: Kind, session: String, project: String, tool: String? = nil,
        notification: String? = nil, agentId: String? = nil, agentType: String? = nil,
        source: String? = nil, reason: String? = nil, error: String? = nil, ts: Int64
    ) {
        self.v = Self.version
        self.event = event
        self.session = session
        self.project = project
        self.tool = tool
        self.notification = notification
        self.agentId = agentId
        self.agentType = agentType
        self.source = source
        self.reason = reason
        self.error = error
        self.ts = ts
    }

    /// Re-applies every sanitization rule. Returns nil if the event is unusable.
    /// The hook uses this on construction and the app uses it again on receipt, because
    /// the app never trusts that the sender was our hook.
    public func sanitized() -> WireEvent? {
        guard v == Self.version else { return nil }
        guard let session = Sanitize.identifier(session) else { return nil }
        let k = event
        return WireEvent(
            event: k,
            session: session,
            project: Sanitize.projectName(fromFolderName: project),
            tool: k.carriesTool ? tool.map(Sanitize.toolName) : nil,
            notification: k == .notification ? Sanitize.enumValue(notification, allowed: Allow.notification, fallback: "other") : nil,
            agentId: agentId.flatMap(Sanitize.identifier),
            agentType: agentType.flatMap(Sanitize.agentType),
            source: k == .sessionStart ? Sanitize.enumValue(source, allowed: Allow.source, fallback: "other") : nil,
            reason: k == .sessionEnd ? Sanitize.enumValue(reason, allowed: Allow.reason, fallback: "other") : nil,
            error: k == .stopFailure ? Sanitize.enumValue(error, allowed: Allow.error, fallback: "unknown") : nil,
            ts: max(0, ts)
        )
    }

    /// Enum allowlists (docs/architecture/data-contract.md#enum-allowlists).
    public enum Allow {
        public static let notification: Set<String> = [
            "permission_prompt", "idle_prompt", "auth_success", "elicitation_dialog",
            "elicitation_url_dialog", "elicitation_complete", "elicitation_response",
            "agent_needs_input", "agent_completed",
        ]
        public static let source: Set<String> = ["startup", "resume", "clear", "compact", "fork"]
        public static let reason: Set<String> = ["clear", "resume", "logout", "prompt_input_exit", "other"]
        public static let error: Set<String> = [
            "rate_limit", "overloaded", "authentication_failed", "oauth_org_not_allowed",
            "account_on_hold", "billing_error", "invalid_request", "model_not_found",
            "server_error", "max_output_tokens", "cloud_credential_error", "unknown",
        ]
    }
}
