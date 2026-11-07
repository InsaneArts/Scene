import Foundation
import SceneThemes
import SceneFoundation

/// The theme file for the user's own scripts, `~/.config/scene/theme.json`, and the environment a script gets from it.
/// Both hold typed values only: colors as `#rrggbb`, the appearance, and the theme's id and version, each checked.
public enum ThemeFileRenderer {
    public static let format = 1

    /// The 15 interface roles, by the names the file and the environment use.
    public static func roles(_ ui: InterfaceColors) -> [(name: String, color: RGBA)] {
        [("background", ui.background), ("surface", ui.surface), ("overlay", ui.overlay), ("border", ui.border),
         ("foreground", ui.foreground), ("muted", ui.muted), ("accent", ui.accent), ("selection", ui.selection),
         ("cursor", ui.cursor), ("currentLine", ui.currentLine), ("search", ui.search), ("error", ui.error),
         ("warning", ui.warning), ("success", ui.success), ("info", ui.info)]
    }

    /// `mode` is how the theme was applied (`system`, `light`, or `dark`); `appearance` is the look on screen.
    public static func file(themeID: String, version: String, mode: String, appearance: Appearance,
                            variants: [Appearance: ResolvedVariant]) throws -> Data {
        var out: [String: Any] = ["format": format, "mode": mode, "appearance": appearance.rawValue]
        var theme: [String: Any] = [:]
        if isSafeID(themeID) { theme["id"] = themeID }
        if let version = SemanticVersion(version) { theme["version"] = version.description }
        out["theme"] = theme
        var rendered: [String: Any] = [:]
        for (look, v) in variants {
            let t = v.terminal
            rendered[look.rawValue] = [
                "interface": Dictionary(uniqueKeysWithValues: roles(v.interface).map { ($0.name, $0.color.hex) }),
                "terminal": ["background": t.background.hex, "foreground": t.foreground.hex, "cursor": t.cursor.hex,
                             "cursorText": t.cursorText.hex, "selectionBackground": t.selectionBackground.hex,
                             "selectionForeground": t.selectionForeground.hex, "ansi": t.ansi.map(\.hex)] as [String: Any],
            ]
        }
        out["variants"] = rendered
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The environment for the look on screen: `SCENE_THEME_ID`, `SCENE_APPEARANCE`, one `SCENE_<ROLE>` per interface
    /// role (`SCENE_CURRENT_LINE` for `currentLine`), and `SCENE_ANSI_0` to `SCENE_ANSI_15`. Nil when the file is not
    /// one that `file` wrote. A value that is not a color or a known word is left out.
    public static func environment(_ data: Data) -> [String: String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], root["format"] as? Int == format,
              let appearance = (root["appearance"] as? String).flatMap(Appearance.init(rawValue:)),
              let variant = (root["variants"] as? [String: Any])?[appearance.rawValue] as? [String: Any] else { return nil }
        var env = ["SCENE_APPEARANCE": appearance.rawValue]
        if let id = (root["theme"] as? [String: Any])?["id"] as? String, isSafeID(id) { env["SCENE_THEME_ID"] = id }
        let interface = variant["interface"] as? [String: Any] ?? [:]
        for (name, value) in interface {
            guard let hex = value as? String, isHex(hex), name.allSatisfy({ $0.isLetter }) else { continue }
            env["SCENE_" + snake(name)] = hex
        }
        let ansi = (variant["terminal"] as? [String: Any])?["ansi"] as? [Any] ?? []
        for (index, value) in ansi.prefix(16).enumerated() {
            if let hex = value as? String, isHex(hex) { env["SCENE_ANSI_\(index)"] = hex }
        }
        return env
    }

    static func snake(_ name: String) -> String {
        name.reduce(into: "") { out, c in out += c.isUppercase ? "_" + String(c) : String(c).uppercased() }
    }

    static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy { $0.isHexDigit }
    }

    /// Theme ids look like `scene/amber` or `owner/repo`.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 200 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/-_.".contains($0)) }
    }
}
