import CoreGraphics
import Foundation
import Testing
@testable import AgentvilleCore

/// Pixel art handed to a layer every frame in the display's own colour space, so Core Animation
/// needn't colour-match each frame (docs/quality/performance-budget.md: the desk panel at 12 fps).
@Suite("Pixel colour matching")
struct PixelColorMatcherTests {
    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    static func bytes(_ img: CGImage) -> [UInt8] {
        Array(img.dataProvider!.data! as Data)
    }

    @Test("In sRGB it's exactly PixelImage: same bytes, same space")
    func identity() throws {
        let c = PixelImageTests.checker()
        let a = try #require(PixelImage.cgImage(c, scale: 2))
        let b = try #require(PixelColorMatcher(space: Self.srgb).cgImage(c, scale: 2))
        #expect(Self.bytes(a) == Self.bytes(b))
        #expect(b.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test("In Display P3 each colour is converted (sRGB red → P3 234, 51, 35), transparency kept, image tagged P3")
    func displayP3() throws {
        var c = PixelCanvas(width: 3, height: 1)
        c.dot(0, 0, RGB("#FF0000"))
        c.dot(2, 0, RGB("#FFFFFF"))
        let img = try #require(PixelColorMatcher(space: Self.p3).cgImage(c))
        #expect(img.colorSpace?.name == CGColorSpace.displayP3)
        let b = Self.bytes(img)
        #expect(Array(b[0..<4]) == [234, 51, 35, 255])
        #expect(Array(b[4..<8]) == [0, 0, 0, 0])
        #expect(Array(b[8..<12]) == [255, 255, 255, 255])
    }

    @Test("Converted colours look the same: back to sRGB they're within 1.5 steps of the original")
    func roundTrip() throws {
        let m = PixelColorMatcher(space: Self.p3)
        for hex in ["#FF004D", "#29ADFF", "#00E436", "#FFEC27", "#1A1330", "#83769C", "#FFF1E8"] {
            let rgb = RGB(hex)
            let p = m.convert(PixelCanvas.packed(rgb))
            let back = CGColor(colorSpace: Self.p3, components: [CGFloat(p >> 16 & 0xFF) / 255, CGFloat(p >> 8 & 0xFF) / 255,
                                                                CGFloat(p & 0xFF) / 255, 1])!
                .converted(to: Self.srgb, intent: .defaultIntent, options: nil)!.components!
            // P3 is wider than sRGB, so one 8-bit P3 step spans up to ~1.4 sRGB steps: rounding
            // to 8 bits can't do better (nor can Core Animation's own matching on an 8-bit P3 display).
            for (got, want) in zip(back.prefix(3), [rgb.r, rgb.g, rgb.b]) {
                #expect(abs(got * 255 - Double(want)) <= 1.5, "\(hex)")
            }
        }
    }
}
