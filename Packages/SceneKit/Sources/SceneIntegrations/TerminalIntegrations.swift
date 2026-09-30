import Foundation
import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation

// MARK: - Ghostty

public struct GhosttyIntegration: Integration {
    public let id = "ghostty"
    public let displayName = "Ghostty"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "com.mitchellh.ghostty"
    public init() {}

    /// Config files in Ghostty's load order. The first existing XDG file wins; App Support files load later.
    static func candidates(_ env: SceneEnvironment) -> [URL] {
        let xdg = env.xdgConfigHome.appendingPathComponent("ghostty")
        let support = env.home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")
        return [xdg.appendingPathComponent("config.ghostty"), xdg.appendingPathComponent("config"),
                support.appendingPathComponent("config.ghostty"), support.appendingPathComponent("config")]
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let version = Processes.appVersion(at: app)
        let config = Self.candidates(env).first { FileManager.default.fileExists(atPath: $0.path) }
            ?? env.xdgConfigHome.appendingPathComponent("ghostty/config")
        var conflicts: [String] = []
        var setup = SetupState.ready
        if let text = FileOps.read(FileOps.resolvedTarget(config)).map({ String(decoding: $0, as: UTF8.self) }) {
            let lines = Self.userLines(text)
            if lines.contains(where: { $0.key == "theme" }) {
                conflicts.append("Your config selects a theme. Scene's include loads after it and takes over; Restore brings yours back.")
            }
            let colorKeys = lines.filter { GhosttyRenderer.colorKeys.contains($0.key) }
            if !colorKeys.isEmpty {
                let names = colorKeys.map { $0.key == "palette" ? "palette \($0.value.split(separator: "=").first ?? "")" : $0.key }
                conflicts.append("\(colorKeys.count) color line\(colorKeys.count == 1 ? "" : "s") in your config override the theme: \(names.joined(separator: ", ")).")
            }
        }
        if FileOps.exists(config) && !FileOps.isWritable(config) {
            setup = .blocked("\(Operation.tilde(config.path)) is read-only. Add this line to your config source: config-file = ?\"\(config.deletingLastPathComponent().appendingPathComponent("scene.conf").path)\"")
        }
        let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: config.path)) != nil
        return Detection(installed: true, version: version,
                         detail: Operation.tilde(config.path) + (isLink ? " (symlink)" : ""), setup: setup, conflicts: conflicts,
                         context: ["config": config.path, "app": app.path, "version": version ?? ""])
    }

    /// Key/value lines outside Scene's block, ignoring comments.
    static func userLines(_ text: String) -> [(key: String, value: String)] {
        let withoutBlock = Anchor.remove(from: text)
        return withoutBlock.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { return nil }
            return (line[..<eq].trimmingCharacters(in: .whitespaces), line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
        }
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let config = URL(fileURLWithPath: detection.context["config"]!)
        let version = SemanticVersion(detection.context["version"] ?? "")
        let themes = env.xdgConfigHome.appendingPathComponent("ghostty/themes")
        let include = config.deletingLastPathComponent().appendingPathComponent("scene.conf")
        let variants = request.nativeVariants
        var ops: [Operation] = variants.keys.sorted { $0.rawValue < $1.rawValue }.map { appearance in
            .writeManagedFile(path: themes.appendingPathComponent(GhosttyRenderer.themeNames[appearance]!).path,
                              contents: Data(GhosttyRenderer.themeFile(variants[appearance]!, version: version).utf8))
        }
        let forced = variants.count == 1 ? variants.keys.first : nil
        ops.append(.writeManagedFile(path: include.path, contents: Data(GhosttyRenderer.includeFile(appearances: Array(variants.keys), forced: forced).utf8)))
        ops.append(.ensureAnchor(path: config.path, block: Anchor.block(lines: ["config-file = ?\"\(include.path)\""], comment: "#"), placement: .end))
        var notes: [String] = []
        if let version, version < SemanticVersion(1, 2, 0) { notes.append("Ghostty \(version) cannot reload on request. Press ⌘⇧, in Ghostty after applying.") }
        return IntegrationPlan(operations: ops, conflicts: detection.conflicts, notes: notes)
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        let pids = services.processes(bundleID: Self.bundleID)
        guard !pids.isEmpty else { return .notRunning }
        guard let version = SemanticVersion(detection.context["version"] ?? ""), version >= SemanticVersion(1, 2, 0) else {
            return .needsUserAction("Press ⌘⇧, in Ghostty to reload its config")
        }
        // SIGUSR2 reloads the config on 1.2 and later. Older versions would quit, so they are excluded above.
        return services.signal(SIGUSR2, to: pids) > 0 ? .reloaded : .failed("could not signal Ghostty")
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        if case .mismatch(let reason) = Self.verifyFiles(plan) { return .mismatch(reason) }
        // Ghostty's own view of the files on disk: the effective theme must be Scene's.
        if let app = detection.context["app"] {
            let binary = URL(fileURLWithPath: app).appendingPathComponent("Contents/MacOS/ghostty").path
            if FileManager.default.isExecutableFile(atPath: binary),
               let result = try? await services.run(binary, ["+show-config"], environment: ["XDG_CONFIG_HOME": env.xdgConfigHome.path, "HOME": env.home.path]),
               result.status == 0 {
                let themeLine = result.stdout.split(separator: "\n").first { $0.hasPrefix("theme = ") }.map(String.init)
                guard let themeLine, themeLine.contains("scene-") else {
                    return .mismatch("Ghostty does not load Scene's include (effective \(themeLine ?? "no theme"))")
                }
            }
        }
        let overrides = detection.conflicts.filter { $0.contains("override the theme") }
        return overrides.isEmpty ? .matches : .overridden(overrides)
    }
}

// MARK: - iTerm2

public struct ITermIntegration: Integration {
    public let id = "iterm2"
    public let displayName = "iTerm2"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "com.googlecode.iterm2"
    public init() {}

    static func profileURL(_ env: SceneEnvironment) -> URL {
        env.home.appendingPathComponent("Library/Application Support/iTerm2/DynamicProfiles/scene.json")
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let defaultGUID: String? = { if case .string(let v)? = services.preference(domain: "com.googlecode.iterm2", key: "Default Bookmark Guid") { v } else { nil } }()
        var parent = defaultGUID
        if defaultGUID == ITermRenderer.profileGUID,
           let data = FileOps.read(Self.profileURL(env)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let profile = (json["Profiles"] as? [[String: Any]])?.first {
            parent = profile["Dynamic Profile Parent GUID"] as? String
        }
        let isDefault = defaultGUID == ITermRenderer.profileGUID
        return Detection(installed: true, version: Processes.appVersion(at: app),
                         detail: isDefault ? "“Scene” is your default profile" : "Adds a “Scene” profile",
                         setup: isDefault ? .ready : .needsOneTimeSetup("In iTerm2, open Settings → Profiles, select “Scene”, and choose Other Actions → Set as Default. Theme changes then apply live."),
                         context: ["parent": parent ?? ""])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let parent = detection.context["parent"].flatMap { $0.isEmpty ? nil : $0 }
        let data = try ITermRenderer.dynamicProfile(variants: request.nativeVariants, parentGUID: parent)
        var plan = IntegrationPlan(operations: [.writeManagedFile(path: Self.profileURL(env).path, contents: data)])
        if case .needsOneTimeSetup(let step) = detection.setup { plan.requirements.append(.oneTimeSetup(step)) }
        return plan
    }
}

// MARK: - kitty

public struct KittyIntegration: Integration {
    public let id = "kitty"
    public let displayName = "kitty"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "net.kovidgoyal.kitty"
    /// Files kitty 0.38 and later load for each macOS appearance. They override every other color.
    static let autoFiles: [(file: String, appearance: Appearance?)] = [
        ("light-theme.auto.conf", .light), ("dark-theme.auto.conf", .dark), ("no-preference-theme.auto.conf", nil),
    ]
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let folder = env.xdgConfigHome.appendingPathComponent("kitty")
        let config = folder.appendingPathComponent("kitty.conf")
        var setup = SetupState.ready
        if FileOps.exists(config) && !FileOps.isWritable(config) {
            setup = .blocked("\(Operation.tilde(config.path)) is read-only. Add this line to your config source: include scene-theme.conf")
        }
        let auto = Self.autoFiles.map(\.file).filter { FileOps.exists(folder.appendingPathComponent($0)) }
        var notes: [String] = []
        if !auto.isEmpty { notes.append("Your kitty switches themes with macOS through \(auto.joined(separator: ", ")). Scene writes its colors into them, and Restore puts yours back.") }
        return Detection(installed: true, version: Processes.appVersion(at: app), detail: Operation.tilde(config.path), setup: setup,
                         conflicts: notes, context: ["folder": folder.path, "auto": auto.joined(separator: ","), "version": Processes.appVersion(at: app) ?? ""])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let folder = URL(fileURLWithPath: detection.context["folder"]!)
        var ops: [Operation] = [
            .writeManagedFile(path: folder.appendingPathComponent("scene-theme.conf").path, contents: Data(KittyRenderer.themeFile(request.current).utf8)),
            .ensureAnchor(path: folder.appendingPathComponent("kitty.conf").path,
                          block: Anchor.block(lines: ["include scene-theme.conf"], comment: "#"), placement: .end),
        ]
        let existing = Set(detection.context["auto", default: ""].split(separator: ",").map(String.init))
        for (file, appearance) in Self.autoFiles where existing.contains(file) {
            let variant = appearance.map { request.nativeVariants[$0] ?? request.current } ?? request.current
            ops.append(.writeManagedFile(path: folder.appendingPathComponent(file).path, contents: Data(KittyRenderer.themeFile(variant).utf8)))
        }
        return IntegrationPlan(operations: ops, conflicts: detection.conflicts)
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        let pids = Set(services.processes(bundleID: Self.bundleID) + services.processes(named: "kitty"))
        guard !pids.isEmpty else { return .notRunning }
        guard let version = SemanticVersion(detection.context["version"] ?? ""), version >= SemanticVersion(0, 24, 0) else {
            return .needsUserAction("Press ⌃⌘, in kitty to reload its config")
        }
        // SIGUSR1 makes kitty reload its config. On macOS, kitty before 0.24 quits on it instead, so it is excluded above.
        return services.signal(SIGUSR1, to: Array(pids)) > 0 ? .reloaded : .failed("could not signal kitty")
    }
}

// MARK: - Terminal

public struct TerminalAppIntegration: Integration {
    public let id = "terminal"
    public let displayName = "Terminal"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "com.apple.Terminal"
    static let domain = "com.apple.Terminal"
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let current: String = { if case .string(let name)? = services.preference(domain: Self.domain, key: "Default Window Settings") { name } else { "Basic" } }()
        // The Scene profile starts as a copy of the default profile, so the font and window size stay.
        var base: PlistValue?
        if case .dictionary(let profiles)? = services.preference(domain: Self.domain, key: "Window Settings") { base = profiles[current] }
        let encoded = base.flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        let isScene = current == TerminalAppRenderer.profileName
        return Detection(installed: true, version: Processes.appVersion(at: app),
                         detail: isScene ? "“Scene” is your default profile" : "Adds a “Scene” profile based on “\(current)”",
                         context: ["base": encoded, "current": current])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        var profile: [String: PlistValue] = [:]
        if let json = detection.context["base"], !json.isEmpty, case .dictionary(let base)? = try? JSONDecoder().decode(PlistValue.self, from: Data(json.utf8)) {
            profile = base
        }
        for (key, data) in try TerminalAppRenderer.colors(request.current) { profile[key] = .data(data) }
        profile["name"] = .string(TerminalAppRenderer.profileName)
        profile["type"] = .string("Window Settings")
        var notes: [String] = []
        if let current = detection.context["current"], current != TerminalAppRenderer.profileName {
            notes.append("The “Scene” profile copies your default profile, “\(current)”, and changes its colors.")
        }
        return IntegrationPlan(operations: [
            .setPreferenceEntry(domain: Self.domain, key: "Window Settings", entry: TerminalAppRenderer.profileName, value: .dictionary(profile)),
            .setPreference(domain: Self.domain, key: "Default Window Settings", value: .string(TerminalAppRenderer.profileName)),
            .setPreference(domain: Self.domain, key: "Startup Window Settings", value: .string(TerminalAppRenderer.profileName)),
        ], notes: notes)
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        // Terminal reads its profiles when it starts.
        services.processes(bundleID: Self.bundleID).isEmpty ? .notNeeded : .needsRestart("Quit and reopen Terminal to see the theme.")
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        guard case .dictionary(let profiles)? = services.preference(domain: Self.domain, key: "Window Settings"),
              profiles[TerminalAppRenderer.profileName] != nil,
              services.preference(domain: Self.domain, key: "Default Window Settings") == .string(TerminalAppRenderer.profileName) else {
            return .mismatch("Terminal's settings did not keep the Scene profile")
        }
        return .matches
    }
}

// MARK: - Alacritty

public struct AlacrittyIntegration: Integration {
    public let id = "alacritty"
    public let displayName = "Alacritty"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "org.alacritty"
    public init() {}

    /// Config files in Alacritty's search order.
    static func candidates(_ env: SceneEnvironment) -> [URL] {
        [env.xdgConfigHome.appendingPathComponent("alacritty/alacritty.toml"), env.xdgConfigHome.appendingPathComponent("alacritty.toml"),
         env.home.appendingPathComponent(".config/alacritty/alacritty.toml"), env.home.appendingPathComponent(".alacritty.toml")]
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let version = Processes.appVersion(at: app)
        let config = Self.candidates(env).first { FileOps.exists($0) } ?? Self.candidates(env)[0]
        guard let semver = SemanticVersion(version ?? ""), semver >= SemanticVersion(0, 13, 0) else {
            return Detection(installed: true, version: version, setup: .blocked("Scene needs Alacritty 0.13 or later, which reads alacritty.toml."))
        }
        let doc = KeyValueDocument(text: FileOps.read(FileOps.resolvedTarget(config)).map { String(decoding: $0, as: UTF8.self) } ?? "")
        // 0.14 moved `import` to `general.import`. A file that still has the old key keeps it.
        let key = doc.value(forKey: "import") != nil || semver < SemanticVersion(0, 14, 0) ? "import" : "general.import"
        var imports: [String] = []
        if let raw = doc.value(forKey: key) {
            guard let list = KeyValueDocument.stringArray(raw) else {
                return Detection(installed: true, version: version, detail: Operation.tilde(config.path),
                                 setup: .blocked("Scene cannot read the \(key) list in \(Operation.tilde(config.path)). Add \"\(Self.file(env).path)\" to it yourself."))
            }
            imports = list
        }
        var conflicts: [String] = []
        let own = doc.keys.filter { $0.hasPrefix("colors.") }
        if !own.isEmpty {
            conflicts.append("\(own.count) color setting\(own.count == 1 ? "" : "s") in your alacritty.toml win over imported files, so they override the theme.")
        }
        return Detection(installed: true, version: version, detail: Operation.tilde(config.path), conflicts: conflicts,
                         context: ["config": config.path, "key": key, "imports": imports.joined(separator: "\n"), "version": version ?? "",
                                   "firstInstall": imports.contains(Self.file(env).path) ? "0" : "1"])
    }

    static func file(_ env: SceneEnvironment) -> URL { env.xdgConfigHome.appendingPathComponent("alacritty/scene.toml") }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let file = Self.file(env)
        let key = detection.context["key"]!
        // Scene's file goes last, so it wins over the themes the user imports.
        let existing = detection.context["imports", default: ""].split(separator: "\n").map(String.init).filter { $0 != file.path }
        let list = "[" + (existing + [file.path]).map(KeyValueDocument.quoted).joined(separator: ", ") + "]"
        var notes: [String] = []
        if detection.context["firstInstall"] == "1" {
            // Alacritty watches only the imports that existed when it started.
            notes.append("Open Alacritty windows show this theme now. Restart Alacritty once, and later theme changes apply live.")
        }
        return IntegrationPlan(operations: [
            .writeManagedFile(path: file.path, contents: Data(AlacrittyRenderer.themeFile(request.current).utf8)),
            .setConfigValue(path: detection.context["config"]!, table: key == "import" ? nil : "general", key: "import", value: list),
        ], conflicts: detection.conflicts, notes: notes)
    }

    /// Alacritty watches its config, and imported files since 0.14.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        guard !services.processes(bundleID: Self.bundleID).isEmpty else { return .notRunning }
        if let version = SemanticVersion(detection.context["version"] ?? ""), version < SemanticVersion(0, 14, 0) {
            return .needsRestart("Alacritty before 0.14 does not reload imported files. Restart it to see the theme.")
        }
        return .notNeeded
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        if case .mismatch(let reason) = Self.verifyFiles(plan) { return .mismatch(reason) }
        return detection.conflicts.isEmpty ? .matches : .overridden(detection.conflicts)
    }
}

// MARK: - Warp

public struct WarpIntegration: Integration {
    public let id = "warp"
    public let displayName = "Warp"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "dev.warp.Warp-Stable"
    /// Warp loads changed theme files about half a second after they change, and a setting that names a theme it has
    /// not loaded yet falls back to Dark. So while Warp runs, Scene waits this long between the files and the setting.
    static let settle = 1000
    public init() {}

    static func folder(_ env: SceneEnvironment) -> URL { env.home.appendingPathComponent(".warp") }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let settings = Self.folder(env).appendingPathComponent("settings.toml")
        // Warp moves its settings into this file once. Creating it first would skip that move.
        guard FileOps.exists(settings) else {
            return Detection(installed: true, version: Processes.appVersion(at: app),
                             setup: .blocked("Warp has no settings file yet. Update Warp and open it once, then apply again."))
        }
        return Detection(installed: true, version: Processes.appVersion(at: app), detail: Operation.tilde(settings.path),
                         conflicts: ["If Settings Sync is on, other Macs receive the theme name. Without Scene they show Warp's Dark theme."],
                         context: ["settings": settings.path, "running": services.processes(bundleID: Self.bundleID).isEmpty ? "0" : "1"])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let themes = Self.folder(env).appendingPathComponent("themes/scene")
        var ops: [Operation] = []
        var entries: [Appearance: String] = [:]
        for (appearance, variant) in request.nativeVariants.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            // A file and a name for each theme and look: Warp repaints only when the setting names another theme.
            let name = "Scene: \(request.theme.id) (\(appearance.rawValue))"
            let file = themes.appendingPathComponent("\(request.theme.id.replacingOccurrences(of: "/", with: "-"))-\(appearance.rawValue).yaml")
            ops.append(.writeManagedFile(path: file.path, contents: Data(WarpRenderer.themeFile(variant, name: name).utf8)))
            entries[appearance] = "{ custom = { name = \(KeyValueDocument.quoted(name)), path = \(KeyValueDocument.quoted(file.path)) } }"
        }
        if detection.context["running"] == "1" { ops.append(.pause(milliseconds: Self.settle)) }
        let settings = detection.context["settings"]!, table = "appearance.themes"
        let followsSystem = entries.count == 2
        ops.append(.setConfigValue(path: settings, table: table, key: "theme", value: entries[request.effectiveAppearance] ?? entries.values.first!))
        ops.append(.setConfigValue(path: settings, table: table, key: "system_theme", value: followsSystem ? "true" : "false"))
        if followsSystem {
            ops.append(.setConfigValue(path: settings, table: table, key: "selected_system_themes",
                                       value: "{ light = \(entries[.light]!), dark = \(entries[.dark]!) }"))
        }
        return IntegrationPlan(operations: ops, conflicts: detection.conflicts)
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for op in plan.operations {
            guard case let .setConfigValue(path, table, key, value) = op else { continue }
            let doc = KeyValueDocument(text: FileOps.read(URL(fileURLWithPath: path)).map { String(decoding: $0, as: UTF8.self) } ?? "")
            if doc.value(forKey: (table.map { $0 + "." } ?? "") + key) != value { return .mismatch("\(key) was not saved") }
        }
        return Self.verifyFiles(plan)
    }
}
