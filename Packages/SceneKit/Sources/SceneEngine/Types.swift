import Foundation
import SceneThemes
import SceneFoundation

// MARK: - Values

/// A property-list value, for CFPreferences reads and writes.
public indirect enum PlistValue: Codable, Sendable, Equatable {
    case string(String), int(Int), double(Double), bool(Bool), data(Data), array([PlistValue]), dictionary([String: PlistValue])

    public init?(any value: Any?) {
        switch value {
        case let v as String: self = .string(v)
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() { self = .bool(v.boolValue) }
            else if CFNumberIsFloatType(v) { self = .double(v.doubleValue) }
            else { self = .int(v.intValue) }
        case let v as Data: self = .data(v)
        case let v as [Any]: self = .array(v.compactMap { PlistValue(any: $0) })
        case let v as [String: Any]: self = .dictionary(v.compactMapValues { PlistValue(any: $0) })
        default: return nil
        }
    }

    public var any: Any {
        switch self {
        case .string(let v): v
        case .int(let v): v
        case .double(let v): v
        case .bool(let v): v
        case .data(let v): v
        case .array(let v): v.map(\.any)
        case .dictionary(let v): v.mapValues(\.any)
        }
    }
}

// MARK: - Operations

/// The closed set of changes the engine knows how to back up, apply, verify, and undo.
public enum Operation: Codable, Sendable, Equatable {
    case writeManagedFile(path: String, contents: Data)
    case ensureAnchor(path: String, block: String, placement: Placement)
    case setJSONValue(path: String, key: String, value: JSONValue?)
    case setPreference(domain: String, key: String, value: PlistValue?)
    /// One entry of a dictionary preference, such as one profile in Terminal's `Window Settings`.
    case setPreferenceEntry(domain: String, key: String, entry: String, value: PlistValue?)
    /// One key in a TOML-style file. `value` is raw TOML text that Scene renders.
    case setConfigValue(path: String, table: String?, key: String, value: String?)
    case setWallpaper(displayID: UInt32, imagePath: String, fit: WallpaperFit)
    case setAppearance(dark: Bool)
    case installEditorExtension(cli: String, packagePath: String, extensionID: String, version: String)
    case setTweak(id: String, value: JSONValue)
    /// Waits between two changes, so an app that watches files loads the first before it reads the second.
    /// It changes nothing, so the engine records nothing for it.
    case pause(milliseconds: Int)

    /// The resource the operation owns. The ledger keeps one original value per resource.
    public var resource: String {
        switch self {
        case .writeManagedFile(let path, _): "file:\(path)"
        case .ensureAnchor(let path, _, _): "anchor:\(path)"
        case .setJSONValue(let path, let key, _): "json:\(path)#\(key)"
        case .setPreference(let domain, let key, _): "pref:\(domain)#\(key)"
        case .setPreferenceEntry(let domain, let key, let entry, _): "pref:\(domain)#\(key)/\(entry)"
        case .setConfigValue(let path, let table, let key, _): "conf:\(path)#\(table.map { $0 + "." } ?? "")\(key)"
        case .setWallpaper(let id, _, _): "wallpaper:\(id)"
        case .setAppearance: "appearance"
        case .installEditorExtension(let cli, _, let id, _): "extension:\(cli)#\(id)"
        case .setTweak(let id, _): "tweak:\(id)"
        case .pause: "pause"
        }
    }

    /// One line for the plan and the details view.
    public var summary: String {
        switch self {
        case .writeManagedFile(let path, _): "Write \(Self.tilde(path))"
        case .ensureAnchor(let path, _, _): "Add one include block to \(Self.tilde(path))"
        case .setJSONValue(let path, let key, let value): value == nil ? "Remove \"\(key)\" from \(Self.tilde(path))" : "Set \"\(key)\" in \(Self.tilde(path))"
        case .setPreference(let domain, let key, _): "Set \(key) in \(domain)"
        case .setPreferenceEntry(let domain, let key, let entry, let value): value == nil ? "Remove “\(entry)” from \(key) in \(domain)" : "Set “\(entry)” in \(key) in \(domain)"
        case .setConfigValue(let path, _, let key, let value): value == nil ? "Remove \(key) from \(Self.tilde(path))" : "Set \(key) in \(Self.tilde(path))"
        case .setWallpaper(let id, let path, _): "Set wallpaper of display \(id) to \((path as NSString).lastPathComponent)"
        case .setAppearance(let dark): "Switch macOS to \(dark ? "Dark" : "Light")"
        case .installEditorExtension(let cli, _, _, let version): "Install Scene Themes \(version) with \((cli as NSString).lastPathComponent)"
        case .setTweak(let id, _): "Set \(id) (experimental)"
        case .pause(let milliseconds): "Wait \(milliseconds) ms, so the app loads the new files first"
        }
    }

    public static func tilde(_ path: String) -> String {
        path.hasPrefix(NSHomeDirectory()) ? "~" + path.dropFirst(NSHomeDirectory().count) : path
    }
}

/// What a resource looked like before or after Scene touched it.
public enum ResourceState: Codable, Sendable, Equatable {
    case absent
    case file(sha256: String, backup: String?)
    case anchor(block: String?, fileBackup: String?, fileExisted: Bool)
    case json(JSONValue?)
    case plist(PlistValue?)
    /// The raw text of a key in a TOML-style file, or nil when the file does not set it.
    case configValue(String?)
    case wallpaper(path: String?)
    case appearance(dark: Bool, auto: Bool)
    case extensionVersion(String?)
    case tweak(JSONValue)
}

// MARK: - Detection and plans

public enum IntegrationKind: String, Sendable, Codable { case system, terminal, editor, tool, experimental }

public enum SupportLevel: Sendable, Equatable {
    case official, scripting
    case experimental(tested: Bool)
    case unavailable(String)
}

public enum SetupState: Sendable, Equatable {
    case ready
    case needsOneTimeSetup(String)
    case blocked(String)
}

public struct Detection: Sendable {
    public var installed: Bool
    public var version: String?
    public var detail: String?
    public var support: SupportLevel
    public var setup: SetupState
    public var conflicts: [String]
    public var context: [String: String]
    public var liveUpdate: Bool

    public init(installed: Bool, version: String? = nil, detail: String? = nil, support: SupportLevel = .official,
                setup: SetupState = .ready, conflicts: [String] = [], context: [String: String] = [:], liveUpdate: Bool = true) {
        self.installed = installed; self.version = version; self.detail = detail; self.support = support
        self.setup = setup; self.conflicts = conflicts; self.context = context; self.liveUpdate = liveUpdate
    }

    public static func notInstalled(_ detail: String? = nil) -> Detection {
        Detection(installed: false, detail: detail, support: .unavailable("Not installed"))
    }
}

public enum Requirement: Sendable, Equatable {
    case automation(String)
    case restart(String)
    case oneTimeSetup(String)
}

public struct IntegrationPlan: Sendable {
    public var operations: [Operation]
    public var requirements: [Requirement]
    public var conflicts: [String]
    public var notes: [String]

    public init(operations: [Operation] = [], requirements: [Requirement] = [], conflicts: [String] = [], notes: [String] = []) {
        self.operations = operations; self.requirements = requirements; self.conflicts = conflicts; self.notes = notes
    }
}

public enum ReloadResult: Sendable, Equatable {
    case reloaded, notRunning, notNeeded, needsRestart(String), needsUserAction(String), failed(String)
}

public enum Verification: Sendable, Equatable {
    case matches
    case overridden([String])
    case mismatch(String)
}

// MARK: - Requests and reports

public enum AppearanceMode: String, Sendable, Codable, CaseIterable {
    case system, light, dark
}

public struct ApplyRequest: Sendable {
    public var theme: Theme
    public var mode: AppearanceMode
    /// The appearance that single-variant apps should show now.
    public var effectiveAppearance: Appearance
    /// The appearance Scene sets on macOS, if any.
    public var forcedAppearance: Appearance?
    /// The file name of the wallpaper to show. Without it, or when the variant has no such file, the variant's first wallpaper.
    public var wallpaperName: String?

    public init(theme: Theme, mode: AppearanceMode, systemIsDark: Bool) {
        self.theme = theme
        self.mode = mode
        let available = theme.availableAppearances
        switch mode {
        case .light: forcedAppearance = .light
        case .dark: forcedAppearance = .dark
        case .system: forcedAppearance = available.count == 1 ? available[0] : nil
        }
        let wanted = forcedAppearance ?? (systemIsDark ? .dark : .light)
        effectiveAppearance = available.contains(wanted) ? wanted : (available.first ?? .dark)
    }

    public func variant(_ appearance: Appearance) -> ResolvedVariant {
        theme.variants[appearance] ?? theme.variants[effectiveAppearance] ?? theme.variants.values.first!
    }

    public var current: ResolvedVariant { variant(effectiveAppearance) }

    /// The wallpaper this request shows.
    public var wallpaper: Wallpaper? { current.wallpaper(named: wallpaperName) }

    /// Variants for apps that switch on their own. A forced appearance collapses them to one.
    public var nativeVariants: [Appearance: ResolvedVariant] {
        if let forced = forcedAppearance { return [forced: variant(forced)] }
        return theme.variants
    }
}

public enum Outcome: Sendable, Equatable {
    case applied
    case appliedRestartNeeded(String)
    case appliedPartlyOverridden([String])
    case needsAction(String)
    case skipped(String)
    case failed(String)

    public var isSuccess: Bool {
        switch self {
        case .applied, .appliedRestartNeeded, .appliedPartlyOverridden: true
        default: false
        }
    }
}

public struct IntegrationResult: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var outcome: Outcome
    public var operations: [String]
    public var notes: [String]
}

public struct ApplyReport: Sendable {
    public var themeName: String
    public var results: [IntegrationResult]
    public var date: Date
}

public struct RestoreItem: Sendable, Identifiable {
    public var id: String { resource }
    public var resource: String
    public var integration: String
    public var result: String
    public var keptUserChange: Bool
}
