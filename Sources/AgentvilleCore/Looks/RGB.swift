import Foundation

/// An sRGB colour with 8-bit channels, plus exact ports of the prototype's `shade` and `mix`.
public struct RGB: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var r: UInt8, g: UInt8, b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

    /// Parses `#RRGGBB` (case-insensitive). Traps on malformed literals: palettes are compile-time constants.
    public init(_ hex: String) {
        precondition(hex.count == 7 && hex.hasPrefix("#"), "bad colour literal \(hex)")
        let n = UInt32(hex.dropFirst(), radix: 16)!
        self.init(r: UInt8(n >> 16), g: UInt8((n >> 8) & 255), b: UInt8(n & 255))
    }

    /// Lower-case `#rrggbb`, matching the prototype's `toHex`.
    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    public var description: String { hex }

    /// JS `toHex`: `Math.round(clamp(v, 0, 255))`. Math.round rounds .5 up (toward +∞).
    static func channel(_ v: Double) -> UInt8 {
        UInt8((min(255, max(0, v)) + 0.5).rounded(.down))
    }

    /// Port of `shade(h, f)`: f < 0 darkens (×(1+f)), f > 0 lightens toward white.
    public func shade(_ f: Double) -> RGB {
        var (rr, gg, bb) = (Double(r), Double(g), Double(b))
        if f < 0 {
            rr *= 1 + f; gg *= 1 + f; bb *= 1 + f
        } else {
            rr += (255 - rr) * f; gg += (255 - gg) * f; bb += (255 - bb) * f
        }
        return RGB(r: Self.channel(rr), g: Self.channel(gg), b: Self.channel(bb))
    }

    /// Port of `mix(a, b, t)`: linear interpolation per channel.
    public func mix(_ other: RGB, _ t: Double) -> RGB {
        func l(_ a: UInt8, _ b: UInt8) -> UInt8 { Self.channel(Double(a) + (Double(b) - Double(a)) * t) }
        return RGB(r: l(r, other.r), g: l(g, other.g), b: l(b, other.b))
    }
}
