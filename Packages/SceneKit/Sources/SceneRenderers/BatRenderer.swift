import Foundation
import SceneThemes
import SceneFoundation

/// Renders TextMate themes for bat, which delta reads from bat's cache, and delta's diff colors.
/// Token rules are the same as the VS Code theme's, so both show code alike.
public enum BatRenderer {
    public static let names: [Appearance: String] = [.dark: "scene-dark", .light: "scene-light"]

    public static func tmTheme(_ v: ResolvedVariant, name: String) throws -> Data {
        let ui = v.interface, bg = ui.background
        let global: [String: String] = [
            "background": bg.hex, "foreground": ui.foreground.hex, "caret": ui.cursor.hex, "selection": ui.selection.hex,
            "lineHighlight": ui.currentLine.hex, "invisibles": ui.border.hex, "gutter": bg.hex,
            "gutterForeground": ui.muted.mixed(over: bg, amount: 0.7).hex, "findHighlight": ui.search.hex,
        ]
        var settings: [[String: Any]] = [["settings": global]]
        for rule in VSCodeRenderer.tokenColors(v) {
            guard let scopes = rule["scope"] as? [String], let style = rule["settings"] as? [String: String] else { continue }
            var entry: [String: Any] = ["scope": scopes.joined(separator: ", "), "settings": style]
            if let title = rule["name"] as? String { entry["name"] = title }
            settings.append(entry)
        }
        let theme: [String: Any] = ["name": name, "settings": settings, "semanticClass": "theme.\(v.appearance.rawValue).\(name)"]
        return try PropertyListSerialization.data(fromPropertyList: theme, format: .xml, options: 0)
    }

    /// A git config file with delta's settings. `~/.gitconfig` includes it.
    public static func deltaConfig(_ v: ResolvedVariant) -> String {
        let s = v.syntax, ui = v.interface, bg = ui.background
        func tint(_ c: RGBA, _ amount: Double) -> String { c.mixed(over: bg, amount: amount).hex }
        return """
        # Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file.
        [delta]
        \tsyntax-theme = \(names[v.appearance]!)
        \tminus-style = syntax "\(tint(s.removed.color, 0.18))"
        \tminus-emph-style = syntax "\(tint(s.removed.color, 0.38))"
        \tplus-style = syntax "\(tint(s.added.color, 0.16))"
        \tplus-emph-style = syntax "\(tint(s.added.color, 0.34))"
        \tline-numbers-minus-style = "\(s.removed.color.hex)"
        \tline-numbers-plus-style = "\(s.added.color.hex)"
        \tline-numbers-zero-style = "\(ui.muted.hex)"

        """
    }
}
