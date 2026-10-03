import CoreGraphics
import Foundation

/// Turns pixel art (sRGB) into a `CGImage` already in a display's colour space. A layer that gets
/// a fresh image every frame (the desk panel's office, ≈12 fps) otherwise has Core Animation
/// colour-match the whole image each time: measured 2026-10-03, that was half of the open panel's
/// CPU (4.3% → 2.2%; docs/quality/performance-budget.md). Pixel art has a few dozen colours, so each
/// is converted once with CoreGraphics and cached. CoreGraphics only: Core stays free of AppKit.
public final class PixelColorMatcher {
    public let space: CGColorSpace
    private let identity: Bool
    /// 0xFF_RR_GG_BB in sRGB → the same in `space`. Bounded; pixel art never comes close.
    private var cache: [UInt32: UInt32] = [:]
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    public init(space: CGColorSpace) {
        self.space = space
        identity = space.name == CGColorSpace.sRGB
    }

    /// One opaque packed colour (`PixelCanvas.pixels` format) in `space`.
    public func convert(_ p: UInt32) -> UInt32 {
        if identity || p == 0 { return p }
        if let q = cache[p] { return q }
        let src = [CGFloat(p >> 16 & 0xFF) / 255, CGFloat(p >> 8 & 0xFF) / 255, CGFloat(p & 0xFF) / 255, 1]
        var q = p
        if let c = CGColor(colorSpace: Self.srgb, components: src)?.converted(to: space, intent: .defaultIntent, options: nil),
           let k = c.components, k.count >= 3 {
            func byte(_ v: CGFloat) -> UInt32 { UInt32((min(1, max(0, v)) * 255).rounded()) }
            q = 0xFF00_0000 | byte(k[0]) << 16 | byte(k[1]) << 8 | byte(k[2])
        }
        if cache.count >= 4096 { cache.removeAll(keepingCapacity: true) }
        cache[p] = q
        return q
    }

    /// Like `PixelImage.cgImage`, but in `space`.
    public func cgImage(_ canvas: PixelCanvas, scale: Int = 1) -> CGImage? {
        if identity { return PixelImage.cgImage(canvas, scale: scale) }
        let c = canvas.scaled(by: scale)
        guard c.width > 0, c.height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: c.pixels.count * 4)
        var lastIn: UInt32 = 0, lastOut: UInt32 = 0
        c.pixels.withUnsafeBufferPointer { px in
            bytes.withUnsafeMutableBufferPointer { out in
                for i in 0..<px.count {
                    let p = px[i]
                    guard p != 0 else { continue }
                    // Neighbouring pixels are mostly the same colour.
                    if p != lastIn { lastIn = p; lastOut = convert(p) }
                    out[i * 4] = UInt8(lastOut >> 16 & 0xFF)
                    out[i * 4 + 1] = UInt8(lastOut >> 8 & 0xFF)
                    out[i * 4 + 2] = UInt8(lastOut & 0xFF)
                    out[i * 4 + 3] = 255
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        // Alpha is only ever 0 or 255, so straight and premultiplied bytes are identical.
        return CGImage(width: c.width, height: c.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: c.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
