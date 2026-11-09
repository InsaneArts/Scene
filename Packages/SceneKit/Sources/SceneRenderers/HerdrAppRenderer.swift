import Foundation
import SceneThemes

/// A Herdr app theme file (`~/.config/herdr-app/themes/<name>.json`): the terminal's colors, from which Herdr derives
/// its panel colors, and Scene's accent over the derived one.
public enum HerdrAppRenderer {
    public static func themeFile(_ variant: ResolvedVariant) throws -> Data {
        let terminal = variant.terminal
        return try JSONSerialization.data(withJSONObject: [
            "background": terminal.background.description,
            "foreground": terminal.foreground.description,
            "selection": terminal.selectionBackground.description,
            "cursor": terminal.cursor.description,
            "ansi": terminal.ansi.map(\.description),
            "colors": ["accent": variant.interface.accent.description],
        ], options: [.prettyPrinted, .sortedKeys])
    }
}
