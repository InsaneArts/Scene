import Foundation
import ImageIO
import SceneFoundation
import UniformTypeIdentifiers

/// A theme being made: Omarchy's color keys for each look, the macOS look, and three wallpapers per look with
/// their credits. The Theme Maker edits one, an agent writes one as JSON, and `write(to:)` turns it into a theme
/// folder that Scene installs and that can go on GitHub as it is.
public struct ThemeDraft: Codable, Sendable, Equatable {
    public var name: String
    public var summary: String
    public var author: String
    /// The theme's own license, as an SPDX id such as MIT.
    public var license: String
    public var version: String
    public var tags: [String]
    public var dark: Look?
    public var light: Look?

    public struct Look: Codable, Sendable, Equatable {
        /// Omarchy's colors.toml keys (`ThemeDraft.colorKeys`), as `#rrggbb`.
        public var colors: [String: String]
        /// `auto` (the preset nearest the accent) or a preset: multicolor, graphite, red, orange, yellow, green, blue, purple, pink.
        public var accentColor: String
        /// default, dark, clear, or tinted.
        public var iconStyle: String
        /// For tinted icons: `accent`, a preset, or `#rrggbb`.
        public var iconTint: String?
        public var wallpapers: [Wallpaper]

        public init(colors: [String: String], accentColor: String = "auto", iconStyle: String = "default", iconTint: String? = nil,
                    wallpapers: [Wallpaper] = []) {
            self.colors = colors; self.accentColor = accentColor; self.iconStyle = iconStyle; self.iconTint = iconTint; self.wallpapers = wallpapers
        }

        /// True when the macOS look holds values Scene accepts, so the preview can show it.
        var hasValidSystem: Bool {
            let tintValid = iconTint.map { $0 == "accent" || AccentPreset(name: $0) != nil || RGBA(hex: $0) != nil } ?? false
            return (accentColor == "auto" || AccentPreset(name: accentColor) != nil) && IconStyle(rawValue: iconStyle) != nil
                && (iconStyle != IconStyle.tinted.rawValue || tintValid)
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            colors = try c.decode([String: String].self, forKey: .colors)
            accentColor = try c.decodeIfPresent(String.self, forKey: .accentColor) ?? "auto"
            iconStyle = try c.decodeIfPresent(String.self, forKey: .iconStyle) ?? "default"
            iconTint = try c.decodeIfPresent(String.self, forKey: .iconTint)
            wallpapers = try c.decodeIfPresent([Wallpaper].self, forKey: .wallpapers) ?? []
        }
    }

    public struct Wallpaper: Codable, Sendable, Equatable {
        /// The image. In a draft file, a relative path is relative to the file.
        public var file: String
        /// An SPDX id such as CC0-1.0, or LicenseRef-OwnWork for your own picture.
        public var license: String
        public var attribution: String?
        public var source: String?

        public init(file: String, license: String = "", attribution: String? = nil, source: String? = nil) {
            self.file = file; self.license = license; self.attribution = attribution; self.source = source
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            file = try c.decode(String.self, forKey: .file)
            license = try c.decodeIfPresent(String.self, forKey: .license) ?? ""
            attribution = try c.decodeIfPresent(String.self, forKey: .attribution)
            source = try c.decodeIfPresent(String.self, forKey: .source)
        }
    }

    public init(name: String, summary: String = "", author: String, license: String = "MIT", version: String = "1.0.0",
                tags: [String] = [], dark: Look? = nil, light: Look? = nil) {
        self.name = name; self.summary = summary; self.author = author; self.license = license; self.version = version
        self.tags = tags; self.dark = dark; self.light = light
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        license = try c.decodeIfPresent(String.self, forKey: .license) ?? ""
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? "1.0.0"
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        dark = try c.decodeIfPresent(Look.self, forKey: .dark)
        light = try c.decodeIfPresent(Look.self, forKey: .light)
    }

    public static let wallpapersPerLook = 3

    /// The keys a look sets, in the Theme Maker's order: base, shades, colors, bright colors.
    public static let colorKeys = ["background", "foreground", "accent", "selection",
                                   "dark_background", "lighter_background", "muted", "dark_foreground", "bright_foreground",
                                   "red", "orange", "yellow", "green", "cyan", "blue", "magenta",
                                   "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]
    /// The keys without which a look cannot be built. The others are mixed from these.
    public static let requiredKeys = ["background", "foreground", "accent", "red", "yellow", "green", "cyan", "blue", "magenta"]

    /// The Theme Maker's names for the keys. The palette check uses the same words.
    public static let labels: [String: String] = [
        "background": "Background", "dark_background": "Panels", "lighter_background": "Popups", "foreground": "Text",
        "dark_foreground": "Dim text", "bright_foreground": "Bright text", "muted": "Borders", "selection": "Selection",
        "accent": "Accent", "red": "Red", "orange": "Orange", "yellow": "Yellow", "green": "Green", "cyan": "Cyan",
        "blue": "Blue", "magenta": "Magenta", "bright_red": "Bright red", "bright_yellow": "Bright yellow",
        "bright_green": "Bright green", "bright_cyan": "Bright cyan", "bright_blue": "Bright blue", "bright_magenta": "Bright magenta",
    ]

    public func look(_ appearance: Appearance) -> Look? { appearance == .dark ? dark : light }

    public mutating func setLook(_ look: Look?, for appearance: Appearance) {
        if appearance == .dark { dark = look } else { light = look }
    }

    public var looks: [(appearance: Appearance, look: Look)] {
        [(Appearance.dark, dark), (.light, light)].compactMap { appearance, look in look.map { (appearance, $0) } }
    }

    /// `<author>/<name>` in the characters a theme id allows. Saving a draft again with the same author and name
    /// replaces the theme it made before.
    public var id: String {
        let creator = Self.slug(author), slug = Self.slug(name)
        return "\(creator.isEmpty ? "local" : creator)/\(slug.isEmpty ? "theme" : slug)"
    }

    /// The name of the theme's folder, for example `amber-night`.
    public var folderName: String { Self.slug(name).isEmpty ? "theme" : Self.slug(name) }

    /// Lowercase ASCII letters and digits, with "-" between words.
    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        var out = ""
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) { out.unicodeScalars.append(scalar) }
            else if !out.isEmpty && !out.hasSuffix("-") { out.append("-") }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return String(out.prefix(60))
    }

    // MARK: Starting points

    /// Starts from an existing theme: its colors in Omarchy's keys, its macOS look, and its wallpapers with their credits.
    /// Another author's theme becomes "<name> Copy", so saving it adds a theme instead of replacing one.
    public init(theme: Theme, author: String) {
        let own = ThemeDraft(name: theme.manifest.name, author: author).id == theme.id
        self.init(name: own ? theme.manifest.name : String((theme.manifest.name + " Copy").prefix(64)),
                  summary: theme.manifest.summary ?? "", author: author, license: own ? theme.manifest.license : "MIT",
                  version: own ? theme.manifest.version : "1.0.0", tags: theme.manifest.tags ?? [])
        let assets = theme.manifest.assets ?? []
        dark = theme.variants[.dark].map { Self.look($0, assets: assets) }
        light = theme.variants[.light].map { Self.look($0, assets: assets) }
    }

    static func look(_ v: ResolvedVariant, assets: [ThemeManifest.AssetSpec]) -> Look {
        let ui = v.interface, a = v.terminal.ansi
        let colors: [String: RGBA] = [
            "background": ui.background, "dark_background": ui.surface, "lighter_background": ui.overlay, "foreground": ui.foreground,
            "dark_foreground": ui.muted, "bright_foreground": ui.cursor, "muted": ui.border, "selection": ui.selection, "accent": ui.accent,
            "red": a[1], "green": a[2], "yellow": a[3], "blue": a[4], "magenta": a[5], "cyan": a[6], "orange": v.syntax.number.color,
            "bright_red": a[9], "bright_green": a[10], "bright_yellow": a[11], "bright_blue": a[12], "bright_magenta": a[13], "bright_cyan": a[14],
        ]
        let tint: String? = switch v.system.iconTint {
        case .preset(let preset)?: preset.name
        case .custom(let color)?: color == ui.accent ? "accent" : color.hex
        case nil: nil
        }
        let wallpapers = v.wallpapers.map { wallpaper in
            let asset = assets.first { $0.file == "wallpapers/\(wallpaper.name)" }
            return Wallpaper(file: wallpaper.url.path, license: asset?.license ?? "", attribution: asset?.attribution, source: asset?.source)
        }
        return Look(colors: colors.mapValues(\.hex), accentColor: v.system.accent?.name ?? "auto",
                    iconStyle: v.system.iconStyle?.rawValue ?? "default",
                    iconTint: v.system.iconStyle == .tinted ? (tint ?? "accent") : tint, wallpapers: wallpapers)
    }

    /// Reads a draft file. Relative wallpaper paths become absolute, relative to the file.
    public static func read(_ url: URL) throws -> ThemeDraft {
        var draft: ThemeDraft
        do { draft = try JSONDecoder().decode(ThemeDraft.self, from: Data(contentsOf: url)) }
        catch let error as DecodingError { throw SceneError.invalid("\(url.lastPathComponent): \(ThemeLoader.describe(error))") }
        let base = url.deletingLastPathComponent()
        func absolute(_ look: inout Look?) {
            guard var value = look else { return }
            for index in value.wallpapers.indices where !value.wallpapers[index].file.hasPrefix("/") {
                value.wallpapers[index].file = base.appendingPathComponent(value.wallpapers[index].file).standardizedFileURL.path
            }
            look = value
        }
        absolute(&draft.dark)
        absolute(&draft.light)
        return draft
    }

    // MARK: Checks

    public struct Issue: Sendable, Equatable, Hashable {
        public var message: String
        public var isError: Bool
    }

    /// What stops the draft from becoming a complete theme (errors), and weak spots worth a look (warnings).
    public func check() -> [Issue] {
        var issues: [Issue] = []
        func error(_ message: String) { issues.append(Issue(message: message, isError: true)) }
        func warning(_ message: String) { issues.append(Issue(message: message, isError: false)) }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { error("Give the theme a name.") }
        if trimmedName.count > 64 || ThemeLoader.sanitized(name) != name { error("Keep the name to 64 characters of plain text.") }
        if author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error("Add the author's name.") }
        if version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) == nil { error("The version must look like 1.2.0.") }
        if looks.isEmpty { error("Turn on the dark look, the light look, or both.") }

        var bytes = 0
        let limits = ThemeLoader.Limits()
        for (appearance, look) in looks {
            let title = appearance == .dark ? "Dark look" : "Light look"
            var colorsValid = true
            for key in Self.requiredKeys where look.colors[key] == nil {
                error("\(title): \(Self.labels[key] ?? key) needs a color, such as #1a1b26."); colorsValid = false
            }
            for (key, value) in look.colors.sorted(by: { $0.key < $1.key }) where RGBA(hex: value) == nil {
                error("\(title): \(Self.labels[key] ?? key) is “\(ThemeLoader.sanitized(value))”, not a color such as #1a1b26."); colorsValid = false
            }
            if colorsValid {
                do {
                    let variant = try preview(only: appearance).variants[appearance]!
                    let result = PaletteCheck.check(variant)
                    result.errors.forEach { error("\(title): \($0)") }
                    result.warnings.forEach { warning("\(title): \($0)") }
                } catch {
                    issues.append(Issue(message: "\(title): \(error)", isError: true))
                }
            }
            if look.accentColor != "auto" && AccentPreset(name: look.accentColor) == nil {
                error("\(title): the accent color must be auto or a macOS preset, such as blue.")
            }
            if IconStyle(rawValue: look.iconStyle) == nil { error("\(title): the icon style must be default, dark, clear, or tinted.") }
            if look.iconStyle == IconStyle.tinted.rawValue {
                let tint = look.iconTint ?? ""
                if tint != "accent" && AccentPreset(name: tint) == nil && RGBA(hex: tint) == nil {
                    error("\(title): tinted icons need a tint: accent, a macOS preset, or a color such as #ff8800.")
                }
            }
            let missing = Self.wallpapersPerLook - look.wallpapers.count
            if missing > 0 { error("\(title): add \(missing) more wallpaper\(missing == 1 ? "" : "s"). A theme has \(Self.wallpapersPerLook) for each look.") }
            for (index, wallpaper) in look.wallpapers.enumerated() {
                let label = "\(title), wallpaper \(index + 1)"
                let url = URL(fileURLWithPath: wallpaper.file)
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? nil
                if size == nil {
                    error("\(label): \(url.lastPathComponent) cannot be read.")
                } else if let problem = ThemeLoader.checkImage(url, limits: limits) {
                    error("\(label): \(problem).")
                } else if let size, size > limits.maxImageBytes {
                    error("\(label): the file is \(size / 1_048_576) MB. Keep each wallpaper under 20 MB.")
                }
                bytes += size ?? 0
            }
        }
        if bytes > limits.maxTotalBytes - limits.maxJSONBytes {
            error("The wallpapers are \(bytes / 1_048_576) MB together. A theme holds at most \((limits.maxTotalBytes - limits.maxJSONBytes) / 1_048_576) MB.")
        }
        return issues
    }

    // MARK: Building

    /// The theme's colors as Scene resolves them, without wallpapers or files. The Theme Maker's preview uses it on
    /// every slider move.
    public func preview(only appearance: Appearance? = nil) throws -> Theme {
        try ThemeLoader.load(manifest: try manifest(files: [:], preview: true, only: appearance),
                             folder: FileManager.default.temporaryDirectory)
    }

    /// theme.json. `files` holds each look's wallpaper names in the theme's `wallpapers/` folder.
    /// A preview has no wallpapers, and takes the macOS look only when it is valid, so it loads while the draft is incomplete.
    func manifest(files: [Appearance: [String]], preview: Bool = false, only: Appearance? = nil) throws -> Data {
        var variants: [String: Any] = [:]
        var assets: [[String: String]] = []
        for (appearance, look) in looks where only == nil || only == appearance {
            var system = ["accentColor": look.accentColor, "iconStyle": look.iconStyle]
            if look.iconStyle == IconStyle.tinted.rawValue, let tint = look.iconTint { system["iconTint"] = tint }
            let names = files[appearance] ?? []
            variants[appearance.rawValue] = try OmarchyImporter.variant(colors: look.colors, system: preview && !look.hasValidSystem ? ["accentColor": "auto"] : system,
                                                                        wallpapers: names.map { "wallpapers/\($0)" })
            // Credits are optional. A wallpaper that has some keeps them in the theme and its README.
            for (name, wallpaper) in zip(names, look.wallpapers) {
                func clean(_ text: String?) -> String? { text?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty }
                let license = clean(wallpaper.license), attribution = clean(wallpaper.attribution), source = clean(wallpaper.source)
                guard license != nil || attribution != nil || source != nil else { continue }
                var asset = ["file": "wallpapers/\(name)", "license": license ?? "NOASSERTION"]
                if let attribution { asset["attribution"] = attribution }
                if let source { asset["source"] = source }
                assets.append(asset)
            }
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLicense = license.trimmingCharacters(in: .whitespacesAndNewlines)
        var manifest: [String: Any] = [
            "format": 1, "id": id, "version": preview ? "1.0.0" : version,
            "name": preview && trimmedName.isEmpty ? "Preview" : trimmedName,
            "authors": [["name": preview ? "Preview" : author.trimmingCharacters(in: .whitespacesAndNewlines)]],
            "license": preview || trimmedLicense.isEmpty ? "MIT" : trimmedLicense, "variants": variants,
        ]
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty { manifest["summary"] = trimmedSummary }
        if !tags.isEmpty { manifest["tags"] = tags }
        if !assets.isEmpty { manifest["assets"] = assets }
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    /// Writes the theme folder: theme.json, README.md, and `wallpapers/<look>-<n>.<ext>`. Scene builds it in a scratch
    /// folder and loads it first, so the target changes only when the theme is valid. Other files in the target stay,
    /// so the folder can be a git repository with its own LICENSE.
    public func write(to folder: URL) throws {
        let errors = check().filter(\.isError)
        guard errors.isEmpty else { throw SceneError.invalid(errors.map(\.message).joined(separator: "\n")) }
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: folder.path),
           contents.contains(where: { !$0.hasPrefix(".") }), !contents.contains("theme.json") {
            throw SceneError.invalid("\(folder.path) already holds other files. Choose an empty folder or a theme folder.")
        }
        let staging = fm.temporaryDirectory.appendingPathComponent("scene-draft-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        var files: [Appearance: [String]] = [:]
        for (appearance, look) in looks {
            for (index, wallpaper) in look.wallpapers.enumerated() {
                let source = URL(fileURLWithPath: wallpaper.file)
                let name = "\(appearance.rawValue)-\(index + 1).\(Self.imageExtension(source))"
                try FileOps.write(Data(contentsOf: source), to: staging.appendingPathComponent("wallpapers/\(name)"))
                files[appearance, default: []].append(name)
            }
        }
        try FileOps.write(try manifest(files: files), to: staging.appendingPathComponent("theme.json"))
        try FileOps.write(readme(files: files), to: staging.appendingPathComponent("README.md"))
        _ = try ThemeLoader.load(folder: staging)

        // Replace the files Scene writes, and nothing else.
        let wallpapers = folder.appendingPathComponent("wallpapers")
        for name in (try? fm.contentsOfDirectory(atPath: wallpapers.path)) ?? []
        where name.range(of: #"^(dark|light)-[0-9]+\.(jpg|jpeg|png|heic)$"#, options: .regularExpression) != nil {
            try fm.removeItem(at: wallpapers.appendingPathComponent(name))
        }
        for relative in try ThemeLibrary.allowedFiles(in: staging) {
            try FileOps.write(Data(contentsOf: staging.appendingPathComponent(relative)), to: folder.appendingPathComponent(relative))
        }
    }

    /// The extension for an image's real type: jpg, png, or heic.
    static func imageExtension(_ url: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) as String? else { return "jpg" }
        switch type {
        case UTType.png.identifier: return "png"
        case UTType.heic.identifier: return "heic"
        default: return "jpg"
        }
    }

    /// A README for the theme's repository: a picture, how to install, the colors, and every credit.
    func readme(files: [Appearance: [String]]) -> String {
        let name = ThemeLoader.sanitized(self.name.trimmingCharacters(in: .whitespacesAndNewlines))
        var lines = ["<!-- Made with Scene's Theme Maker. Scene writes this file again when you export the theme. -->", "# \(name)", ""]
        let summary = ThemeLoader.sanitized(self.summary.trimmingCharacters(in: .whitespacesAndNewlines))
        if !summary.isEmpty { lines += [summary, ""] }
        // GitHub shows JPEG and PNG pictures in every browser, and HEIC only in Safari.
        if let picture = ((files[.dark] ?? []) + (files[.light] ?? [])).first(where: { !$0.hasSuffix(".heic") }) {
            lines += ["![\(name)](wallpapers/\(picture))", ""]
        }
        lines += ["A theme for [Scene](https://github.com/InsaneArts/Scene), the Mac app that gives the desktop, terminals, and code editors one theme in one step.",
                  "", "## Install", "", "In Scene, choose **Add Theme → Install from GitHub…**, and paste the address of this repository.", "", "## Looks", ""]
        for (appearance, look) in looks {
            let keys = ["background", "foreground", "accent"].map { "\(Self.labels[$0]!.lowercased()) `\(look.colors[$0] ?? "")`" }
            lines.append("- \(appearance == .dark ? "Dark" : "Light"): \(keys.joined(separator: ", ")).")
        }
        lines += ["", "## Credits", "", "- Theme: \(ThemeLoader.sanitized(author))."]
        for (appearance, look) in looks {
            for (file, wallpaper) in zip(files[appearance] ?? [], look.wallpapers) {
                func clean(_ text: String?) -> String? { text.map { ThemeLoader.sanitized($0.trimmingCharacters(in: .whitespacesAndNewlines)) }?.nonEmpty }
                let source = clean(wallpaper.source).map { $0.hasPrefix("https://") || $0.hasPrefix("http://") ? "[source](\($0))" : $0 }
                let parts = [clean(wallpaper.attribution), source].compactMap { $0 }
                if !parts.isEmpty { lines.append("- `wallpapers/\(file)`: \(parts.joined(separator: ", ")).") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
