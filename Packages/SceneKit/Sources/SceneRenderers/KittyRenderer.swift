import Foundation
import SceneThemes
import SceneFoundation

/// Renders a kitty color file. Only color options are written, and every value is a formatted `RGBA`.
public enum KittyRenderer {
    public static func themeFile(_ v: ResolvedVariant) -> String {
        let t = v.terminal, ui = v.interface
        var lines = [
            "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file.",
            "background \(t.background.hex)",
            "foreground \(t.foreground.hex)",
            "selection_background \(t.selectionBackground.hex)",
            "selection_foreground \(t.selectionForeground.hex)",
            "cursor \(t.cursor.hex)",
            "cursor_text_color \(t.cursorText.hex)",
            "url_color \(ui.accent.hex)",
            "active_border_color \(ui.accent.hex)",
            "inactive_border_color \(ui.border.hex)",
            "bell_border_color \(ui.warning.hex)",
            "tab_bar_background \(ui.surface.hex)",
            "active_tab_background \(ui.accent.hex)",
            "active_tab_foreground \(v.textOnAccent.hex)",
            "inactive_tab_background \(ui.surface.hex)",
            "inactive_tab_foreground \(ui.muted.hex)",
        ]
        for (index, color) in t.ansi.enumerated() { lines.append("color\(index) \(color.hex)") }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension ResolvedVariant {
    /// Text on an accent-colored background: the background color when it reads well, otherwise black or white.
    var textOnAccent: RGBA {
        let ui = interface
        if ui.accent.contrast(with: ui.background) >= 3 { return ui.background }
        return ui.accent.luminance > 0.3 ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 255, g: 255, b: 255)
    }
}
