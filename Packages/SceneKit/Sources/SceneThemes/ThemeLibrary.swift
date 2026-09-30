import Foundation
import SceneFoundation

/// Bundled themes (read-only, inside the app) and installed themes (~/Library/Application Support/Scene/Themes).
/// Every theme passes `ThemeLoader` validation before it is listed or installed.
public final class ThemeLibrary: @unchecked Sendable {
    public let bundledFolder: URL?
    public let installedFolder: URL

    public init(bundledFolder: URL?, installedFolder: URL) {
        self.bundledFolder = bundledFolder
        self.installedFolder = installedFolder
    }

    public struct Problem: Sendable, Identifiable {
        public var id: String { folder }
        public var folder: String
        public var errors: [String]
    }

    public func loadAll() -> (themes: [Theme], problems: [Problem]) {
        var themes: [Theme] = []
        var problems: [Problem] = []
        for (root, bundled) in [(bundledFolder, true), (Optional(installedFolder), false)] {
            guard let root, let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                guard !folder.lastPathComponent.hasPrefix(".") else { continue }
                do { themes.append(try ThemeLoader.load(folder: folder, isBundled: bundled)) }
                catch let error as ThemeLoadError { problems.append(Problem(folder: folder.lastPathComponent, errors: error.errors)) }
                catch { problems.append(Problem(folder: folder.lastPathComponent, errors: ["\(error)"])) }
            }
        }
        // An installed theme with the same id replaces the bundled one.
        var byID: [String: Theme] = [:]
        for theme in themes where byID[theme.id] == nil || !theme.isBundled { byID[theme.id] = theme }
        return (byID.values.sorted { $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending }, problems)
    }

    public func find(id: String) -> Theme? { loadAll().themes.first { $0.id == id } }

    // MARK: Import

    static let allowedPath = #"^(theme\.json|README\.md|wallpapers/[A-Za-z0-9._ -]{1,80}\.(heic|jpg|jpeg|png)|apps/[A-Za-z0-9._-]{1,80}\.json)$"#

    /// Imports a `.scenetheme` file or a theme folder. The theme is validated before anything is installed.
    @discardableResult
    public func importPackage(at url: URL) throws -> Theme {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { throw SceneError.invalid("\(url.lastPathComponent) does not exist") }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scene-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        if isDirectory.boolValue {
            if OmarchyImporter.colorFiles.contains(where: { FileManager.default.fileExists(atPath: url.appendingPathComponent($0).path) }),
               !FileManager.default.fileExists(atPath: url.appendingPathComponent("theme.json").path) {
                return try importOmarchy(folder: url)
            }
            // Only the theme's own files are copied, and install() validates the copy. Other files, such as
            // a repository's .git folder or LICENSE, stay behind.
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for relative in try Self.allowedFiles(in: url) {
                try FileOps.write(Data(contentsOf: url.appendingPathComponent(relative)), to: staging.appendingPathComponent(relative))
            }
        } else {
            let files = try ZipArchive.read(Data(contentsOf: url))
            for path in files.keys where path.range(of: Self.allowedPath, options: .regularExpression) == nil {
                throw SceneError.invalid("\(path) is not allowed in a theme package")
            }
            for (path, data) in files { try FileOps.write(data, to: staging.appendingPathComponent(path)) }
        }
        return try install(staging)
    }

    static func allowedFiles(in folder: URL) throws -> [String] {
        let base = folder.standardizedFileURL.path
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if relative.range(of: allowedPath, options: .regularExpression) != nil { files.append(relative) }
        }
        return files
    }

    /// Validates a staged folder and moves it into the library, replacing an older copy of the same theme.
    func install(_ staging: URL) throws -> Theme {
        let theme = try ThemeLoader.load(folder: staging)
        let target = installedFolder.appendingPathComponent(theme.id.replacingOccurrences(of: "/", with: "--"))
        try FileManager.default.createDirectory(at: installedFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: staging, to: target)
        return try ThemeLoader.load(folder: target)
    }

    public func remove(_ theme: Theme) throws {
        guard !theme.isBundled else { throw SceneError.invalid("Bundled themes cannot be removed") }
        try FileManager.default.removeItem(at: theme.folder)
    }

    // MARK: Export

    public func export(_ theme: Theme, to url: URL) throws {
        let files = try Self.allowedFiles(in: theme.folder).sorted().map { (path: $0, data: try Data(contentsOf: theme.folder.appendingPathComponent($0))) }
        try ZipArchive.create(files: files).write(to: url, options: .atomic)
    }

    // MARK: Omarchy

    /// Converts an Omarchy theme folder (colors.toml and backgrounds/) into a Scene theme. A theme without
    /// colors.toml gives its colors through alacritty.toml. Only colors and images are read.
    /// Config files and Lua in the folder are ignored and never run.
    @discardableResult
    public func importOmarchy(folder: URL) throws -> Theme {
        let colors: [String: String]
        if let text = try? String(contentsOf: folder.appendingPathComponent("colors.toml"), encoding: .utf8) {
            colors = OmarchyImporter.parse(text)
        } else if let text = try? String(contentsOf: folder.appendingPathComponent("alacritty.toml"), encoding: .utf8) {
            colors = OmarchyImporter.parseAlacritty(text)
        } else {
            throw SceneError.invalid("\(folder.lastPathComponent) has no colors.toml or alacritty.toml")
        }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scene-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging.appendingPathComponent("wallpapers"), withIntermediateDirectories: true)
        let name = folder.lastPathComponent
        // Every background that fits in a theme package, in Omarchy's order.
        let limits = ThemeLoader.Limits()
        var wallpapers: [String] = []
        var bytes = 0
        let backgrounds = (try? FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("backgrounds"), includingPropertiesForKeys: nil)) ?? []
        for image in backgrounds.filter({ ["jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try? image.resourceValues(forKeys: [.isSymbolicLinkKey, .fileSizeKey])
            let size = values?.fileSize ?? .max
            let file = "wallpapers/\(OmarchyImporter.slug(image.deletingPathExtension().lastPathComponent)).\(image.pathExtension.lowercased())"
            guard values?.isSymbolicLink != true, size <= limits.maxImageBytes, bytes + size <= limits.maxTotalBytes - limits.maxJSONBytes,
                  !wallpapers.contains(file), ThemeLoader.checkImage(image, limits: limits) == nil else { continue }
            try FileManager.default.copyItem(at: image, to: staging.appendingPathComponent(file))
            wallpapers.append(file)
            bytes += size
        }
        let manifest = try OmarchyImporter.manifest(name: name, colors: colors, wallpapers: wallpapers)
        try manifest.write(to: staging.appendingPathComponent("theme.json"))
        return try install(staging)
    }
}

/// Maps Omarchy's colors.toml keys to Scene roles, following Omarchy's own templates.
/// Omarchy 4 uses named keys (`red`, `bright_red`, `muted`). Older themes use `color0` to `color15`,
/// which map as Omarchy maps them: 8 is muted, 9 to 14 the bright colors, 15 the bright foreground.
public enum OmarchyImporter {
    /// The files an Omarchy theme can give its colors in, in the order Scene reads them.
    public static let colorFiles = ["colors.toml", "alacritty.toml"]

    /// Colors from an Alacritty config, under the keys `parse` returns for an older colors.toml.
    public static func parseAlacritty(_ text: String) -> [String: String] {
        let doc = KeyValueDocument(text: text)
        func value(_ key: String) -> String? {
            guard var raw = doc.value(forKey: key)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) else { return nil }
            if raw.lowercased().hasPrefix("0x") { raw = "#" + raw.dropFirst(2) }
            return raw
        }
        var out: [String: String] = [:]
        out["background"] = value("colors.primary.background")
        out["foreground"] = value("colors.primary.foreground")
        out["selection_background"] = value("colors.selection.background")
        for (index, name) in ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"].enumerated() {
            out["color\(index)"] = value("colors.normal.\(name)")
            out["color\(index + 8)"] = value("colors.bright.\(name)")
        }
        return out.compactMapValues { $0 }
    }

    /// Reads `key = "value"` lines. Anything else is ignored.
    public static func parse(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard key.range(of: #"^[a-z0-9_]{1,40}$"#, options: .regularExpression) != nil else { continue }
            out[key] = value
        }
        return out
    }

    public static func slug(_ s: String) -> String {
        let cleaned = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(String(cleaned).split(separator: "-").joined(separator: "-").prefix(60))
    }

    /// One theme.json variant from Omarchy-style colors, with the role mapping of Omarchy's own templates.
    /// Missing shades are mixed from the other colors. Scene's own themes and theme drafts use the same mapping.
    public static func variant(colors c: [String: String], system: [String: String] = ["accentColor": "auto"],
                               wallpapers: [String]) throws -> [String: Any] {
        func color(_ key: String, _ fallbacks: String...) throws -> String {
            for k in [key] + fallbacks { if let v = c[k], RGBA(hex: v) != nil { return v } }
            throw SceneError.invalid("colors.toml has no valid \(key)")
        }
        func mix(_ a: String, _ b: String, _ amount: Double) -> String {
            RGBA(hex: a)!.mixed(over: RGBA(hex: b)!, amount: amount).hex
        }
        let bg = try color("background", "bg"), fg = try color("foreground", "fg")
        let bright = (try? color("bright_foreground", "bright_fg", "color15")) ?? fg
        let darkFg = (try? color("dark_foreground", "dark_fg", "muted", "color8")) ?? mix(fg, bg, 0.5)
        let muted = (try? color("muted", "color8", "dark_foreground", "dark_fg")) ?? mix(fg, bg, 0.3)
        let darkBg = (try? color("dark_background", "dark_bg")) ?? mix("#000000", bg, 0.2)
        let lighterBg = (try? color("lighter_background", "lighter_bg")) ?? mix(fg, bg, 0.08)
        let red = try color("red", "color1"), green = try color("green", "color2"), yellow = try color("yellow", "color3")
        let blue = try color("blue", "color4"), magenta = try color("magenta", "purple", "color5"), cyan = try color("cyan", "color6")
        let orange = (try? color("orange")) ?? yellow
        func b(_ key: String, _ legacy: String, _ normal: String) -> String { (try? color(key, legacy)) ?? normal }
        let accent = (try? color("accent")) ?? blue
        let selection = (try? color("selection", "selection_background")) ?? mix(accent, bg, 0.3)
        var variant: [String: Any] = [
            "palette": ["background": bg, "surface": darkBg, "overlay": lighterBg, "border": muted, "foreground": fg, "muted": darkFg,
                        "accent": accent, "selection": selection, "cursor": bright, "currentLine": mix(lighterBg, bg, 0.5),
                        "search": mix(yellow, bg, 0.3), "error": red, "warning": yellow, "success": green, "info": blue],
            "terminal": ["background": "@background", "foreground": "@foreground", "cursor": "@cursor", "cursorText": "@background",
                         "selectionBackground": "@selection", "selectionForeground": bright,
                         "ansi": ["black": bg, "red": red, "green": green, "yellow": yellow, "blue": blue, "magenta": magenta, "cyan": cyan, "white": fg,
                                  "brightBlack": muted, "brightRed": b("bright_red", "color9", red), "brightGreen": b("bright_green", "color10", green),
                                  "brightYellow": b("bright_yellow", "color11", yellow), "brightBlue": b("bright_blue", "color12", blue),
                                  "brightMagenta": b("bright_magenta", "color13", magenta), "brightCyan": b("bright_cyan", "color14", cyan),
                                  "brightWhite": bright]],
            "syntax": ["comment": ["color": darkFg, "italic": true], "keyword": b("bright_magenta", "color13", magenta),
                       "operator": b("bright_blue", "color12", blue),
                       "punctuation": darkFg, "string": green, "escape": b("bright_magenta", "color13", magenta), "number": orange, "constant": orange,
                       "function": blue, "type": yellow, "builtin": cyan, "variable": fg, "parameter": ["color": cyan, "italic": true],
                       "property": cyan, "tag": red, "attribute": ["color": cyan, "italic": true], "added": green, "removed": red, "changed": yellow],
            "system": system,
        ]
        if !wallpapers.isEmpty { variant["wallpapers"] = wallpapers.map { ["file": $0, "fit": "fill"] } }
        return variant
    }

    /// "dark" or "light": the `mode` key, or else how dark the background is.
    public static func mode(colors c: [String: String]) -> String {
        if let m = c["mode"], ["light", "dark"].contains(m) { return m }
        return (RGBA(hex: c["background"] ?? c["bg"] ?? "") ?? RGBA(r: 0, g: 0, b: 0)).isDark ? "dark" : "light"
    }

    public static func manifest(name: String, colors c: [String: String], wallpapers: [String]) throws -> Data {
        let variant = try variant(colors: c, wallpapers: wallpapers)
        let mode = mode(colors: c)
        let assets = wallpapers.map { ["file": $0, "license": "NOASSERTION", "attribution": "From the Omarchy theme \(ThemeLoader.sanitized(name))"] }
        let displayName = name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        var manifest: [String: Any] = [
            "format": 1, "id": "omarchy/\(slug(name))", "version": "1.0.0", "name": String(displayName.prefix(64)),
            "summary": "Imported from an Omarchy theme. Colors only; config files were ignored.",
            "authors": [["name": "Omarchy theme author"]], "license": "NOASSERTION", "tags": ["omarchy", "imported"],
            "variants": [mode: variant],
        ]
        if !assets.isEmpty { manifest["assets"] = assets }
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }
}
