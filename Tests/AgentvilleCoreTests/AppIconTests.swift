import Testing
@testable import AgentvilleCore

@Suite("App icon")
struct AppIconTests {
    let c = AppIcon.canvas()

    @Test("64×64, transparent corners and margin, an ink ring round an opaque tile")
    func shape() {
        #expect(c.width == 64 && c.height == 64)
        for (x, y) in [(0, 0), (63, 63), (6, 6), (57, 6), (3, 32), (60, 32)] { #expect(!c.isOpaque(x: x, y: y), "\(x),\(y)") }
        #expect(c.color(x: 32, y: 6) == AppIcon.ink)
        #expect(c.color(x: 6, y: 32) == AppIcon.ink)
        #expect(c.color(x: 9, y: 20) == AppIcon.orange)
        // Fully opaque inside the ring.
        for y in 8...55 { for x in 12...51 { #expect(c.isOpaque(x: x, y: y)) } }
    }

    @Test("Shows the welcome character, and is stable")
    func character() {
        let avatar = SpriteRenderer.avatar(LookGenerator.look(for: AppIcon.character))
        let x = (64 - avatar.width * 3) / 2, y = 55 - avatar.height * 3 + 1
        for ay in 0..<avatar.height {
            for ax in 0..<avatar.width {
                guard let px = avatar.color(x: ax, y: ay) else { continue }
                #expect(c.color(x: x + ax * 3 + 1, y: y + ay * 3 + 1) == px)
            }
        }
        #expect(AppIcon.canvas() == c)
    }
}
