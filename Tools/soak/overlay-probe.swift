// overlay-probe: watches Agentville overlays for bug 0001 (docs/bugs/0001-grey-screen-overlay.md).
// Built and run by scripts/soak-overlay.sh; a dev tool, not part of the app.
//
// Usage: overlay-probe --pids 123,456 --seconds 600 --interval 1 --out DIR
//
// Every interval, for each pid: finds its overlay (the full-screen window just below the menu bar),
// captures only that window with `screencapture -l`, and measures the share of opaque pixels. A
// normal frame is about 0–5% opaque (the crew, bubbles, HUD); the bug would show as ~100%. Frames
// over the threshold are kept in DIR with the time; the rest are deleted. Prints one line per check
// and a summary. Needs Screen Recording permission for the terminal that runs it.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

var pids: [Int32] = []
var seconds = 600.0, interval = 1.0, threshold = 0.5
var out = NSTemporaryDirectory()
var it = CommandLine.arguments.dropFirst().makeIterator()
while let a = it.next() {
    switch a {
    case "--pids": pids = (it.next() ?? "").split(separator: ",").compactMap { Int32($0) }
    case "--seconds": seconds = Double(it.next() ?? "") ?? seconds
    case "--interval": interval = Double(it.next() ?? "") ?? interval
    case "--threshold": threshold = Double(it.next() ?? "") ?? threshold
    case "--out": out = it.next() ?? out
    default: break
    }
}
guard !pids.isEmpty else { print("usage: overlay-probe --pids P1,P2 [--seconds S] [--interval I] [--out DIR]"); exit(2) }

let overlayLevel = Int(CGWindowLevelForKey(.mainMenuWindow)) - 1
let screen = NSScreen.screens.first?.frame.size ?? .zero

/// The pid's overlay window, if it's on screen.
func overlayWindow(_ pid: Int32) -> CGWindowID? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return nil }
    for w in list {
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
              (w[kCGWindowLayer as String] as? Int) == overlayLevel,
              let b = w[kCGWindowBounds as String] as? [String: Double],
              b["Width"] == Double(screen.width), b["Height"] == Double(screen.height),
              let id = w[kCGWindowNumber as String] as? UInt32 else { continue }
        return id
    }
    return nil
}

/// Share of pixels with alpha ≥ 250, sampling every 3rd pixel in both directions.
func opaqueShare(_ url: URL) -> Double? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    var opaque = 0, total = 0
    for y in stride(from: 0, to: h, by: 3) {
        for x in stride(from: 0, to: w, by: 3) {
            total += 1
            if buf[(y * w + x) * 4 + 3] >= 250 { opaque += 1 }
        }
    }
    return total == 0 ? nil : Double(opaque) / Double(total)
}

func capture(_ id: CGWindowID, to url: URL) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-x", "-o", "-l\(id)", "-t", "png", url.path]
    do { try p.run(); p.waitUntilExit() } catch { return false }
    return p.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
}

let stamp = DateFormatter()
stamp.dateFormat = "HH:mm:ss"
var checks = 0, captured = 0, flagged = 0, worst = 0.0
let end = Date().addingTimeInterval(seconds)
while Date() < end {
    for pid in pids {
        guard kill(pid, 0) == 0 else { continue }
        checks += 1
        guard let id = overlayWindow(pid) else { continue }
        let t = stamp.string(from: Date())
        let url = URL(fileURLWithPath: out).appendingPathComponent("overlay-\(pid)-\(t.replacingOccurrences(of: ":", with: "")).png")
        guard capture(id, to: url), let share = opaqueShare(url) else { continue }
        captured += 1
        worst = max(worst, share)
        if share >= threshold {
            flagged += 1
            print("\(t) pid \(pid) OPAQUE \(String(format: "%.1f", share * 100))% kept \(url.path)")
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
    fflush(stdout)
    Thread.sleep(forTimeInterval: interval)
}
print("overlay-probe: \(captured) captures, \(flagged) mostly opaque, most opaque \(String(format: "%.2f", worst * 100))%")
exit(flagged > 0 ? 1 : 0)
