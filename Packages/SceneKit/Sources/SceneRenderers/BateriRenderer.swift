import Foundation
import SceneThemes
import SceneFoundation

/// Renders bateri theme files (`themes/NAME.toml`). Only color keys are written, and every value is a formatted `RGBA`.
/// A missing key would come from one of bateri's built-in themes, so the file writes all of them.
public enum BateriRenderer {
    public static let themeNames: [Appearance: String] = [.dark: "scene-dark", .light: "scene-light"]

    /// The keys of bateri's `[ansi]` section, in ANSI order.
    static let ansiKeys = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                           "bright_black", "bright_red", "bright_green", "bright_yellow",
                           "bright_blue", "bright_magenta", "bright_cyan", "bright_white"]

    public static func themeFile(_ v: ResolvedVariant) -> String {
        let t = v.terminal, ui = v.interface
        func line(_ key: String, _ color: RGBA) -> String { "\(key) = \"\(color.hex)\"" }
        var lines = [
            "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file.",
            line("background", t.background),
            line("foreground", t.foreground),
            line("dim", ui.muted),
            line("accent", ui.accent),
            line("cursor", t.cursor),
            line("selection", t.selectionBackground),
            line("search_match", ui.search),
            line("search_current", ui.accent),
            line("success", ui.success),
            line("error", ui.error),
            line("info", ui.info),
            line("warning", ui.warning),
            "",
            "[ansi]",
        ]
        for (key, color) in zip(ansiKeys, t.ansi) { lines.append(line(key, color)) }
        return lines.joined(separator: "\n") + "\n"
    }
}
