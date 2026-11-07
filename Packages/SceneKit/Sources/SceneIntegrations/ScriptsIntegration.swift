import Foundation
import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation

/// Runs the scripts the user listed in Settings after each theme change, so their own tools can follow it.
/// Scene writes the theme to `~/.config/scene/theme.json` and runs each script without a shell, with the colors of the
/// shown look in `SCENE_…` variables. Restore deletes the file and runs the scripts with `SCENE_EVENT=restore`.
/// Scripts come only from Settings, never from a theme.
public struct ScriptsIntegration: Integration {
    public let id = "scripts"
    public let displayName = "Your scripts"
    public let kind = IntegrationKind.tool
    /// How long one script may run.
    public static let timeout: TimeInterval = 10
    let scripts: @Sendable () -> [String]

    /// - Parameter scripts: the paths listed in Settings, read at each detect.
    public init(scripts: @escaping @Sendable () -> [String]) { self.scripts = scripts }

    public static func file(_ env: SceneEnvironment) -> URL { env.xdgConfigHome.appendingPathComponent("scene/theme.json") }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        let listed = scripts()
        guard !listed.isEmpty else { return .notInstalled() }
        var usable: [String] = [], problems: [String] = []
        for path in listed {
            if let problem = Self.problem(path) { problems.append(problem) } else { usable.append(path) }
        }
        let names = usable.map { ($0 as NSString).lastPathComponent }
        return Detection(installed: true, detail: names.isEmpty ? nil : names.joined(separator: ", "),
                         setup: usable.isEmpty ? .blocked(problems.joined(separator: " ")) : .ready,
                         conflicts: problems, context: ["scripts": usable.joined(separator: "\n")])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let data = try ThemeFileRenderer.file(variants: request.nativeVariants, appearance: request.effectiveAppearance, mode: request.mode.rawValue)
        let names = Self.scripts(detection).map { ($0 as NSString).lastPathComponent }
        return IntegrationPlan(operations: [.writeManagedFile(path: Self.file(env).path, contents: data)], conflicts: detection.conflicts,
                               notes: ["Runs \(names.joined(separator: ", ")) with the theme's colors in SCENE_ variables."])
    }

    /// Runs each script in turn. After a restore the file is gone, and the scripts get `SCENE_EVENT=restore` and no colors.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        let file = Self.file(env)
        var environment = ["SCENE_EVENT": "restore", "SCENE_THEME_FILE": file.path]
        if let data = FileOps.read(file) {
            guard let colors = ThemeFileRenderer.environment(file: data) else {
                return .needsUserAction("\(Operation.tilde(file.path)) is not the file Scene wrote, so Scene did not run your scripts.")
            }
            environment.merge(colors) { $1 }
            environment["SCENE_EVENT"] = "apply"
        }
        var failures: [String] = []
        for script in Self.scripts(detection) {
            let name = (script as NSString).lastPathComponent
            do {
                let result = try await services.run(script, [], environment: environment, timeout: Self.timeout)
                if result.status != 0 {
                    let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)
                    failures.append("\(name) exited with \(result.status)" + (message.isEmpty ? "." : ": \(message)"))
                }
            } catch {
                failures.append("\(name): \(error).")
            }
        }
        return failures.isEmpty ? .reloaded : .needsUserAction(failures.joined(separator: " "))
    }

    static func scripts(_ detection: Detection) -> [String] {
        detection.context["scripts"].map { $0.split(separator: "\n").map(String.init) } ?? []
    }

    /// Why Scene won't run this file, or nil when it will. A script must be an executable file of this user, and
    /// neither it nor its folder may be writable by others, because it runs with Scene's permissions.
    /// A symbolic link is followed, and the same rules apply to its target.
    public static func problem(_ path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard path.hasPrefix("/"), !path.contains("\n") else { return "\(name) is not a full path." }
        let target = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: target.path) else { return "\(name) does not exist." }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return "\(name) is not a file." }
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { return "\(name) belongs to another user." }
        guard fm.isExecutableFile(atPath: target.path) else { return "\(name) is not executable. Run chmod +x on it." }
        let folder = target.deletingLastPathComponent().path
        for item in [target.path, folder] {
            guard let permissions = (try? fm.attributesOfItem(atPath: item))?[.posixPermissions] as? NSNumber else { return "Scene cannot read \(item)." }
            if permissions.intValue & 0o022 != 0 { return "\(Operation.tilde(item)) is writable by other users." }
        }
        return nil
    }
}
