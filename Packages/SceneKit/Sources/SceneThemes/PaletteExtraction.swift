import CoreGraphics
import Foundation
import ImageIO

/// A palette that starts from pictures. A port of `Scripts/palette-from-image.py`: k-means in OKLab on a small copy
/// of each image, then the background from the picture's darkest (or lightest) third, the accent from a vivid color
/// that stands apart from it, and each hue from the picture when it has one near its usual angle.
public enum PaletteExtraction {
    public struct Result: Sendable, Equatable {
        public var recipe: PaletteRecipe
        /// Vivid colors of the picture that could be the accent, best first.
        public var accents: [OKLCH]
    }

    struct Cluster { var l, c, h, share: Double }

    public static func palette(from images: [URL], appearance: Appearance) -> Result? {
        let found = clusters(images.flatMap(pixels))
        return found.isEmpty ? nil : derive(found, appearance)
    }

    /// About this many pixels per image are enough for the main colors, and keep a click on the button quick.
    static let samples = 4000

    // MARK: Pixels and clusters

    /// OKLab values of about `samples` pixels, from a copy of the image no larger than 120 px.
    static func pixels(_ url: URL) -> [SIMD3<Double>] {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 120,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        let step = max(1, width * height / samples) * 4
        return stride(from: 0, to: bytes.count, by: step).map { i in
            let lab = RGBA(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2]).oklab
            return SIMD3(lab.l, lab.a, lab.b)
        }
    }

    /// k-means++ with a fixed seed, so a picture always gives the same palette.
    static func clusters(_ points: [SIMD3<Double>], k: Int = 12, iterations: Int = 12) -> [Cluster] {
        guard points.count >= k * 4 else { return [] }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(1 << 53)
        }
        func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double { let d = a - b; return (d * d).sum() }
        var centers = [points[Int(random() * Double(points.count)) % points.count]]
        var nearest = points.map { distance($0, centers[0]) }
        while centers.count < k {
            let total = nearest.reduce(0, +)
            var target = random() * total, index = 0
            while index < points.count - 1, target > nearest[index] { target -= nearest[index]; index += 1 }
            centers.append(points[index])
            for i in points.indices { nearest[i] = min(nearest[i], distance(points[i], points[index])) }
        }
        var labels = [Int](repeating: 0, count: points.count)
        for _ in 0..<iterations {
            var sums = [SIMD3<Double>](repeating: .zero, count: k), counts = [Int](repeating: 0, count: k)
            for (i, point) in points.enumerated() {
                var best = 0, bestDistance = Double.infinity
                for (j, center) in centers.enumerated() {
                    let d = distance(point, center)
                    if d < bestDistance { bestDistance = d; best = j }
                }
                labels[i] = best
                sums[best] += point
                counts[best] += 1
            }
            for j in 0..<k where counts[j] > 0 { centers[j] = sums[j] / Double(counts[j]) }
        }
        var counts = [Int](repeating: 0, count: k)
        for label in labels { counts[label] += 1 }
        return centers.enumerated().compactMap { j, center in
            guard counts[j] > 0 else { return nil }
            let c = (center.y * center.y + center.z * center.z).squareRoot()
            let h = (atan2(center.z, center.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            return Cluster(l: center.x, c: c, h: h, share: Double(counts[j]) / Double(points.count))
        }
    }

    // MARK: Deriving the recipe

    /// The signed shortest turn from hue a to hue b, in degrees.
    static func gap(_ a: Double, _ b: Double) -> Double {
        ((b - a + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) - 180
    }

    /// The chroma- and share-weighted circular mean hue of the clusters, and their mean chroma.
    static func meanHue(_ colors: [Cluster]) -> (h: Double, c: Double) {
        let x = colors.reduce(0) { $0 + $1.c * $1.share * cos($1.h * .pi / 180) }
        let y = colors.reduce(0) { $0 + $1.c * $1.share * sin($1.h * .pi / 180) }
        let weight = max(colors.reduce(0) { $0 + $1.share }, 1e-9)
        return ((atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360), colors.reduce(0) { $0 + $1.c * $1.share } / weight)
    }

    static func derive(_ colors: [Cluster], _ appearance: Appearance) -> Result {
        let dark = appearance == .dark
        // The background: the darkest (or lightest) third of the picture, tinted as the picture is.
        var groundColors: [Cluster] = [], total = 0.0
        for color in colors.sorted(by: { dark ? $0.l < $1.l : $0.l > $1.l }) {
            groundColors.append(color)
            total += color.share
            if total >= 0.33 { break }
        }
        let tint = meanHue(groundColors)
        let groundL = groundColors.reduce(0) { $0 + $1.l * $1.share } / max(total, 1e-9)
        let ground = dark ? OKLCH(min(max(groundL, 0.15), 0.23), min(tint.c * 0.6, 0.05), tint.h)
                          : OKLCH(min(max(groundL, 0.94), 0.975), min(tint.c * 0.5, 0.03), tint.h)
        // The accent: a vivid color that covers some of the picture and stands apart from the background.
        let vivid = colors.filter { $0.c > 0.05 && $0.l > 0.3 && $0.l < 0.97 }
            .sorted { a, b in
                func score(_ x: Cluster) -> Double { x.c * pow(x.share, 0.35) * (1 + 0.8 * abs(gap(tint.h, x.h)) / 180) }
                return score(a) > score(b)
            }
        let accentLightness = dark ? 0.8 : 0.55
        let accents = vivid.prefix(4).map { OKLCH(accentLightness, min(max($0.c, 0.1), 0.19), $0.h) }
        let accent = accents.first ?? OKLCH(accentLightness, 0.1, tint.h)
        // The hues: the picture's own near their usual angle, otherwise the usual angle turned a little toward the accent.
        let order = PaletteRecipe.hueOrder, angles = PaletteRecipe.angles
        var reach: [String: Double] = [:]
        for (i, role) in order.enumerated() {
            let before = angles[order[(i + order.count - 1) % order.count]]!, after = angles[order[(i + 1) % order.count]]!
            let own = angles[role]!
            reach[role] = min((own - before + 360).truncatingRemainder(dividingBy: 360), (after - own + 360).truncatingRemainder(dividingBy: 360)) / 2 - 8
        }
        var hues: [String: PaletteRecipe.HueChoice] = [:]
        for role in order {
            let angle = angles[role]!
            let near = colors.filter { $0.c >= 0.035 && abs(gap(angle, $0.h)) <= 32 }
            if !near.isEmpty {
                let mean = meanHue(near)
                let turned = angle + max(-reach[role]!, min(reach[role]!, gap(angle, mean.h)))
                hues[role] = .init(angle: (turned + 360).truncatingRemainder(dividingBy: 360), chroma: min(max(mean.c, 0.08), 0.17))
            } else {
                let turn = max(-12, min(12, gap(angle, accent.h) * 0.2))
                hues[role] = .init(angle: (angle + turn + 360).truncatingRemainder(dividingBy: 360), chroma: dark ? 0.085 : 0.1)
            }
        }
        // Neighbours pulled toward the same color would look alike in code: push them apart again.
        for _ in 0..<3 {
            for (i, role) in order.enumerated() {
                let after = order[(i + 1) % order.count]
                let wanted = min((angles[after]! - angles[role]! + 360).truncatingRemainder(dividingBy: 360), 42)
                let short = wanted - gap(hues[role]!.angle, hues[after]!.angle)
                if short > 0 {
                    hues[role]!.angle = (hues[role]!.angle - short / 2 + 360).truncatingRemainder(dividingBy: 360)
                    hues[after]!.angle = (hues[after]!.angle + short / 2 + 360).truncatingRemainder(dividingBy: 360)
                }
            }
        }
        return Result(recipe: PaletteRecipe(appearance: appearance, ground: ground, accent: accent, hues: hues), accents: Array(accents))
    }
}
