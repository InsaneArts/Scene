import SceneThemes

/// A bb app theme: one `theme.css` with a block for each look. bb derives its neutral ramp from the two anchors
/// `--canvas` and `--ink`, so Scene sets the anchors, the accent, the semantic colors, and the terminal palette.
/// Every value is a hex color formatted from a parsed color, or a fixed `color-mix` of two of them.
public enum BbRenderer {
    public static func themeFile(light: ResolvedVariant, dark: ResolvedVariant) -> String {
        """
        /* Scene theme for bb. Scene rewrites this file on every apply. */
        :root,
        .light {
        \(block(light))
        }
        .dark {
        \(block(dark))
        }

        """
    }

    static func block(_ v: ResolvedVariant) -> String {
        let ui = v.interface, syntax = v.syntax, ansi = v.terminal.ansi
        /// The theme's background or foreground, whichever reads better on `color`.
        func readable(on color: RGBA) -> RGBA { ui.background.contrast(with: color) >= ui.foreground.contrast(with: color) ? ui.background : ui.foreground }
        var lines: [(String, String)] = [
            ("--canvas", ui.background.hex), ("--ink", ui.foreground.hex),
            ("--primary", ui.accent.hex), ("--primary-foreground", readable(on: ui.accent).hex),
            ("--muted-foreground", "color-mix(in oklch, var(--ink) 70%, var(--canvas))"),
            ("--subtle-foreground", "color-mix(in oklch, var(--ink) 58%, var(--canvas))"),
            ("--readback-foreground", "color-mix(in oklch, var(--ink) 64%, var(--canvas))"),
            ("--destructive", ui.error.hex), ("--destructive-foreground", readable(on: ui.error).hex), ("--destructive-text", ui.error.hex),
            ("--warning", ui.warning.hex), ("--warning-text", ui.warning.hex), ("--attention", ui.warning.hex),
            ("--success", ui.success.hex), ("--diff-added", syntax.added.color.hex), ("--diff-removed", syntax.removed.color.hex),
            ("--pr-merged", ansi[5].hex), ("--file-accent", ui.accent.hex),
        ]
        for (index, color) in ansi.prefix(16).enumerated() {
            lines.append(("--ansi-\(index)", color.hex))
            lines.append(("--ansi-bg-fg-\(index)", readable(on: color).hex))
        }
        return lines.map { "  \($0.0): \($0.1);" }.joined(separator: "\n")
    }
}
