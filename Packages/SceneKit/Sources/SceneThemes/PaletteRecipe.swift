import Foundation

/// OKLCH: lightness (0 to 1), chroma, and hue in degrees. Steps in it look even, so it is what the Theme Maker's
/// sliders move.
public struct OKLCH: Sendable, Equatable, Codable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(_ l: Double, _ c: Double, _ h: Double) { self.l = l; self.c = c; self.h = h }

    public init(_ color: RGBA) {
        let lab = color.oklab
        l = lab.l
        c = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        h = (atan2(lab.b, lab.a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The sRGB color, with chroma reduced until it fits in sRGB. A port of `from_oklch` in `Scripts/themekit.py`.
    public var rgba: RGBA {
        let l = min(max(self.l, 0), 1)
        var chroma = max(c, 0)
        while true {
            let a = chroma * cos(h * .pi / 180), b = chroma * sin(h * .pi / 180)
            let l3 = pow(l + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m3 = pow(l - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s3 = pow(l - 0.0894841775 * a - 1.2914855480 * b, 3)
            let linear = [4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
                          -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
                          -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3]
            if linear.allSatisfy({ $0 >= -1e-4 && $0 <= 1.0001 }) || chroma <= 0 {
                func channel(_ v: Double) -> UInt8 {
                    let v = max(0, v)
                    let encoded = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
                    return UInt8((min(1, max(0, encoded)) * 255).rounded())
                }
                return RGBA(r: channel(linear[0]), g: channel(linear[1]), b: channel(linear[2]))
            }
            chroma -= 0.002
        }
    }
}

/// The few choices a look's palette follows from, in OKLCH: the background, the text's contrast, the accent, and the
/// seven hues. The Theme Maker's sliders move them, and `colors()` builds the whole palette in Omarchy's keys by the
/// rules Scene's own themes were made with (`build_palette` in `Scripts/themekit.py`).
public struct PaletteRecipe: Sendable, Equatable, Codable {
    public var appearance: Appearance
    /// The background.
    public var ground: OKLCH
    /// The text's lightness. Further from the background reads more easily.
    public var text: Double
    public var accent: OKLCH
    /// The seven hues' lightness and vividness.
    public var level: Double
    public var chroma: Double
    /// Turns every hue around the color circle, in degrees.
    public var shift: Double
    /// A hue's own angle and chroma, when it has one, for example from a wallpaper. Others sit at `angles`.
    public var hues: [String: HueChoice]

    public struct HueChoice: Sendable, Equatable, Codable {
        public var angle: Double
        public var chroma: Double
        public init(angle: Double, chroma: Double) { self.angle = angle; self.chroma = chroma }
    }

    /// Where each hue sits on the OKLCH circle by default.
    public static let angles: [String: Double] = ["red": 27, "orange": 55, "yellow": 92, "green": 145, "cyan": 195, "blue": 255, "magenta": 325]
    public static let hueOrder = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta"]

    /// Slider ranges for each look.
    public struct Ranges: Sendable {
        public let groundLightness: ClosedRange<Double>
        public let groundChroma: ClosedRange<Double> = 0...0.06
        public let text: ClosedRange<Double>
        public let accentChroma: ClosedRange<Double> = 0.03...0.22
        public let accentLightness: ClosedRange<Double>
        public let level: ClosedRange<Double>
        public let chroma: ClosedRange<Double> = 0.02...0.2
        public let shift: ClosedRange<Double> = -40...40
    }

    public static func ranges(_ appearance: Appearance) -> Ranges {
        appearance == .dark
            ? Ranges(groundLightness: 0.1...0.32, text: 0.76...0.97, accentLightness: 0.6...0.9, level: 0.62...0.87)
            : Ranges(groundLightness: 0.88...0.995, text: 0.16...0.42, accentLightness: 0.38...0.66, level: 0.38...0.62)
    }

    public init(appearance: Appearance, ground: OKLCH, text: Double? = nil, accent: OKLCH, level: Double? = nil, chroma: Double? = nil,
                shift: Double = 0, hues: [String: HueChoice] = [:]) {
        let dark = appearance == .dark
        self.appearance = appearance
        self.ground = ground
        self.text = text ?? (dark ? 0.88 : 0.3)
        self.accent = accent
        self.level = level ?? (dark ? 0.77 : 0.52)
        self.chroma = chroma ?? (dark ? 0.12 : 0.14)
        self.shift = shift
        self.hues = hues
    }

    /// A calm starting point for a look.
    public static func starting(_ appearance: Appearance) -> PaletteRecipe {
        appearance == .dark
            ? PaletteRecipe(appearance: .dark, ground: OKLCH(0.2, 0.02, 255), accent: OKLCH(0.8, 0.13, 230))
            : PaletteRecipe(appearance: .light, ground: OKLCH(0.97, 0.01, 90), accent: OKLCH(0.55, 0.16, 255))
    }

    /// The palette, in Omarchy's keys, as `#rrggbb`. With `readable`, a color below the palette check's minimum
    /// contrast moves in lightness, away from what it sits on, until it passes; its hue and chroma stay. So no slider
    /// position makes code unreadable.
    public func colors(readable: Bool = true) -> [String: String] {
        var p = built()
        if readable { Self.makeReadable(&p, appearance) }
        return p
    }

    func built() -> [String: String] {
        let L = ground.l, C = ground.c, H = ground.h, dark = appearance == .dark
        let textHue = H, textChroma = dark ? min(0.03, C + 0.01) : min(0.04, C + 0.015)
        func c(_ l: Double, _ chroma: Double, _ h: Double) -> String { OKLCH(l, chroma, h).rgba.hex }
        var p: [String: String]
        let offsets: [String: Double]
        let brighter: Double
        if dark {
            p = ["background": c(L, C, H), "dark_background": c(L - 0.035, C * 0.9, H),
                 "lighter_background": c(L + 0.045, C * 1.15 + 0.004, H),
                 "selection": c(L + 0.12, max(C, 0.03) + 0.03, accent.h), "muted": c(L + 0.2, C * 1.3 + 0.008, H),
                 // Dim text keeps its place between the background and the text.
                 "dark_foreground": c(0.6 + (text - 0.88) * 0.5, C * 1.3 + 0.012, H),
                 "foreground": c(text, textChroma, textHue), "bright_foreground": c(min(0.99, text + 0.07), textChroma * 0.8, textHue)]
            // Yellow and green look darker than they measure, and red and blue lighter.
            offsets = ["yellow": 0.06, "green": 0.03, "cyan": 0.03, "red": -0.03, "blue": -0.03, "magenta": -0.02, "orange": 0.02]
            brighter = 0.06
        } else {
            p = ["background": c(L, C, H), "dark_background": c(L - 0.03, C * 1.1 + 0.003, H),
                 "lighter_background": c(L - 0.045, C * 1.2 + 0.004, H),
                 "selection": c(L - 0.11, max(C, 0.025) + 0.03, accent.h), "muted": c(L - 0.2, C * 1.2 + 0.008, H),
                 "dark_foreground": c(0.55 + (text - 0.3) * 0.5, C + 0.015, H),
                 "foreground": c(text, textChroma, textHue), "bright_foreground": c(max(0.1, text - 0.08), textChroma, textHue)]
            offsets = ["yellow": 0.04, "green": 0.0, "cyan": -0.01, "red": 0.02, "blue": 0.0, "magenta": 0.03, "orange": 0.03]
            brighter = 0.05
        }
        p["accent"] = accent.rgba.hex
        for role in Self.hueOrder {
            let choice = hues[role] ?? HueChoice(angle: Self.angles[role]!, chroma: chroma)
            // A hue from the wallpaper keeps its own vividness, scaled with the slider.
            let roleChroma = hues[role] == nil ? chroma : choice.chroma * chroma / (dark ? 0.12 : 0.14)
            let angle = (choice.angle + shift + 360).truncatingRemainder(dividingBy: 360)
            p[role] = c(level + offsets[role]!, roleChroma, angle)
            if role != "orange" { p["bright_\(role)"] = c(min(0.97, level + offsets[role]! + brighter), roleChroma + 0.01, angle) }
        }
        return p
    }

    /// Lifts each color over the palette check's error thresholds (`PaletteCheck`), with a small margin.
    static func makeReadable(_ p: inout [String: String], _ appearance: Appearance) {
        let dark = appearance == .dark
        func color(_ key: String) -> RGBA? { p[key].flatMap(RGBA.init(hex:)) }
        /// Moves `key` lighter (`up`) or darker until it holds `minimum` against `other`.
        func adjust(_ key: String, against otherKey: String, _ minimum: Double, up: Bool) {
            guard let start = color(key), let other = color(otherKey) else { return }
            var lch = OKLCH(start), result = start
            for _ in 0..<100 where result.contrast(with: other) < minimum {
                lch.l = min(1, max(0, lch.l + (up ? 0.01 : -0.01)))
                result = lch.rgba
            }
            p[key] = result.hex
        }
        adjust("foreground", against: "background", 4.6, up: dark)
        adjust("selection", against: "foreground", 3.6, up: !dark)
        adjust("dark_foreground", against: "background", 2.3, up: dark)
        adjust("accent", against: "background", 2.6, up: dark)
        for hue in ["red", "green", "yellow", "blue", "magenta", "cyan"] {
            adjust(hue, against: "background", dark ? 3.1 : 2.1, up: dark)
        }
    }

    /// The recipe nearest an existing palette, so a theme opened in the Theme Maker starts where it is.
    public init(fitting colors: [String: String], appearance: Appearance) {
        func lch(_ key: String) -> OKLCH? { colors[key].flatMap(RGBA.init(hex:)).map(OKLCH.init) }
        let starting = Self.starting(appearance)
        let ground = lch("background") ?? starting.ground
        let accent = lch("accent") ?? starting.accent
        var hues: [String: HueChoice] = [:]
        var levels: [Double] = []
        for role in Self.hueOrder {
            guard let color = lch(role) else { continue }
            hues[role] = HueChoice(angle: color.h, chroma: color.c)
            levels.append(color.l)
        }
        let dark = appearance == .dark
        let range = Self.ranges(appearance)
        let mean = { (values: [Double], fallback: Double) in values.isEmpty ? fallback : values.reduce(0, +) / Double(values.count) }
        self.init(appearance: appearance, ground: ground,
                  text: (lch("foreground")?.l).map { min(max($0, range.text.lowerBound), range.text.upperBound) },
                  accent: accent, level: min(max(mean(levels, dark ? 0.77 : 0.52), range.level.lowerBound), range.level.upperBound),
                  chroma: dark ? 0.12 : 0.14, hues: hues)
    }
}

/// A look in the Theme Maker: the recipe its sliders move, and colors set by hand, which win over the recipe.
/// A look opened from a theme shows that theme's exact colors until the first slider moves.
public struct PaletteEdit: Sendable, Equatable {
    public private(set) var recipe: PaletteRecipe
    /// The starting theme's own colors, until a slider moves.
    public private(set) var original: [String: String]?
    /// Colors set by hand, by key.
    public private(set) var pinned: [String: String] = [:]

    public init(recipe: PaletteRecipe) {
        self.recipe = recipe
    }

    public init(colors: [String: String], appearance: Appearance) {
        recipe = PaletteRecipe(fitting: colors, appearance: appearance)
        original = colors
    }

    public var colors: [String: String] {
        (original ?? recipe.colors()).merging(pinned) { $1 }
    }

    /// Moves a slider. The starting theme's own colors give way to the recipe; colors set by hand stay.
    public mutating func slide(_ change: (inout PaletteRecipe) -> Void) {
        original = nil
        change(&recipe)
    }

    /// A new recipe, for example from a wallpaper or a shuffle. Colors set by hand go too.
    public mutating func replace(with recipe: PaletteRecipe) {
        self.recipe = recipe
        original = nil
        pinned = [:]
    }

    /// Sets one color by hand, or gives it back to the recipe with nil.
    public mutating func pin(_ key: String, _ hex: String?) {
        pinned[key] = hex
    }
}
