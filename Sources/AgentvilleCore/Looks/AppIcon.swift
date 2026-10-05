/// The app's icon (Finder, the login items list, the welcome window's title bar): the welcome
/// character's head and shoulders, from `SpriteRenderer.avatar`, on a rounded orange tile with an
/// ink ring. Original art (non-negotiable #12), drawn on a 64×64 pixel grid and scaled up
/// nearest-neighbour for each icon size by `agentville-icon` (scripts/bundle-app.sh).
public enum AppIcon {
    public static let size = 64
    /// The tile leaves a margin, like macOS icons (about 52 of 64).
    public static let tile = (min: 6, max: 57)
    /// The character the welcome window shows.
    public static let character = "agentville"

    static let ink = RGB(0x1A1330), orange = RGB(0xFFA300), light = RGB(0xFFC94D), shade = RGB(0xE08A00)

    public static func canvas() -> PixelCanvas {
        var c = PixelCanvas(width: size, height: size)
        let lo = tile.min, hi = tile.max, r = 7
        // A rounded square, stepped like pixel art: each row inset by its distance into the corner.
        for y in lo...hi {
            let dy = max(0, max(lo + r - y, y - (hi - r)))
            let inset = dy == 0 ? 0 : r - Int((Double(r * r - dy * dy)).squareRoot().rounded())
            c.fill(lo + inset, y, hi - lo + 1 - 2 * inset, 1, ink)
        }
        for y in (lo + 2)...(hi - 2) {
            let dy = max(0, max(lo + 2 + (r - 2) - y, y - (hi - 2 - (r - 2))))
            let rr = r - 2
            let inset = dy == 0 ? 0 : rr - Int((Double(rr * rr - dy * dy)).squareRoot().rounded())
            let color = y < lo + 6 ? light : (y > hi - 9 ? shade : orange)
            c.fill(lo + 2 + inset, y, hi - lo - 3 - 2 * inset, 1, color)
        }
        // The character, three pixels per sprite pixel, standing on the tile's lower edge.
        let avatar = SpriteRenderer.avatar(LookGenerator.look(for: character))
        let s = 3
        let x = (size - avatar.width * s) / 2, y = hi - 2 - avatar.height * s + 1
        c.draw(avatar, x: x, y: y, scale: s)
        return c
    }
}
