import Darwin
import Dispatch
import Foundation

/// The app's receiving end of the hook socket (docs/architecture/app.md#components).
///
/// Binds the `AF_UNIX` datagram socket, drains it on a background `DispatchSource`, decodes every
/// datagram with `WireCodec.decode` (untrusted input: size cap, schema, re-sanitize) and hands
/// decoded events to `onBatch` on the delivery queue, in order, at most `Limits.listenerBatch`
/// at a time. Undecodable datagrams are dropped and counted. `stop()` closes the socket and
/// removes the socket file, unless another listener has since been bound at the same path.
public final class SocketListener: @unchecked Sendable {
    public struct Stats: Equatable, Sendable {
        /// Datagrams that decoded into an event.
        public var received = 0
        /// Datagrams dropped as malformed, oversize or of an unknown schema.
        public var dropped = 0
    }

    public let path: String
    private let deliverQueue: DispatchQueue
    private let onBatch: @Sendable ([WireEvent]) -> Void
    /// Owns `fd`, `source`, `buffer` and `_stats`.
    private let ioQueue = DispatchQueue(label: "agentville.socket-listener", qos: .userInitiated)

    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    /// Identity of the socket file we bound, so `stop()` never removes a newer listener's file.
    private var boundFile: (dev: dev_t, ino: ino_t)?
    /// Reused receive buffer: one byte more than the codec accepts, so oversize datagrams are detectable.
    private var buffer = [UInt8](repeating: 0, count: WireCodec.maxReceiveBytes + 1)
    private var _stats = Stats()

    public init(path: String, deliverOn queue: DispatchQueue = .main,
                onBatch: @escaping @Sendable ([WireEvent]) -> Void) {
        self.path = path
        self.deliverQueue = queue
        self.onBatch = onBatch
    }

    deinit { if fd >= 0 { stopOnQueue() } }

    public var stats: Stats { ioQueue.sync { _stats } }

    /// Binds and starts reading. Returns false if the socket can't be bound (bad path, no directory).
    @discardableResult
    public func start() -> Bool {
        ioQueue.sync {
            guard fd < 0 else { return true }
            let newFD = DatagramSocket.bindReceiver(at: path)
            guard newFD >= 0 else { return false }
            _ = fcntl(newFD, F_SETFL, fcntl(newFD, F_GETFL) | O_NONBLOCK)
            var st = stat()
            boundFile = lstat(path, &st) == 0 ? (st.st_dev, st.st_ino) : nil
            fd = newFD

            let src = DispatchSource.makeReadSource(fileDescriptor: newFD, queue: ioQueue)
            src.setEventHandler { [unowned self] in self.drain() }
            src.setCancelHandler { close(newFD) }
            source = src
            src.resume()
            return true
        }
    }

    /// Stops reading, closes the socket and removes its file. Safe to call more than once.
    public func stop() {
        ioQueue.sync { stopOnQueue() }
    }

    private func stopOnQueue() {
        guard fd >= 0 else { return }
        source?.cancel() // closes fd in the cancel handler
        source = nil
        fd = -1
        var st = stat()
        if let b = boundFile, lstat(path, &st) == 0, st.st_dev == b.dev, st.st_ino == b.ino {
            unlink(path)
        }
        boundFile = nil
    }

    /// Reads up to one batch of pending datagrams. If more remain, the source fires again.
    private func drain() {
        guard fd >= 0 else { return }
        var batch: [WireEvent] = []
        batch.reserveCapacity(64)
        let cap = buffer.count
        while batch.count < Limits.listenerBatch {
            let n = buffer.withUnsafeMutableBytes { recv(fd, $0.baseAddress, cap, MSG_DONTWAIT) }
            guard n > 0 else { break }
            if n <= WireCodec.maxReceiveBytes,
               let e = WireCodec.decode(Data(bytes: buffer, count: n)) {
                batch.append(e)
            } else {
                _stats.dropped += 1
            }
        }
        guard !batch.isEmpty else { return }
        _stats.received += batch.count
        let deliver = onBatch, events = batch
        deliverQueue.async { deliver(events) }
    }
}
