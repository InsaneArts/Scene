import Foundation
import SceneThemes

/// ZapFast's documented JSON palette, with explicit interface and chat colors.
public enum ZapFastRenderer {
    public static func themeFile(_ variant: ResolvedVariant) throws -> Data {
        let ui = variant.interface
        let black = RGBA(r: 0, g: 0, b: 0)
        let white = RGBA(r: 255, g: 255, b: 255)
        let onAccent = black.contrast(with: ui.accent) > white.contrast(with: ui.accent) ? black : white
        let colors: [String: RGBA] = [
            "window": ui.background, "panel": ui.surface, "surface": ui.overlay,
            "surface_hover": ui.currentLine, "surface_active": ui.selection,
            "outline": ui.border, "text": ui.foreground, "secondary": ui.muted,
            "dim": ui.muted, "accent": ui.accent,
            "accent_hover": ui.foreground.mixed(over: ui.accent, amount: 0.12),
            "on_accent": onAccent, "danger": ui.error, "warning": ui.warning,
            "overlay": ui.overlay, "shadow": black.with(alpha: 0.25),
            "chat": ui.background, "bubble_in": ui.surface,
            "bubble_out": ui.accent.mixed(over: ui.surface, amount: 0.24),
            "link": ui.accent, "read": ui.info,
        ]
        return try JSONSerialization.data(withJSONObject: [
            "base": variant.appearance.rawValue,
            "colors": colors.mapValues(\.description),
        ], options: [.prettyPrinted, .sortedKeys])
    }
}
