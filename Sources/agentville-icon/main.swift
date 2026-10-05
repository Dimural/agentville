// agentville-icon: writes Agentville's icon (`AppIcon`, Core) as an .iconset for `iconutil`.
// Dev and build tool, run by scripts/bundle-app.sh; not part of the app.
//
// Usage: agentville-icon <dir.iconset>
import AgentvilleCore
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: agentville-icon <dir.iconset>\n".utf8)); exit(2)
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let art = AppIcon.canvas()

/// Whole multiples of the 64-pixel art stay crisp; 16 and 32 are drawn down smoothly.
func image(_ px: Int) -> CGImage {
    if px % AppIcon.size == 0 { return PixelImage.cgImage(art, scale: px / AppIcon.size)! }
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(PixelImage.cgImage(art, scale: 4)!, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let dest = CGImageDestinationCreateWithURL(dir.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image(points * scale), nil)
        guard CGImageDestinationFinalize(dest) else { FileHandle.standardError.write(Data("failed: \(name)\n".utf8)); exit(1) }
    }
}
