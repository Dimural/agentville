import Foundation

/// Where the app listens and the hook sends (docs/decisions/0005-socket-location.md).
public enum SocketPath {
    public static let fileName = "agentville.sock"
    public static let overrideEnv = "AGENTVILLE_SOCKET"
    /// `sun_path` is 104 bytes on Darwin, including the terminating NUL.
    public static let maxPathBytes = 103

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        if let override = environment[overrideEnv], !override.isEmpty {
            return override.utf8.count <= maxPathBytes ? override : nil
        }
        guard let dir = darwinUserTempDir() else { return nil }
        let path = (dir.hasSuffix("/") ? dir : dir + "/") + fileName
        return path.utf8.count <= maxPathBytes ? path : nil
    }

    /// `confstr(_CS_DARWIN_USER_TEMP_DIR)`: per-user, private, cleared on reboot, and the same for every
    /// process the user launches (unlike `$TMPDIR`).
    static func darwinUserTempDir() -> String? {
        let len = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard len > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: len)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, len) > 0 else { return nil }
        let bytes = buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
