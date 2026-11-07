import Foundation

/// macOS keeps a wallpaper per Space in `com.apple.wallpaper/Store/Index.plist`, and
/// `NSWorkspace.setDesktopImageURL` changes only the Space on screen. This writes one display's
/// image into every Space of that display, so all desktops show it.
/// ponytail: undocumented store format, seen on macOS 15–27; when it changes, `spreading` returns nil and only the current Space changes.
public enum WallpaperStore {
    public static var indexURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    /// The store with `image` on every Space of the display `displayUUID`, and as the default for new Spaces.
    /// A Space with no entry for the display shows its `Default`, so that one is set instead.
    public static func spreading(_ data: Data, displayUUID: String, image: URL, now: Date = Date()) throws -> Data? {
        guard var root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              var spaces = root["Spaces"] as? [String: Any] else { return nil }
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["type": "imageFile", "url": ["relative": image.absoluteString]], format: .binary, options: 0)
        let choice: [String: Any] = ["Configuration": configuration, "Files": [Any](), "Provider": "com.apple.wallpaper.choice.image"]
        func set(_ node: Any?) -> [String: Any] {
            var node = node as? [String: Any] ?? [:]
            var desktop = node["Desktop"] as? [String: Any] ?? [:]
            var content = desktop["Content"] as? [String: Any] ?? [:]
            content["Choices"] = [choice]
            desktop["Content"] = content
            desktop["LastSet"] = now
            desktop["LastUse"] = now
            node["Desktop"] = desktop
            return node
        }
        for (id, value) in spaces {
            guard var space = value as? [String: Any] else { continue }
            if var displays = space["Displays"] as? [String: Any], displays[displayUUID] != nil {
                displays[displayUUID] = set(displays[displayUUID])
                space["Displays"] = displays
            } else {
                space["Default"] = set(space["Default"])
            }
            spaces[id] = space
        }
        root["Spaces"] = spaces
        var displays = root["Displays"] as? [String: Any] ?? [:]
        displays[displayUUID] = set(displays[displayUUID])
        root["Displays"] = displays
        if root["SystemDefault"] != nil { root["SystemDefault"] = set(root["SystemDefault"]) }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }
}
