import Foundation
import SceneEngine
import SceneFoundation
import SceneRenderers

/// ZapFast reads the selected palette from settings on startup. `zapfast reload-themes` rescans the palette files
/// but keeps the selection it holds in memory, so it shows a new `scene.json` live only when ZapFast already had
/// `scene.json` selected. Switching to it from another palette needs a restart.
public struct ZapFastIntegration: Integration {
    public let id = "zapfast"
    public let displayName = "ZapFast"
    public let kind = IntegrationKind.tool
    // ZapFast retains its original bundle identity after the rename.
    public static let bundleID = "me.paolino.fastsapp"
    static let file = "scene.json"
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let folder = env.path("Library/Application Support/me.paolino.zapfast")
        let settings = folder.appendingPathComponent("settings.json")
        var setup = SetupState.ready
        var selected = false
        if FileOps.exists(settings) && !FileOps.isWritable(settings) {
            setup = .blocked("\(Operation.tilde(settings.path)) is read-only.")
        } else if let data = FileOps.read(FileOps.resolvedTarget(settings)) {
            do { selected = try JSONCDocument(text: String(decoding: data, as: UTF8.self)).value(forKey: "custom_theme") == .string(Self.file) }
            catch { setup = .blocked("settings.json cannot be read: \(error). Fix it in ZapFast first.") }
        }
        let executable = (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleExecutable"] as? String) ?? "zapfast"
        return Detection(installed: true, version: Processes.appVersion(at: app),
                         detail: Operation.tilde(settings.path), setup: setup,
                         context: ["settings": settings.path, "themes": folder.appendingPathComponent("themes").path,
                                   "executable": app.appendingPathComponent("Contents/MacOS/\(executable)").path,
                                   "selected": selected ? "1" : "0"])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let settings = detection.context["settings"]!
        let file = URL(fileURLWithPath: detection.context["themes"]!).appendingPathComponent(Self.file)
        return IntegrationPlan(operations: [
            .writeManagedFile(path: file.path, contents: try ZapFastRenderer.themeFile(request.current)),
            .setJSONValue(path: settings, key: "custom_theme", value: .string(Self.file)),
        ], notes: [detection.context["selected"] == "1"
            ? "ZapFast already uses Scene's palette, so a running ZapFast reloads it with zapfast reload-themes."
            : "Quit ZapFast before this first apply so it cannot save over the theme setting, then reopen it. After that, theme changes show without a restart."])
    }

    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        guard !(services.processes(bundleID: Self.bundleID).isEmpty && services.processes(named: "zapfast").isEmpty) else { return .notRunning }
        // A running ZapFast keeps its selection in memory, so reload-themes shows the new file only when it was already selected.
        guard detection.context["selected"] == "1", let executable = detection.context["executable"] else {
            return .needsRestart("Quit and reopen ZapFast to load the selected theme.")
        }
        guard let result = try? await services.run(executable, ["reload-themes"], environment: nil, timeout: 10), result.status == 0 else {
            return .failed("zapfast reload-themes failed")
        }
        return .reloaded
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
