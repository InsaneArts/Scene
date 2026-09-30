import Foundation
import SceneThemes
import SceneFoundation

/// Renders a Helix theme (TOML). Every value is a formatted `RGBA` or a fixed modifier name.
public enum HelixRenderer {
    public static let name = "scene"

    public static func themeFile(_ v: ResolvedVariant) -> String {
        let ui = v.interface, s = v.syntax, bg = ui.background
        func q(_ c: RGBA) -> String { "\"\(c.hex)\"" }
        func style(fg: RGBA? = nil, bg: RGBA? = nil, _ modifiers: String...) -> String {
            var parts: [String] = []
            if let fg { parts.append("fg = \(q(fg))") }
            if let bg { parts.append("bg = \(q(bg))") }
            if !modifiers.isEmpty { parts.append("modifiers = [" + modifiers.map { "\"\($0)\"" }.joined(separator: ", ") + "]") }
            return "{ " + parts.joined(separator: ", ") + " }"
        }
        func syntax(_ st: SyntaxStyle) -> String {
            let modifiers = [st.bold ? "bold" : nil, st.italic ? "italic" : nil].compactMap { $0 }
            guard !modifiers.isEmpty || st.underline else { return q(st.color) }
            var parts = ["fg = \(q(st.color))"]
            if !modifiers.isEmpty { parts.append("modifiers = [" + modifiers.map { "\"\($0)\"" }.joined(separator: ", ") + "]") }
            if st.underline { parts.append("underline = { style = \"line\" }") }
            return "{ " + parts.joined(separator: ", ") + " }"
        }
        func curl(_ c: RGBA) -> String { "{ underline = { color = \(q(c)), style = \"curl\" } }" }
        let entries: [(String, String)] = [
            ("ui.background", style(bg: bg)), ("ui.text", q(ui.foreground)), ("ui.text.focus", style(fg: ui.foreground, "bold")),
            ("ui.cursor", style(fg: bg, bg: ui.cursor.mixed(over: bg, amount: 0.6))), ("ui.cursor.primary", style(fg: bg, bg: ui.cursor)),
            ("ui.cursor.match", style(bg: ui.selection, "bold")),
            ("ui.selection", style(bg: ui.selection.mixed(over: bg, amount: 0.6))), ("ui.selection.primary", style(bg: ui.selection)),
            ("ui.linenr", q(ui.muted.mixed(over: bg, amount: 0.7))), ("ui.linenr.selected", style(fg: ui.foreground, "bold")),
            ("ui.cursorline.primary", style(bg: ui.currentLine)), ("ui.gutter", style(bg: bg)), ("ui.highlight", style(bg: ui.currentLine)),
            ("ui.statusline", style(fg: ui.foreground, bg: ui.surface)), ("ui.statusline.inactive", style(fg: ui.muted, bg: ui.surface)),
            ("ui.statusline.normal", style(fg: v.textOnAccent, bg: ui.accent, "bold")),
            ("ui.statusline.insert", style(fg: bg, bg: ui.success, "bold")), ("ui.statusline.select", style(fg: bg, bg: ui.warning, "bold")),
            ("ui.bufferline", style(fg: ui.muted, bg: ui.surface)), ("ui.bufferline.active", style(fg: ui.foreground, bg: bg, "bold")),
            ("ui.popup", style(fg: ui.foreground, bg: ui.overlay)), ("ui.window", q(ui.border)), ("ui.help", style(fg: ui.foreground, bg: ui.overlay)),
            ("ui.menu", style(fg: ui.foreground, bg: ui.overlay)), ("ui.menu.selected", style(fg: ui.foreground, bg: ui.selection)),
            ("ui.virtual.whitespace", q(ui.border)), ("ui.virtual.ruler", style(bg: ui.surface)), ("ui.virtual.indent-guide", q(ui.border)),
            ("ui.virtual.inlay-hint", q(ui.muted)),
            ("error", q(ui.error)), ("warning", q(ui.warning)), ("info", q(ui.info)), ("hint", q(ui.muted)),
            ("diagnostic.error", curl(ui.error)), ("diagnostic.warning", curl(ui.warning)),
            ("diagnostic.info", curl(ui.info)), ("diagnostic.hint", curl(ui.muted)),
            ("comment", syntax(s.comment)), ("keyword", syntax(s.keyword)), ("operator", syntax(s.operator)),
            ("punctuation", syntax(s.punctuation)), ("string", syntax(s.string)), ("constant.character.escape", syntax(s.escape)),
            ("constant.numeric", syntax(s.number)), ("constant", syntax(s.constant)), ("function", syntax(s.function)),
            ("constructor", syntax(s.type)), ("type", syntax(s.type)), ("type.builtin", syntax(s.builtin)),
            ("variable", syntax(s.variable)), ("variable.builtin", syntax(s.builtin)), ("variable.parameter", syntax(s.parameter)),
            ("variable.other.member", syntax(s.property)), ("tag", syntax(s.tag)), ("attribute", syntax(s.attribute)),
            ("namespace", syntax(s.type)), ("label", syntax(s.tag)), ("special", syntax(s.escape)),
            ("markup.heading", style(fg: s.keyword.color, "bold")), ("markup.bold", style("bold")), ("markup.italic", style("italic")),
            ("markup.link.url", "{ fg = \(q(ui.accent)), underline = { style = \"line\" } }"), ("markup.link.text", q(ui.accent)), ("markup.raw", q(s.string.color)),
            ("markup.list", q(s.keyword.color)), ("markup.quote", q(s.comment.color)),
            ("diff.plus", q(s.added.color)), ("diff.minus", q(s.removed.color)), ("diff.delta", q(s.changed.color)),
        ]
        let header = "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file."
        return ([header] + entries.map { "\"\($0.0)\" = \($0.1)" }).joined(separator: "\n") + "\n"
    }
}
