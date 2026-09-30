import Foundation
import SceneThemes
import SceneFoundation

/// Renders a Warp custom theme (YAML). Every value is a quoted, formatted `RGBA` or a fixed word.
public enum WarpRenderer {
    public static let names: [Appearance: String] = [.dark: "Scene Dark", .light: "Scene Light"]
    public static let fileNames: [Appearance: String] = [.dark: "scene_dark.yaml", .light: "scene_light.yaml"]

    public static func themeFile(_ v: ResolvedVariant, name: String) -> String {
        let t = v.terminal
        func q(_ c: RGBA) -> String { "'\(c.hex)'" }
        let colors = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        var lines = [
            "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file.",
            "name: '\(name)'",
            "accent: \(q(v.interface.accent))",
            "cursor: \(q(t.cursor))",
            "background: \(q(t.background))",
            "foreground: \(q(t.foreground))",
            // Warp draws borders and overlays darker than the background for a dark theme, lighter for a light one.
            "details: \(v.appearance == .dark ? "darker" : "lighter")",
            "terminal_colors:",
            "  normal:",
        ]
        lines += colors.enumerated().map { "    \($0.element): \(q(t.ansi[$0.offset]))" }
        lines.append("  bright:")
        lines += colors.enumerated().map { "    \($0.element): \(q(t.ansi[$0.offset + 8]))" }
        return lines.joined(separator: "\n") + "\n"
    }
}
