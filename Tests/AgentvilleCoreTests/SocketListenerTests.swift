import Darwin
import Foundation
import Testing
@testable import AgentvilleCore
@testable import AgentvilleWire

/// The app's receiving end of the socket (docs/architecture/app.md#components). Runs the real
/// listener on a real socket in the temp dir.
@Suite("Socket listener")
struct SocketListenerTests {
    /// Thread-safe sink for delivered batches.
    final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var _batches: [[WireEvent]] = []
        func add(_ b: [WireEvent]) { lock.lock(); _batches.append(b); lock.unlock() }
        var batches: [[WireEvent]] { lock.lock(); defer { lock.unlock() }; return _batches }
        var events: [WireEvent] { batches.flatMap { $0 } }
    }

    static let queue = DispatchQueue(label: "agentville.tests.listener-delivery")

    static func tempSocketPath() -> String {
        NSTemporaryDirectory() + "av-\(UInt32.random(in: 0...UInt32.max)).sock"
    }

    static func waitUntil(timeout: TimeInterval = 3, _ cond: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond(), Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    static func exists(_ path: String) -> Bool {
        var st = stat()
        return lstat(path, &st) == 0
    }

    func makeListener(_ path: String, _ sink: Sink) -> SocketListener {
        SocketListener(path: path, deliverOn: Self.queue) { sink.add($0) }
    }

    @Test("Delivers decoded events in order; malformed datagrams are dropped and counted")
    func deliversAndDrops() async throws {
        let path = Self.tempSocketPath(), sink = Sink()
        let listener = makeListener(path, sink)
        #expect(listener.start())
        defer { listener.stop() }

        let good = (0..<5).map { WireEvent(event: .preToolUse, session: "s\($0)", project: "blog", tool: "Edit", ts: 1) }
        DatagramSocket.send(WireCodec.encode(good[0])!, to: path)
        // Junk the kernel accepts. (Oversize datagrams are refused at send time: macOS caps local
        // datagrams at net.local.dgram.maxdgram = 2048, which is also why the codec cap is 2048.)
        var junk = 0
        for d in [Data("{not json".utf8), Data(#"{"v":2,"event":"Stop","session":"s","project":"p","ts":1}"#.utf8),
                  Data(repeating: 0x7b, count: WireCodec.maxReceiveBytes + 100)] {
            if DatagramSocket.send(d, to: path) { junk += 1 }
        }
        #expect(junk >= 2)
        for e in good.dropFirst() { DatagramSocket.send(WireCodec.encode(e)!, to: path) }

        await Self.waitUntil { sink.events.count >= good.count && listener.stats.dropped >= junk }
        #expect(sink.events == good)
        #expect(listener.stats.received == good.count)
        #expect(listener.stats.dropped == junk)
    }

    @Test("Received events are re-sanitized, never trusted")
    func resanitizes() async throws {
        let path = Self.tempSocketPath(), sink = Sink()
        let listener = makeListener(path, sink)
        #expect(listener.start())
        defer { listener.stop() }
        DatagramSocket.send(Data(#"{"v":1,"event":"PreToolUse","session":"s/../1","project":"/etc/passwd","tool":"mcp__evil__x","ts":-5}"#.utf8), to: path)
        await Self.waitUntil { !sink.events.isEmpty }
        let e = try #require(sink.events.first)
        #expect(e.session == "s1" && e.project == "etcpasswd" && e.tool == "mcp" && e.ts == 0)
    }

    @Test("The socket file is private, and stop() removes it (nothing left behind)")
    func cleanup() throws {
        let path = Self.tempSocketPath(), sink = Sink()
        let listener = makeListener(path, sink)
        #expect(listener.start())
        var st = stat()
        #expect(lstat(path, &st) == 0)
        #expect(st.st_mode & 0o777 == 0o600)
        listener.stop()
        #expect(!Self.exists(path))
        listener.stop() // idempotent
    }

    @Test("stop() leaves a socket that a newer listener bound at the same path alone")
    func doesNotUnlinkReplacement() async throws {
        let path = Self.tempSocketPath()
        let oldSink = Sink(), newSink = Sink()
        let old = makeListener(path, oldSink)
        #expect(old.start())
        let new = makeListener(path, newSink)
        #expect(new.start())
        old.stop()
        #expect(Self.exists(path))
        DatagramSocket.send(WireCodec.encode(WireEvent(event: .stop, session: "s", project: "p", ts: 0))!, to: path)
        await Self.waitUntil { !newSink.events.isEmpty }
        #expect(newSink.events.count == 1)
        new.stop()
        #expect(!Self.exists(path))
    }

    @Test("start() fails cleanly for an unusable path")
    func badPath() {
        let tooLong = NSTemporaryDirectory() + String(repeating: "x", count: 200)
        #expect(!SocketListener(path: tooLong, deliverOn: Self.queue) { _ in }.start())
        #expect(!SocketListener(path: "/nonexistent-dir/agentville.sock", deliverOn: Self.queue) { _ in }.start())
    }

    @Test("A burst arrives complete and batched (non-negotiable #11)")
    func burst() async throws {
        let path = Self.tempSocketPath(), sink = Sink()
        let listener = makeListener(path, sink)
        #expect(listener.start())
        defer { listener.stop() }
        var accepted = 0
        for i in 0..<2000 {
            let e = WireEvent(event: .postToolUse, session: "b\(i % 100)", project: "p\(i % 7)", tool: "Read", ts: Int64(i))
            if DatagramSocket.send(WireCodec.encode(e)!, to: path) { accepted += 1 }
        }
        #expect(accepted > 0)
        await Self.waitUntil { sink.events.count >= accepted }
        #expect(sink.events.count == accepted)
        #expect(sink.batches.allSatisfy { $0.count <= Limits.listenerBatch })
        #expect(sink.batches.count < accepted, "events should be delivered in batches, not one by one")
        // Order is preserved within the stream.
        #expect(sink.events.map(\.ts) == sink.events.map(\.ts).sorted())
    }

    @Test("Socket → listener → store gives the same states as applying the scenario directly")
    func endToEnd() async throws {
        let text = try readRepoFile("Tools/scenarios/demo-mix.jsonl")
        let datagrams = try Scenario.parse(text).steps.compactMap { Scenario.datagram(for: $0.step) }
        let path = Self.tempSocketPath(), sink = Sink()
        let listener = makeListener(path, sink)
        #expect(listener.start())
        defer { listener.stop() }
        for d in datagrams { DatagramSocket.send(d, to: path) }

        let expected = datagrams.compactMap(WireCodec.decode)
        await Self.waitUntil { sink.events.count >= expected.count }

        let viaSocket = SessionStore(), direct = SessionStore()
        for e in sink.events { viaSocket.apply(e, now: 100) }
        for e in expected { direct.apply(e, now: 100) }
        #expect(!direct.sessions.isEmpty)
        #expect(viaSocket.order == direct.order)
        #expect(viaSocket.ordered.map { Scenario.statusString($0) } == direct.ordered.map { Scenario.statusString($0) })
    }
}
