/// What a working session is doing. Spec: docs/product/sessions-and-states.md#tool--activity-mapping.
public enum Activity: String, CaseIterable, Sendable {
    case thinking, editing, reading, running, searching, web, planning, tinkering, working

    /// Status chip label in the desk window list.
    public var label: String {
        switch self {
        case .thinking: "Thinking"
        case .editing: "Editing"
        case .reading: "Reading"
        case .running: "Running"
        case .searching: "Searching"
        case .web: "On the web"
        case .planning: "Planning"
        case .tinkering: "Tinkering"
        case .working: "Working"
        }
    }
}

/// The single source of truth for tool → activity. Keep in sync with the doc table (a test enforces it).
public enum ActivityMapping {
    public static let table: [String: Activity] = {
        var t: [String: Activity] = [:]
        for n in ["Read", "NotebookRead"] { t[n] = .reading }
        for n in ["Edit", "Write", "MultiEdit", "NotebookEdit"] { t[n] = .editing }
        for n in ["Bash", "BashOutput", "KillShell", "KillBash", "PowerShell"] { t[n] = .running }
        for n in ["Grep", "Glob", "LS"] { t[n] = .searching }
        for n in ["WebSearch", "WebFetch"] { t[n] = .web }
        for n in ["TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "ExitPlanMode", "EnterPlanMode"] { t[n] = .planning }
        t["mcp"] = .tinkering
        return t
    }()

    /// Tools covered by the subagent sidekick: the main character keeps its previous activity.
    public static let subagentTools: Set<String> = ["Task", "Agent"]

    /// Returns nil when the tool shouldn't change the current activity (subagent launchers).
    public static func activity(forTool tool: String?) -> Activity? {
        guard let tool else { return .thinking }
        if subagentTools.contains(tool) { return nil }
        return table[tool] ?? .working
    }
}
