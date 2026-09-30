import Foundation
import SceneThemes
import SceneFoundation

/// Renders a Zed theme family (schema v0.2.0) with "Scene Dark" and "Scene Light".
/// Both names are always present, so a setting that names either one keeps resolving.
public enum ZedRenderer {
    public static let names: [Appearance: String] = [.dark: "Scene Dark", .light: "Scene Light"]

    public static func themeFile(variants: [Appearance: ResolvedVariant]) throws -> Data {
        guard let fallback = variants[.dark] ?? variants[.light] else { throw SceneError.invalid("no variant to render") }
        let themes: [[String: Any]] = Appearance.allCases.reversed().map { slot in
            let v = variants[slot] ?? fallback
            return ["name": names[slot]!, "appearance": v.appearance.rawValue, "style": style(v)]
        }
        let json: [String: Any] = ["$schema": "https://zed.dev/schema/themes/v0.2.0.json", "name": "Scene", "author": "Scene", "themes": themes]
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    static func style(_ v: ResolvedVariant) -> [String: Any] {
        let ui = v.interface, t = v.terminal, s = v.syntax, bg = ui.background
        func c(_ color: RGBA) -> String { color.hexWithAlpha }
        func a(_ color: RGBA, _ alpha: Double) -> String { color.with(alpha: alpha).hexWithAlpha }
        let clear = "#00000000"
        var style: [String: Any] = [
            "background": c(ui.surface), "surface.background": c(ui.surface), "elevated_surface.background": c(ui.overlay),
            "panel.background": c(ui.surface), "panel.focused_border": c(ui.accent), "pane.focused_border": c(ui.accent),
            "border": c(ui.border), "border.variant": c(ui.border.mixed(over: bg, amount: 0.6)), "border.focused": c(ui.accent),
            "border.selected": c(ui.accent), "border.transparent": clear, "border.disabled": c(ui.border.mixed(over: bg, amount: 0.5)),
            "element.background": c(ui.overlay), "element.hover": c(ui.currentLine), "element.active": c(ui.selection),
            "element.selected": c(ui.selection), "element.disabled": c(ui.surface),
            "ghost_element.background": clear, "ghost_element.hover": c(ui.currentLine), "ghost_element.active": c(ui.selection),
            "ghost_element.selected": c(ui.selection), "ghost_element.disabled": clear,
            "drop_target.background": a(ui.accent, 0.25),
            "text": c(ui.foreground), "text.muted": c(ui.muted), "text.placeholder": c(ui.muted.mixed(over: bg, amount: 0.8)),
            "text.disabled": c(ui.muted.mixed(over: bg, amount: 0.6)), "text.accent": c(ui.accent),
            "icon": c(ui.foreground), "icon.muted": c(ui.muted), "icon.disabled": c(ui.muted.mixed(over: bg, amount: 0.6)),
            "icon.placeholder": c(ui.muted), "icon.accent": c(ui.accent),
            "status_bar.background": c(ui.surface), "title_bar.background": c(ui.surface), "title_bar.inactive_background": c(ui.surface),
            "toolbar.background": c(bg), "tab_bar.background": c(ui.surface), "tab.inactive_background": c(ui.surface), "tab.active_background": c(bg),
            "search.match_background": a(ui.search, 0.6), "link_text.hover": c(ui.accent),
            "scrollbar.thumb.background": a(ui.muted, 0.3), "scrollbar.thumb.hover_background": a(ui.muted, 0.45),
            "scrollbar.thumb.border": clear, "scrollbar.track.background": clear, "scrollbar.track.border": clear,
            "editor.background": c(bg), "editor.foreground": c(ui.foreground), "editor.gutter.background": c(bg),
            "editor.subheader.background": c(ui.surface), "editor.active_line.background": c(ui.currentLine),
            "editor.highlighted_line.background": c(ui.currentLine),
            "editor.line_number": c(ui.muted.mixed(over: bg, amount: 0.7)), "editor.active_line_number": c(ui.foreground),
            "editor.invisible": c(ui.border), "editor.wrap_guide": a(ui.border, 0.5), "editor.active_wrap_guide": c(ui.border),
            "editor.indent_guide": c(ui.border), "editor.indent_guide_active": c(ui.muted),
            "editor.document_highlight.read_background": a(ui.selection, 0.5), "editor.document_highlight.write_background": a(ui.selection, 0.7),
            "terminal.background": c(t.background), "terminal.foreground": c(t.foreground),
            "terminal.bright_foreground": c(t.ansi[15]), "terminal.dim_foreground": c(t.foreground.mixed(over: t.background, amount: 0.7)),
        ]
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        for (i, name) in names.enumerated() {
            style["terminal.ansi.\(name)"] = c(t.ansi[i])
            style["terminal.ansi.bright_\(name)"] = c(t.ansi[i + 8])
            style["terminal.ansi.dim_\(name)"] = c(t.ansi[i].mixed(over: t.background, amount: 0.7))
        }
        let statuses: [(String, RGBA)] = [
            ("error", ui.error), ("warning", ui.warning), ("success", ui.success), ("info", ui.info), ("hint", ui.muted),
            ("created", s.added.color), ("deleted", s.removed.color), ("modified", s.changed.color), ("conflict", ui.warning),
            ("renamed", ui.info), ("hidden", ui.muted), ("ignored", ui.muted), ("predictive", ui.muted), ("unreachable", ui.muted),
        ]
        for (name, color) in statuses {
            style[name] = c(color)
            style["\(name).background"] = a(color, 0.15)
            style["\(name).border"] = a(color, 0.5)
        }
        // Zed takes editor selections and cursors from the first player.
        style["players"] = [[ "cursor": c(ui.cursor), "background": c(ui.accent), "selection": c(ui.selection) ]]
            + [t.ansi[2], t.ansi[5], t.ansi[3], t.ansi[6], t.ansi[1]].map { ["cursor": c($0), "background": c($0), "selection": a($0, 0.25)] }
        style["syntax"] = syntax(v)
        return style
    }

    static func syntax(_ v: ResolvedVariant) -> [String: Any] {
        let s = v.syntax, ui = v.interface
        func entry(_ style: SyntaxStyle, bold: Bool = false, italic: Bool = false) -> [String: Any] {
            var out: [String: Any] = ["color": style.color.hexWithAlpha]
            out["font_style"] = (style.italic || italic) ? "italic" : NSNull()
            out["font_weight"] = (style.bold || bold) ? 700 : NSNull()
            return out
        }
        func plain(_ color: RGBA, italic: Bool = false) -> [String: Any] { entry(SyntaxStyle(color: color), italic: italic) }
        return [
            "attribute": entry(s.attribute), "boolean": entry(s.constant), "comment": entry(s.comment), "comment.doc": entry(s.comment),
            "constant": entry(s.constant), "constructor": entry(s.function), "embedded": plain(ui.foreground),
            "emphasis": plain(ui.accent, italic: true), "emphasis.strong": entry(SyntaxStyle(color: ui.accent), bold: true),
            "enum": entry(s.type), "function": entry(s.function), "hint": plain(ui.muted), "keyword": entry(s.keyword),
            "label": entry(s.tag), "link_text": plain(ui.accent), "link_uri": entry(SyntaxStyle(color: ui.accent, underline: true)),
            "number": entry(s.number), "operator": entry(s.operator), "predictive": plain(ui.muted, italic: true),
            "preproc": entry(s.attribute), "primary": plain(ui.foreground), "property": entry(s.property),
            "punctuation": entry(s.punctuation), "punctuation.bracket": entry(s.punctuation), "punctuation.delimiter": entry(s.punctuation),
            "punctuation.list_marker": entry(s.punctuation), "punctuation.special": entry(s.escape),
            "string": entry(s.string), "string.escape": entry(s.escape), "string.regex": entry(s.escape), "string.special": entry(s.escape),
            "string.special.symbol": entry(s.constant), "tag": entry(s.tag), "text.literal": entry(s.string),
            "title": entry(s.keyword, bold: true), "type": entry(s.type), "type.builtin": entry(s.builtin),
            "variable": entry(s.variable), "variable.special": entry(s.builtin), "variable.parameter": entry(s.parameter),
            "variant": entry(s.constant),
        ]
    }

    /// The value of `theme` in Zed's settings.json. Without a forced appearance, Zed follows macOS.
    public static func setting(forced: Appearance?) -> JSONValue {
        .object([JSONMember("mode", .string(forced?.rawValue ?? "system")),
                 JSONMember("light", .string(names[.light]!)), JSONMember("dark", .string(names[.dark]!))])
    }
}
