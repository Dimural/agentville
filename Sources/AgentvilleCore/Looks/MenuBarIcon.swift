/// The menu bar's pixel head. Port of the `mbIcon` pattern in the prototype's `paintIcons`.
/// Drawn in one colour; the app uses it as a template image so macOS tints it for the menu bar.
public enum MenuBarIcon {
    public static let pattern = ["..#####..", ".#######.", "##.....##", "#..#.#..#", "#.......#",
                                 ".#.###.#.", "..#####..", ".#.....#.", "#.......#"]

    public static let head: PixelCanvas = {
        var c = PixelCanvas(width: 9, height: 9)
        for (y, row) in pattern.enumerated() {
            for (x, ch) in row.enumerated() where ch == "#" { c.dot(x, y, RGB(r: 0, g: 0, b: 0)) }
        }
        return c
    }()
}
