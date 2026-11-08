import Foundation
import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import ImageIO

/// Repository paths for tests.
public enum Repo {
    public static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    public static let themes = root.appendingPathComponent("Themes")

    /// The `scene-tweak` helper from the last Xcode build, if there is one.
    public static var tweakHelper: URL? {
        ["Debug", "Release"].map { root.appendingPathComponent(".build/Xcode/Build/Products/\($0)/scene-tweak") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// A disposable home folder. Nothing a test does touches the real home.
public final class FixtureHome {
    public let url: URL
    public init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("scene-test-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    public func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    @discardableResult
    public func write(_ relative: String, _ text: String) throws -> URL {
        let file = path(relative)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    public func read(_ relative: String) -> String? { try? String(contentsOf: path(relative), encoding: .utf8) }

    /// A fake .app bundle with a version and optional executables inside.
    public func fakeApp(_ name: String, version: String, executables: [String] = []) throws -> URL {
        let app = path("Applications/\(name).app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleShortVersionString": version, "CFBundleIdentifier": "test.\(name)", "CFBundleName": name]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        for exe in executables {
            let url = app.appendingPathComponent(exe)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\nexit 0\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return app
    }
}

/// In-memory system surfaces. Records every call so tests can assert on them.
public final class FakeServices: SystemServices, @unchecked Sendable {
    public let lock = NSLock()
    public var wallpapers: [UInt32: String] = [1: "/System/Library/Desktop Pictures/Original.heic", 2: "/Users/me/Pictures/second.jpg"]
    public var appearanceState = AppearanceState(dark: false, auto: false)
    public var prefs: [String: PlistValue] = [:]
    public var tweaks: [String: JSONValue] = ["accent": .number(4), "iconStyle": .object([JSONMember("style", .string("RegularLight")), JSONMember("tint", .string("None")), JSONMember("custom", .null)])]
    public var tweaksAvailable = true
    public var failWallpaper = false
    /// macOS's wallpaper store, or nil for none. `setWallpaper` writes the entry of `currentSpace`, as macOS does, and
    /// `setWallpaperStore` shows that entry again, as a restarted WallpaperAgent does.
    public var wallpaperStoreData: Data?
    public var currentSpace = "S1"
    public var wallpaperAgentRestarts = 0
    public var failWallpaperStore = false
    public var extensions: [String: String] = [:]   // id -> version
    /// Canned results for commands, keyed by "<executable name> <arguments>".
    public var responses: [String: CLIResult] = [:]
    /// Pretend running processes, keyed by bundle id or executable name. Nothing real is ever signaled.
    public var running: [String: [pid_t]] = [:]
    public var calls: [String] = []
    /// The environment of the last run of each executable, by name.
    public var environments: [String: [String: String]?] = [:]

    public init() {}

    public func record(_ s: String) { lock.withLock { calls.append(s) } }

    public func displays() async -> [UInt32] { [1, 2] }
    public func wallpaper(displayID: UInt32) async -> String? { lock.withLock { wallpapers[displayID] } }
    public func setWallpaper(displayID: UInt32, path: String, fit: WallpaperFit) async throws {
        record("wallpaper \(displayID)")
        if failWallpaper { throw SceneError.failed("injected wallpaper failure") }
        lock.withLock {
            wallpapers[displayID] = path
            guard let data = wallpaperStoreData, var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  var spaces = root["Spaces"] as? [String: Any], var space = spaces[currentSpace] as? [String: Any] else { return }
            let uuid = "UUID-\(displayID)"
            let desktop: [String: Any] = ["Content": Self.wallpaperContent(path, fit: fit), "LastSet": Date(), "LastUse": Date()]
            if var displays = space["Displays"] as? [String: Any], displays[uuid] != nil {
                displays[uuid] = ["Desktop": desktop]
                space["Displays"] = displays
            } else {
                space["Default"] = ["Desktop": desktop]
            }
            spaces[currentSpace] = space
            root["Spaces"] = spaces
            wallpaperStoreData = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        }
    }
    public func displayUUID(_ displayID: UInt32) -> String? { "UUID-\(displayID)" }
    public func wallpaperStore() -> Data? { lock.withLock { wallpaperStoreData } }
    public func setWallpaperStore(_ data: Data) async throws {
        record("wallpaper store")
        if failWallpaperStore { throw SceneError.failed("injected wallpaper store failure") }
        lock.withLock {
            wallpaperStoreData = data
            wallpaperAgentRestarts += 1
            for id in wallpapers.keys {
                let uuid = "UUID-\(id)"
                let image = WallpaperStore.images(data, displays: [uuid])?.first { $0.key == "Spaces/\(currentSpace)/Displays/\(uuid)" || $0.key == "Spaces/\(currentSpace)/Default" }
                if let path = image?.value, path.hasPrefix("/") { wallpapers[id] = path }
            }
        }
    }

    /// A wallpaper store entry's content, the way macOS writes it for an image.
    public static func wallpaperContent(_ path: String, fit: WallpaperFit = .fill) -> [String: Any] {
        let configuration = try! PropertyListSerialization.data(
            fromPropertyList: ["type": "imageFile", "url": ["relative": URL(fileURLWithPath: path).absoluteString]], format: .binary, options: 0)
        return ["Choices": [["Configuration": configuration, "Files": [Any](), "Provider": "com.apple.wallpaper.choice.image"]],
                "EncodedOptionValues": Data("placement \(fit.rawValue)".utf8), "Shuffle": "$null"]
    }
    public func appearance() async -> AppearanceState { lock.withLock { appearanceState } }
    public func setAppearance(dark: Bool) async throws { record("appearance \(dark)"); lock.withLock { appearanceState = AppearanceState(dark: dark, auto: false) } }
    public func setAutoAppearance() async throws { record("auto"); lock.withLock { appearanceState.auto = true } }
    public func canRestoreAuto() -> Bool { tweaksAvailable }
    public func preference(domain: String, key: String) -> PlistValue? { lock.withLock { prefs["\(domain)#\(key)"] } }
    public func setPreference(domain: String, key: String, value: PlistValue?) throws { lock.withLock { prefs["\(domain)#\(key)"] = value } }

    public func run(_ executable: String, _ arguments: [String], environment: [String: String]?, timeout: TimeInterval) async throws -> CLIResult {
        let command = "\((executable as NSString).lastPathComponent) \(arguments.joined(separator: " "))"
        record("run \(command)")
        lock.withLock { environments[(executable as NSString).lastPathComponent] = environment }
        if let response = lock.withLock({ responses[command] }) { return response }
        if (executable as NSString).lastPathComponent == "rex" { return rex(arguments) }
        if arguments.first == "--install-extension", let vsix = arguments.dropFirst().first {
            let name = (vsix as NSString).lastPathComponent   // scene-themes-<version>.vsix
            let version = name.replacingOccurrences(of: "scene-themes-", with: "").replacingOccurrences(of: ".vsix", with: "")
            guard FileManager.default.fileExists(atPath: vsix), (try? ZipArchive.entries(of: Data(contentsOf: URL(fileURLWithPath: vsix)))) != nil else {
                return CLIResult(status: 1, stdout: "", stderr: "not a vsix")
            }
            lock.withLock { extensions[VSCodeRenderer.extensionID] = version }
            return CLIResult(status: 0, stdout: "installed", stderr: "")
        }
        if arguments.first == "--uninstall-extension", let id = arguments.dropFirst().first {
            lock.withLock { extensions[id] = nil }
            return CLIResult(status: 0, stdout: "", stderr: "")
        }
        if arguments.first == "--list-extensions" {
            return CLIResult(status: 0, stdout: lock.withLock { extensions.map { "\($0.key)@\($0.value)" }.joined(separator: "\n") }, stderr: "")
        }
        if arguments.first == "--version" { return CLIResult(status: 0, stdout: "NVIM v0.11.5\n", stderr: "") }
        return CLIResult(status: 0, stdout: "", stderr: "")
    }

    /// Rex's built-in themes, by id, with their look.
    public var rexBuiltInThemes = ["velvet-dusk": "dark", "merino-light": "light"]

    /// Rex's theme actions as the open Rex app runs them. It keeps custom themes as JSON in its preferences, names an
    /// import after its file, replaces a theme of the same name, and picks the look from the background.
    func rex(_ arguments: [String]) -> CLIResult {
        let domain = "com.superlogical.rex"
        guard !processes(bundleID: domain).isEmpty else { return CLIResult(status: 1, stdout: "", stderr: "Error: no app client is connected") }
        let args = Dictionary(arguments.compactMap { argument -> (String, String)? in
            guard !argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") else { return nil }
            return (String(argument[..<eq]), String(argument[argument.index(after: eq)...]))
        }, uniquingKeysWith: { $1 })
        return lock.withLock {
            var themes: [[String: Any]] = []
            if case .data(let data)? = prefs["\(domain)#Workspace.customThemes"] {
                themes = (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
            }
            switch arguments.dropFirst().first {
            case "client.theme.import":
                guard let path = args["path"], let text = try? String(contentsOfFile: path, encoding: .utf8),
                      let line = text.split(separator: "\n").first(where: { $0.hasPrefix("background = ") }),
                      let color = RGBA(hex: String(line.dropFirst("background = ".count))) else {
                    return CLIResult(status: 1, stdout: "", stderr: "Error: Expected a UTF-8 Ghostty theme or iTerm color file.")
                }
                let name = (path as NSString).lastPathComponent, look = color.isDark ? "dark" : "light"
                let id = themes.first { $0["name"] as? String == name }?["id"] as? String ?? "custom-\(UUID().uuidString)"
                themes.removeAll { $0["id"] as? String == id }
                let background = ["red": Double(color.r) / 255, "green": Double(color.g) / 255, "blue": Double(color.b) / 255, "alpha": 1]
                themes.append(["id": id, "name": name, "appearance": look, "palette": ["background": background]])
                prefs["\(domain)#Workspace.customThemes"] = .data(try! JSONSerialization.data(withJSONObject: themes))
                prefs["\(domain)#Workspace.\(look)ThemeID"] = .string(id)
            case "client.theme.change":
                guard let name = args["name"],
                      let look = rexBuiltInThemes[name] ?? themes.first(where: { $0["id"] as? String == name })?["appearance"] as? String else {
                    return CLIResult(status: 1, stdout: "", stderr: "Error: no theme matches")
                }
                prefs["\(domain)#Workspace.\(look)ThemeID"] = .string(name)
            default:
                return CLIResult(status: 1, stdout: "", stderr: "Error: unknown action")
            }
            return CLIResult(status: 0, stdout: "null\n", stderr: "")
        }
    }

    public func processes(bundleID: String) -> [pid_t] { lock.withLock { running[bundleID] ?? [] } }
    public func processes(named name: String) -> [pid_t] { lock.withLock { running[name] ?? [] } }
    public func signal(_ signal: Int32, to pids: [pid_t]) -> Int {
        record("signal \(signal) \(pids.sorted().map(String.init).joined(separator: ","))")
        return pids.count
    }

    public func tweakAvailability(_ id: String) -> TweakAvailability { tweaksAvailable ? .available : .disabled("off in tests") }
    public func tweakGet(_ id: String) async throws -> JSONValue { lock.withLock { tweaks[id] ?? .null } }
    public func tweakSet(_ id: String, _ value: JSONValue) async throws -> JSONValue {
        record("tweak \(id)")
        return lock.withLock { tweaks[id] = value; return value }
    }
}

public enum Fixtures {
    public static func environment(_ home: FixtureHome, apps: [String: URL], nvim: URL? = nil) -> SceneEnvironment {
        SceneEnvironment(home: home.url, locateApp: { apps[$0] }, locateExecutable: { $0 == "nvim" ? nvim : nil })
    }

    public static func theme(_ folder: String) throws -> Theme {
        try ThemeLoader.load(folder: Repo.themes.appendingPathComponent(folder), isBundled: true)
    }

    /// A copy of a bundled theme with two generated wallpapers for each variant (`<variant>-1.png`, `<variant>-2.png`),
    /// so tests do not depend on downloaded images.
    public static func themeWithWallpaper(_ folder: String, in home: FixtureHome) throws -> Theme {
        let source = Repo.themes.appendingPathComponent(folder)
        let target = home.path("themes/\(folder)")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("wallpapers"), withIntermediateDirectories: true)
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: source.appendingPathComponent("theme.json"))) as! [String: Any]
        var variants = manifest["variants"] as! [String: Any]
        for (name, value) in variants {
            var spec = value as! [String: Any]
            let files = ["wallpapers/\(name)-1.png", "wallpapers/\(name)-2.png"]
            for file in files { try png(width: 1600, height: 900).write(to: target.appendingPathComponent(file)) }
            spec["wallpapers"] = files.map { ["file": $0, "fit": "fill"] }
            variants[name] = spec
        }
        manifest["variants"] = variants
        manifest["assets"] = variants.keys.flatMap { name in (1...2).map { ["file": "wallpapers/\(name)-\($0).png", "license": "CC0-1.0"] } }
        try JSONSerialization.data(withJSONObject: manifest).write(to: target.appendingPathComponent("theme.json"))
        return try ThemeLoader.load(folder: target)
    }

    public static func png(width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.3, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        guard CGImageDestinationFinalize(destination) else { throw SceneError.failed("png") }
        return data as Data
    }
}
