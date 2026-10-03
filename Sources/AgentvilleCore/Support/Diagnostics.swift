import Foundation

/// The app's diagnostics: a bounded, in-memory list of short lines (`Limits.diagnosticsLines`),
/// never written to disk (non-negotiable #8). Lines describe what the app did (the overlay woke,
/// slept, stalled), never what a session sent. The user can copy them from the status menu.
public struct Diagnostics: Sendable {
    public let capacity: Int
    /// Oldest first.
    public private(set) var lines: [String] = []
    /// Lines pushed out by newer ones.
    public private(set) var dropped = 0
    private let formatter: DateFormatter

    public init(capacity: Int = Limits.diagnosticsLines, timeZone: TimeZone = .current) {
        self.capacity = max(1, capacity)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "HH:mm:ss.SSS"
        formatter = f
    }

    /// Adds a line stamped with the wall-clock time, so it can be matched with a screenshot or the
    /// system log.
    public mutating func log(_ message: String, at date: Date = Date()) {
        if lines.count >= capacity {
            lines.removeFirst(lines.count - capacity + 1)
            dropped += 1
        }
        lines.append(formatter.string(from: date) + " " + message)
    }

    /// Everything, one line each, for the clipboard.
    public var text: String {
        (dropped > 0 ? "(\(dropped) older lines dropped)\n" : "") + lines.map { $0 + "\n" }.joined()
    }
}
