import Foundation
import SceneThemes
import SceneFoundation

/// Renders an iTerm2 Dynamic Profile. iTerm2 watches the DynamicProfiles folder and updates
/// sessions that use the profile. The profile inherits everything else from the user's default profile.
public enum ITermRenderer {
    public static let profileGUID = "com.insanearts.scene.profile"
    public static let profileName = "Scene"

    public static func dynamicProfile(variants: [Appearance: ResolvedVariant], parentGUID: String?) throws -> Data {
        guard let fallback = variants[.dark] ?? variants[.light] else { throw SceneError.invalid("no variant to render") }
        var profile: [String: Any] = [
            "Name": profileName,
            "Guid": profileGUID,
            "Use Separate Colors for Light and Dark Mode": true,
        ]
        if let parentGUID { profile["Dynamic Profile Parent GUID"] = parentGUID }
        for appearance in Appearance.allCases {
            let v = variants[appearance] ?? fallback
            let suffix = appearance == .dark ? " (Dark)" : " (Light)"
            for (key, color) in colors(v) { profile[key + suffix] = dictionary(color) }
        }
        // Plain keys too, for iTerm2 versions before 3.5.
        for (key, color) in colors(fallback) { profile[key] = dictionary(color) }
        return try JSONSerialization.data(withJSONObject: ["Profiles": [profile]], options: [.prettyPrinted, .sortedKeys])
    }

    static func colors(_ v: ResolvedVariant) -> [(String, RGBA)] {
        let t = v.terminal, ui = v.interface
        var list: [(String, RGBA)] = [
            ("Background Color", t.background), ("Foreground Color", t.foreground), ("Bold Color", t.foreground),
            ("Cursor Color", t.cursor), ("Cursor Text Color", t.cursorText),
            ("Selection Color", t.selectionBackground), ("Selected Text Color", t.selectionForeground),
            ("Link Color", ui.accent), ("Badge Color", ui.accent.with(alpha: 0.5)), ("Cursor Guide Color", ui.currentLine),
        ]
        for (index, color) in t.ansi.enumerated() { list.append(("Ansi \(index) Color", color)) }
        return list
    }

    static func dictionary(_ c: RGBA) -> [String: Any] {
        ["Red Component": c.red, "Green Component": c.green, "Blue Component": c.blue, "Alpha Component": c.alpha, "Color Space": "sRGB"]
    }
}
