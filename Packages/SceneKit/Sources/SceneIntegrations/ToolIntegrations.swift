import Foundation
import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation

// MARK: - tmux

public struct TmuxIntegration: Integration {
    public let id = "tmux"
    public let displayName = "tmux"
    public let kind = IntegrationKind.tool
    public init() {}

    static func file(_ env: SceneEnvironment) -> URL { env.xdgConfigHome.appendingPathComponent("tmux/scene.conf") }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let tmux = env.locateExecutable("tmux") else { return .notInstalled() }
        var version: String?
        if let result = try? await services.run(tmux.path, ["-V"], environment: nil), result.status == 0 {
            version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "tmux ", with: "")
        }
        // tmux reads ~/.tmux.conf, or the XDG file when there is none.
        let candidates = [env.home.appendingPathComponent(".tmux.conf"), env.xdgConfigHome.appendingPathComponent("tmux/tmux.conf")]
        let config = candidates.first { FileOps.exists($0) } ?? candidates[0]
        var setup = SetupState.ready
        if FileOps.exists(config) && !FileOps.isWritable(config) {
            setup = .blocked("\(Operation.tilde(config.path)) is read-only. Add this line to your config source: source-file -q '\(Self.file(env).path)'")
        }
        return Detection(installed: true, version: version, detail: Operation.tilde(config.path), setup: setup,
                         context: ["tmux": tmux.path, "config": config.path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let file = Self.file(env)
        guard !file.path.contains("'") else { throw SceneError.invalid("the path \(file.path) has a quote in it") }
        return IntegrationPlan(operations: [
            .writeManagedFile(path: file.path, contents: Data(TmuxRenderer.configFile(request.current).utf8)),
            .ensureAnchor(path: detection.context["config"]!, block: Anchor.block(lines: ["source-file -q '\(file.path)'"], comment: "#"), placement: .end),
        ], notes: ["Running tmux sessions change right away."])
    }

    /// Loads Scene's file into the running server. After a restore, unsets Scene's options and loads the user's config again.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        guard let tmux = detection.context["tmux"], let config = detection.context["config"] else { return .notNeeded }
        let file = Self.file(env)
        var arguments: [String]
        if FileOps.exists(file) {
            arguments = ["source-file", "-q", file.path]
        } else {
            arguments = TmuxRenderer.options.flatMap { ["set", "-gqu", $0, ";"] }
            if FileOps.exists(URL(fileURLWithPath: config)) { arguments += ["source-file", "-q", config] } else { arguments.removeLast() }
        }
        guard let result = try? await services.run(tmux, arguments, environment: nil) else { return .failed("could not run tmux") }
        if result.status == 0 { return .reloaded }
        return result.stderr.contains("no server running") || result.stderr.contains("error connecting") ? .notRunning : .failed(result.stderr)
    }
}

// MARK: - bat and delta

public struct BatIntegration: Integration {
    public let id = "bat"
    public let displayName = "bat & delta"
    public let kind = IntegrationKind.tool
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let bat = env.locateExecutable("bat") else { return .notInstalled() }
        var version: String?
        if let result = try? await services.run(bat.path, ["--version"], environment: nil), result.status == 0 {
            version = result.stdout.split(separator: " ").dropFirst().first.map(String.init)
        }
        let delta = env.locateExecutable("delta")
        // Git reads ~/.gitconfig and the XDG file. Scene adds its include to the one that exists.
        let candidates = [env.home.appendingPathComponent(".gitconfig"), env.xdgConfigHome.appendingPathComponent("git/config")]
        let gitconfig = candidates.first { FileOps.exists($0) } ?? candidates[0]
        var context = ["bat": bat.path, "version": version ?? ""]
        if let delta { context["delta"] = delta.path; context["gitconfig"] = gitconfig.path }
        return Detection(installed: true, version: version, detail: delta == nil ? "bat. delta is not installed." : "bat, and delta through \(Operation.tilde(gitconfig.path))",
                         context: context)
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let folder = env.xdgConfigHome.appendingPathComponent("bat")
        let variants = request.nativeVariants
        var ops: [Operation] = []
        for slot in [Appearance.dark, .light] {
            let name = BatRenderer.names[slot]!
            ops.append(.writeManagedFile(path: folder.appendingPathComponent("themes/\(name).tmTheme").path,
                                         contents: try BatRenderer.tmTheme(variants[slot] ?? request.current, name: name)))
        }
        // bat 0.25 added --theme-dark, --theme-light, and auto:system. An older bat stops at an option it does not know.
        let adaptive = variants.count == 2 && (SemanticVersion(detection.context["version"] ?? "").map { $0 >= SemanticVersion(0, 25, 0) } ?? false)
        let lines = adaptive
            ? ["--theme=auto:system", "--theme-dark=\(BatRenderer.names[.dark]!)", "--theme-light=\(BatRenderer.names[.light]!)"]
            : ["--theme=\(BatRenderer.names[request.effectiveAppearance]!)"]
        ops.append(.ensureAnchor(path: folder.appendingPathComponent("config").path, block: Anchor.block(lines: lines, comment: "#"), placement: .end))
        var notes = ["Scene rebuilds bat's theme cache with “bat cache --build”. A BAT_THEME variable in your shell wins over this theme."]
        if let gitconfig = detection.context["gitconfig"] {
            let include = env.xdgConfigHome.appendingPathComponent("git/scene-delta.gitconfig")
            guard !include.path.contains("\"") else { throw SceneError.invalid("the path \(include.path) has a quote in it") }
            ops.append(.writeManagedFile(path: include.path, contents: Data(BatRenderer.deltaConfig(request.current).utf8)))
            ops.append(.ensureAnchor(path: gitconfig, block: Anchor.block(lines: ["[include]", "\tpath = \"\(include.path)\""], comment: "#"), placement: .end))
            notes.append("delta shows the \(request.effectiveAppearance.rawValue) look.")
        }
        return IntegrationPlan(operations: ops, notes: notes)
    }

    /// bat and delta read themes from bat's cache, so it is built again after every change.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        guard let bat = detection.context["bat"] else { return .notNeeded }
        guard let result = try? await services.run(bat, ["cache", "--build"], environment: nil) else { return .failed("could not run bat") }
        return result.status == 0 ? .notNeeded : .failed("bat cache --build: \(result.stderr.prefix(200))")
    }
}

// MARK: - btop

public struct BtopIntegration: Integration {
    public let id = "btop"
    public let displayName = "btop"
    public let kind = IntegrationKind.tool
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let btop = env.locateExecutable("btop") else { return .notInstalled() }
        var version: String?
        if let result = try? await services.run(btop.path, ["--version"], environment: nil), result.status == 0,
           let match = result.stdout.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
            version = String(result.stdout[match])
        }
        let folder = env.xdgConfigHome.appendingPathComponent("btop")
        return Detection(installed: true, version: version, detail: Operation.tilde(folder.appendingPathComponent("btop.conf").path),
                         context: ["folder": folder.path, "version": version ?? ""])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let folder = URL(fileURLWithPath: detection.context["folder"]!)
        return IntegrationPlan(operations: [
            .writeManagedFile(path: folder.appendingPathComponent("themes/\(BtopRenderer.name).theme").path,
                              contents: Data(BtopRenderer.themeFile(request.current).utf8)),
            .setConfigValue(path: folder.appendingPathComponent("btop.conf").path, table: nil, key: "color_theme",
                            value: KeyValueDocument.quoted(BtopRenderer.name)),
        ])
    }

    /// btop 1.3.1 and later read their config again on SIGUSR2.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        let pids = services.processes(named: "btop")
        guard !pids.isEmpty else { return .notRunning }
        guard let version = SemanticVersion(detection.context["version"] ?? ""), version >= SemanticVersion(1, 3, 1) else {
            return .needsRestart("Quit and reopen btop to see the theme.")
        }
        return services.signal(SIGUSR2, to: pids) > 0 ? .reloaded : .failed("could not signal btop")
    }
}
