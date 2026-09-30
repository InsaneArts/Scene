import AppKit
import Foundation
import SceneThemes
import SceneFoundation

/// Renders the colors of a Terminal profile as keyed archives of `NSColor`, as Terminal stores them.
public enum TerminalAppRenderer {
    public static let profileName = "Scene"

    static let ansiKeys = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

    /// Color keys of a profile. Everything else, such as the font, comes from the user's own default profile.
    public static func colors(_ v: ResolvedVariant) throws -> [String: Data] {
        let t = v.terminal
        var colors: [String: RGBA] = [
            "BackgroundColor": t.background, "TextColor": t.foreground, "TextBoldColor": t.foreground,
            "CursorColor": t.cursor, "SelectionColor": t.selectionBackground,
        ]
        for (index, name) in ansiKeys.enumerated() {
            colors["ANSI\(name)Color"] = t.ansi[index]
            colors["ANSIBright\(name)Color"] = t.ansi[index + 8]
        }
        return try colors.mapValues(archive)
    }

    static func archive(_ c: RGBA) throws -> Data {
        let color = NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
        return try NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
    }
}
