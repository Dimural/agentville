/// A small RGBA pixel buffer with the few canvas operations the prototype's sprite code uses
/// (`fillRect`, `clearRect`, `translate`, and the `outline` pass). Every pixel is either fully
/// transparent or fully opaque, so it renders exactly like the prototype's 2D canvas.
public struct PixelCanvas: Equatable, Sendable {
    public let width: Int, height: Int
    /// Row-major, 0 = transparent, otherwise 0xFF_RR_GG_BB.
    public private(set) var pixels: [UInt32]
    /// Like `ctx.translate`: added to every drawing coordinate.
    public var origin: (x: Int, y: Int) = (0, 0)

    public static func == (a: PixelCanvas, b: PixelCanvas) -> Bool {
        a.width == b.width && a.height == b.height && a.pixels == b.pixels
    }

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = Array(repeating: 0, count: width * height)
    }

    @inline(__always) static func packed(_ c: RGB) -> UInt32 {
        0xFF00_0000 | UInt32(c.r) << 16 | UInt32(c.g) << 8 | UInt32(c.b)
    }

    /// The colour at (x, y), or nil when transparent or out of bounds.
    public func color(x: Int, y: Int) -> RGB? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let p = pixels[y * width + x]
        guard p != 0 else { return nil }
        return RGB(r: UInt8(p >> 16 & 0xFF), g: UInt8(p >> 8 & 0xFF), b: UInt8(p & 0xFF))
    }

    public func isOpaque(x: Int, y: Int) -> Bool { color(x: x, y: y) != nil }

    /// `fillRect` with an opaque colour, clipped to the canvas.
    public mutating func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB) {
        set(x, y, w, h, Self.packed(c))
    }

    /// One pixel (the prototype's `P`).
    public mutating func dot(_ x: Int, _ y: Int, _ c: RGB) { fill(x, y, 1, 1, c) }

    /// `clearRect`, clipped to the canvas.
    public mutating func clear(_ x: Int, _ y: Int, _ w: Int, _ h: Int) { set(x, y, w, h, 0) }

    private mutating func set(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ v: UInt32) {
        let x0 = max(0, x + origin.x), y0 = max(0, y + origin.y)
        let x1 = min(width, x + origin.x + w), y1 = min(height, y + origin.y + h)
        guard x0 < x1, y0 < y1 else { return }
        let w = width, n = x1 - x0
        pixels.withUnsafeMutableBufferPointer { buf in
            for yy in y0..<y1 { (buf.baseAddress! + yy * w + x0).update(repeating: v, count: n) }
        }
    }

    /// `fillRect` with a translucent colour over what's there (canvas source-over), using the same
    /// 8-bit arithmetic as Chrome's raster canvas: alpha byte α = round(a·255), source term
    /// round(c·α/255), destination term (d·(256−α)) >> 8. Golden-tested in `OfficeRendererTests`.
    /// Only drawn over opaque pixels, which is all the prototype does.
    public mutating func blend(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB, alpha: Double) {
        let a = Int((alpha * 255).rounded()), inv = 256 - a
        let sr = (Int(c.r) * a + 127) / 255, sg = (Int(c.g) * a + 127) / 255, sb = (Int(c.b) * a + 127) / 255
        let x0 = max(0, x + origin.x), y0 = max(0, y + origin.y)
        let x1 = min(width, x + origin.x + w), y1 = min(height, y + origin.y + h)
        guard x0 < x1, y0 < y1 else { return }
        for yy in y0..<y1 {
            for xx in x0..<x1 {
                let i = yy * width + xx, d = pixels[i]
                let r = sr + (Int(d >> 16 & 0xFF) * inv) >> 8
                let g = sg + (Int(d >> 8 & 0xFF) * inv) >> 8
                let b = sb + (Int(d & 0xFF) * inv) >> 8
                pixels[i] = 0xFF00_0000 | UInt32(min(255, r)) << 16 | UInt32(min(255, g)) << 8 | UInt32(min(255, b))
            }
        }
    }

    /// `drawImage(src, x, y, w·scale, h·scale)` with smoothing off: opaque source pixels are copied as
    /// scale×scale blocks, transparent ones leave the destination alone. Clipped to the canvas.
    public mutating func draw(_ src: PixelCanvas, x: Int, y: Int, scale: Int = 1) {
        let ox = x + origin.x, oy = y + origin.y, w = width, h = height, sw = src.width
        pixels.withUnsafeMutableBufferPointer { dst in
            src.pixels.withUnsafeBufferPointer { sp in
                for sy in 0..<src.height {
                    for sx in 0..<sw {
                        let p = sp[sy * sw + sx]
                        guard p != 0 else { continue }
                        let bx = ox + sx * scale, by = oy + sy * scale
                        let x0 = max(0, bx), x1 = min(w, bx + scale)
                        guard x0 < x1 else { continue }
                        for yy in max(0, by)..<min(h, by + scale) {
                            (dst.baseAddress! + yy * w + x0).update(repeating: p, count: x1 - x0)
                        }
                    }
                }
            }
        }
    }

    /// Port of `outline(c, col)`: every transparent pixel with an opaque 4-neighbour becomes `col`.
    /// Neighbours are judged on the canvas before this pass, so the outline is exactly 1 px.
    public mutating func outline(_ c: RGB) {
        let v = Self.packed(c), src = pixels
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                guard src[i] == 0 else { continue }
                if (x > 0 && src[i - 1] != 0) || (x < width - 1 && src[i + 1] != 0)
                    || (y > 0 && src[i - width] != 0) || (y < height - 1 && src[i + width] != 0) {
                    pixels[i] = v
                }
            }
        }
    }

    /// A copy of the rectangle (x, y, w, h); pixels outside the canvas come out transparent.
    public func cropped(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> PixelCanvas {
        var out = PixelCanvas(width: w, height: h)
        for yy in 0..<h {
            for xx in 0..<w {
                let sx = x + xx, sy = y + yy
                if sx >= 0, sy >= 0, sx < width, sy < height { out.pixels[yy * w + xx] = pixels[sy * width + sx] }
            }
        }
        return out
    }

    /// RGBA bytes (premultiplied and straight are the same here: alpha is 0 or 255), for CGImage.
    public var rgbaBytes: [UInt8] {
        var out = [UInt8](repeating: 0, count: pixels.count * 4)
        for (i, p) in pixels.enumerated() where p != 0 {
            out[i * 4] = UInt8(p >> 16 & 0xFF)
            out[i * 4 + 1] = UInt8(p >> 8 & 0xFF)
            out[i * 4 + 2] = UInt8(p & 0xFF)
            out[i * 4 + 3] = 255
        }
        return out
    }
}
