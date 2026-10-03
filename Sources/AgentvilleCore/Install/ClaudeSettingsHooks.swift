import AgentvilleWire
import Foundation

/// Path B of Connect: our hooks in `~/.claude/settings.json`, for people without the `claude` CLI
/// (docs/architecture/installation.md#path-b-settings-file-fallback-no-cli).
///
/// Pure text in, text out; the app reads and writes the file (and its backup). Rules:
/// - **Smallest edit.** Nothing is re-serialised: ours is appended after the last member or element
///   of the object or array it joins, copying that file's separator and indentation, so every
///   existing key, hook, order and format is kept.
/// - **Marked.** Each command we add ends in `marker`, so Disconnect removes only ours.
/// - **Exact undo.** Disconnect deletes exactly what Connect appended; when that leaves one of our
///   containers empty (an event list, the `hooks` object) the container goes too, so a file comes
///   back byte for byte. (An empty `"hooks": {}` or event list that was there before is dropped
///   with it; it means the same to Claude Code.)
/// - **Never overwrite what we can't read.** Anything that isn't strict JSON with the expected
///   shape throws `Failure`; the app then stops and explains.
public enum ClaudeSettingsHooks {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// Not strict JSON (offset in bytes, and why).
        case unparseable(offset: Int, reason: String)
        /// The top level isn't an object.
        case notAnObject
        /// `hooks` or something inside it isn't shaped like Claude Code's hooks.
        case unexpectedShape(String)

        public var description: String {
            switch self {
            case .unparseable(let o, let r): "settings.json isn't valid JSON (\(r), at byte \(o))"
            case .notAnObject: "settings.json doesn't contain a JSON object"
            case .unexpectedShape(let what): "settings.json has hooks in a shape Agentville doesn't recognise (\(what))"
            }
        }
    }

    /// Ends every command we add. A shell comment, so it doesn't change what runs.
    public static let marker = "# agentville-hook"

    /// The plugin's silent shell-form command (ADR 0007) plus the marker.
    public static let command =
        "h=\"$HOME/Library/Application Support/Agentville/bin/agentville-hook\"; if [ -x \"$h\" ]; then \"$h\"; else cat >/dev/null; fi; exit 0 "
        + marker

    /// The plugin's events, in its order (`PluginManifestTests` and our tests keep them equal).
    public static let events = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop",
    ]

    // MARK: - Reading

    /// Every event has our hook.
    public static func isConnected(_ text: String) -> Bool {
        guard let doc = try? JSONSpans(text), case .object(let root) = doc.root else { return false }
        return events.allSatisfy { hasOurs(root, event: $0) }
    }

    /// `"disableAllHooks": true` turns every hook off, ours included.
    public static func hooksDisabled(_ text: String) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return false }
        return obj["disableAllHooks"] as? Bool == true
    }

    // MARK: - Connect

    /// Adds our hook to every event that lacks it. `nil` or blank text (no file yet) gives a new file.
    public static func connect(_ text: String?) throws -> String {
        guard let text, !text.allSatisfy(\.isWhitespace) else {
            return render(.object([("hooks", hooksObject(events))]), indent: "", style: .default) + "\n"
        }
        var bytes = Array(text.utf8)
        // One edit at a time, re-reading after each, so every offset is fresh.
        for _ in 0...events.count {
            let doc = try parse(bytes)
            guard case .object(let root) = doc.root else { throw Failure.notAnObject }
            let style = Style(bytes)
            guard let hooks = root.members.first(where: { $0.key == "hooks" }) else {
                let member = Out.member("hooks", hooksObject(events))
                bytes = append(member, to: root.range, elements: root.elementRanges, in: bytes, style: style)
                continue
            }
            guard case .object(let hooksObj) = hooks.value else { throw Failure.unexpectedShape("\"hooks\" isn't an object") }
            guard let event = events.first(where: { !hasOurs(root, event: $0) }) else { return String(decoding: bytes, as: UTF8.self) }
            if let existing = hooksObj.members.first(where: { $0.key == event }) {
                guard case .array(let list) = existing.value else { throw Failure.unexpectedShape("\"\(event)\" isn't a list") }
                bytes = append(ourGroup, to: list.range, elements: list.elementRanges, in: bytes, style: style)
            } else {
                bytes = append(.member(event, .array([ourGroup])), to: hooksObj.range, elements: hooksObj.elementRanges, in: bytes, style: style)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    // MARK: - Disconnect

    /// Removes every hook carrying our marker, and any container that leaves empty.
    public static func disconnect(_ text: String) throws -> String {
        var bytes = Array(text.utf8)
        for _ in 0..<10_000 {
            let doc = try parse(bytes)
            guard case .object(let root) = doc.root else { throw Failure.notAnObject }
            guard let cut = firstRemoval(root) else { break }
            bytes.removeSubrange(cut)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The bytes to delete to remove one of our hooks, cascading up while a container would empty.
    private static func firstRemoval(_ root: JSONSpans.Object) -> Range<Int>? {
        guard let hooksIndex = root.members.firstIndex(where: { $0.key == "hooks" }),
              case .object(let hooksObj) = root.members[hooksIndex].value else { return nil }
        for (ei, event) in hooksObj.members.enumerated() {
            guard case .array(let groups) = event.value else { continue }
            for (gi, g) in groups.elements.enumerated() {
                guard case .object(let group) = g,
                      let inner = group.members.first(where: { $0.key == "hooks" }),
                      case .array(let list) = inner.value else { continue }
                for (hi, h) in list.elements.enumerated() where isOurs(h) {
                    if list.elements.count > 1 { return removal(hi, of: list.elementRanges, in: list.range) }
                    if groups.elements.count > 1 { return removal(gi, of: groups.elementRanges, in: groups.range) }
                    if hooksObj.members.count > 1 { return removal(ei, of: hooksObj.elementRanges, in: hooksObj.range) }
                    return removal(hooksIndex, of: root.elementRanges, in: root.range)
                }
            }
        }
        return nil
    }

    /// Deleting element `i`: with the comma and space before it (the exact inverse of `append`),
    /// or after it if it's first; everything inside the brackets if it's the only one.
    private static func removal(_ i: Int, of elements: [Range<Int>], in container: Range<Int>) -> Range<Int> {
        if elements.count == 1 { return (container.lowerBound + 1)..<(container.upperBound - 1) }
        if i > 0 { return elements[i - 1].upperBound..<elements[i].upperBound }
        return elements[0].lowerBound..<elements[1].lowerBound
    }

    // MARK: - Shape checks

    private static func parse(_ bytes: [UInt8]) throws -> JSONSpans {
        let text = String(decoding: bytes, as: UTF8.self)
        let doc: JSONSpans
        do { doc = try JSONSpans(text) } catch let e as JSONSpans.ParseError {
            throw Failure.unparseable(offset: e.offset, reason: e.reason)
        }
        guard case .object(let root) = doc.root else { throw Failure.notAnObject }
        try checkShape(root)
        return doc
    }

    /// Claude Code's shape: `hooks` is an object of lists of objects, each with an optional list of
    /// hook objects. We only touch files that look like that.
    private static func checkShape(_ root: JSONSpans.Object) throws {
        guard let hooks = root.members.first(where: { $0.key == "hooks" }) else { return }
        guard case .object(let obj) = hooks.value else { throw Failure.unexpectedShape("\"hooks\" isn't an object") }
        for event in obj.members {
            guard case .array(let groups) = event.value else { throw Failure.unexpectedShape("\"\(event.key)\" isn't a list") }
            for g in groups.elements {
                guard case .object(let group) = g else { throw Failure.unexpectedShape("an entry under \"\(event.key)\" isn't an object") }
                guard let inner = group.members.first(where: { $0.key == "hooks" }) else { continue }
                guard case .array(let list) = inner.value else { throw Failure.unexpectedShape("\"hooks\" under \"\(event.key)\" isn't a list") }
                for h in list.elements {
                    guard case .object = h else { throw Failure.unexpectedShape("a hook under \"\(event.key)\" isn't an object") }
                }
            }
        }
    }

    private static func isOurs(_ hook: JSONSpans.Value) -> Bool {
        guard case .object(let h) = hook,
              let c = h.members.first(where: { $0.key == "command" }),
              case .scalar(_, let s?) = c.value else { return false }
        return s.contains(marker)
    }

    private static func hasOurs(_ root: JSONSpans.Object, event: String) -> Bool {
        guard let hooks = root.members.first(where: { $0.key == "hooks" }), case .object(let obj) = hooks.value,
              let list = obj.members.first(where: { $0.key == event }), case .array(let groups) = list.value else { return false }
        return groups.elements.contains { g in
            guard case .object(let group) = g, let inner = group.members.first(where: { $0.key == "hooks" }),
                  case .array(let hs) = inner.value else { return false }
            return hs.elements.contains(where: isOurs)
        }
    }

    // MARK: - Writing

    /// What we add, before it's laid out.
    private indirect enum Out {
        case object([(String, Out)])
        case array([Out])
        case string(String)
        case bool(Bool)
        /// An object member on its own (`"key": value`), for appending to an object.
        case member(String, Out)
    }

    private static var ourGroup: Out {
        .object([("hooks", .array([.object([("type", .string("command")), ("command", .string(command)), ("async", .bool(true))])]))])
    }

    private static func hooksObject(_ events: [String]) -> Out {
        .object(events.map { ($0, .array([ourGroup])) })
    }

    /// How the file is laid out: its line ending and one level of indentation.
    private struct Style {
        var newline = "\n"
        var unit = "  "
        static let `default` = Style()

        init() {}

        init(_ bytes: [UInt8]) {
            if let i = bytes.firstIndex(of: 0x0A), i > 0, bytes[i - 1] == 0x0D { newline = "\r\n" }
            // The first indented line's indentation.
            var i = 0
            while let nl = bytes[i...].firstIndex(of: 0x0A) {
                var j = nl + 1
                while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09 { j += 1 }
                if j > nl + 1, j < bytes.count, bytes[j] != 0x0A, bytes[j] != 0x0D {
                    unit = String(decoding: bytes[(nl + 1)..<j], as: UTF8.self)
                    break
                }
                i = nl + 1
            }
        }
    }

    /// Appends `item` after the last of `elements` (or into the empty container), laid out like its
    /// neighbours: one line if they share one, otherwise one per line at their indentation.
    private static func append(_ item: Out, to container: Range<Int>, elements: [Range<Int>], in bytes: [UInt8], style: Style) -> [UInt8] {
        var out = bytes
        if let last = elements.last {
            // The whitespace between the last element and the comma or bracket before it.
            var d = last.lowerBound - 1
            while d > container.lowerBound, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[d]) { d -= 1 }
            let sep = String(decoding: bytes[(d + 1)..<last.lowerBound], as: UTF8.self)
            let compact = !sep.contains("\n")
            let indent = compact ? "" : String(sep[sep.index(after: sep.lastIndex(of: "\n")!)...])
            let text = "," + sep + render(item, indent: indent, style: style, compact: compact)
            out.insert(contentsOf: Array(text.utf8), at: last.upperBound)
        } else {
            let compact = !bytes.contains(0x0A) && container.lowerBound > 0
            let outer = lineIndent(bytes, at: container.lowerBound)
            let inner = outer + style.unit
            let text = compact
                ? render(item, indent: "", style: style, compact: true)
                : style.newline + inner + render(item, indent: inner, style: style) + style.newline + outer
            out.replaceSubrange((container.lowerBound + 1)..<(container.upperBound - 1), with: Array(text.utf8))
        }
        return out
    }

    /// The leading whitespace of the line that holds `offset`.
    private static func lineIndent(_ bytes: [UInt8], at offset: Int) -> String {
        var start = offset
        while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
        var end = start
        while end < offset, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// JSON text for `v` whose first line starts at `indent` (already written by the caller).
    private static func render(_ v: Out, indent: String, style: Style, compact: Bool = false) -> String {
        let nl = compact ? "" : style.newline, inner = compact ? "" : indent + style.unit, colon = compact ? ":" : ": "
        switch v {
        case .string(let s): return quote(s)
        case .bool(let b): return b ? "true" : "false"
        case .member(let k, let value): return quote(k) + colon + render(value, indent: indent, style: style, compact: compact)
        case .array(let items):
            let body = items.map { inner + render($0, indent: inner, style: style, compact: compact) }
            return "[" + nl + body.joined(separator: "," + nl) + nl + (compact ? "" : indent) + "]"
        case .object(let members):
            let body = members.map { inner + quote($0.0) + colon + render($0.1, indent: inner, style: style, compact: compact) }
            return "{" + nl + body.joined(separator: "," + nl) + nl + (compact ? "" : indent) + "}"
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }
}
