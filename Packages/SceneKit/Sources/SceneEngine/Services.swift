import AppKit
import Foundation
import SceneThemes
import SceneFoundation

public struct AppearanceState: Sendable, Equatable {
    public var dark: Bool
    public var auto: Bool
    public init(dark: Bool, auto: Bool) { self.dark = dark; self.auto = auto }
}

/// Everything the engine does to the system outside plain files. Tests use a fake.
public protocol SystemServices: Sendable {
    func displays() async -> [UInt32]
    func wallpaper(displayID: UInt32) async -> String?
    func setWallpaper(displayID: UInt32, path: String, fit: WallpaperFit) async throws
    func appearance() async -> AppearanceState
    func setAppearance(dark: Bool) async throws
    func setAutoAppearance() async throws
    func canRestoreAuto() -> Bool
    func preference(domain: String, key: String) -> PlistValue?
    func setPreference(domain: String, key: String, value: PlistValue?) throws
    func run(_ executable: String, _ arguments: [String], environment: [String: String]?) async throws -> CLIResult
    /// Running processes of this user, by app bundle id or by executable name.
    func processes(bundleID: String) -> [pid_t]
    func processes(named name: String) -> [pid_t]
    /// Sends a signal and returns how many processes received it.
    func signal(_ signal: Int32, to pids: [pid_t]) -> Int
    func tweakAvailability(_ id: String) -> TweakAvailability
    func tweakGet(_ id: String) async throws -> JSONValue
    func tweakSet(_ id: String, _ value: JSONValue) async throws -> JSONValue
}

public enum TweakAvailability: Sendable, Equatable {
    case available
    case disabled(String)
}

/// The real macOS implementation.
public final class LiveSystemServices: SystemServices, @unchecked Sendable {
    public let tweaks: TweakRunner

    public init(tweaks: TweakRunner) { self.tweaks = tweaks }

    // MARK: Wallpaper

    @MainActor static func screen(_ id: UInt32) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }
    }

    public func displays() async -> [UInt32] {
        await MainActor.run {
            NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
        }
    }

    public func wallpaper(displayID: UInt32) async -> String? {
        await MainActor.run {
            guard let screen = Self.screen(displayID) else { return nil }
            return NSWorkspace.shared.desktopImageURL(for: screen)?.path
        }
    }

    public func setWallpaper(displayID: UInt32, path: String, fit: WallpaperFit) async throws {
        // macOS can drop a set that follows another one closely, so read back, and set once more if needed.
        for _ in 0..<2 {
            try await setWallpaperOnce(displayID: displayID, path: path, fit: fit)
            for _ in 0..<10 {
                if await wallpaper(displayID: displayID) == path { return }
                try await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func setWallpaperOnce(displayID: UInt32, path: String, fit: WallpaperFit) async throws {
        try await MainActor.run {
            guard let screen = Self.screen(displayID) else { throw SceneError.failed("display \(displayID) is not connected") }
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            switch fit {
            case .fill: options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue; options[.allowClipping] = true
            case .fit: options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue; options[.allowClipping] = false
            case .stretch: options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
            case .center: options[.imageScaling] = NSImageScaling.scaleNone.rawValue
            }
            try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: options)
        }
    }

    // MARK: Appearance

    public func appearance() async -> AppearanceState {
        if tweakAvailability("appearance") == .available, let value = try? await tweakGet("appearance"),
           case .object(let members) = value {
            let dark = members.first { $0.key == "dark" }?.value == .bool(true)
            let auto = members.first { $0.key == "auto" }?.value == .bool(true)
            return AppearanceState(dark: dark, auto: auto)
        }
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        let auto = CFPreferencesCopyAppValue("AppleInterfaceStyleSwitchesAutomatically" as CFString, kCFPreferencesAnyApplication) as? Bool ?? false
        return AppearanceState(dark: style == "Dark", auto: auto)
    }

    public func setAppearance(dark: Bool) async throws {
        if tweakAvailability("appearance") == .available {
            _ = try await tweakSet("appearance", .object([JSONMember("dark", .bool(dark)), JSONMember("auto", .bool(false))]))
            return
        }
        try await AppleScript.run("tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)")
    }

    public func canRestoreAuto() -> Bool { tweakAvailability("appearance") == .available }

    public func setAutoAppearance() async throws {
        guard canRestoreAuto() else { throw SceneError.failed("Turning Auto back on needs the experimental appearance setting") }
        let current = await appearance()
        _ = try await tweakSet("appearance", .object([JSONMember("dark", .bool(current.dark)), JSONMember("auto", .bool(true))]))
    }

    // MARK: Preferences

    public func preference(domain: String, key: String) -> PlistValue? {
        CFPreferencesAppSynchronize(domain as CFString)
        return PlistValue(any: CFPreferencesCopyAppValue(key as CFString, domain as CFString))
    }

    public func setPreference(domain: String, key: String, value: PlistValue?) throws {
        CFPreferencesSetAppValue(key as CFString, value?.any as CFPropertyList?, domain as CFString)
        guard CFPreferencesAppSynchronize(domain as CFString) else { throw SceneError.failed("could not save \(domain)") }
    }

    // MARK: Processes and tweaks

    public func run(_ executable: String, _ arguments: [String], environment: [String: String]?) async throws -> CLIResult {
        try await Task.detached { try Processes.run(executable, arguments, environment: environment, timeout: 120) }.value
    }

    public func processes(bundleID: String) -> [pid_t] { Processes.pids(bundleID: bundleID) }
    public func processes(named name: String) -> [pid_t] { Processes.pids(named: name) }
    public func signal(_ signal: Int32, to pids: [pid_t]) -> Int { Processes.signal(signal, to: pids) }

    public func tweakAvailability(_ id: String) -> TweakAvailability { tweaks.availability(id) }
    public func tweakGet(_ id: String) async throws -> JSONValue { try await tweaks.get(id) }
    public func tweakSet(_ id: String, _ value: JSONValue) async throws -> JSONValue { try await tweaks.set(id, value) }
}

public enum AppleScript {
    /// Runs AppleScript on the main thread. The first run against an app triggers macOS's Automation prompt.
    @discardableResult
    public static func run(_ source: String) async throws -> String? {
        try await MainActor.run {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { throw SceneError.failed("invalid AppleScript") }
            let result = script.executeAndReturnError(&error)
            if let error {
                let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                if number == -1743 { throw SceneError.failed("Scene is not allowed to control this app. Allow it in System Settings → Privacy & Security → Automation.") }
                throw SceneError.failed(error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(number)")
            }
            return result.stringValue
        }
    }
}
