import Foundation
import SceneEngine
import SceneFoundation
import SceneRenderers
import SceneThemes

/// The Herdr app (dev.herdr.app), herdr's desktop window. Scene writes `themes/scene.json`, or `scene-dark.json` and
/// `scene-light.json` for a theme with both looks, and sets `theme` in `settings.json`. Herdr reads both live.
/// A theme picked in Herdr's theme menu wins over settings.json and stays on that layout, so while Herdr runs,
/// Scene also picks its theme with `app.theme` on the shown layout.
public struct HerdrAppIntegration: Integration {
    public let id = "herdr-app"
    public let displayName = "Herdr app"
    public let kind = IntegrationKind.terminal
    public static let bundleID = "dev.herdr.app"
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let app = env.locateApp(Self.bundleID) else { return .notInstalled() }
        let folder = env.path(".config/herdr-app")
        let settings = folder.appendingPathComponent("settings.json")
        var setup = SetupState.ready
        if FileOps.exists(settings) && !FileOps.isWritable(settings) {
            setup = .blocked("\(Operation.tilde(settings.path)) is read-only.")
        } else if let data = FileOps.read(FileOps.resolvedTarget(settings)) {
            do { _ = try JSONCDocument(text: String(decoding: data, as: UTF8.self)) }
            catch { setup = .blocked("settings.json cannot be read: \(error). Fix it in Herdr first.") }
        }
        return Detection(installed: true, version: Processes.appVersion(at: app),
                         detail: Operation.tilde(settings.path), setup: setup,
                         context: ["settings": settings.path, "themes": folder.appendingPathComponent("themes").path,
                                   "herdr": app.appendingPathComponent("Contents/MacOS/Herdr").path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let themes = URL(fileURLWithPath: detection.context["themes"]!)
        func file(_ name: String, _ v: ResolvedVariant) throws -> Operation {
            .writeManagedFile(path: themes.appendingPathComponent("\(name).json").path, contents: try HerdrAppRenderer.themeFile(v))
        }
        let notes = ["Herdr keeps a theme picked in its menu on that layout. Scene picks its theme on the shown layout; after Restore, pick yours again in Herdr's theme menu."]
        let variants = request.nativeVariants
        let operations: [Operation]
        if let dark = variants[.dark], let light = variants[.light] {
            operations = [try file("scene-dark", dark), try file("scene-light", light),
                          .setJSONValue(path: detection.context["settings"]!, key: "theme",
                                        value: .object([JSONMember("light", .string("scene-light")), JSONMember("dark", .string("scene-dark"))]))]
        } else {
            operations = [try file("scene", request.current),
                          .setJSONValue(path: detection.context["settings"]!, key: "theme", value: .string("scene"))]
        }
        return IntegrationPlan(operations: operations, notes: notes)
    }

    /// Herdr reloads its files by itself. A theme picked in its menu would still hide Scene's, so pick each of
    /// Scene's themes on the shown layout; `app.theme` sets the half of the pick that matches the theme's lightness.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        guard let herdr = detection.context["herdr"], let settings = detection.context["settings"] else { return .notNeeded }
        guard !services.processes(bundleID: Self.bundleID).isEmpty else { return .notRunning }
        guard let data = FileOps.read(URL(fileURLWithPath: settings)),
              let doc = try? JSONCDocument(text: String(decoding: data, as: UTF8.self)) else { return .notNeeded }
        let names: [String] = switch doc.value(forKey: "theme") {
        case let .string(name): [name]
        case let .object(members): members.compactMap { if case let .string(name) = $0.value { name } else { nil } }
        default: []
        }
        for name in names where name.hasPrefix("scene") {
            guard let result = try? await services.run(herdr, ["do", "app.theme", "{\"name\":\"\(name)\"}"], environment: nil) else {
                return .failed("could not run Herdr")
            }
            if result.status != 0 { return .failed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
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
