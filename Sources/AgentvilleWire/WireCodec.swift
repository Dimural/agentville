import Foundation

/// Encodes and decodes `WireEvent` datagrams. Both directions enforce size caps;
/// decode treats input as untrusted (docs/architecture/data-contract.md#app-side-validation-wirecodecdecode).
public enum WireCodec {
    /// The hook never sends more than this; it drops the event instead.
    public static let maxSendBytes = 1024
    /// The app drops anything larger than this without parsing.
    public static let maxReceiveBytes = 2048

    public static func encode(_ event: WireEvent) -> Data? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(event), data.count <= maxSendBytes else { return nil }
        return data
    }

    public static func decode(_ data: Data) -> WireEvent? {
        guard !data.isEmpty, data.count <= maxReceiveBytes,
              let event = try? JSONDecoder().decode(WireEvent.self, from: data)
        else { return nil }
        return event.sanitized()
    }
}
