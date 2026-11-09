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
}
