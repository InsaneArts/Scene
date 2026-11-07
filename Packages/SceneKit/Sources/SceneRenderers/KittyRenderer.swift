import Foundation
import SceneThemes
import SceneFoundation

/// Renders a kitty color file. Only color options are written, and every value is a formatted `RGBA`.
///
/// It sets every macOS color option that kitty's own themes set (except the rare `color16` and up), because
/// an option Scene leaves out keeps the value from the user's previous theme, such as a titlebar in that theme's color.
public enum KittyRenderer {
    public static func themeFile(_ v: ResolvedVariant) -> String {
        let t = v.terminal, ui = v.interface
        // Marks highlight text that matches a pattern. Kitty's defaults are teal, cream, and pink.
        let marks = [t.ansi[6], t.ansi[3], t.ansi[5]]
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
            "tab_bar_margin_color \(ui.surface.hex)",
            "macos_titlebar_color \(t.background.hex)",
            "cursor_trail_color \(t.cursor.hex)",
            // With no color set, kitty flashes the selection color.
            "visual_bell_color \(t.selectionBackground.hex)",
        ]
        for (index, mark) in marks.enumerated() {
            lines.append("mark\(index + 1)_foreground \(readableText(on: mark, preferred: t.background).hex)")
            lines.append("mark\(index + 1)_background \(mark.hex)")
        }
        for (index, color) in t.ansi.enumerated() { lines.append("color\(index) \(color.hex)") }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Text on `color`: `preferred` when it reads well, otherwise black or white.
    static func readableText(on color: RGBA, preferred: RGBA) -> RGBA {
        if preferred.contrast(with: color) >= 4.5 { return preferred }
        return color.luminance > 0.18 ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 255, g: 255, b: 255)
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
