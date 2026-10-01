import Darwin
import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// Runs the real `agentville-hook` binary (non-negotiable #4; docs/architecture/hook.md#tests).
/// `scripts/test.sh` builds it first.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

func hookBinary() throws -> URL {
    for config in ["debug", "release"] {
        let u = repoRoot.appendingPathComponent(".build/\(config)/agentville-hook")
        if FileManager.default.isExecutableFile(atPath: u.path) { return u }
    }
    Issue.record("agentville-hook not built. Run scripts/test.sh (it builds the hook first).")
    throw CancellationError()
}

struct RunResult { var status: Int32; var stdout: Data; var stderr: Data; var seconds: Double }

func run(_ exe: URL, args: [String] = [], stdin: Data, env: [String: String]) throws -> RunResult {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    p.environment = env
    let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
    p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe
    let t0 = Date()
    try p.run()
    // Write on a background thread so large inputs can't deadlock against a full pipe.
    let writer = Thread { inPipe.fileHandleForWriting.write(stdin); try? inPipe.fileHandleForWriting.close() }
    writer.start()
    let out = outPipe.fileHandleForReading.readDataToEndOfFile()
    let err = errPipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return RunResult(status: p.terminationStatus, stdout: out, stderr: err, seconds: Date().timeIntervalSince(t0))
}

func payload(_ obj: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: obj) }

final class SocketFixture {
    let path: String, fd: Int32
    init() {
        path = NSTemporaryDirectory() + "avh-\(UUID().uuidString.prefix(8)).sock"
        fd = DatagramSocket.bindReceiver(at: path)
    }
    deinit { close(fd); unlink(path) }
    func drain() -> [Data] {
        var out: [Data] = []
        while let d = DatagramSocket.receive(fd: fd) { out.append(d) }
        return out
    }
}

@Suite("Hook binary", .serialized)
struct HookBinaryTests {
    let secret = "SECRET-HOOK-INTEGRATION-1234"

    func event(_ name: String, _ extra: [String: Any] = [:]) -> Data {
        var p: [String: Any] = [
            "hook_event_name": name, "session_id": "sess-1", "cwd": "/Users/x/\(secret)/blog",
            "transcript_path": "/x/\(secret)", "user_prompt": secret,
            "tool_input": ["command": secret], "tool_output": String(repeating: "o", count: 200_000) + secret,
            "last_assistant_message": String(repeating: "m", count: 100_000) + secret,
        ]
        for (k, v) in extra { p[k] = v }
        return payload(p)
    }

    @Test("Valid events arrive at the socket with only allowlisted data")
    func delivers() throws {
        let exe = try hookBinary(), sock = SocketFixture()
        try #require(sock.fd >= 0)
        for kind in WireEvent.Kind.allCases {
            let r = try run(exe, stdin: event(kind.rawValue, ["tool_name": "Edit"]), env: ["AGENTVILLE_SOCKET": sock.path])
            #expect(r.status == 0 && r.stdout.isEmpty && r.stderr.isEmpty, "\(kind)")
        }
        let got = sock.drain()
        #expect(got.count == WireEvent.Kind.allCases.count)
        for d in got {
            #expect(!String(decoding: d, as: UTF8.self).contains(secret))
            let e = try #require(WireCodec.decode(d))
            #expect(e.project == "blog" && e.session == "sess-1")
        }
    }

    @Test("A large but valid payload (3 MB tool_output) is still delivered, quickly")
    func largePayload() throws {
        let exe = try hookBinary(), sock = SocketFixture()
        let big = event("PostToolUse", ["tool_name": "Read", "tool_output": String(repeating: "z", count: 3_000_000) + secret])
        let r = try run(exe, stdin: big, env: ["AGENTVILLE_SOCKET": sock.path])
        #expect(r.status == 0 && r.stdout.isEmpty)
        #expect(r.seconds < 0.5, "3 MB payload took \(r.seconds)s")
        let got = sock.drain()
        #expect(got.count == 1)
        #expect(!got.contains { String(decoding: $0, as: UTF8.self).contains(secret) })
    }

    @Test("Always exit 0 with empty stdout, whatever the input")
    func neverFails() throws {
        let exe = try hookBinary(), sock = SocketFixture()
        let inputs: [Data] = [
            Data(), Data("not json".utf8), Data("[]".utf8), Data("{}".utf8), Data("null".utf8),
            Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31) }),
            event("PreCompact"), event("Stop", ["session_id": 42]),
            Data(repeating: 0x20, count: 5_000_000),   // 5 MB of whitespace: over the input cap
            Data(#"{"hook_event_name":"Stop","session_id":"s","cwd":"/a/b","#.utf8), // truncated
        ]
        for (i, input) in inputs.enumerated() {
            let r = try run(exe, stdin: input, env: ["AGENTVILLE_SOCKET": sock.path])
            #expect(r.status == 0, "input \(i)")
            #expect(r.stdout.isEmpty, "input \(i)")
            #expect(r.stderr.isEmpty, "input \(i)")
        }
        #expect(sock.drain().isEmpty, "none of those inputs is a valid registered event")
    }

    @Test("App absent: missing socket, path is a regular file, bad path. All silent, exit 0")
    func appAbsent() throws {
        let exe = try hookBinary()
        let regular = NSTemporaryDirectory() + "avh-regular-\(UUID().uuidString.prefix(6))"
        FileManager.default.createFile(atPath: regular, contents: Data("x".utf8))
        defer { unlink(regular) }
        for path in ["/nonexistent/dir/agentville.sock", regular, "/" + String(repeating: "a", count: 300)] {
            let r = try run(exe, stdin: event("Stop"), env: ["AGENTVILLE_SOCKET": path])
            #expect(r.status == 0 && r.stdout.isEmpty && r.stderr.isEmpty, "\(path.prefix(40))")
        }
    }

    @Test("Timing: p99 within budget with the app listening and absent")
    func timing() throws {
        let exe = try hookBinary(), sock = SocketFixture()
        // CI machines are noisy: assert 2× the budget there (docs/quality/testing-strategy.md).
        let slack = ProcessInfo.processInfo.environment["CI"] == nil ? 1.0 : 2.0
        let input = event("PreToolUse", ["tool_name": "Bash"])
        func p99(_ env: [String: String]) throws -> Double {
            var times: [Double] = []
            for _ in 0..<120 { times.append(try run(exe, stdin: input, env: env).seconds) }
            times.sort()
            return times[Int(Double(times.count) * 0.99) - 1]
        }
        let listening = try p99(["AGENTVILLE_SOCKET": sock.path])
        let absent = try p99(["AGENTVILLE_SOCKET": "/nonexistent/agentville.sock"])
        _ = sock.drain()
        // Measured wall time includes Process spawn overhead from the test harness itself.
        #expect(listening < 0.050 * slack, "p99 listening = \(listening)s")
        #expect(absent < 0.050 * slack, "p99 absent = \(absent)s")
    }

    @Test("The plugin's shell command exits 0 silently when the helper is missing")
    func shellCommandWithoutHelper() throws {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Plugin/agentville/hooks/hooks.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(obj["hooks"] as? [String: [[String: Any]]])
        let cmd = try #require((hooks["Stop"]?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        let fakeHome = NSTemporaryDirectory() + "avh-home-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: fakeHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: fakeHome) }
        let r = try run(URL(fileURLWithPath: "/bin/sh"), args: ["-c", cmd], stdin: event("Stop"), env: ["HOME": fakeHome, "PATH": "/usr/bin:/bin"])
        #expect(r.status == 0 && r.stdout.isEmpty && r.stderr.isEmpty)
    }

    @Test("The plugin's shell command runs the helper through the symlink when present")
    func shellCommandWithHelper() throws {
        let exe = try hookBinary(), sock = SocketFixture()
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("Plugin/agentville/hooks/hooks.json"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(obj["hooks"] as? [String: [[String: Any]]])
        let cmd = try #require((hooks["Stop"]?.first?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        let fakeHome = NSTemporaryDirectory() + "avh-home-\(UUID().uuidString.prefix(6))"
        let bin = fakeHome + "/Library/Application Support/Agentville/bin"
        try FileManager.default.createDirectory(atPath: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: fakeHome) }
        try FileManager.default.createSymbolicLink(atPath: bin + "/agentville-hook", withDestinationPath: exe.path)
        let r = try run(URL(fileURLWithPath: "/bin/sh"), args: ["-c", cmd], stdin: event("Stop"),
                        env: ["HOME": fakeHome, "PATH": "/usr/bin:/bin", "AGENTVILLE_SOCKET": sock.path])
        #expect(r.status == 0 && r.stdout.isEmpty && r.stderr.isEmpty)
        #expect(sock.drain().count == 1)
    }
}
