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
    public var extensions: [String: String] = [:]   // id -> version
    public var calls: [String] = []

    public init() {}

    public func record(_ s: String) { lock.withLock { calls.append(s) } }

    public func displays() async -> [UInt32] { [1, 2] }
    public func wallpaper(displayID: UInt32) async -> String? { lock.withLock { wallpapers[displayID] } }
    public func setWallpaper(displayID: UInt32, path: String, fit: WallpaperFit) async throws {
        record("wallpaper \(displayID)")
        if failWallpaper { throw SceneError.failed("injected wallpaper failure") }
        lock.withLock { wallpapers[displayID] = path }
    }
    public func appearance() async -> AppearanceState { lock.withLock { appearanceState } }
    public func setAppearance(dark: Bool) async throws { record("appearance \(dark)"); lock.withLock { appearanceState = AppearanceState(dark: dark, auto: false) } }
    public func setAutoAppearance() async throws { record("auto"); lock.withLock { appearanceState.auto = true } }
    public func canRestoreAuto() -> Bool { tweaksAvailable }
    public func preference(domain: String, key: String) -> PlistValue? { lock.withLock { prefs["\(domain)#\(key)"] } }
    public func setPreference(domain: String, key: String, value: PlistValue?) throws { lock.withLock { prefs["\(domain)#\(key)"] = value } }

    public func run(_ executable: String, _ arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        record("run \((executable as NSString).lastPathComponent) \(arguments.joined(separator: " "))")
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
