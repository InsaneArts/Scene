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
        let pids = Processes.pids(bundleID: Self.bundleID)
        guard !pids.isEmpty else { return .notRunning }
        guard let version = SemanticVersion(detection.context["version"] ?? ""), version >= SemanticVersion(1, 2, 0) else {
            return .needsUserAction("Press ⌘⇧, in Ghostty to reload its config")
        }
        // SIGUSR2 reloads the config on 1.2 and later. Older versions would quit, so they are excluded above.
        return Processes.signal(SIGUSR2, to: pids) > 0 ? .reloaded : .failed("could not signal Ghostty")
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
