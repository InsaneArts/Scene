import Foundation
import SceneThemes
import SceneFoundation

/// Renders a btop theme file: `theme[key]="#rrggbb"` lines.
public enum BtopRenderer {
    public static let name = "scene"

    public static func themeFile(_ v: ResolvedVariant) -> String {
        let ui = v.interface, t = v.terminal
        let red = t.ansi[1], green = t.ansi[2], yellow = t.ansi[3], blue = t.ansi[4], magenta = t.ansi[5], cyan = t.ansi[6]
        func mid(_ a: RGBA, _ b: RGBA) -> RGBA { a.mixed(over: b, amount: 0.5) }
        let keys: [(String, RGBA)] = [
            ("main_bg", ui.background), ("main_fg", ui.foreground), ("title", ui.foreground), ("hi_fg", ui.accent),
            ("selected_bg", ui.selection), ("selected_fg", ui.foreground), ("inactive_fg", ui.muted), ("graph_text", ui.muted),
            ("meter_bg", ui.overlay), ("proc_misc", ui.accent), ("cpu_box", ui.border), ("mem_box", ui.border),
            ("net_box", ui.border), ("proc_box", ui.border), ("div_line", ui.border),
            ("temp_start", green), ("temp_mid", yellow), ("temp_end", red),
            ("cpu_start", green), ("cpu_mid", yellow), ("cpu_end", red),
            ("free_start", mid(green, ui.background)), ("free_mid", green), ("free_end", green),
            ("cached_start", mid(blue, ui.background)), ("cached_mid", blue), ("cached_end", blue),
            ("available_start", mid(cyan, ui.background)), ("available_mid", cyan), ("available_end", cyan),
            ("used_start", mid(red, ui.background)), ("used_mid", red), ("used_end", red),
            ("download_start", mid(blue, ui.background)), ("download_mid", blue), ("download_end", cyan),
            ("upload_start", mid(magenta, ui.background)), ("upload_mid", magenta), ("upload_end", red),
            ("process_start", green), ("process_mid", yellow), ("process_end", red),
        ]
        let header = "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file."
        return ([header] + keys.map { "theme[\($0.0)]=\"\($0.1.hex)\"" }).joined(separator: "\n") + "\n"
    }
}
