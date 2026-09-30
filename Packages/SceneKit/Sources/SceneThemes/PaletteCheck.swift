import Foundation

/// Checks that a look reads well in a terminal and an editor. A port of `Scripts/check-palette.py`:
/// errors are colors people cannot read, and warnings are weak spots worth a second look.
/// The thresholds are WCAG contrast ratios, calibrated on the Omarchy palettes.
public enum PaletteCheck {
    public struct Result: Sendable, Equatable {
        public var errors: [String] = []
        public var warnings: [String] = []
    }

    public static func check(_ v: ResolvedVariant) -> Result {
        var result = Result()
        let ui = v.interface, bg = ui.background, a = v.terminal.ansi
        let light = bg.luminance > 0.4
        func need(_ name: String, _ color: RGBA, on otherName: String, _ other: RGBA, _ minimum: Double, _ good: Double) {
            let ratio = color.contrast(with: other)
            let text = "\(name) \(color.hex) on \(otherName): \(String(format: "%.2f", ratio))"
            if ratio < minimum { result.errors.append("\(text), needs \(minimum)") }
            else if ratio < good { result.warnings.append("\(text), \(good) reads better") }
        }
        need("Text", ui.foreground, on: "Background", bg, 4.5, 7)
        need("Dim text", ui.muted, on: "Background", bg, 2.2, 3)          // comments and line numbers
        need("Accent", ui.accent, on: "Background", bg, 2.5, 3)
        need("Text", ui.foreground, on: "Selection", ui.selection, 3.5, 4.5)
        // A light look prints yellow and cyan darker than a dark look needs.
        let hues: [(String, RGBA)] = [("Red", a[1]), ("Green", a[2]), ("Yellow", a[3]), ("Blue", a[4]), ("Magenta", a[5]), ("Cyan", a[6])]
        for (name, color) in hues { need(name, color, on: "Background", bg, light ? 2 : 3, light ? 3 : 4.5) }
        if ui.selection.contrast(with: bg) < 1.15 { result.warnings.append("Selection \(ui.selection.hex) is hard to see on the background") }
        if ui.border.contrast(with: bg) < 1.3 { result.warnings.append("Borders \(ui.border.hex) are hard to see on the background") }

        let named = [("Red", a[1]), ("Orange", v.syntax.number.color), ("Yellow", a[3]), ("Green", a[2]),
                     ("Cyan", a[6]), ("Blue", a[4]), ("Magenta", a[5])]
        for i in named.indices {
            for j in named.indices where j > i {
                let pair = (named[i].0, named[j].0)
                if pair == ("Red", "Orange") || pair == ("Orange", "Yellow") { continue }
                let distance = named[i].1.oklabDistance(to: named[j].1)
                if distance < 0.06 { result.warnings.append("\(pair.0) and \(pair.1) look alike (\(String(format: "%.3f", distance)))") }
            }
        }
        let grays = named.filter { $0.1.oklabChroma < 0.03 }.map(\.0)
        if !grays.isEmpty { result.warnings.append("No color in \(grays.joined(separator: ", ")). Fine if the theme uses one hue on purpose.") }
        if light != (v.appearance == .light) {
            result.errors.append("The \(v.appearance.rawValue) look has a \(light ? "light" : "dark") background")
        }
        return result
    }
}

extension RGBA {
    /// OKLab, the perceptual space the palette checks measure in.
    var oklab: (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// Perceived difference. About 0.02 is just noticeable.
    func oklabDistance(to other: RGBA) -> Double {
        let (x, y) = (oklab, other.oklab)
        return ((x.l - y.l) * (x.l - y.l) + (x.a - y.a) * (x.a - y.a) + (x.b - y.b) * (x.b - y.b)).squareRoot()
    }

    var oklabChroma: Double { let lab = oklab; return (lab.a * lab.a + lab.b * lab.b).squareRoot() }
}
