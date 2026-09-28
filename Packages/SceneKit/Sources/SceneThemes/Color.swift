import Foundation
import SceneFoundation

/// An sRGB color with 8-bit channels. Every theme color becomes one of these at load time,
/// so no color string from a theme ever reaches a config file.
public struct RGBA: Hashable, Sendable, CustomStringConvertible {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`. Nothing else is accepted.
    public init?(hex: String) {
        guard hex.utf8.count == 7 || hex.utf8.count == 9, hex.first == "#" else { return nil }
        var value: UInt64 = 0
        for character in hex.dropFirst() {
            guard character.isASCII, let digit = character.hexDigitValue else { return nil }
            value = value << 4 | UInt64(digit)
        }
        if hex.utf8.count == 7 {
            self.init(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
        } else {
            self.init(r: UInt8(value >> 24 & 0xFF), g: UInt8(value >> 16 & 0xFF), b: UInt8(value >> 8 & 0xFF), a: UInt8(value & 0xFF))
        }
    }

    /// `#rrggbb` (alpha dropped).
    public var hex: String { String(format: "#%02x%02x%02x", r, g, b) }
    /// `#rrggbbaa`.
    public var hexWithAlpha: String { String(format: "#%02x%02x%02x%02x", r, g, b, a) }
    /// `rrggbb` without `#`.
    public var hexStripped: String { String(format: "%02x%02x%02x", r, g, b) }
    public var description: String { a == 255 ? hex : hexWithAlpha }

    public var red: Double { Double(r) / 255 }
    public var green: Double { Double(g) / 255 }
    public var blue: Double { Double(b) / 255 }
    public var alpha: Double { Double(a) / 255 }

    public func with(alpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: UInt8((max(0, min(1, alpha)) * 255).rounded()))
    }

    /// Mixes `self` over `background`: `amount` 1 gives `self`, 0 gives `background`. Result is opaque.
    public func mixed(over background: RGBA, amount: Double) -> RGBA {
        let t = max(0, min(1, amount))
        func channel(_ top: UInt8, _ bottom: UInt8) -> UInt8 {
            UInt8((Double(top) * t + Double(bottom) * (1 - t)).rounded())
        }
        return RGBA(r: channel(r, background.r), g: channel(g, background.g), b: channel(b, background.b))
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio between two opaque colors (1...21).
    public func contrast(with other: RGBA) -> Double {
        let (l1, l2) = (luminance, other.luminance)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    public var isDark: Bool { luminance < 0.18 }

    /// Hue in degrees (0..<360), saturation and lightness in 0...1.
    public var hsl: (h: Double, s: Double, l: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        switch maxC {
        case red: h = (green - blue) / d + (green < blue ? 6 : 0)
        case green: h = (blue - red) / d + 2
        default: h = (red - green) / d + 4
        }
        h *= 60
        return (h, s, l)
    }
}
