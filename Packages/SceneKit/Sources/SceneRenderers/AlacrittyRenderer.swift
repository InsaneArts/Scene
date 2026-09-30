import Foundation
import SceneThemes
import SceneFoundation

/// Renders an Alacritty color file (TOML). Only color tables are written, and every value is a formatted `RGBA`.
public enum AlacrittyRenderer {
    public static func themeFile(_ v: ResolvedVariant) -> String {
        let t = v.terminal, ui = v.interface
        func q(_ c: RGBA) -> String { "\"\(c.hex)\"" }
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        var lines = [
            "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file.",
            "[colors.primary]", "background = \(q(t.background))", "foreground = \(q(t.foreground))", "",
            "[colors.cursor]", "text = \(q(t.cursorText))", "cursor = \(q(t.cursor))", "",
            "[colors.vi_mode_cursor]", "text = \(q(t.cursorText))", "cursor = \(q(ui.accent))", "",
            "[colors.selection]", "text = \(q(t.selectionForeground))", "background = \(q(t.selectionBackground))", "",
            "[colors.search.matches]", "foreground = \(q(ui.foreground))", "background = \(q(ui.search))", "",
            "[colors.search.focused_match]", "foreground = \(q(v.textOnAccent))", "background = \(q(ui.accent))", "",
            "[colors.footer_bar]", "foreground = \(q(ui.foreground))", "background = \(q(ui.surface))", "",
            "[colors.hints.start]", "foreground = \(q(v.textOnAccent))", "background = \(q(ui.accent))", "",
            "[colors.hints.end]", "foreground = \(q(ui.foreground))", "background = \(q(ui.overlay))", "",
            "[colors.normal]",
        ]
        lines += names.enumerated().map { "\($0.element) = \(q(t.ansi[$0.offset]))" }
        lines += ["", "[colors.bright]"]
        lines += names.enumerated().map { "\($0.element) = \(q(t.ansi[$0.offset + 8]))" }
        return lines.joined(separator: "\n") + "\n"
    }
}
