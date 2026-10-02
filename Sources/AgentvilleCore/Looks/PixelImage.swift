import CoreGraphics
import Foundation

extension PixelCanvas {
    /// Nearest-neighbour upscale: each pixel becomes a k×k block. Scales below 1 count as 1.
    public func scaled(by k: Int) -> PixelCanvas {
        guard k > 1 else { return self }
        var out = PixelCanvas(width: width * k, height: height * k)
        out.draw(self, x: 0, y: 0, scale: k)
        return out
    }
}

/// PixelCanvas → `CGImage` for AppKit and SpriteKit (docs/architecture/app.md#rendering).
/// The image is pre-scaled by an integer factor (pass the display's backing scale × points per
/// pixel), so nothing downstream has to interpolate; `shouldInterpolate` is off as a second guard.
/// CoreGraphics only: Core stays free of AppKit.
public enum PixelImage {
    private static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    public static func cgImage(_ canvas: PixelCanvas, scale: Int = 1) -> CGImage? {
        let c = canvas.scaled(by: scale)
        guard c.width > 0, c.height > 0,
              let provider = CGDataProvider(data: Data(c.rgbaBytes) as CFData) else { return nil }
        // Alpha is only ever 0 or 255, so straight and premultiplied bytes are identical.
        return CGImage(width: c.width, height: c.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: c.width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
