import Foundation
import SceneThemes

/// The theme file for the user's own scripts, and the environment Scene runs them with.
/// Only typed values go in: colors as hex, the theme id (restricted by the loader), its version, and its sanitized name.
public enum ThemeFileRenderer {
    /// The interface roles, in the order of `InterfaceColors`, with their key in the file.
    public static let roles: [(key: String, color: KeyPath<InterfaceColors, RGBA> & Sendable)] = [
        ("background", \.background), ("surface", \.surface), ("overlay", \.overlay), ("border", \.border),
        ("foreground", \.foreground), ("muted", \.muted), ("accent", \.accent), ("selection", \.selection),
        ("cursor", \.cursor), ("currentLine", \.currentLine), ("search", \.search), ("error", \.error),
        ("warning", \.warning), ("success", \.success), ("info", \.info),
    ]

    /// `#rrggbb`, or `#rrggbbaa` when the color is not opaque.
    static func hex(_ color: RGBA) -> String { color.a == 255 ? color.hex : color.hexWithAlpha }

    /// - Parameters:
    ///   - variants: the looks apps that switch on their own should have.
    ///   - appearance: the look Scene shows now.
    ///   - mode: `system`, `light`, or `dark`.
    public static func file(variants: [Appearance: ResolvedVariant], appearance: Appearance, mode: String) throws -> Data {
        guard let shown = variants[appearance] ?? variants.values.first else { throw CocoaError(.coderInvalidValue) }
        var rendered: [String: Any] = [:]
        for (look, v) in variants {
            let t = v.terminal
            rendered[look.rawValue] = [
                "interface": Dictionary(uniqueKeysWithValues: roles.map { ($0.key, hex(v.interface[keyPath: $0.color])) }),
                "terminal": [
                    "background": hex(t.background), "foreground": hex(t.foreground), "cursor": hex(t.cursor),
                    "cursorText": hex(t.cursorText), "selectionBackground": hex(t.selectionBackground),
                    "selectionForeground": hex(t.selectionForeground), "ansi": t.ansi.map(hex),
                ] as [String: Any],
            ]
        }
        let out: [String: Any] = [
            "format": 1,
            "theme": ["id": shown.themeID, "name": ThemeLoader.sanitized(shown.themeName), "version": shown.themeVersion],
            "mode": mode,
            "appearance": variants[appearance] == nil ? shown.appearance.rawValue : appearance.rawValue,
            "variants": rendered,
        ]
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// The colors of the shown look as `SCENE_…` variables: `SCENE_THEME_ID`, `SCENE_APPEARANCE`, one per interface
    /// role (`SCENE_CURRENT_LINE` for `currentLine`), and `SCENE_ANSI_0` to `SCENE_ANSI_15`.
    /// Nil when the file is not one Scene wrote: every value is checked again before it reaches a script.
    public static func environment(file data: Data) -> [String: String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? Int == 1,
              let appearance = root["appearance"] as? String, Appearance(rawValue: appearance) != nil,
              let id = (root["theme"] as? [String: Any])?["id"] as? String, isThemeID(id),
              let variant = (root["variants"] as? [String: Any])?[appearance] as? [String: Any],
              let interface = variant["interface"] as? [String: String],
              let ansi = (variant["terminal"] as? [String: Any])?["ansi"] as? [String], ansi.count == 16 else { return nil }
        var out = ["SCENE_THEME_ID": id, "SCENE_APPEARANCE": appearance]
        for (key, _) in roles {
            guard let value = interface[key], isHex(value) else { return nil }
            out["SCENE_" + snake(key)] = value
        }
        for (index, value) in ansi.enumerated() {
            guard isHex(value) else { return nil }
            out["SCENE_ANSI_\(index)"] = value
        }
        return out
    }

    /// `currentLine` becomes `CURRENT_LINE`.
    static func snake(_ key: String) -> String {
        key.reduce(into: "") { out, c in
            if c.isUppercase { out += "_" }
            out += c.uppercased()
        }
    }

    static func isHex(_ s: String) -> Bool {
        (s.utf8.count == 7 || s.utf8.count == 9) && s.first == "#" && s.utf8.dropFirst().allSatisfy { "0123456789abcdefABCDEF".utf8.contains($0) }
    }

    static func isThemeID(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789._-/".utf8.contains($0) }
    }
}
