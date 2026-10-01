import Darwin
import Foundation

/// Minimal AF_UNIX / SOCK_DGRAM helpers. Local-only by construction: there is no code path that
/// creates an internet socket (enforced by scripts/check-no-network.sh).
public enum DatagramSocket {
    /// Fire-and-forget send. Never blocks, never retries, never reports errors.
    /// Returns true if the kernel accepted the datagram (used only by tests).
    @discardableResult
    public static func send(_ data: Data, to path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        guard var addr = makeAddress(path) else { return false }
        let sent = data.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, MSG_DONTWAIT, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
        return sent == data.count
    }

    /// Binds a receiving datagram socket at `path`, replacing a stale file. Returns the fd or -1.
    /// Used by the app's SocketListener and by tests.
    public static func bindReceiver(at path: String, receiveBuffer: Int32 = 1 << 20) -> Int32 {
        guard var addr = makeAddress(path) else { return -1 }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return -1 }
        var size = receiveBuffer
        setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        let ok = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { close(fd); return -1 }
        chmod(path, 0o600)
        return fd
    }

    /// Reads one datagram (non-blocking). Returns nil when nothing is pending.
    public static func receive(fd: Int32, maxBytes: Int = WireCodec.maxReceiveBytes + 1) -> Data? {
        var buf = [UInt8](repeating: 0, count: maxBytes)
        let n = recv(fd, &buf, maxBytes, MSG_DONTWAIT)
        guard n > 0 else { return nil }
        return Data(buf[0..<n])
    }

    static func makeAddress(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }
}
