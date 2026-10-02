import CoreGraphics
import Foundation
import Testing
@testable import AgentvilleCore

/// PixelCanvas → CGImage: nearest-neighbour, integer scales only (docs/architecture/app.md#rendering).
@Suite("Pixel images")
struct PixelImageTests {
    static func checker() -> PixelCanvas {
        var c = PixelCanvas(width: 3, height: 2)
        c.dot(0, 0, RGB("#FF004D"))
        c.dot(2, 0, RGB("#29ADFF"))
        c.dot(1, 1, RGB("#00C853"))
        return c
    }

    @Test func scaledCopiesEachPixelAsABlock() {
        let s = Self.checker().scaled(by: 3)
        #expect(s.width == 9 && s.height == 6)
        for y in 0..<6 {
            for x in 0..<9 {
                #expect(s.color(x: x, y: y) == Self.checker().color(x: x / 3, y: y / 3), "(\(x),\(y))")
            }
        }
    }

    @Test func scaleBelowOneIsOne() {
        #expect(Self.checker().scaled(by: 0) == Self.checker())
        #expect(Self.checker().scaled(by: 1) == Self.checker())
    }

    @Test func cgImageHasTheScaledSizeAndExactBytes() throws {
        let c = Self.checker()
        let img = try #require(PixelImage.cgImage(c, scale: 2))
        #expect(img.width == 6 && img.height == 4)
        #expect(img.bitsPerPixel == 32 && img.bitsPerComponent == 8)
        #expect(img.shouldInterpolate == false)
        let data = try #require(img.dataProvider?.data) as Data
        let want = c.scaled(by: 2).rgbaBytes
        // Rows may be padded; compare row by row.
        for y in 0..<img.height {
            let row = Array(data[(y * img.bytesPerRow)..<(y * img.bytesPerRow + img.width * 4)])
            #expect(row == Array(want[(y * img.width * 4)..<((y + 1) * img.width * 4)]), "row \(y)")
        }
    }

    @Test func transparentPixelsStayTransparent() throws {
        let img = try #require(PixelImage.cgImage(PixelCanvas(width: 2, height: 2), scale: 1))
        let data = try #require(img.dataProvider?.data) as Data
        #expect(data.prefix(16).allSatisfy { $0 == 0 })
        #expect(img.alphaInfo == .premultipliedLast)
    }
}
