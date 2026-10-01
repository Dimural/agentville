/// Exact ports of the prototype's `hash` and `rng` (docs/design/sprites-and-poses.md#looks).
public enum LookHash {
    /// 32-bit FNV-1a over UTF-16 code units (JS `charCodeAt`), as an unsigned 32-bit value.
    public static func fnv1a(_ s: String) -> UInt32 {
        var h: UInt32 = 2_166_136_261
        for unit in s.utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        return h
    }
}

/// Port of the prototype's xorshift32 `rng(seed)`: returns values in [0, 1) with 5-digit resolution.
public struct XorShift32: Sendable {
    private var s: UInt32

    public init(seed: UInt32) { s = seed == 0 ? 1 : seed }

    public mutating func next() -> Double {
        s ^= s << 13
        s ^= s >> 17
        s ^= s << 5
        return Double(s % 100_000) / 100_000
    }

    /// `a[Math.floor(r() * a.length)]`
    public mutating func pick<T>(_ a: [T]) -> T {
        a[Int((next() * Double(a.count)).rounded(.down))]
    }
}
