import Foundation
import SceneFoundation

// MARK: - Manifest (the JSON a theme package ships, decoded without interpretation)

/// `theme.json`, decoded strictly. Colors stay strings here; `ThemeResolver` turns them into `RGBA`.
public struct ThemeManifest: Codable, Sendable, Equatable {
    public var schema: String?
    public var format: Int
    public var id: String
    public var version: String
    public var name: String
    public var summary: String?
    public var authors: [Author]
    public var license: String
    public var homepage: String?
    public var tags: [String]?
    public var requires: Requires?
    public var variants: [String: VariantSpec]
    public var apps: AppsSpec?
    public var assets: [AssetSpec]?

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case format, id, version, name, summary, authors, license, homepage, tags, requires, variants, apps, assets
    }

    public struct Author: Codable, Sendable, Equatable {
        public var name: String
        public var url: String?
    }

    public struct Requires: Codable, Sendable, Equatable {
        public var scene: String?
    }

    public struct AssetSpec: Codable, Sendable, Equatable {
        public var file: String
        public var license: String
        public var attribution: String?
        public var source: String?
    }
}

public struct VariantSpec: Codable, Sendable, Equatable {
    public var palette: [String: String]
    public var terminal: TerminalSpec
    public var syntax: [String: SyntaxSpec]
    /// The first one is the default. You can pick another in Scene.
    public var wallpapers: [WallpaperSpec]?
    public var system: SystemSpec?
}

public struct TerminalSpec: Codable, Sendable, Equatable {
    public var background: String?
    public var foreground: String?
    public var cursor: String?
    public var cursorText: String?
    public var selectionBackground: String?
    public var selectionForeground: String?
    public var ansi: [String: String]
}

/// A syntax role is either a plain color string or an object with style flags.
public enum SyntaxSpec: Codable, Sendable, Equatable {
    case color(String)
    case styled(color: String, bold: Bool?, italic: Bool?, underline: Bool?)

    enum CodingKeys: String, CodingKey { case color, bold, italic, underline }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
            self = .color(value)
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self = .styled(color: try c.decode(String.self, forKey: .color),
                       bold: try c.decodeIfPresent(Bool.self, forKey: .bold),
                       italic: try c.decodeIfPresent(Bool.self, forKey: .italic),
                       underline: try c.decodeIfPresent(Bool.self, forKey: .underline))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .color(let value):
            var single = encoder.singleValueContainer()
            try single.encode(value)
        case let .styled(color, bold, italic, underline):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(color, forKey: .color)
            try c.encodeIfPresent(bold, forKey: .bold)
            try c.encodeIfPresent(italic, forKey: .italic)
            try c.encodeIfPresent(underline, forKey: .underline)
        }
    }

    var colorString: String {
        switch self {
        case .color(let value): value
        case .styled(let color, _, _, _): color
        }
    }
}

public struct WallpaperSpec: Codable, Sendable, Equatable {
    public var file: String
    public var fit: String?
}

public struct SystemSpec: Codable, Sendable, Equatable {
    /// Text highlight color (`#hex` or `@role`).
    public var highlightColor: String?
    /// `auto` (nearest preset to `palette.accent`) or a preset name: multicolor, graphite, red, orange, yellow, green, blue, purple, pink.
    public var accentColor: String?
    /// default, dark, clear, tinted.
    public var iconStyle: String?
    /// For tinted icons: `accent`, a preset name, or `#hex`.
    public var iconTint: String?
}

public struct AppsSpec: Codable, Sendable, Equatable {
    public var vscode: AppOverrideSpec?
    public var neovim: AppOverrideSpec?
}

public struct AppOverrideSpec: Codable, Sendable, Equatable {
    public var dark: String?
    public var light: String?
    public var preferInstalled: PreferInstalled?

    public struct PreferInstalled: Codable, Sendable, Hashable {
        public var colorscheme: String?
        public var extensionID: String?
        public var theme: String?

        enum CodingKeys: String, CodingKey {
            case colorscheme
            case extensionID = "extension"
            case theme
        }
    }
}

// MARK: - Resolved model (typed, validated, ready for renderers)

public enum Appearance: String, Codable, Sendable, CaseIterable {
    case light, dark
}

public struct SyntaxStyle: Hashable, Sendable {
    public var color: RGBA
    public var bold = false
    public var italic = false
    public var underline = false

    public init(color: RGBA, bold: Bool = false, italic: Bool = false, underline: Bool = false) {
        self.color = color; self.bold = bold; self.italic = italic; self.underline = underline
    }
}

public struct InterfaceColors: Hashable, Sendable {
    public var background, surface, overlay, border, foreground, muted, accent, selection, cursor, currentLine, search, error, warning, success, info: RGBA
}

public struct TerminalColors: Hashable, Sendable {
    public var background, foreground, cursor, cursorText, selectionBackground, selectionForeground: RGBA
    /// 16 colors: black, red, green, yellow, blue, magenta, cyan, white, then the bright versions.
    public var ansi: [RGBA]
}

public struct SyntaxColors: Hashable, Sendable {
    public var comment, keyword, `operator`, punctuation, string, escape, number, constant, function, type, builtin, variable, parameter, property, tag, attribute, added, removed, changed: SyntaxStyle
}

public enum WallpaperFit: String, Sendable, Codable { case fill, fit, stretch, center }

public struct Wallpaper: Hashable, Sendable {
    public var url: URL
    public var fit: WallpaperFit

    public init(url: URL, fit: WallpaperFit) {
        self.url = url
        self.fit = fit
    }

    /// The file name. It identifies the wallpaper within its theme.
    public var name: String { url.lastPathComponent }
}

public enum AccentPreset: Int, Sendable, Codable, CaseIterable {
    case hardware = -3, multicolor = -2, graphite = -1, red = 0, orange, yellow, green, blue, purple, pink

    public var name: String { String(describing: self) }

    public init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
        self = match
    }
}

public enum IconStyle: String, Sendable, Codable, CaseIterable {
    case `default`, dark, clear, tinted
}

public struct SystemLook: Hashable, Sendable {
    public var highlightColor: RGBA?
    public var accent: AccentPreset?
    public var iconStyle: IconStyle?
    public var iconTint: IconTint?
}

public enum IconTint: Hashable, Sendable {
    case preset(AccentPreset)
    case custom(RGBA)
}

public struct ResolvedVariant: Hashable, Sendable {
    public var themeID: String
    public var themeName: String
    public var themeVersion: String
    public var appearance: Appearance
    public var interface: InterfaceColors
    public var terminal: TerminalColors
    public var syntax: SyntaxColors
    /// In the theme's order. The first one is the default.
    public var wallpapers: [Wallpaper]
    public var system: SystemLook
    /// Curated override files from `apps/`, already validated, keyed by integration id.
    public var overrides: [String: Data]
    public var preferInstalled: [String: AppOverrideSpec.PreferInstalled]

    /// The wallpaper with this file name, or the first one when there is no such wallpaper.
    public func wallpaper(named name: String?) -> Wallpaper? {
        wallpapers.first { $0.name == name } ?? wallpapers.first
    }

    /// The wallpaper after the one `wallpaper(named:)` returns. After the last one comes the first.
    public func wallpaper(after name: String?) -> Wallpaper? {
        guard let current = wallpaper(named: name), let index = wallpapers.firstIndex(of: current) else { return nil }
        return wallpapers[(index + 1) % wallpapers.count]
    }
}

/// A theme on disk with its manifest and resolved variants.
public struct Theme: Sendable, Identifiable, Hashable {
    public var id: String { manifest.id }
    public var manifest: ThemeManifest
    public var folder: URL
    public var variants: [Appearance: ResolvedVariant]
    public var warnings: [String]
    public var isBundled: Bool

    public static func == (lhs: Theme, rhs: Theme) -> Bool {
        lhs.manifest.id == rhs.manifest.id && lhs.manifest.version == rhs.manifest.version && lhs.folder == rhs.folder
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(manifest.id); hasher.combine(manifest.version); hasher.combine(folder)
    }

    public var availableAppearances: [Appearance] { Appearance.allCases.filter { variants[$0] != nil } }
}
