import Foundation
import Testing
@testable import AgentvilleCore

/// Bug 0001 (docs/bugs/0001-grey-screen-overlay.md): a full-screen overlay that stops drawing must
/// not stay on screen. The watchdog decides when to take it off and when to try it again.
@Suite("Overlay watchdog")
struct OverlayWatchdogTests {
    @Test("Frames keep coming: nothing to do")
    func healthy() {
        var w = OverlayWatchdog()
        w.awake(at: 0)
        for i in 1...300 {
            let t = Double(i) / 60
            #expect(w.frame(at: t) == nil)
            #expect(w.check(at: t) == nil)
        }
        #expect(w.stalls == 0)
    }

    @Test("A grace period after waking: no frame yet is not a stall")
    func grace() {
        var w = OverlayWatchdog()
        w.awake(at: 10)
        #expect(w.check(at: 10 + Timing.overlayStall - 0.01) == nil)
        #expect(w.check(at: 10 + Timing.overlayStall + 0.01) == .hide)
    }

    @Test("No frames for the stall time: hide, then retry with a doubling backoff up to the cap")
    func backoff() {
        var w = OverlayWatchdog()
        w.awake(at: 0)
        var t = 0.0
        var waits: [Double] = []
        for _ in 0..<8 {
            // Stalled while shown: hidden once the stall time passes.
            t += Timing.overlayStall + 0.01
            #expect(w.check(at: t) == .hide)
            #expect(!w.visible)
            // Waits off screen, then tries again.
            let hiddenAt = t
            while w.check(at: t) != .show { t += 0.25 }
            waits.append(t - hiddenAt)
            #expect(w.visible)
        }
        #expect(waits[0] >= Timing.overlayRetryFirst && waits[0] < Timing.overlayRetryFirst + 0.3)
        #expect(waits[1] >= 2 * Timing.overlayRetryFirst)
        #expect(waits.last! >= Timing.overlayRetryMax && waits.last! < Timing.overlayRetryMax + 0.3)
        #expect(w.stalls == 8)
    }

    @Test("A frame while hidden brings it straight back and clears the backoff")
    func recovers() {
        var w = OverlayWatchdog()
        w.awake(at: 0)
        #expect(w.check(at: 3) == .hide)
        #expect(w.frame(at: 3.5) == .show)
        #expect(w.visible)
        #expect(w.frame(at: 3.6) == nil)
        #expect(w.stalls == 0)
        // Healthy again: the next stall starts the backoff from the beginning.
        #expect(w.check(at: 3.6 + Timing.overlayStall + 0.01) == .hide)
        #expect(w.check(at: 3.6 + Timing.overlayStall + Timing.overlayRetryFirst + 0.02) == .show)
    }

    @Test("Asleep (crew home, overlay off screen on purpose): never acts")
    func asleep() {
        var w = OverlayWatchdog()
        #expect(w.check(at: 100) == nil)
        w.awake(at: 0)
        w.asleep()
        #expect(w.check(at: 100) == nil)
        #expect(w.frame(at: 100) == nil)
    }
}

@Suite("Diagnostics")
struct DiagnosticsTests {
    let utc = TimeZone(identifier: "UTC")!

    @Test("Lines carry a wall-clock time, oldest first")
    func lines() {
        var d = Diagnostics(timeZone: utc)
        d.log("overlay wake (release)", at: Date(timeIntervalSince1970: 45_296.123))
        d.log("overlay sleep", at: Date(timeIntervalSince1970: 45_300))
        #expect(d.lines == ["12:34:56.123 overlay wake (release)", "12:35:00.000 overlay sleep"])
        #expect(d.text == "12:34:56.123 overlay wake (release)\n12:35:00.000 overlay sleep\n")
    }

    @Test("Bounded: keeps the newest lines and counts the rest")
    func bounded() {
        var d = Diagnostics(capacity: 3, timeZone: utc)
        for i in 0..<10 { d.log("line \(i)", at: Date(timeIntervalSince1970: Double(i))) }
        #expect(d.lines.count == 3)
        #expect(d.lines.map { String($0.split(separator: " ", maxSplits: 1)[1]) } == ["line 7", "line 8", "line 9"])
        #expect(d.dropped == 7)
        #expect(d.text.hasPrefix("(7 older lines dropped)\n"))
    }

    @Test("The default capacity is the documented cap")
    func defaultCap() {
        var d = Diagnostics(timeZone: utc)
        for i in 0..<(Limits.diagnosticsLines + 50) { d.log("\(i)", at: Date(timeIntervalSince1970: 0)) }
        #expect(d.lines.count == Limits.diagnosticsLines)
    }
}
