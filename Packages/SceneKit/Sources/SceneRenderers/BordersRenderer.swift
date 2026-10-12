import Foundation
import SceneThemes
import SceneFoundation

/// JankyBorders colors: the theme's own border colors, or else the focused window's border in the accent color and
/// the others in the border color. Two colors make a gradient from the top left to the bottom right.
public enum BordersRenderer {
    /// Arguments for `borders`: `0xAARRGGBB` values, or `gradient(…)` of two of them.
    public static func arguments(_ v: ResolvedVariant) -> [String] {
        let active = v.borders?.active ?? [v.interface.accent], inactive = v.borders?.inactive ?? [v.interface.border]
        return ["active_color=\(value(active))", "inactive_color=\(value(inactive))"]
    }

    /// The `borders` line for bordersrc, a shell script. A gradient's parentheses need quotes there.
    public static func scriptLine(_ v: ResolvedVariant) -> String {
        (["borders"] + arguments(v).map { $0.contains("(") ? "'\($0)'" : $0 }).joined(separator: " ")
    }

    static func value(_ colors: [RGBA]) -> String {
        func hex(_ c: RGBA) -> String { String(format: "0x%02x", c.a) + c.hexStripped }
        return colors.count == 2 ? "gradient(top_left=\(hex(colors[0])),bottom_right=\(hex(colors[1])))" : hex(colors[0])
    }

    /// The last `active_color` and `inactive_color` a bordersrc sets, as arguments for `borders`. Plain colors,
    /// gradients, and glows count, with or without quotes; anything else is left out.
    public static func colors(in script: String) -> [String] {
        let color = "0x[0-9A-Fa-f]{8}", corner = "(?:top_left|top_right|bottom_left|bottom_right)"
        let value = "\(color)|gradient\\(\(corner)=\(color),\(corner)=\(color)\\)|glow\\(\(color)\\)"
        return ["active_color", "inactive_color"].compactMap { key in
            guard let regex = try? NSRegularExpression(pattern: "\\b\(key)=(\(value))(?![0-9A-Za-z_(])") else { return nil }
            let range = NSRange(script.startIndex..., in: script)
            guard let match = regex.matches(in: script, range: range).last, let found = Range(match.range(at: 1), in: script) else { return nil }
            return "\(key)=\(script[found])"
        }
    }
}
