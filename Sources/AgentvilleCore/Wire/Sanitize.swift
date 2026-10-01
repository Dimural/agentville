import Foundation

/// Field-level sanitization rules from docs/architecture/data-contract.md.
/// Every rule is total: it returns a safe value or nil, and never throws.
public enum Sanitize {
    public static let maxIdentifier = 64
    public static let maxProject = 64
    public static let maxTool = 40
    public static let maxAgentType = 40

    /// session_id / agent_id: keep `[A-Za-z0-9_-]`, ≤ 64 chars. Empty → nil.
    public static func identifier(_ raw: String) -> String? {
        var out = ""
        for u in raw.unicodeScalars where out.unicodeScalars.count < maxIdentifier {
            if isASCIIAlnum(u) || u == "_" || u == "-" { out.unicodeScalars.append(u) }
        }
        return out.isEmpty ? nil : out
    }

    /// Last path component of `cwd`. Never the full path.
    public static func projectName(fromCwd cwd: String?) -> String {
        guard let cwd else { return "unknown" }
        let trimmed = cwd.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        return projectName(fromFolderName: trimmed)
    }

    /// Strip control/format characters and path separators, cap length. Empty → "unknown".
    public static func projectName(fromFolderName name: String) -> String {
        var out = String.UnicodeScalarView()
        for u in name.unicodeScalars where out.count < maxProject {
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned, .privateUse:
                continue
            default:
                if u == "/" || u == "\\" { continue }
                out.append(u)
            }
        }
        let s = String(out).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? "unknown" : s
    }

    /// Tool name: `mcp__*` → "mcp"; otherwise `^[A-Za-z][A-Za-z0-9_]{0,39}$`, else "other".
    public static func toolName(_ raw: String) -> String {
        if raw.hasPrefix("mcp__") { return "mcp" }
        let scalars = Array(raw.unicodeScalars)
        guard let first = scalars.first, isASCIIAlpha(first), scalars.count <= maxTool,
              scalars.allSatisfy({ isASCIIAlnum($0) || $0 == "_" })
        else { return "other" }
        return raw
    }

    /// agent_type: `[A-Za-z0-9_:.-]`, ≤ 40 chars; anything else → nil (dropped).
    public static func agentType(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.unicodeScalars.count <= maxAgentType,
              raw.unicodeScalars.allSatisfy({ isASCIIAlnum($0) || "_:.-".unicodeScalars.contains($0) })
        else { return nil }
        return raw
    }

    /// Small enum: an allowed value passes, any other present value becomes `fallback`, absent stays nil.
    public static func enumValue(_ raw: String?, allowed: Set<String>, fallback: String) -> String? {
        guard let raw else { return nil }
        return allowed.contains(raw) ? raw : fallback
    }

    private static func isASCIIAlpha(_ u: Unicode.Scalar) -> Bool {
        (u >= "a" && u <= "z") || (u >= "A" && u <= "Z")
    }

    private static func isASCIIAlnum(_ u: Unicode.Scalar) -> Bool {
        isASCIIAlpha(u) || (u >= "0" && u <= "9")
    }
}
