// agentville-replay: sends scripted WireEvents to the app's socket (docs/quality/testing-strategy.md).
//
// Usage:
//   agentville-replay <scenario.jsonl> [--speed 2] [--socket /path]
//   agentville-replay --generate burst|hundred [--seconds 10] [--rate 500]
//
// Scenario format: one JSON object per line: {"at": <seconds>, "event": "...", "session": "...", ...}.
// Any WireEvent field may appear; "v" and "ts" are filled in. A line {"at": t, "raw": "<text>"} sends the
// raw text as-is (for malformed-input scenarios). Lines starting with "//" are comments.
import AgentvilleCore
import Foundation

struct Options {
    var file: String?
    var generate: String?
    var speed = 1.0
    var socket: String?
    var seconds = 10.0
    var rate = 500.0
}

func parseArgs() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        switch a {
        case "--speed": o.speed = Double(it.next() ?? "") ?? 1
        case "--socket": o.socket = it.next()
        case "--generate": o.generate = it.next()
        case "--seconds": o.seconds = Double(it.next() ?? "") ?? 10
        case "--rate": o.rate = Double(it.next() ?? "") ?? 500
        case "-h", "--help":
            print("usage: agentville-replay <scenario.jsonl> [--speed N] [--socket PATH] | --generate burst|hundred [--seconds S] [--rate R]")
            exit(0)
        default: o.file = a
        }
    }
    return o
}

struct Step { var at: Double; var payload: Data }

func loadScenario(_ path: String) -> [Step] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        FileHandle.standardError.write(Data("cannot read \(path)\n".utf8)); exit(1)
    }
    var steps: [Step] = []
    for (n, line) in text.split(separator: "\n").enumerated() {
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.isEmpty || l.hasPrefix("//") { continue }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [String: Any],
              let at = obj["at"] as? Double
        else { FileHandle.standardError.write(Data("line \(n + 1): needs {\"at\": seconds, ...}\n".utf8)); exit(1) }
        if let raw = obj["raw"] as? String {
            steps.append(Step(at: at, payload: Data(raw.utf8)))
            continue
        }
        var fields = obj
        fields["at"] = nil
        fields["v"] = WireEvent.version
        fields["ts"] = 0
        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              var ev = try? JSONDecoder().decode(WireEvent.self, from: data)
        else { FileHandle.standardError.write(Data("line \(n + 1): not a valid WireEvent\n".utf8)); exit(1) }
        ev.ts = 0
        steps.append(Step(at: at, payload: WireCodec.encode(ev) ?? Data()))
    }
    return steps.sorted { $0.at < $1.at }
}

/// Synthetic load: many sessions with a realistic tool mix.
func generate(_ kind: String, seconds: Double, rate: Double) -> [Step] {
    let sessions = kind == "hundred" ? 100 : 40
    let tools = ["Read", "Edit", "Bash", "Grep", "Glob", "WebSearch", "Write", "TodoWrite", "mcp", "Task"]
    var steps: [Step] = []
    var rng = XorShift32(seed: 42)
    func send(_ at: Double, _ e: WireEvent) { if let d = WireCodec.encode(e) { steps.append(Step(at: at, payload: d)) } }
    for i in 0..<sessions {
        let sid = String(format: "gen-%04d", i), proj = "project-\(i % 37)"
        send(0.01 * Double(i), WireEvent(event: .sessionStart, session: sid, project: proj, source: "startup", ts: 0))
        send(0.01 * Double(i) + 0.005, WireEvent(event: .userPromptSubmit, session: sid, project: proj, ts: 0))
    }
    let total = Int(seconds * rate)
    for n in 0..<total {
        let at = 1 + Double(n) / rate
        let i = Int(rng.next() * Double(sessions))
        let sid = String(format: "gen-%04d", i), proj = "project-\(i % 37)"
        let roll = rng.next()
        let ev: WireEvent
        if roll < 0.45 { ev = WireEvent(event: .preToolUse, session: sid, project: proj, tool: rng.pick(tools), ts: 0) }
        else if roll < 0.9 { ev = WireEvent(event: .postToolUse, session: sid, project: proj, tool: rng.pick(tools), ts: 0) }
        else if roll < 0.93 { ev = WireEvent(event: .permissionRequest, session: sid, project: proj, tool: "Bash", ts: 0) }
        else if roll < 0.96 { ev = WireEvent(event: .stop, session: sid, project: proj, ts: 0) }
        else { ev = WireEvent(event: .userPromptSubmit, session: sid, project: proj, ts: 0) }
        send(at, ev)
    }
    return steps
}

let opts = parseArgs()
guard let path = opts.socket ?? SocketPath.resolve() else {
    FileHandle.standardError.write(Data("cannot resolve socket path\n".utf8)); exit(1)
}
let steps: [Step]
if let g = opts.generate { steps = generate(g, seconds: opts.seconds, rate: opts.rate) }
else if let f = opts.file { steps = loadScenario(f) }
else { FileHandle.standardError.write(Data("give a scenario file or --generate\n".utf8)); exit(1) }

let start = Date()
var delivered = 0
for s in steps {
    let wait = s.at / max(0.01, opts.speed) - Date().timeIntervalSince(start)
    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
    if DatagramSocket.send(s.payload, to: path) { delivered += 1 }
}
print("sent \(steps.count) events (\(delivered) accepted by socket) to \(path)")
