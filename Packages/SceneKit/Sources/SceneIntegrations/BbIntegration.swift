import Foundation
import SceneEngine
import SceneFoundation
import SceneRenderers

/// bb, the app for managing AI coding agents. Its themes are CSS files in `<theme folder>/<name>/theme.css`, and its
/// server keeps which one is active. Scene writes `scene/theme.css` with a block for each look and selects it with
/// `bb theme set`, so Restore selects the theme that was active before. bb shows the change live in every open window.
public struct BbIntegration: Integration {
    public let id = "bb"
    public let displayName = "bb"
    public let kind = IntegrationKind.tool
    public static let themeID = "scene"
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let bb = env.locateExecutable("bb") else { return .notInstalled() }
        var version: String?
        if let result = try? await services.run(bb.path, ["--version"], environment: nil), result.status == 0 {
            version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // bb knows where its data lives, which depends on how it was installed. Its default is ~/.bb/theme.
        var folder = env.path(".bb/theme")
        if let result = try? await services.run(bb.path, ["theme", "dir"], environment: nil), result.status == 0 {
            let printed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if printed.hasPrefix("/") { folder = URL(fileURLWithPath: printed) }
        }
        var detail = Operation.tilde(folder.path)
        var setup = SetupState.ready
        if let result = try? await services.run(bb.path, ["theme", "show", "--json"], environment: nil), result.status == 0,
           let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any], let current = root["themeId"] as? String {
            detail = "Current theme: \(current)"
        } else {
            setup = .blocked("bb does not answer. Open bb, then apply again.")
        }
        return Detection(installed: true, version: version, detail: detail, setup: setup,
                         context: ["cli": bb.path, "file": folder.appendingPathComponent("\(Self.themeID)/theme.css").path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        // A theme with one look fills both blocks with it.
        let light = request.nativeVariants[.light] ?? request.current, dark = request.nativeVariants[.dark] ?? request.current
        return IntegrationPlan(operations: [
            .writeManagedFile(path: detection.context["file"]!, contents: Data(BbRenderer.themeFile(light: light, dark: dark).utf8)),
            .setBbTheme(cli: detection.context["cli"]!, id: Self.themeID),
        ], notes: ["bb follows its own Light/Dark setting. Its diff and file preview colors keep bb's code theme."])
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for case let .setBbTheme(cli, id) in plan.operations {
            guard let result = try? await services.run(cli, ["theme", "show", "--json"], environment: nil), result.status == 0,
                  let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
                  root["themeId"] as? String == id else { return .mismatch("bb did not report \(id) as its theme") }
        }
        return Self.verifyFiles(plan)
    }
}
