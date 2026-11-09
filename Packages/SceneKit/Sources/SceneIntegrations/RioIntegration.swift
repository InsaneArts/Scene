import Foundation
import SceneEngine
import SceneFoundation
import SceneRenderers
import SceneThemes

public struct RioIntegration: Integration {
    public let id = "rio"
    public let displayName = "Rio"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "com.raphaelamorim.rio"
    private let configHome: URL?

    /// Rio on macOS uses ~/.config/rio, independently of XDG_CONFIG_HOME.
    public init(configHome: URL? = ProcessInfo.processInfo.environment["RIO_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }) {
        self.configHome = configHome
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let folder = configHome ?? env.path(".config/rio")
        let config = folder.appendingPathComponent("config.toml")
        let setup: SetupState = FileOps.exists(config) && !FileOps.isWritable(config)
            ? .blocked("\(Operation.tilde(config.path)) is read-only.") : .ready
        let doc = KeyValueDocument(text: FileOps.read(FileOps.resolvedTarget(config)).map { String(decoding: $0, as: UTF8.self) } ?? "")
        let conflicts = doc.value(forKey: "force-theme") == nil ? [] : ["Your force-theme setting pins Rio to one appearance, so it does not follow macOS Light/Dark."]
        return Detection(installed: true, version: Processes.appVersion(at: app), detail: Operation.tilde(config.path), setup: setup, conflicts: conflicts,
                         context: ["config": config.path, "themes": folder.appendingPathComponent("themes").path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let config = detection.context["config"]!
        let folder = URL(fileURLWithPath: detection.context["themes"]!)
        var operations: [Operation] = []
        // A forced or single-look theme fills both slots with the current look.
        for appearance in [Appearance.dark, .light] {
            let variant = request.nativeVariants[appearance] ?? request.current
            operations.append(.writeManagedFile(path: folder.appendingPathComponent("scene-\(appearance.rawValue).toml").path,
                                                contents: Data(RioRenderer.themeFile(variant).utf8)))
        }
        operations += [
            .setConfigValue(path: config, table: nil, key: "theme", value: KeyValueDocument.quoted("scene-" + request.current.appearance.rawValue)),
            .setConfigValue(path: config, table: "adaptive-theme", key: "dark", value: KeyValueDocument.quoted("scene-dark")),
            .setConfigValue(path: config, table: "adaptive-theme", key: "light", value: KeyValueDocument.quoted("scene-light")),
        ]
        return IntegrationPlan(operations: operations, conflicts: request.nativeVariants.count == 2 ? detection.conflicts : [], notes: ["Rio watches its configuration for changes. Themes with both looks follow macOS Light/Dark."])
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for case let .setConfigValue(path, table, key, value) in plan.operations {
            let doc = KeyValueDocument(text: FileOps.read(URL(fileURLWithPath: path)).map { String(decoding: $0, as: UTF8.self) } ?? "")
            guard doc.value(forKey: (table.map { $0 + "." } ?? "") + key) == value else { return .mismatch("\(key) was not saved") }
        }
        if case .mismatch(let reason) = Self.verifyFiles(plan) { return .mismatch(reason) }
        return plan.conflicts.isEmpty ? .matches : .overridden(plan.conflicts)
    }
}
