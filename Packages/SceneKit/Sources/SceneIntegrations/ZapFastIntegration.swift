import Foundation
import SceneEngine
import SceneFoundation
import SceneRenderers

/// ZapFast reads the selected palette from settings on startup. reload-themes only
/// refreshes its in-memory selection, so changing settings requires a restart.
public struct ZapFastIntegration: Integration {
    public let id = "zapfast"
    public let displayName = "ZapFast"
    public let kind = IntegrationKind.tool
    // ZapFast retains its original bundle identity after the rename.
    public static let bundleID = "me.paolino.fastsapp"
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let folder = env.path("Library/Application Support/me.paolino.zapfast")
        let settings = folder.appendingPathComponent("settings.json")
        var setup = SetupState.ready
        if FileOps.exists(settings) && !FileOps.isWritable(settings) {
            setup = .blocked("\(Operation.tilde(settings.path)) is read-only.")
        } else if let data = FileOps.read(FileOps.resolvedTarget(settings)) {
            do { _ = try JSONCDocument(text: String(decoding: data, as: UTF8.self)) }
            catch { setup = .blocked("settings.json cannot be read: \(error). Fix it in ZapFast first.") }
        }
        return Detection(installed: true, version: Processes.appVersion(at: app),
                         detail: Operation.tilde(settings.path), setup: setup,
                         context: ["settings": settings.path, "themes": folder.appendingPathComponent("themes").path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let settings = detection.context["settings"]!
        let file = URL(fileURLWithPath: detection.context["themes"]!).appendingPathComponent("scene.json")
        return IntegrationPlan(operations: [
            .writeManagedFile(path: file.path, contents: try ZapFastRenderer.themeFile(request.current)),
            .setJSONValue(path: settings, key: "custom_theme", value: .string("scene.json")),
        ], notes: ["Quit ZapFast before applying or restoring so it cannot save over the theme setting. Reopen it to see the new look."])
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        services.processes(bundleID: Self.bundleID).isEmpty && services.processes(named: "zapfast").isEmpty
            ? .notRunning : .needsRestart("Quit and reopen ZapFast to load the selected theme.")
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for case let .setJSONValue(path, key, value) in plan.operations {
            guard let data = FileOps.read(URL(fileURLWithPath: path)),
                  let doc = try? JSONCDocument(text: String(decoding: data, as: UTF8.self)),
                  doc.value(forKey: key) == value else { return .mismatch("\(key) was not saved") }
        }
        return Self.verifyFiles(plan)
    }
}
