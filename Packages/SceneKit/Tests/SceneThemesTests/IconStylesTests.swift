import Foundation
@testable import SceneThemes
import Testing

@Suite("Icon styles")
struct IconStylesTests {
    /// A 64 px icon: a plate inside an 8 px clear margin, and a square glyph in the middle.
    static func icon(plate: RGBA, glyph: RGBA) -> IconStyles.Pixels {
        let n = 64
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for y in 8..<56 {
            for x in 8..<56 {
                let color = (24..<40).contains(x) && (24..<40).contains(y) ? glyph : plate
                bytes.replaceSubrange((y * n + x) * 4..<(y * n + x) * 4 + 4, with: [color.r, color.g, color.b, 255])
            }
        }
        return IconStyles.Pixels(size: n, bytes: bytes)
    }

    static func pixel(_ image: IconStyles.Pixels, _ x: Int, _ y: Int) -> RGBA {
        let i = (y * image.size + x) * 4
        return RGBA(r: image.bytes[i], g: image.bytes[i + 1], b: image.bytes[i + 2], a: image.bytes[i + 3])
    }

    @Test func aWhiteGlyphOnAColoredPlateTakesThePlatesColor() throws {
        let blue = try #require(RGBA(hex: "#1e7bf2"))
        let (dark, glyph) = IconStyles.derive(Self.icon(plate: blue, glyph: RGBA(r: 255, g: 255, b: 255)))
        let plate = OKLCH(Self.pixel(dark, 16, 16)), mark = OKLCH(Self.pixel(dark, 32, 32))
        #expect(plate.l < 0.35 && plate.c < 0.02, "the plate goes dark gray: \(plate)")
        #expect(mark.c > 0.1 && abs(mark.h - OKLCH(blue).h) < 10, "the envelope turns blue: \(mark)")
        #expect(Self.pixel(dark, 2, 2).a == 0)
        // For Clear and Tinted: only the glyph, and bright, because it was white.
        #expect(Self.pixel(glyph, 32, 32).a == 255 && Self.pixel(glyph, 32, 32).r > 230)
        #expect(Self.pixel(glyph, 16, 16).a == 0 && Self.pixel(glyph, 9, 32).a == 0)
    }

    @Test func aColoredGlyphOnALightPlateKeepsItsColor() throws {
        let red = try #require(RGBA(hex: "#e5484d"))
        let (dark, glyph) = IconStyles.derive(Self.icon(plate: RGBA(r: 245, g: 245, b: 245), glyph: red))
        #expect(OKLCH(Self.pixel(dark, 16, 16)).l < 0.35)
        #expect(Self.pixel(dark, 32, 32) == red)
        #expect(Self.pixel(glyph, 32, 32).a == 255 && Self.pixel(glyph, 16, 16).a == 0)
    }

    @Test func anEmptyImageComesBackAsItIs() {
        let empty = IconStyles.Pixels(size: 8, bytes: [UInt8](repeating: 0, count: 256))
        #expect(IconStyles.derive(empty).dark == empty)
    }
}
