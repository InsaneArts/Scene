import Foundation
import SceneThemes
import SceneFoundation

/// Renders tmux style options. `set -gq` ignores options an older tmux does not know.
public enum TmuxRenderer {
    /// Every option Scene sets. Restore unsets them on the running server.
    public static let options = [
        "status-style", "window-status-style", "window-status-current-style", "window-status-activity-style", "window-status-bell-style",
        "pane-border-style", "pane-active-border-style", "message-style", "message-command-style", "mode-style",
        "clock-mode-colour", "display-panes-colour", "display-panes-active-colour", "popup-style", "popup-border-style",
        "menu-style", "menu-selected-style", "menu-border-style", "copy-mode-match-style", "copy-mode-current-match-style",
    ]

    public static func configFile(_ v: ResolvedVariant) -> String {
        let ui = v.interface
        func style(_ pairs: (String, RGBA)..., bold: Bool = false) -> String {
            "\"" + (pairs.map { "\($0.0)=\($0.1.hex)" } + (bold ? ["bold"] : [])).joined(separator: ",") + "\""
        }
        let values: [String: String] = [
            "status-style": style(("bg", ui.surface), ("fg", ui.foreground)),
            "window-status-style": style(("bg", ui.surface), ("fg", ui.muted)),
            "window-status-current-style": style(("bg", ui.accent), ("fg", v.textOnAccent), bold: true),
            "window-status-activity-style": style(("bg", ui.surface), ("fg", ui.warning)),
            "window-status-bell-style": style(("bg", ui.surface), ("fg", ui.error), bold: true),
            "pane-border-style": style(("fg", ui.border)),
            "pane-active-border-style": style(("fg", ui.accent)),
            "message-style": style(("bg", ui.overlay), ("fg", ui.foreground)),
            "message-command-style": style(("bg", ui.overlay), ("fg", ui.accent)),
            "mode-style": style(("bg", ui.selection), ("fg", ui.foreground)),
            "clock-mode-colour": "\"\(ui.accent.hex)\"",
            "display-panes-colour": "\"\(ui.muted.hex)\"",
            "display-panes-active-colour": "\"\(ui.accent.hex)\"",
            "popup-style": style(("bg", ui.overlay), ("fg", ui.foreground)),
            "popup-border-style": style(("fg", ui.border)),
            "menu-style": style(("bg", ui.overlay), ("fg", ui.foreground)),
            "menu-selected-style": style(("bg", ui.selection), ("fg", ui.foreground)),
            "menu-border-style": style(("fg", ui.border)),
            "copy-mode-match-style": style(("bg", ui.search), ("fg", ui.foreground)),
            "copy-mode-current-match-style": style(("bg", ui.accent), ("fg", v.textOnAccent)),
        ]
        let header = "# Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(v.themeVersion) (\(v.appearance.rawValue)). Scene overwrites this file."
        return ([header] + options.map { "set -gq \($0) \(values[$0]!)" }).joined(separator: "\n") + "\n"
    }
}
