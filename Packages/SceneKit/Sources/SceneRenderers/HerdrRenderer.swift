import Foundation
import SceneThemes

/// herdr's interface colors: the tokens of its `[theme.custom]` table, from Scene's roles. Each token paints what
/// herdr's `Palette` (src/app/state.rs) says. `sidebar_bg` stays unset, so the sidebar keeps the terminal's own
/// background, which Scene themes too.
public enum HerdrRenderer {
    /// The built-in theme under the tokens, so anything herdr adds later starts from the right look.
    public static func base(_ appearance: Appearance) -> String { appearance == .dark ? "catppuccin" : "catppuccin-latte" }

    public static func tokens(_ v: ResolvedVariant) -> [(name: String, color: RGBA)] {
        let ui = v.interface
        return [
            ("accent", ui.accent),                                                  // highlights, active borders
            ("panel_bg", ui.surface),                                               // tab bar, panels, modals
            ("active_row_bg", ui.currentLine),                                      // the active space and agent rows
            ("selection_bg", ui.selection),                                         // the Navigate-mode cursor row
            ("surface0", ui.overlay),                                               // selected and focused items
            ("surface1", ui.border),                                                // hover and active states
            ("surface_dim", ui.background),                                         // separators
            ("overlay0", ui.muted),                                                 // muted text, numbers
            ("overlay1", ui.muted.mixed(over: ui.foreground, amount: 0.7)),         // slightly brighter muted text
            ("text", ui.foreground),
            ("subtext0", ui.muted.mixed(over: ui.foreground, amount: 0.35)),        // dim labels
            ("mauve", v.syntax.keyword.color),                                      // branch names, special labels
            ("green", ui.success),                                                  // done and idle agents
            ("yellow", ui.warning),                                                 // working agents
            ("red", ui.error),                                                      // blocked agents
            ("blue", ui.info),                                                      // done notifications
            ("teal", v.terminal.ansi[6]),                                           // unseen markers
            ("peach", v.syntax.number.color),                                       // interrupted agents
        ]
    }
}
