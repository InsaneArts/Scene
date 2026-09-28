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
