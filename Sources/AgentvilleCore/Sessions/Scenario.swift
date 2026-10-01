import Foundation

/// Replay scenarios (`Tools/scenarios/*.jsonl`): scripted event sequences that double as executable specs.
/// Used by `agentville-replay` (sends them to the app) and by `ScenarioTests` (runs them through
/// `SessionStore` and checks the `expect` lines).
///
/// One JSON object per line; blank lines and lines starting with `//` are ignored:
///   {"at": 1.5, "event": "PreToolUse", "session": "s1", "project": "blog", "tool": "Edit"}
///   {"at": 2.0, "raw": "{not json"}                         // sent verbatim (malformed input)
///   {"at": 3.0, "expect": {"session": "s1", "status": "working:editing"}}
///   {"at": 3.0, "tick": true}                                // run SessionStore.tick (tests only)
/// Status strings: idle, needsYou, finished, error, gone, working:<activity>.
public struct Scenario: Sendable {
    public enum Step: Sendable {
        case event(WireEvent)
        case raw(Data)
        case expect(session: String, status: String)
        case tick
    }

    public struct ParseError: Error, CustomStringConvertible {
        public let line: Int, message: String
        public var description: String { "line \(line): \(message)" }
    }

    public var steps: [(at: Double, step: Step)]

    public static func parse(_ text: String) throws -> Scenario {
        var steps: [(Double, Step)] = []
        for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("//") { continue }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any],
                  let at = (obj["at"] as? NSNumber)?.doubleValue
            else { throw ParseError(line: n + 1, message: #"needs {"at": seconds, ...}"#) }

            if let raw = obj["raw"] as? String {
                steps.append((at, .raw(Data(raw.utf8)))); continue
            }
            if obj["tick"] as? Bool == true {
                steps.append((at, .tick)); continue
            }
            if let ex = obj["expect"] as? [String: Any] {
                guard let s = ex["session"] as? String, let st = ex["status"] as? String
                else { throw ParseError(line: n + 1, message: "expect needs session and status") }
                steps.append((at, .expect(session: s, status: st))); continue
            }
            var fields = obj
            fields["at"] = nil
            fields["v"] = WireEvent.version
            fields["ts"] = 0
            guard let data = try? JSONSerialization.data(withJSONObject: fields),
                  let ev = try? JSONDecoder().decode(WireEvent.self, from: data),
                  let clean = ev.sanitized()
            else { throw ParseError(line: n + 1, message: "not a valid WireEvent") }
            steps.append((at, .event(clean)))
        }
        // Stable sort keeps same-time lines in file order.
        let sorted = steps.enumerated().sorted { ($0.element.0, $0.offset) < ($1.element.0, $1.offset) }.map(\.element)
        return Scenario(steps: sorted.map { (at: $0.0, step: $0.1) })
    }

    /// Bytes to put on the wire for a step (nil for test-only steps).
    public static func datagram(for step: Step) -> Data? {
        switch step {
        case .event(let e): WireCodec.encode(e)
        case .raw(let d): d
        case .expect, .tick: nil
        }
    }

    /// The string form used by `expect` lines.
    public static func statusString(_ s: Session?) -> String {
        guard let s else { return "gone" }
        switch s.status {
        case .idle: return "idle"
        case .needsYou: return "needsYou"
        case .finished: return "finished"
        case .error: return "error"
        case .working(let a): return "working:\(a.rawValue)"
        }
    }
}
