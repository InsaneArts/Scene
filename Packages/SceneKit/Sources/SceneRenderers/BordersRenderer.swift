import Foundation
import SceneThemes
import SceneFoundation

/// JankyBorders colors: the focused window's border in the accent color, the others in the border color.
public enum BordersRenderer {
    /// Arguments for `borders`, as `0xAARRGGBB` values.
    public static func arguments(_ v: ResolvedVariant) -> [String] {
        ["active_color=0xff\(v.interface.accent.hexStripped)", "inactive_color=0xff\(v.interface.border.hexStripped)"]
    }

    /// The last `active_color` and `inactive_color` a bordersrc sets, when they are plain `0xAARRGGBB` values.
    public static func colors(in script: String) -> [String] {
        ["active_color", "inactive_color"].compactMap { key in
            guard let regex = try? NSRegularExpression(pattern: "\\b\(key)=(0x[0-9A-Fa-f]{8})\\b") else { return nil }
            let range = NSRange(script.startIndex..., in: script)
            guard let match = regex.matches(in: script, range: range).last, let value = Range(match.range(at: 1), in: script) else { return nil }
            return "\(key)=\(script[value])"
        }
    }
}
