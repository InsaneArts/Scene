import SceneThemes

/// Rio's [colors] TOML table. Values are formatted from parsed colors only.
public enum RioRenderer {
    public static func themeFile(_ variant: ResolvedVariant) -> String {
        let terminal = variant.terminal, ui = variant.interface
        var colors: [(String, RGBA)] = [
            ("background", terminal.background), ("foreground", terminal.foreground),
            ("cursor", terminal.cursor), ("vi-cursor", ui.accent),
            ("selection-background", terminal.selectionBackground), ("selection-foreground", terminal.selectionForeground),
            ("tabs", ui.muted), ("tabs-active", ui.foreground), ("split-active", ui.accent), ("split", ui.border),
            ("search-match-background", ui.search), ("search-match-foreground", ui.foreground),
            ("search-focused-match-background", ui.accent), ("search-focused-match-foreground", terminal.cursorText),
            ("hint-background", ui.accent), ("hint-foreground", terminal.cursorText),
            ("dim-foreground", ui.muted), ("light-foreground", terminal.foreground),
        ]
        for (index, name) in ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"].enumerated() {
            colors.append((name, terminal.ansi[index]))
            colors.append(("light-" + name, terminal.ansi[index + 8]))
            colors.append(("dim-" + name, terminal.background.mixed(over: terminal.ansi[index], amount: 0.3)))
        }
        return "[colors]\n" + colors.map { "\($0.0) = \"\($0.1.description)\"" }.joined(separator: "\n") + "\n"
    }
}
