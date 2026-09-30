import Foundation
import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation

// MARK: - VS Code family

/// One integration per editor that shares VS Code's theme and settings format.
public struct VSCodeFamilyIntegration: Integration {
    public let id: String
    public let displayName: String
    public let kind = IntegrationKind.editor
    public let bundleIDs: [String]
    let cliName: String
    let userFolder: String

    public static let all: [VSCodeFamilyIntegration] = [
        .init(id: "vscode", displayName: "VS Code", bundleIDs: ["com.microsoft.VSCode"], cliName: "code", userFolder: "Code"),
        .init(id: "cursor", displayName: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], cliName: "cursor", userFolder: "Cursor"),
        .init(id: "vscodium", displayName: "VSCodium", bundleIDs: ["com.vscodium", "com.visualstudio.code.oss"], cliName: "codium", userFolder: "VSCodium"),
        .init(id: "windsurf", displayName: "Windsurf / Devin Desktop", bundleIDs: ["com.exafunction.windsurf"], cliName: "windsurf", userFolder: "Windsurf"),
    ]

    func settingsURL(_ env: SceneEnvironment) -> URL {
        env.home.appendingPathComponent("Library/Application Support/\(userFolder)/User/settings.json")
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = bundleIDs.lazy.compactMap(env.locateApp).first else { return .notInstalled() }
        let cli = app.appendingPathComponent("Contents/Resources/app/bin/\(cliName)")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else {
            return Detection(installed: true, support: .unavailable("CLI missing"), setup: .blocked("\(displayName)'s command-line tool is missing from the app bundle"))
        }
        let settings = settingsURL(env)
        var context = ["cli": cli.path, "settings": settings.path, "autoDetect": "0"]
        var conflicts: [String] = []
        var detail = Operation.tilde(settings.path)
        if let data = FileOps.read(FileOps.resolvedTarget(settings)) {
            do {
                let doc = try JSONCDocument(text: String(decoding: data, as: UTF8.self))
                if doc.value(forKey: "window.autoDetectColorScheme") == .bool(true) { context["autoDetect"] = "1" }
                if case .string(let current)? = doc.value(forKey: "workbench.colorTheme"), !current.hasPrefix("Scene ") {
                    detail = "Current theme: \(current)"
                }
            } catch {
                return Detection(installed: true, version: Processes.appVersion(at: app), setup: .blocked("settings.json cannot be read: \(error). Fix it in \(displayName) first."))
            }
        }
        conflicts.append("If Settings Sync is on, other Macs receive the theme name. Without Scene they show \(displayName)'s default theme.")
        return Detection(installed: true, version: Processes.appVersion(at: app), detail: detail, conflicts: conflicts, context: context)
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let (files, version) = try VSCodeRenderer.extensionFiles(variants: request.theme.variants)
        let vsix = env.appSupport.appendingPathComponent("VSCode/scene-themes-\(version).vsix")
        let settings = detection.context["settings"]!
        var ops: [Operation] = [
            .writeManagedFile(path: vsix.path, contents: try ZipArchive.create(files: files)),
            .installEditorExtension(cli: detection.context["cli"]!, packagePath: vsix.path, extensionID: VSCodeRenderer.extensionID, version: version),
        ]
        if detection.context["autoDetect"] == "1" {
            // With autodetect on, VS Code ignores workbench.colorTheme and reads the preferred keys.
            ops.append(.setJSONValue(path: settings, key: "workbench.preferredDarkColorTheme", value: .string(VSCodeRenderer.labels[.dark]!)))
            ops.append(.setJSONValue(path: settings, key: "workbench.preferredLightColorTheme", value: .string(VSCodeRenderer.labels[.light]!)))
        } else {
            let label = VSCodeRenderer.labels[request.forcedAppearance ?? request.effectiveAppearance]!
            ops.append(.setJSONValue(path: settings, key: "workbench.colorTheme", value: .string(label)))
        }
        return IntegrationPlan(operations: ops, conflicts: detection.conflicts)
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for op in plan.operations {
            guard case let .setJSONValue(path, key, value) = op else { continue }
            guard let data = FileOps.read(URL(fileURLWithPath: path)),
                  let doc = try? JSONCDocument(text: String(decoding: data, as: UTF8.self)),
                  doc.value(forKey: key) == value else { return .mismatch("\(key) was not saved") }
        }
        return Self.verifyFiles(plan)
    }
}

// MARK: - Neovim

public struct NeovimIntegration: Integration {
    public let id = "neovim"
    public let displayName = "Neovim"
    public let kind = IntegrationKind.editor
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let nvim = env.locateExecutable("nvim") else { return .notInstalled() }
        let config = env.xdgConfigHome.appendingPathComponent("nvim")
        let shim = config.appendingPathComponent("plugin/scene.lua")
        var version: String?
        if let result = try? await services.run(nvim.path, ["--version"], environment: nil), result.status == 0 {
            version = result.stdout.split(separator: "\n").first.map { String($0.replacingOccurrences(of: "NVIM v", with: "")) }
        }
        var conflicts: [String] = []
        if let hits = Self.grep(config, patterns: ["auto-dark-mode", "dark-notify", "dark_notify"]), !hits.isEmpty {
            conflicts.append("Your config switches colorschemes with the system appearance (\(hits.joined(separator: ", "))). Scene's theme also follows Light/Dark; one of them wins at each switch.")
        }
        let firstInstall = !FileOps.exists(shim)
        return Detection(installed: true, version: version, detail: Operation.tilde(config.path), conflicts: conflicts,
                         context: ["config": config.path, "firstInstall": firstInstall ? "1" : "0"])
    }

    /// Lists config files that mention any pattern. Read-only and bounded.
    static func grep(_ folder: URL, patterns: [String]) -> [String]? {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return nil }
        var hits: [String] = []
        var checked = 0
        for case let url as URL in enumerator where ["lua", "vim"].contains(url.pathExtension) {
            checked += 1
            if checked > 400 { break }
            if url.lastPathComponent == "scene.lua" { continue }
            guard let text = FileOps.read(url).map({ String(decoding: $0, as: UTF8.self) }) else { continue }
            if patterns.contains(where: { text.contains($0) }) { hits.append(url.lastPathComponent) }
        }
        return hits
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let config = URL(fileURLWithPath: detection.context["config"]!)
        let data = env.appSupport.appendingPathComponent("Neovim/theme.json")
        let ops: [Operation] = [
            .writeManagedFile(path: config.appendingPathComponent("plugin/scene.lua").path, contents: Data(try NeovimRenderer.shim(dataPath: data.path).utf8)),
            .writeManagedFile(path: config.appendingPathComponent("colors/scene.lua").path, contents: Data(NeovimRenderer.colorsFile.utf8)),
            .writeManagedFile(path: data.path, contents: try NeovimRenderer.dataFile(variants: request.nativeVariants)),
        ]
        var notes = ["Scene adds plugin/scene.lua and colors/scene.lua. It never edits your init.lua."]
        if detection.context["firstInstall"] == "1" { notes.append("Neovim windows that are already open pick up the theme after a restart. Later theme changes apply live.") }
        return IntegrationPlan(operations: ops, conflicts: detection.conflicts, notes: notes)
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        detection.context["firstInstall"] == "1" ? .needsRestart("Open Neovim windows show the theme after a restart. Later changes apply live.") : .notNeeded
    }
}

// MARK: - Zed

public struct ZedIntegration: Integration {
    public let id = "zed"
    public let displayName = "Zed"
    public let kind = IntegrationKind.editor
    public static let bundleIDs = ["dev.zed.Zed", "dev.zed.Zed-Preview"]
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = Self.bundleIDs.lazy.compactMap(env.locateApp).first else { return .notInstalled() }
        let folder = env.xdgConfigHome.appendingPathComponent("zed")
        let settings = folder.appendingPathComponent("settings.json")
        var detail = Operation.tilde(settings.path)
        if let data = FileOps.read(FileOps.resolvedTarget(settings)) {
            do {
                let doc = try JSONCDocument(text: String(decoding: data, as: UTF8.self))
                switch doc.value(forKey: "theme") {
                case .string(let name)?: detail = "Current theme: \(name)"
                case .object(let members)?:
                    let names = ["dark", "light"].compactMap { key in members.first { $0.key == key }.flatMap { if case .string(let v) = $0.value { v } else { nil } } }
                    if !names.isEmpty { detail = "Current themes: " + names.joined(separator: ", ") }
                default: break
                }
            } catch {
                return Detection(installed: true, version: Processes.appVersion(at: app),
                                 setup: .blocked("settings.json cannot be read: \(error). Fix it in Zed first."))
            }
        }
        return Detection(installed: true, version: Processes.appVersion(at: app), detail: detail,
                         context: ["settings": settings.path, "themes": folder.appendingPathComponent("themes").path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let theme = URL(fileURLWithPath: detection.context["themes"]!).appendingPathComponent("scene.json")
        return IntegrationPlan(operations: [
            .writeManagedFile(path: theme.path, contents: try ZedRenderer.themeFile(variants: request.nativeVariants)),
            .setJSONValue(path: detection.context["settings"]!, key: "theme", value: ZedRenderer.setting(forced: request.forcedAppearance)),
        ])
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for op in plan.operations {
            guard case let .setJSONValue(path, key, value) = op else { continue }
            guard let data = FileOps.read(URL(fileURLWithPath: path)),
                  let doc = try? JSONCDocument(text: String(decoding: data, as: UTF8.self)),
                  doc.value(forKey: key) == value else { return .mismatch("\(key) was not saved") }
        }
        return Self.verifyFiles(plan)
    }
}

// MARK: - Xcode

public struct XcodeIntegration: Integration {
    public let id = "xcode"
    public let displayName = "Xcode"
    public let kind = IntegrationKind.editor
    public static let bundleID = "com.apple.dt.Xcode"
    static let domain = "com.apple.dt.Xcode"
    /// Xcode keeps one theme for Light and one for Dark, and switches with macOS.
    static let keys: [Appearance: String] = [.light: "XCFontAndColorCurrentTheme", .dark: "XCFontAndColorCurrentDarkTheme"]
    public init() {}

    static func folder(_ env: SceneEnvironment) -> URL {
        env.home.appendingPathComponent("Library/Developer/Xcode/UserData/FontAndColorThemes")
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        var context: [String: String] = [:]
        var names: [String] = []
        for appearance in [Appearance.light, .dark] {
            let current: String = {
                if case .string(let name)? = services.preference(domain: Self.domain, key: Self.keys[appearance]!) { return name }
                return appearance == .dark ? "Default (Dark).xccolortheme" : "Default (Light).xccolortheme"
            }()
            names.append((current as NSString).deletingPathExtension)
            // The theme Scene takes fonts from: the user's own file, or one that ships inside Xcode.
            let shared = app.appendingPathComponent("Contents/SharedFrameworks")
            let candidates = [Self.folder(env).appendingPathComponent(current),
                              shared.appendingPathComponent("DVTUserInterfaceKit.framework/Versions/A/Resources/FontAndColorThemes/\(current)"),
                              shared.appendingPathComponent("SourceEditor.framework/Versions/A/Resources/\(current)")]
            context["\(appearance.rawValue)Base"] = candidates.first { FileOps.exists($0) }?.path ?? ""
        }
        return Detection(installed: true, version: Processes.appVersion(at: app), detail: "Current themes: " + names.joined(separator: ", "),
                         context: context)
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let variants = request.nativeVariants
        guard let fallback = variants[.dark] ?? variants[.light] else { throw SceneError.invalid("no variant to render") }
        var ops: [Operation] = []
        for slot in [Appearance.light, .dark] {
            let basePath = detection.context["\(slot.rawValue)Base"] ?? ""
            let base = FileOps.read(URL(fileURLWithPath: basePath))
                .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
            ops.append(.writeManagedFile(path: Self.folder(env).appendingPathComponent(XcodeRenderer.fileNames[slot]!).path,
                                         contents: try XcodeRenderer.theme(variants[slot] ?? fallback, base: base)))
        }
        for slot in [Appearance.light, .dark] {
            ops.append(.setPreference(domain: Self.domain, key: Self.keys[slot]!, value: .string(XcodeRenderer.fileNames[slot]!)))
        }
        return IntegrationPlan(operations: ops, notes: ["Scene keeps the fonts of your current Xcode themes and changes only the colors."])
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        services.processes(bundleID: Self.bundleID).isEmpty ? .notNeeded : .needsRestart("Quit and reopen Xcode to see the theme.")
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for op in plan.operations {
            if case let .setPreference(domain, key, value) = op, services.preference(domain: domain, key: key) != value {
                return .mismatch("Xcode's \(key) setting was not saved")
            }
        }
        return Self.verifyFiles(plan)
    }
}

// MARK: - Helix

public struct HelixIntegration: Integration {
    public let id = "helix"
    public let displayName = "Helix"
    public let kind = IntegrationKind.editor
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let hx = env.locateExecutable("hx") else { return .notInstalled() }
        var version: String?
        if let result = try? await services.run(hx.path, ["--version"], environment: nil), result.status == 0 {
            version = result.stdout.split(separator: " ").dropFirst().first.map(String.init)
        }
        let folder = env.xdgConfigHome.appendingPathComponent("helix")
        let config = folder.appendingPathComponent("config.toml")
        var context = ["folder": folder.path, "config": config.path]
        var detail = Operation.tilde(config.path)
        if let data = FileOps.read(FileOps.resolvedTarget(config)) {
            let doc = KeyValueDocument(text: String(decoding: data, as: UTF8.self))
            // Newer Helix builds pick a theme per appearance in a [theme] table.
            if doc.keys.contains(where: { $0.hasPrefix("theme.") }) { context["perAppearance"] = "1" }
            if let current = doc.value(forKey: "theme") { detail = "Current theme: \(current.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))" }
        }
        return Detection(installed: true, version: version, detail: detail, context: context)
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let folder = URL(fileURLWithPath: detection.context["folder"]!)
        let config = detection.context["config"]!
        let name = KeyValueDocument.quoted(HelixRenderer.name)
        var ops: [Operation] = [.writeManagedFile(path: folder.appendingPathComponent("themes/\(HelixRenderer.name).toml").path,
                                                  contents: Data(HelixRenderer.themeFile(request.current).utf8))]
        if detection.context["perAppearance"] == "1" {
            ops.append(.setConfigValue(path: config, table: "theme", key: "light", value: name))
            ops.append(.setConfigValue(path: config, table: "theme", key: "dark", value: name))
        } else {
            ops.append(.setConfigValue(path: config, table: nil, key: "theme", value: name))
        }
        return IntegrationPlan(operations: ops)
    }

    /// SIGUSR1 makes Helix read its config and theme again.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        let pids = services.processes(named: "hx")
        guard !pids.isEmpty else { return .notRunning }
        return services.signal(SIGUSR1, to: pids) > 0 ? .reloaded : .failed("could not signal Helix")
    }
}
