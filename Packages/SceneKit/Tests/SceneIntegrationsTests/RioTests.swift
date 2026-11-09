import Foundation
import SceneEngine
import SceneFoundation
import SceneIntegrations
import SceneRenderers
import SceneThemes
import SceneTestSupport
import Testing

@Suite("Rio")
struct RioTests {
    static let original = "# Mine\ntheme = \"nord\" # keep comment\nforce-theme = \"dark\"\n\n[fonts]\nsize = 15\n\n[adaptive-theme]\ndark = \"nord\"\nlight = \"paper\"\n"

    @Test func applyRestoreAndUserEdits() async throws {
        let home = try FixtureHome()
        let app = try home.fakeApp("Rio", version: "0.5.29")
        let env = SceneEnvironment(home: home.url, locateApp: { $0 == RioIntegration.bundleID ? app : nil }, locateExecutable: { _ in nil })
        try home.write(".config/rio/config.toml", Self.original)
        try home.write(".config/rio/themes/scene-dark.toml", "previous palette")
        let services = FakeServices()
        let engine = Engine(env: env, services: services, integrations: [RioIntegration(configHome: nil)])
        for (folder, mode) in [("catppuccin", AppearanceMode.system), ("catppuccin", .dark), ("catppuccin", .light), ("tokyo-night", .system)] {
            let request = ApplyRequest(theme: try Fixtures.theme(folder), mode: mode, systemIsDark: false)
            let planned = await engine.plan(request, detections: await engine.detectAll())
            let report = await engine.apply(request, planned: planned, selected: ["rio"])
            #expect(report.results.count == 1)
            #expect(report.results.allSatisfy { $0.outcome.isSuccess })
            let text = try #require(home.read(".config/rio/config.toml"))
            let doc = KeyValueDocument(text: text)
            #expect(text.contains("# keep comment") && text.contains("size = 15"))
            #expect(doc.value(forKey: "theme") == KeyValueDocument.quoted("scene-" + request.current.appearance.rawValue))
            #expect(doc.value(forKey: "adaptive-theme.dark") == "\"scene-dark\"")
            #expect(doc.value(forKey: "adaptive-theme.light") == "\"scene-light\"")
            #expect(doc.value(forKey: "force-theme") == "\"dark\"")
            #expect(planned.first?.plan?.conflicts.isEmpty == (request.nativeVariants.count != 2))
            for appearance in [Appearance.dark, .light] {
                let palette = try #require(home.read(".config/rio/themes/scene-\(appearance.rawValue).toml"))
                let colors = KeyValueDocument(text: palette)
                let v = request.nativeVariants[appearance] ?? request.current
                #expect(colors.value(forKey: "colors.background") == KeyValueDocument.quoted(v.terminal.background.description))
                #expect(colors.value(forKey: "colors.light-red") == KeyValueDocument.quoted(v.terminal.ansi[9].description))
                #expect(colors.keys.count == 42)
                // Check the generated config and themes with an independent TOML parser.
                let python = Processes.findExecutable("python3", extraPaths: ["/opt/homebrew/bin"])
                if let python {
                    let script = "import sys,tomllib; [tomllib.load(open(p,'rb')) for p in sys.argv[1:]]"
                    let result = try Processes.run(python.path, ["-c", script, home.path(".config/rio/config.toml").path,
                        home.path(".config/rio/themes/scene-\(appearance.rawValue).toml").path])
                    #expect(result.status == 0, "\(result.stderr)")
                }
            }
            _ = await engine.restoreOriginal()
            #expect(home.read(".config/rio/config.toml") == Self.original)
            #expect(home.read(".config/rio/themes/scene-dark.toml") == "previous palette")
            #expect(home.read(".config/rio/themes/scene-light.toml") == nil)
        }
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: true)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        _ = await engine.apply(request, planned: planned, selected: ["rio"])
        var edited = KeyValueDocument(text: try #require(home.read(".config/rio/config.toml")))
        edited.set("\"my-new-theme\"", forKey: "theme")
        edited.set("20", forKey: "size", inTable: "fonts")
        try home.write(".config/rio/config.toml", edited.text)
        _ = await engine.restoreOriginal()
        let restored = KeyValueDocument(text: try #require(home.read(".config/rio/config.toml")))
        #expect(restored.value(forKey: "theme") == "\"my-new-theme\"")
        #expect(restored.value(forKey: "fonts.size") == "20")
        #expect(services.calls.isEmpty)
    }

    @Test func customDirectoryMissingFilesAndDetection() async throws {
        let home = try FixtureHome()
        let app = try home.fakeApp("Rio", version: "0.5.29")
        let env = SceneEnvironment(home: home.url, xdgConfigHome: home.path("unused-xdg"), locateApp: { _ in app }, locateExecutable: { _ in nil })
        let services = FakeServices()
        let standard = await RioIntegration(configHome: nil).detect(env, services)
        #expect(standard.context["config"] == home.path(".config/rio/config.toml").path)
        #expect(standard.version == "0.5.29")
        let integration = RioIntegration(configHome: home.path("custom-rio"))
        let engine = Engine(env: env, services: services, integrations: [integration])
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .system, systemIsDark: true)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        let report = await engine.apply(request, planned: planned, selected: ["rio"])
        #expect(report.results.allSatisfy { $0.outcome.isSuccess })
        #expect(home.read("custom-rio/config.toml") != nil)
        #expect(home.read(".config/rio/config.toml") == nil)
        _ = await engine.restoreOriginal()
        for file in ["config.toml", "themes/scene-dark.toml", "themes/scene-light.toml"] {
            #expect(home.read("custom-rio/" + file) == nil)
        }
        let absent = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { _ in nil })
        #expect(await integration.detect(absent, services).installed == false)
    }
}
