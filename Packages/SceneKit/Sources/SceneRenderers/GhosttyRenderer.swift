import Foundation
import SceneThemes
import SceneFoundation

/// Renders Ghostty theme files. Ghostty theme files are ordinary config files, so only
/// color keys are ever written, and every value is a formatted `RGBA`.
public enum GhosttyRenderer {
    public static let themeNames: [Appearance: String] = [.dark: "scene-dark", .light: "scene-light"]

    /// - Parameter version: Ghostty version, used to skip keys older versions reject.
    public static func themeFile(_ v: ResolvedVariant, version: SemanticVersion?) -> String {
        let t = v.terminal, ui = v.interface
        var lines = [
            "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file.",
            "background = \(t.background.hex)",
            "foreground = \(t.foreground.hex)",
            "cursor-color = \(t.cursor.hex)",
            "cursor-text = \(t.cursorText.hex)",
            "selection-background = \(t.selectionBackground.hex)",
            "selection-foreground = \(t.selectionForeground.hex)",
        ]
        for (index, color) in t.ansi.enumerated() { lines.append("palette = \(index)=\(color.hex)") }
        let v11 = SemanticVersion(1, 1, 0), v13 = SemanticVersion(1, 3, 0)
        if let version, version >= v11 {
            lines.append("split-divider-color = \(ui.border.hex)")
        }
        if let version, version >= v13 {
            lines.append("search-background = \(ui.search.hex)")
            lines.append("search-foreground = \(ui.foreground.hex)")
            lines.append("search-selected-background = \(ui.accent.hex)")
            lines.append("search-selected-foreground = \(ui.background.hex)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The Scene-owned include file. It only selects the theme, so user color lines keep
    /// their documented priority over theme colors.
    public static func includeFile(appearances: [Appearance], forced: Appearance?) -> String {
        var line: String
        if let forced { line = "theme = \(themeNames[forced]!)" }
        else if appearances.count == 2 { line = "theme = light:\(themeNames[.light]!),dark:\(themeNames[.dark]!)" }
        else { line = "theme = \(themeNames[appearances.first ?? .dark]!)" }
        return "# Managed by Scene. Scene overwrites this file.\n" + line + "\n"
    }

    /// Keys in a user config that override theme colors.
    public static let colorKeys: Set<String> = ["background", "foreground", "cursor-color", "cursor-text", "selection-background", "selection-foreground", "palette", "bold-color"]
}
