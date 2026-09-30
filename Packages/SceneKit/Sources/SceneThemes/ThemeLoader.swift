import Foundation
import SceneFoundation
import ImageIO
import UniformTypeIdentifiers

public struct ThemeLoadError: Error, CustomStringConvertible, Sendable {
    public var errors: [String]
    public var warnings: [String]
    public var description: String { errors.joined(separator: "\n") }
}

/// Reads a theme folder, validates it in layers (container, schema, meaning, overrides),
/// and resolves every variant into typed colors. Used for bundled themes, imports, and store downloads.
public enum ThemeLoader {
    public static let supportedFormat = 1

    public struct Limits: Sendable {
        public var maxEntries = 64
        public var maxImageBytes = 20 * 1024 * 1024
        public var maxJSONBytes = 1024 * 1024
        public var maxTotalBytes = 40 * 1024 * 1024
        public var minImageLongSide = 1024
        public var maxImageLongSide = 8192
        public init() {}
    }

    static let interfaceRoles = ["background", "surface", "overlay", "border", "foreground", "muted", "accent", "selection", "cursor", "currentLine", "search", "error", "warning", "success", "info"]
    static let ansiNames = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                            "brightBlack", "brightRed", "brightGreen", "brightYellow", "brightBlue", "brightMagenta", "brightCyan", "brightWhite"]
    static let syntaxRoles = ["comment", "keyword", "operator", "punctuation", "string", "escape", "number", "constant", "function", "type", "builtin", "variable", "parameter", "property", "tag", "attribute", "added", "removed", "changed"]
    static let imageExtensions: Set<String> = ["heic", "jpg", "jpeg", "png"]

    public static func load(folder: URL, isBundled: Bool = false, limits: Limits = .init()) throws -> Theme {
        var errors: [String] = []
        let warnings: [String] = []

        // Layer 1: container.
        try checkContainer(folder: folder, limits: limits, errors: &errors)
        guard errors.isEmpty else { throw ThemeLoadError(errors: errors, warnings: warnings) }

        return try load(manifest: Data(contentsOf: folder.appendingPathComponent("theme.json")), folder: folder, isBundled: isBundled,
                        limits: limits, warnings: warnings)
    }

    /// Layers 2 to 4 for a theme.json already in memory. The Theme Maker's preview uses it on every change,
    /// with no wallpapers and no files.
    static func load(manifest data: Data, folder: URL, isBundled: Bool = false, limits: Limits = .init(),
                     warnings: [String] = []) throws -> Theme {
        var errors: [String] = []
        var warnings = warnings

        // Layer 2: schema.
        let manifest: ThemeManifest
        do {
            manifest = try JSONDecoder().decode(ThemeManifest.self, from: data)
        } catch let error as DecodingError {
            throw ThemeLoadError(errors: ["theme.json: \(describe(error))"], warnings: [])
        }
        checkIdentity(manifest, errors: &errors, warnings: &warnings)
        guard errors.isEmpty else { throw ThemeLoadError(errors: errors, warnings: warnings) }

        // Layer 3 and 4: meaning and overrides, per variant.
        var variants: [Appearance: ResolvedVariant] = [:]
        for (key, spec) in manifest.variants.sorted(by: { $0.key < $1.key }) {
            guard let appearance = Appearance(rawValue: key) else {
                errors.append("variants: unknown variant \"\(key)\"; use \"dark\" or \"light\"")
                continue
            }
            if let resolved = resolve(spec, appearance: appearance, manifest: manifest, folder: folder, limits: limits, errors: &errors, warnings: &warnings) {
                variants[appearance] = resolved
            }
        }
        if manifest.variants.isEmpty { errors.append("variants: a theme needs at least one variant") }
        checkAssets(manifest, folder: folder, isBundled: isBundled, errors: &errors, warnings: &warnings)
        guard errors.isEmpty else { throw ThemeLoadError(errors: errors, warnings: warnings) }
        return Theme(manifest: manifest, folder: folder, variants: variants, warnings: warnings, isBundled: isBundled)
    }

    // MARK: Layer 1

    static func checkContainer(folder: URL, limits: Limits, errors: inout [String]) throws {
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: []) else {
            errors.append("cannot read the theme folder"); return
        }
        var count = 0, total = 0
        let base = folder.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if relative.hasPrefix(".") || relative.contains("/.") { continue } // Finder metadata such as .DS_Store
            count += 1
            if values.isSymbolicLink == true { errors.append("\(relative): symlinks are not allowed"); continue }
            if values.isDirectory == true {
                if !["wallpapers", "apps"].contains(relative) { errors.append("\(relative): unexpected folder") }
                continue
            }
            let size = values.fileSize ?? 0
            total += size
            let parts = relative.split(separator: "/").map(String.init)
            let ext = url.pathExtension.lowercased()
            switch parts.count {
            case 1 where relative == "theme.json" || relative == "README.md":
                if size > limits.maxJSONBytes { errors.append("\(relative): larger than \(limits.maxJSONBytes) bytes") }
            case 2 where parts[0] == "wallpapers" && imageExtensions.contains(ext):
                if size > limits.maxImageBytes { errors.append("\(relative): larger than \(limits.maxImageBytes / 1_048_576) MB") }
            case 2 where parts[0] == "apps" && ext == "json":
                if size > limits.maxJSONBytes { errors.append("\(relative): larger than \(limits.maxJSONBytes) bytes") }
            default:
                errors.append("\(relative): file not allowed in a theme package")
            }
        }
        if count > limits.maxEntries { errors.append("too many files (\(count) > \(limits.maxEntries))") }
        if total > limits.maxTotalBytes { errors.append("package larger than \(limits.maxTotalBytes / 1_048_576) MB") }
        if !FileManager.default.fileExists(atPath: folder.appendingPathComponent("theme.json").path) {
            errors.append("theme.json is missing")
        }
    }

    // MARK: Layer 2

    static func checkIdentity(_ m: ThemeManifest, errors: inout [String], warnings: inout [String]) {
        if m.format > supportedFormat { errors.append("format \(m.format) needs a newer version of Scene") }
        if m.format < 1 { errors.append("format must be 1 or higher") }
        if m.id.range(of: #"^[a-z0-9][a-z0-9._-]{0,63}/[a-z0-9][a-z0-9._-]{0,63}$"#, options: .regularExpression) == nil {
            errors.append("id \"\(sanitized(m.id))\" must look like creator/slug (lowercase letters, digits, . _ -)")
        }
        if m.version.range(of: #"^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$"#, options: .regularExpression) == nil {
            errors.append("version \"\(sanitized(m.version))\" must be a semantic version such as 1.2.0")
        }
        if m.name.isEmpty || m.name.count > 64 { errors.append("name must have 1 to 64 characters") }
        if sanitized(m.name) != m.name { errors.append("name contains control or bidirectional characters") }
        if (m.summary?.count ?? 0) > 200 { warnings.append("summary is longer than 200 characters") }
        if m.license.isEmpty { errors.append("license is required (an SPDX expression)") }
    }

    /// Removes control and bidirectional-override characters.
    public static func sanitized(_ s: String) -> String {
        String(s.unicodeScalars.filter { scalar in
            !(scalar.properties.generalCategory == .control || (0x202A...0x202E).contains(scalar.value) || (0x2066...0x2069).contains(scalar.value))
        }.map(Character.init))
    }

    // MARK: Layer 3

    static func resolve(_ spec: VariantSpec, appearance: Appearance, manifest: ThemeManifest, folder: URL, limits: Limits,
                        errors: inout [String], warnings: inout [String]) -> ResolvedVariant? {
        let where_ = "variants.\(appearance.rawValue)"
        var local: [String] = []

        // Palette values must be literal colors.
        var palette: [String: RGBA] = [:]
        for (role, value) in spec.palette {
            guard interfaceRoles.contains(role) else { warnings.append("\(where_).palette.\(role): unknown role, ignored"); continue }
            guard let color = RGBA(hex: value) else { local.append("\(where_).palette.\(role): \"\(sanitized(value))\" is not #RRGGBB or #RRGGBBAA"); continue }
            palette[role] = color
        }
        for required in ["background", "foreground", "accent"] where palette[required] == nil && !local.contains(where: { $0.contains(".palette.\(required):") }) {
            local.append("\(where_).palette.\(required) is required")
        }

        var ansi: [String: RGBA] = [:]

        func derivedPalette(_ role: String) -> RGBA? {
            guard let bg = palette["background"], let fg = palette["foreground"] else { return nil }
            switch role {
            case "surface": return fg.mixed(over: bg, amount: 0.05)
            case "overlay": return fg.mixed(over: palette["surface"] ?? fg.mixed(over: bg, amount: 0.05), amount: 0.05)
            case "border": return fg.mixed(over: bg, amount: 0.2)
            case "muted": return fg.mixed(over: bg, amount: 0.6)
            case "selection": return (palette["accent"] ?? fg).mixed(over: bg, amount: 0.3)
            case "cursor": return fg
            case "currentLine": return palette["surface"] ?? fg.mixed(over: bg, amount: 0.05)
            case "error": return ansi["red"]
            case "warning": return ansi["yellow"]
            case "success": return ansi["green"]
            case "info": return ansi["blue"]
            case "search": return (palette["warning"] ?? ansi["yellow"] ?? fg).mixed(over: bg, amount: 0.35)
            default: return nil
            }
        }

        func ref(_ value: String?, _ path: String) -> RGBA? {
            guard let value else { return nil }
            if value.hasPrefix("@") {
                let name = String(value.dropFirst())
                guard interfaceRoles.contains(name) else { local.append("\(path): \"\(sanitized(value))\" is not a palette role"); return nil }
                guard let color = palette[name] ?? derivedPalette(name) else { local.append("\(path): \(value) cannot be derived at this point; set it in the palette"); return nil }
                return color
            }
            guard let color = RGBA(hex: value) else { local.append("\(path): \"\(sanitized(value))\" is not #RRGGBB, #RRGGBBAA, or @role"); return nil }
            return color
        }

        // ANSI colors: the 8 normal colors are required, bright ones fall back to normal ones.
        for (name, value) in spec.terminal.ansi {
            guard ansiNames.contains(name) else { warnings.append("\(where_).terminal.ansi.\(name): unknown color, ignored"); continue }
            if let color = ref(value, "\(where_).terminal.ansi.\(name)") { ansi[name] = color }
        }
        for name in ansiNames.prefix(8) where ansi[name] == nil && !local.contains(where: { $0.contains(".ansi.\(name):") }) {
            local.append("\(where_).terminal.ansi.\(name) is required")
        }

        guard local.isEmpty else { errors.append(contentsOf: local); return nil }
        var fallbacks: [String] = []
        func role(_ name: String) -> RGBA {
            if let value = palette[name] { return value }
            fallbacks.append(name)
            let value = derivedPalette(name)!
            palette[name] = value
            return value
        }
        let ui = InterfaceColors(background: role("background"), surface: role("surface"), overlay: role("overlay"), border: role("border"),
                                 foreground: role("foreground"), muted: role("muted"), accent: role("accent"), selection: role("selection"),
                                 cursor: role("cursor"), currentLine: role("currentLine"), search: role("search"), error: role("error"),
                                 warning: role("warning"), success: role("success"), info: role("info"))

        let normal = ansiNames.prefix(8).map { ansi[$0]! }
        let bright = ansiNames.suffix(8).enumerated().map { index, name in ansi[name] ?? normal[index] }
        let t = spec.terminal
        let terminal = TerminalColors(
            background: ref(t.background, "\(where_).terminal.background") ?? ui.background,
            foreground: ref(t.foreground, "\(where_).terminal.foreground") ?? ui.foreground,
            cursor: ref(t.cursor, "\(where_).terminal.cursor") ?? ui.cursor,
            cursorText: ref(t.cursorText, "\(where_).terminal.cursorText") ?? ui.background,
            selectionBackground: ref(t.selectionBackground, "\(where_).terminal.selectionBackground") ?? ui.selection,
            selectionForeground: ref(t.selectionForeground, "\(where_).terminal.selectionForeground") ?? ui.foreground,
            ansi: normal + bright)

        // Syntax roles with fallback chains.
        var syntax: [String: SyntaxStyle] = [:]
        for (name, value) in spec.syntax {
            guard syntaxRoles.contains(name) else { warnings.append("\(where_).syntax.\(name): unknown role, ignored"); continue }
            guard let color = ref(value.colorString, "\(where_).syntax.\(name)") else { continue }
            var style = SyntaxStyle(color: color)
            if case let .styled(_, bold, italic, underline) = value {
                style.bold = bold ?? false; style.italic = italic ?? false; style.underline = underline ?? false
            }
            syntax[name] = style
        }
        guard local.isEmpty else { errors.append(contentsOf: local); return nil }
        let a = terminal.ansi
        func s(_ name: String, _ fallback: @autoclosure () -> SyntaxStyle) -> SyntaxStyle {
            if let v = syntax[name] { return v }
            fallbacks.append("syntax.\(name)")
            let v = fallback(); syntax[name] = v; return v
        }
        let number = s("number", SyntaxStyle(color: a[3]))
        let variable = s("variable", SyntaxStyle(color: ui.foreground))
        let constant = s("constant", number)
        let colors = SyntaxColors(
            comment: s("comment", SyntaxStyle(color: ui.muted, italic: true)), keyword: s("keyword", SyntaxStyle(color: a[5])),
            operator: s("operator", SyntaxStyle(color: ui.foreground)), punctuation: s("punctuation", SyntaxStyle(color: ui.muted)),
            string: s("string", SyntaxStyle(color: a[2])), escape: s("escape", SyntaxStyle(color: a[14])), number: number,
            constant: constant, function: s("function", SyntaxStyle(color: a[4])), type: s("type", SyntaxStyle(color: a[6])),
            builtin: s("builtin", constant), variable: variable, parameter: s("parameter", variable), property: s("property", variable),
            tag: s("tag", SyntaxStyle(color: a[1])), attribute: s("attribute", SyntaxStyle(color: a[3])),
            added: s("added", SyntaxStyle(color: ui.success)), removed: s("removed", SyntaxStyle(color: ui.error)),
            changed: s("changed", SyntaxStyle(color: ui.warning)))
        if !fallbacks.isEmpty { warnings.append("\(where_): derived \(fallbacks.joined(separator: ", "))") }

        // Wallpapers.
        var wallpapers: [Wallpaper] = []
        for (index, w) in (spec.wallpapers ?? []).enumerated() {
            let path = "\(where_).wallpapers[\(index)]"
            let url = folder.appendingPathComponent(w.file).standardizedFileURL
            var fit = WallpaperFit.fill
            if let f = w.fit { if let parsed = WallpaperFit(rawValue: f) { fit = parsed } else { errors.append("\(path).fit must be fill, fit, stretch, or center") } }
            if !w.file.hasPrefix("wallpapers/") || w.file.contains("..") || w.file.split(separator: "/").count != 2 {
                errors.append("\(path).file must be wallpapers/<name>")
            } else if !FileManager.default.fileExists(atPath: url.path) {
                errors.append("\(path).file \(w.file) does not exist")
            } else if let problem = checkImage(url, limits: limits) {
                errors.append("\(w.file): \(problem)")
            } else if wallpapers.contains(where: { $0.name == url.lastPathComponent }) {
                errors.append("\(path).file \(w.file) is listed twice")
            } else {
                wallpapers.append(Wallpaper(url: url, fit: fit))
            }
        }

        // System look.
        var system = SystemLook()
        if let s = spec.system {
            system.highlightColor = ref(s.highlightColor, "\(where_).system.highlightColor")
            if let accent = s.accentColor {
                if accent == "auto" { system.accent = nearestAccent(to: ui.accent) }
                else if let preset = AccentPreset(name: accent), preset != .hardware { system.accent = preset }
                else { errors.append("\(where_).system.accentColor must be auto or a preset name") }
            }
            if let style = s.iconStyle {
                if let parsed = IconStyle(rawValue: style) { system.iconStyle = parsed }
                else { errors.append("\(where_).system.iconStyle must be default, dark, clear, or tinted") }
            }
            if let tint = s.iconTint {
                if tint == "accent" { system.iconTint = .custom(ui.accent) }
                else if let preset = AccentPreset(name: tint), preset.rawValue >= -1 { system.iconTint = .preset(preset) }
                else if let color = RGBA(hex: tint) { system.iconTint = .custom(color) }
                else { errors.append("\(where_).system.iconTint must be accent, a preset name, or #RRGGBB") }
            }
            if !local.isEmpty { errors.append(contentsOf: local); return nil }
        }

        // Curated overrides.
        var overrides: [String: Data] = [:]
        var prefer: [String: AppOverrideSpec.PreferInstalled] = [:]
        let apps: [(String, AppOverrideSpec?)] = [("vscode", manifest.apps?.vscode), ("neovim", manifest.apps?.neovim)]
        for (integration, spec) in apps {
            guard let spec else { continue }
            if let p = spec.preferInstalled { prefer[integration] = p }
            guard let file = appearance == .dark ? spec.dark : spec.light else { continue }
            let url = folder.appendingPathComponent(file)
            guard file.hasPrefix("apps/"), !file.contains(".."), let data = try? Data(contentsOf: url) else {
                errors.append("apps.\(integration).\(appearance.rawValue): \(file) must be an existing apps/<name>.json file"); continue
            }
            let problems = OverrideValidator.validate(data, integration: integration)
            if problems.isEmpty { overrides[integration] = data } else { errors.append(contentsOf: problems.map { "\(file): \($0)" }) }
        }

        let contrast = ui.foreground.contrast(with: ui.background)
        if contrast < 4.5 { warnings.append("\(where_): foreground on background contrast is \(String(format: "%.1f", contrast)):1, below 4.5:1") }

        return ResolvedVariant(themeID: manifest.id, themeName: manifest.name, themeVersion: manifest.version, appearance: appearance,
                               interface: ui, terminal: terminal, syntax: colors, wallpapers: wallpapers,
                               system: system, overrides: overrides, preferInstalled: prefer)
    }

    /// Reads dimensions and type from the image header without decoding pixels.
    static func checkImage(_ url: URL, limits: Limits) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String? else { return "not a readable image" }
        let allowed = [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier]
        guard allowed.contains(type) else { return "image type \(type) is not allowed; use JPEG, PNG, or HEIC" }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return "image has no size information"
        }
        let longSide = max(width, height)
        if longSide < limits.minImageLongSide { return "image is \(width)×\(height); the long side must be at least \(limits.minImageLongSide) px" }
        if longSide > limits.maxImageLongSide { return "image is \(width)×\(height); the long side must be at most \(limits.maxImageLongSide) px" }
        return nil
    }

    static func checkAssets(_ manifest: ThemeManifest, folder: URL, isBundled: Bool, errors: inout [String], warnings: inout [String]) {
        let wallpaperFiles = Set(manifest.variants.values.flatMap { ($0.wallpapers ?? []).map(\.file) })
        let described = Set((manifest.assets ?? []).map(\.file))
        for file in wallpaperFiles where !described.contains(file) {
            warnings.append("\(file): no license or attribution in assets")
        }
        for asset in manifest.assets ?? [] where asset.license.isEmpty {
            errors.append("assets: \(asset.file) needs a license (use NOASSERTION if unknown)")
        }
    }

    /// Maps a color to the nearest macOS accent preset by hue. Low-saturation colors map to graphite.
    public static func nearestAccent(to color: RGBA) -> AccentPreset {
        let (h, s, l) = color.hsl
        if s < 0.15 || l < 0.08 || l > 0.95 { return .graphite }
        switch h {
        case 0..<15, 345..<360: return .red
        case 15..<40: return .orange
        case 40..<65: return .yellow
        case 65..<165: return .green
        case 165..<255: return .blue
        case 255..<290: return .purple
        default: return .pink
        }
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let c): return "\(path(c)).\(key.stringValue) is required"
        case .typeMismatch(_, let c), .valueNotFound(_, let c): return "\(path(c)): \(c.debugDescription)"
        case .dataCorrupted(let c): return "\(path(c)): \(c.debugDescription)"
        @unknown default: return "\(error)"
        }
    }
}

/// Validates curated per-app override files: color IDs and token rules only.
public enum OverrideValidator {
    static let fontStyles: Set<String> = ["", "bold", "italic", "underline", "strikethrough"]

    public static func validate(_ data: Data, integration: String) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ["must be a JSON object"] }
        var problems: [String] = []
        func isColor(_ v: Any) -> Bool { (v as? String).flatMap(RGBA.init(hex:)) != nil }
        switch integration {
        case "vscode":
            for key in root.keys where !["colors", "tokenColors", "semanticTokenColors"].contains(key) { problems.append("key \"\(key)\" is not allowed") }
            if let colors = root["colors"] {
                guard let map = colors as? [String: Any] else { problems.append("colors must be an object"); break }
                for (id, value) in map {
                    if id.range(of: #"^[A-Za-z0-9.]{1,80}$"#, options: .regularExpression) == nil { problems.append("colors: invalid id \"\(ThemeLoader.sanitized(id))\"") }
                    if !isColor(value) { problems.append("colors.\(id) must be #RRGGBB or #RRGGBBAA") }
                }
            }
            if let rules = root["tokenColors"] {
                guard let list = rules as? [[String: Any]] else { problems.append("tokenColors must be an array of rules"); break }
                for (i, rule) in list.enumerated() {
                    for key in rule.keys where !["name", "scope", "settings"].contains(key) { problems.append("tokenColors[\(i)]: key \"\(key)\" is not allowed") }
                    let scopes = (rule["scope"] as? String).map { [$0] } ?? (rule["scope"] as? [String]) ?? []
                    if scopes.isEmpty || scopes.contains(where: { $0.count > 200 }) { problems.append("tokenColors[\(i)].scope must be a string or string array") }
                    guard let settings = rule["settings"] as? [String: Any] else { problems.append("tokenColors[\(i)].settings is required"); continue }
                    for (key, value) in settings {
                        switch key {
                        case "foreground", "background": if !isColor(value) { problems.append("tokenColors[\(i)].settings.\(key) must be a color") }
                        case "fontStyle":
                            let words = (value as? String)?.split(separator: " ").map(String.init) ?? ["?"]
                            if !words.allSatisfy(fontStyles.contains) { problems.append("tokenColors[\(i)].settings.fontStyle is invalid") }
                        default: problems.append("tokenColors[\(i)].settings.\(key) is not allowed")
                        }
                    }
                }
            }
            if let semantic = root["semanticTokenColors"] {
                guard let map = semantic as? [String: Any] else { problems.append("semanticTokenColors must be an object"); break }
                for (selector, value) in map {
                    if selector.range(of: #"^[A-Za-z0-9*.:_-]{1,80}$"#, options: .regularExpression) == nil { problems.append("semanticTokenColors: invalid selector") }
                    if let object = value as? [String: Any] {
                        for (key, v) in object {
                            switch key {
                            case "foreground": if !isColor(v) { problems.append("semanticTokenColors.\(selector).foreground must be a color") }
                            case "bold", "italic", "underline", "strikethrough": if !(v is Bool) { problems.append("semanticTokenColors.\(selector).\(key) must be true or false") }
                            default: problems.append("semanticTokenColors.\(selector).\(key) is not allowed")
                            }
                        }
                    } else if !isColor(value) { problems.append("semanticTokenColors.\(selector) must be a color or style object") }
                }
            }
        case "neovim":
            for key in root.keys where key != "groups" { problems.append("key \"\(key)\" is not allowed") }
            guard let groups = root["groups"] as? [String: Any] else { problems.append("groups must be an object"); break }
            for (name, value) in groups {
                if name.range(of: #"^[@A-Za-z0-9_.]{1,80}$"#, options: .regularExpression) == nil { problems.append("groups: invalid name \"\(ThemeLoader.sanitized(name))\"") }
                guard let spec = value as? [String: Any] else { problems.append("groups.\(name) must be an object"); continue }
                for (key, v) in spec {
                    switch key {
                    case "fg", "bg", "sp": if !isColor(v) { problems.append("groups.\(name).\(key) must be a color") }
                    case "bold", "italic", "underline", "undercurl", "strikethrough", "reverse": if !(v is Bool) { problems.append("groups.\(name).\(key) must be true or false") }
                    case "link":
                        if (v as? String)?.range(of: #"^[@A-Za-z0-9_.]{1,80}$"#, options: .regularExpression) == nil { problems.append("groups.\(name).link is invalid") }
                    default: problems.append("groups.\(name).\(key) is not allowed")
                    }
                }
            }
        default:
            problems.append("no override schema for \(integration)")
        }
        return problems
    }
}
