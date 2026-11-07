import Foundation

/// macOS keeps a wallpaper for each Space in `com.apple.wallpaper/Store/Index.plist`, and
/// `NSWorkspace.setDesktopImageURL` changes only the Space on screen. The format is undocumented (seen on macOS 15 to 27),
/// so Scene writes it only as the experimental tweak `wallpaperSpaces`.
///
/// An entry is a node whose `Desktop` holds the wallpaper. A display has one entry in each Space: the Space's
/// `Displays/<uuid>`, or the Space's `Default` when it has none. `Displays/<uuid>` and `SystemDefault` are what new Spaces
/// start with. Entry keys are paths such as `Spaces/<space>/Displays/<uuid>`.
public enum WallpaperStore {
    public static var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// What each entry of the displays shows: the image path, or `provider:<id>` for a wallpaper that is not an image file.
    /// Entries without a wallpaper are left out. Nil when the store has a shape Scene does not know.
    public static func images(_ data: Data, displays: [String]) -> [String: String]? {
        guard let root = try? read(data), let keys = entryKeys(root, displays: displays) else { return nil }
        var out: [String: String] = [:]
        for key in keys {
            guard let desktop = node(root, key)?["Desktop"] as? [String: Any] else { continue }
            out[key] = describe(desktop)
        }
        return out
    }

    /// Copies the wallpaper that macOS wrote for `imagePath` on the Space on screen to every entry of each display, so the
    /// placement and color that macOS chose come along. Nil until macOS has written that wallpaper for every display.
    public static func spreading(_ data: Data, displays: [String], imagePath: String, now: Date = Date()) throws -> Data? {
        guard var root = try read(data) else { return nil }
        for display in displays {
            guard let keys = entryKeys(root, displays: [display]),
                  let template = keys.lazy.compactMap({ node(root, $0)?["Desktop"] as? [String: Any] })
                      .first(where: { describe($0) == imagePath }),
                  let content = template["Content"] else { return nil }
            for key in keys {
                var entry = node(root, key) ?? [:]
                var desktop = entry["Desktop"] as? [String: Any] ?? [:]
                desktop["Content"] = content
                desktop["LastSet"] = now
                desktop["LastUse"] = now
                entry["Desktop"] = desktop
                root = setting(root, key, entry)
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    /// The `Desktop` of each entry of the displays, as a property list for a backup. An entry without one is an empty dictionary.
    public static func backup(_ data: Data, displays: [String]) throws -> Data? {
        guard let root = try read(data), let keys = entryKeys(root, displays: displays) else { return nil }
        var desktops: [String: Any] = [:]
        for key in keys { desktops[key] = node(root, key)?["Desktop"] as? [String: Any] ?? [String: Any]() }
        return try PropertyListSerialization.data(fromPropertyList: desktops, format: .binary, options: 0)
    }

    /// Puts each entry that still shows `sceneImage` back as it was in `backup`. An entry that someone changed after
    /// Scene keeps its wallpaper. An entry that had no wallpaper before loses the one Scene gave it, and so does an entry that
    /// macOS made after Scene, such as a new Space.
    public static func restoring(_ data: Data, displays: [String], sceneImage: String, backup: Data) throws -> Data? {
        guard var root = try read(data), let keys = entryKeys(root, displays: displays),
              let saved = try PropertyListSerialization.propertyList(from: backup, format: nil) as? [String: Any] else { return nil }
        for key in Set(keys).union(saved.keys) {
            guard var entry = node(root, key), let desktop = entry["Desktop"] as? [String: Any], describe(desktop) == sceneImage else { continue }
            if let original = saved[key] as? [String: Any], !original.isEmpty {
                entry["Desktop"] = original
                root = setting(root, key, entry)
            } else {
                entry["Desktop"] = nil
                root = setting(root, key, entry.isEmpty ? nil : entry)
            }
        }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    // MARK: Format

    static func read(_ data: Data) throws -> [String: Any]? {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["Spaces"] is [String: Any] else { return nil }
        return root
    }

    /// The entries that show a wallpaper on the displays, in a stable order.
    static func entryKeys(_ root: [String: Any], displays: [String]) -> [String]? {
        guard let spaces = root["Spaces"] as? [String: Any] else { return nil }
        var keys: [String] = []
        for display in displays {
            for (id, value) in spaces.sorted(by: { $0.key < $1.key }) {
                guard let space = value as? [String: Any] else { return nil }
                keys.append((space["Displays"] as? [String: Any])?[display] != nil ? "Spaces/\(id)/Displays/\(display)" : "Spaces/\(id)/Default")
            }
            keys.append("Displays/\(display)")
        }
        if root["SystemDefault"] != nil { keys.append("SystemDefault") }
        var seen = Set<String>()
        return keys.filter { seen.insert($0).inserted }
    }

    /// The image path of a `Desktop`, or `provider:<id>` when its wallpaper is not an image file.
    static func describe(_ desktop: [String: Any]) -> String {
        guard let choice = ((desktop["Content"] as? [String: Any])?["Choices"] as? [[String: Any]])?.first else { return "none" }
        if let data = choice["Configuration"] as? Data,
           let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let relative = (configuration["url"] as? [String: Any])?["relative"] as? String, let url = URL(string: relative), url.isFileURL {
            return url.path
        }
        return "provider:\(choice["Provider"] as? String ?? "unknown")"
    }

    static func node(_ root: [String: Any], _ key: String) -> [String: Any]? {
        var current: Any? = root
        for part in key.split(separator: "/", omittingEmptySubsequences: false) { current = (current as? [String: Any])?[String(part)] }
        return current as? [String: Any]
    }

    /// The root with `value` at `key`, creating the dictionaries on the way. A nil value removes the key.
    static func setting(_ root: [String: Any], _ key: String, _ value: [String: Any]?) -> [String: Any] {
        func set(_ dictionary: [String: Any], _ parts: ArraySlice<Substring>) -> [String: Any] {
            var dictionary = dictionary
            let head = String(parts.first!)
            if parts.count == 1 { dictionary[head] = value } else { dictionary[head] = set(dictionary[head] as? [String: Any] ?? [:], parts.dropFirst()) }
            return dictionary
        }
        return set(root, key.split(separator: "/", omittingEmptySubsequences: false)[...])
    }
}
