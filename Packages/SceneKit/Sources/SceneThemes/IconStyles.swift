import Foundation

/// An app icon in the Dark, Clear, and Tinted styles, worked out from its Default icon. macOS renders these styles
/// with a private framework, so the Theme Maker's Dock makes its own: the plate (the icon's background) goes dark,
/// and a glyph lighter than a colored plate takes the plate's color, as macOS draws Mail's white envelope blue.
public enum IconStyles {
    /// Premultiplied sRGB pixels, 4 bytes each, top row first.
    public struct Pixels: Sendable, Equatable {
        public var size: Int
        public var bytes: [UInt8]
        public init(size: Int, bytes: [UInt8]) { self.size = size; self.bytes = bytes }
    }

    /// The icon in the Dark style, and its glyph for Clear and Tinted: a gray whose lightness is the glyph's tone,
    /// with the glyph's coverage in alpha. A view multiplies the glyph by the style's color.
    public static func derive(_ icon: Pixels) -> (dark: Pixels, glyph: Pixels) {
        let n = icon.size, src = icon.bytes
        func alpha(_ x: Int, _ y: Int) -> UInt8 { x < 0 || y < 0 || x >= n || y >= n ? 0 : src[(y * n + x) * 4 + 3] }
        func pixel(_ i: Int) -> (color: RGBA, alpha: Double) {
            let a = Double(src[i * 4 + 3]) / 255
            func channel(_ k: Int) -> UInt8 { a > 0 ? UInt8(min(255, (Double(src[i * 4 + k]) / a).rounded())) : 0 }
            return (RGBA(r: channel(0), g: channel(1), b: channel(2)), a)
        }

        // The plate's color, from a ring just inside the icon's box, away from its rounded corners. When a third of
        // the ring has color (Finder is half blue, half white), the plate is the colored part.
        var minX = n, maxX = 0, minY = n, maxY = 0
        for y in 0..<n { for x in 0..<n where alpha(x, y) > 128 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } }
        guard maxX > minX, maxY > minY else { return (icon, Pixels(size: n, bytes: [UInt8](repeating: 0, count: src.count))) }
        let width = Double(maxX - minX), height = Double(maxY - minY)
        let inset = Int(width * 0.06), rim = max(2, Int(width * 0.035))
        var ring: [OKLCH] = []
        for t in stride(from: 0.25, through: 0.75, by: 0.01) {
            let x = minX + Int(width * t), y = minY + Int(height * t)
            for (px, py) in [(x, minY + inset), (x, maxY - inset), (minX + inset, y), (maxX - inset, y)] { ring.append(OKLCH(pixel(py * n + px).color)) }
        }
        let vivid = ring.filter { $0.c > 0.06 }, colored = Double(vivid.count) >= Double(ring.count) * 0.3
        let plate = mean(colored ? vivid : ring.filter { $0.c <= 0.06 })

        var dark = [UInt8](repeating: 0, count: src.count), glyph = dark
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                let (color, a) = pixel(i)
                guard a > 0 else { continue }
                let p = OKLCH(color)
                var rgb = (color.red, color.green, color.blue)
                var isPlate: Double
                if colored {
                    let sameHue = p.c > 0.02 ? smooth(40, 20, hueGap(p.h, plate.h)) : 0
                    isPlate = sameHue * smooth(0.3 * plate.c, 0.6 * plate.c, p.c) * smooth(0.15, 0.08, abs(p.l - plate.l))
                    let recolor = smooth(0.04, 0.12, p.l - plate.l) * max(sameHue, smooth(0.1, 0.04, p.c))
                    if recolor > 0 {
                        let target = OKLCH(min(0.82, plate.l + 0.06 + 0.4 * (p.l - 0.9)), plate.c * 1.08, plate.h).rgba
                        rgb = (rgb.0 + (target.red - rgb.0) * recolor, rgb.1 + (target.green - rgb.1) * recolor, rgb.2 + (target.blue - rgb.2) * recolor)
                    }
                } else {
                    isPlate = smooth(0.08, 0.04, p.c) * smooth(0.2, 0.1, abs(p.l - plate.l))
                }
                // The lit rim along the icon's edge belongs to the plate.
                if alpha(x - rim, y) < 128 || alpha(x + rim, y) < 128 || alpha(x, y - rim) < 128 || alpha(x, y + rim) < 128 { isPlate = 1 }
                let base = 0.17 - 0.05 * Double(y) / Double(n)   // a dark gray plate, a little lighter at the top
                for (k, v) in [rgb.0, rgb.1, rgb.2].enumerated() {
                    dark[i * 4 + k] = UInt8(min(255, max(0, (v + (base - v) * isPlate) * a * 255)).rounded())
                }
                dark[i * 4 + 3] = src[i * 4 + 3]
                // The glyph's tone comes from the Default icon, so a white glyph stays bright in Tinted and Clear.
                let tone = 0.45 + 0.55 * smooth(0.3, 0.9, p.l), cover = (1 - isPlate) * a
                for k in 0..<3 { glyph[i * 4 + k] = UInt8((tone * cover * 255).rounded()) }
                glyph[i * 4 + 3] = UInt8((cover * 255).rounded())
            }
        }
        return (Pixels(size: n, bytes: dark), Pixels(size: n, bytes: glyph))
    }

    /// The average color, with hues averaged around the circle.
    private static func mean(_ colors: [OKLCH]) -> OKLCH {
        guard !colors.isEmpty else { return OKLCH(0.5, 0, 0) }
        let count = Double(colors.count)
        let a = colors.map { $0.c * cos($0.h * .pi / 180) }.reduce(0, +) / count
        let b = colors.map { $0.c * sin($0.h * .pi / 180) }.reduce(0, +) / count
        return OKLCH(colors.map(\.l).reduce(0, +) / count, (a * a + b * b).squareRoot(), (atan2(b, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360))
    }

    /// 0 at `from`, 1 at `to`, smooth in between. `from` may be the larger one.
    private static func smooth(_ from: Double, _ to: Double, _ x: Double) -> Double {
        let t = max(0, min(1, (x - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    private static func hueGap(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }
}
