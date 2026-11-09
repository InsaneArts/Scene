import Foundation
import SceneThemes

/// The `gui.theme` keys Scene sets in lazygit's `config.yml`, as raw YAML: lists of one quoted hex color and
/// attributes. lazygit's other colors are ANSI names, such as `red` for unstaged changes, so they follow the
/// terminal's theme already.
public enum LazygitRenderer {
    public static func theme(_ v: ResolvedVariant) -> [(key: String, value: String)] {
        let ui = v.interface
        func list(_ color: RGBA, _ attributes: String...) -> String { " [" + (["'\(color.hex)'"] + attributes).joined(separator: ", ") + "]" }
        return [
            ("activeBorderColor", list(ui.accent, "bold")),
            ("inactiveBorderColor", list(ui.muted)),
            ("searchingActiveBorderColor", list(ui.info, "bold")),
            ("optionsTextColor", list(ui.accent)),
            ("selectedLineBgColor", list(ui.selection)),
            ("inactiveViewSelectedLineBgColor", list(ui.currentLine)),
        ]
    }
}
