/// A character's appearance, derived deterministically from its project folder name.
/// Port of the prototype's `lookFor` (docs/design/sprites-and-poses.md#looks).
public struct Look: Equatable, Hashable, Sendable {
    public enum HairStyle: String, CaseIterable, Sendable { case short, spiky, cap, beanie, long, bun, curly }
    public enum Accessory: String, CaseIterable, Sendable { case none, shades, headphones }
    public enum Pattern: String, CaseIterable, Sendable { case plain, stripe, pocket, hood }
    public enum Rest: String, CaseIterable, Sendable { case coffee, sleep }
    public enum DeskItem: String, CaseIterable, Sendable { case mug, plant, duck, stack }

    public var skin, hair, shirt, pants, shoe, cap: RGB
    public var style: HairStyle
    public var acc: Accessory
    public var pattern: Pattern
    public var rest: Rest
    public var desk: DeskItem

    // Derived shades.
    public var skinD, hairD, hairL, shirtD, shirtL, pantsD, capD, capL, blush: RGB
}

/// Palettes from the prototype. Order and duplicates matter (they weight the picks).
public enum Palette {
    public static let skin = ["#FFD9BC", "#F3BE92", "#D8976A", "#AE7048", "#7C4B2E"].map(RGB.init)
    public static let hair = ["#2B2140", "#5A3825", "#A0522D", "#F2C95B", "#FF77A8", "#3AA7FF", "#8E7CC3", "#EDEAF5", "#E4572E", "#1F8A70", "#2B2140"].map(RGB.init)
    public static let shirt = ["#FF004D", "#29ADFF", "#00C853", "#FFA300", "#7E2553", "#FF77A8", "#83769C", "#2E8B72", "#FFD23F", "#4A5BD4", "#E86A33"].map(RGB.init)
    public static let pants = ["#1D2B53", "#3B3355", "#5F574F", "#2F4858", "#6B4A3A"].map(RGB.init)
    public static let shoes = ["#2A2140", "#5A3825", "#F4F0E8", "#C93A3A", "#2A2140"].map(RGB.init)
    public static let styles: [Look.HairStyle] = [.short, .spiky, .cap, .beanie, .long, .bun, .curly]
    public static let accessories: [Look.Accessory] = [.none, .none, .shades, .headphones, .none, .none]
    public static let patterns: [Look.Pattern] = [.plain, .stripe, .pocket, .hood, .plain]
    public static let desks: [Look.DeskItem] = [.mug, .plant, .duck, .mug, .stack]

    public static let outline = RGB("#1A1330")
    public static let highlight = RGB("#FFF6DA")
    public static let blushTint = RGB("#FF5C8A")
}

public enum LookGenerator {
    public static func look(for name: String) -> Look {
        var r = XorShift32(seed: LookHash.fnv1a(name) &+ 11)
        _ = r.next(); _ = r.next()
        let skin = r.pick(Palette.skin)
        let hair = r.pick(Palette.hair)
        let style = r.pick(Palette.styles)
        var acc = r.pick(Palette.accessories)
        let shirt = r.pick(Palette.shirt)
        let pants = r.pick(Palette.pants)
        let shoe = r.pick(Palette.shoes)
        var cap = r.pick(Palette.shirt)
        let pattern = r.pick(Palette.patterns)
        let rest: Look.Rest = r.next() < 0.5 ? .coffee : .sleep
        let desk = r.pick(Palette.desks)

        if cap == shirt {
            let i = Palette.shirt.firstIndex(of: shirt)!
            cap = Palette.shirt[(i + 3) % Palette.shirt.count]
        }
        if (style == .cap || style == .beanie) && acc == .headphones { acc = .none }

        return Look(
            skin: skin, hair: hair, shirt: shirt, pants: pants, shoe: shoe, cap: cap,
            style: style, acc: acc, pattern: pattern, rest: rest, desk: desk,
            skinD: skin.shade(-0.13), hairD: hair.shade(-0.28), hairL: hair.shade(0.28),
            shirtD: shirt.shade(-0.26), shirtL: shirt.shade(0.32), pantsD: pants.shade(-0.3),
            capD: cap.shade(-0.3), capL: cap.shade(0.38), blush: skin.mix(Palette.blushTint, 0.38)
        )
    }
}
