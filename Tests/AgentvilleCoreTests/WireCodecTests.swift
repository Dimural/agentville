import Foundation
import Testing
@testable import AgentvilleCore

@Suite("Wire codec and socket path")
struct WireCodecTests {
    @Test func roundTrip() throws {
        let e = WireEvent(event: .subagentStart, session: "s1", project: "blog", agentId: "a1", agentType: "Explore", ts: 42)
        let d = try #require(WireCodec.encode(e))
        #expect(d.count <= WireCodec.maxSendBytes)
        #expect(WireCodec.decode(d) == e)
    }

    @Test("Decode rejects oversize, wrong version, unknown event, non-object")
    func rejects() {
        #expect(WireCodec.decode(Data(repeating: 32, count: WireCodec.maxReceiveBytes + 1)) == nil)
        #expect(WireCodec.decode(Data(#"{"v":2,"event":"Stop","session":"s","project":"p","ts":1}"#.utf8)) == nil)
        #expect(WireCodec.decode(Data(#"{"v":1,"event":"Explode","session":"s","project":"p","ts":1}"#.utf8)) == nil)
        #expect(WireCodec.decode(Data(#"[1]"#.utf8)) == nil)
        #expect(WireCodec.decode(Data()) == nil)
        #expect(WireCodec.decode(Data(#"{"v":1,"event":"Stop","session":"","project":"p","ts":1}"#.utf8)) == nil)
    }

    @Test("Decode re-sanitizes: the app never trusts the sender")
    func resanitizes() throws {
        let hostile = #"{"v":1,"event":"PreToolUse","session":"s/../1","project":"/etc/passwd","tool":"mcp__evil__x","notification":"idle_prompt","source":"startup","ts":-5,"extra":"ignored"}"#
        let e = try #require(WireCodec.decode(Data(hostile.utf8)))
        #expect(e.session == "s1")
        #expect(e.project == "etcpasswd")
        #expect(e.tool == "mcp")
        #expect(e.notification == nil && e.source == nil)
        #expect(e.ts == 0)
    }

    @Test("Encode refuses to exceed the datagram cap")
    func encodeCap() {
        // Every field is capped by sanitization, so a sanitized event always fits.
        let big = WireEvent(event: .preToolUse, session: String(repeating: "a", count: 64), project: String(repeating: "é", count: 64), tool: "Bash", agentId: String(repeating: "b", count: 64), agentType: String(repeating: "c", count: 40), ts: Int64.max).sanitized()!
        #expect(WireCodec.encode(big) != nil)
    }

    @Test("Socket path: override, default location, length limit")
    func socketPath() throws {
        #expect(SocketPath.resolve(environment: ["AGENTVILLE_SOCKET": "/tmp/x.sock"]) == "/tmp/x.sock")
        #expect(SocketPath.resolve(environment: ["AGENTVILLE_SOCKET": "/" + String(repeating: "a", count: 200)]) == nil)
        let def = try #require(SocketPath.resolve(environment: [:]))
        #expect(def.hasSuffix("/agentville.sock"))
        #expect(def.utf8.count <= SocketPath.maxPathBytes)
    }

    @Test("Datagram send/receive over a real Unix socket")
    func datagram() throws {
        let path = NSTemporaryDirectory() + "av-\(UUID().uuidString.prefix(8)).sock"
        let fd = DatagramSocket.bindReceiver(at: path)
        try #require(fd >= 0)
        defer { close(fd); unlink(path) }
        let e = WireEvent(event: .stop, session: "s", project: "p", ts: 1)
        #expect(DatagramSocket.send(WireCodec.encode(e)!, to: path))
        let got = try #require(DatagramSocket.receive(fd: fd))
        #expect(WireCodec.decode(got) == e)
        #expect(DatagramSocket.receive(fd: fd) == nil)
        #expect(!DatagramSocket.send(Data("x".utf8), to: path + ".missing"))
    }
}
