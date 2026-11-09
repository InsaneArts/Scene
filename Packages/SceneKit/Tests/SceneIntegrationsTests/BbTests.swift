import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("bb", .serialized)
struct BbTests {
    func setup(_ home: FixtureHome, theme: String = "nord") throws -> (FakeServices, Engine) {
        let bb = try home.write("bin/bb", "#!/bin/sh\n")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { $0 == "bb" ? bb : nil })
        let services = FakeServices()
        services.bbTheme = theme
        services.bbThemeFolder = home.path("data/theme").path
        return (services, Engine(env: env, services: services, integrations: [BbIntegration()], store: EngineStore(root: env.appSupport)))
    }

    func apply(_ engine: Engine, _ folder: String = "tokyo-night") async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme(folder), mode: .system, systemIsDark: true)
        return await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["bb"])
    }

    @Test func writesTheStylesheetSelectsItAndRestoreSelectsThePreviousTheme() async throws {
        let home = try FixtureHome()
        let (services, engine) = try setup(home)
        let report = try await apply(engine)
        #expect(report.results.first?.outcome == .applied, "\(String(describing: report.results.first?.outcome))")
        #expect(services.bbTheme == "scene")
        let ui = try #require(try Fixtures.theme("tokyo-night").variants[.dark]).interface
        let css = try #require(home.read("data/theme/scene/theme.css"))
        #expect(css.contains(".dark {") && css.contains("--canvas: \(ui.background.hex);") && css.contains("--primary: \(ui.accent.hex);"))
        _ = try await apply(engine, "catppuccin")
        _ = await engine.restoreOriginal()
        #expect(services.bbTheme == "nord")
        #expect(!FileManager.default.fileExists(atPath: home.path("data/theme/scene/theme.css").path))
    }

    @Test func aStoppedBbBlocksSetup() async throws {
        let home = try FixtureHome()
        let (services, engine) = try setup(home)
        services.bbDown = true
        let detection = await BbIntegration().detect(engine.env, services)
        guard case .blocked(let reason) = detection.setup else { Issue.record("\(detection.setup)"); return }
        #expect(reason.contains("Open bb"))
        let report = try await apply(engine)
        #expect(services.bbTheme == "nord")
        #expect(report.results.first?.outcome != .applied)
    }

    @Test func theStylesheetHasABlockPerLookAndTheWholeTerminalPalette() throws {
        let theme = try Fixtures.theme("catppuccin")
        let light = try #require(theme.variants[.light]), dark = try #require(theme.variants[.dark])
        let css = BbRenderer.themeFile(light: light, dark: dark)
        let blocks = css.components(separatedBy: "\n.dark {\n")
        #expect(blocks.count == 2 && blocks[0].contains(":root,\n.light {"))
        #expect(blocks[0].contains("--canvas: \(light.interface.background.hex);") && blocks[1].contains("--canvas: \(dark.interface.background.hex);"))
        for index in 0..<16 { #expect(blocks[1].contains("--ansi-\(index): ") && blocks[1].contains("--ansi-bg-fg-\(index): ")) }
        #expect(!css.contains("undefined") && !css.contains("nil"))
    }

    /// Undo goes back to the previous theme, and an app that theme did not change goes back to how it was before Scene.
    @Test func undoPutsBackAnAppThePreviousThemeDidNotChange() async throws {
        let home = try FixtureHome()
        let bb = try home.write("bin/bb", "#!/bin/sh\n"), k9s = try home.write("bin/k9s", "#!/bin/sh\n")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { $0 == "bb" ? bb : $0 == "k9s" ? k9s : nil })
        let services = FakeServices()
        services.bbTheme = "nord"
        services.bbThemeFolder = home.path("data/theme").path
        let engine = Engine(env: env, services: services, integrations: [K9sIntegration(), BbIntegration()], store: EngineStore(root: env.appSupport))
        func apply(_ folder: String, _ apps: Set<String>) async throws {
            let request = ApplyRequest(theme: try Fixtures.theme(folder), mode: .system, systemIsDark: true)
            _ = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: apps)
        }
        try await apply("tokyo-night", ["k9s"])
        try await apply("catppuccin", ["k9s", "bb"])
        #expect(services.bbTheme == "scene")
        let themes = [try Fixtures.theme("tokyo-night"), try Fixtures.theme("catppuccin")]
        _ = await engine.undo(resolveTheme: { id, _ in themes.first { $0.id == id } }, systemIsDark: true)
        #expect(services.bbTheme == "nord")
        #expect(!FileManager.default.fileExists(atPath: home.path("data/theme/scene/theme.css").path))
        let ui = try #require(themes[0].variants[.dark]).interface
        #expect(home.read("Library/Application Support/k9s/skins/scene.yaml")?.contains("focusColor: \"\(ui.accent.hex)\"") == true)
        let remaining = await engine.history().map(\.themeID)
        #expect(remaining == [themes[0].id])
    }
}
