import Foundation
import SceneEngine
import SceneFoundation
import SceneIntegrations
import SceneRenderers
import SceneThemes
import SceneTestSupport
import Testing

@Suite("Herdr app")
struct HerdrAppTests {
    static let folder = ".config/herdr-app"
    static let settings = folder + "/settings.json"

    func setup(_ home: FixtureHome) throws -> (SceneEnvironment, FakeServices) {
        let app = try home.fakeApp("Herdr", version: "0.1.14")
        let env = SceneEnvironment(home: home.url, locateApp: { $0 == HerdrAppIntegration.bundleID ? app : nil }, locateExecutable: { _ in nil })
        return (env, FakeServices())
    }

    @Test func applyRestoreAndUserEdits() async throws {
        let home = try FixtureHome()
        let (env, services) = try setup(home)
        let original = "{\n  \"theme\": \"graphite\",\n  \"font_size\": 14\n}\n"
        try home.write(Self.settings, original)
        try home.write(Self.folder + "/themes/scene.json", "previous theme")
        let engine = Engine(env: env, services: services, integrations: [HerdrAppIntegration()])
        for mode in [AppearanceMode.dark, .light, .system] {
            let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: mode, systemIsDark: false)
            let planned = await engine.plan(request, detections: await engine.detectAll())
            let report = await engine.apply(request, planned: planned, selected: ["herdr-app"])
            #expect(report.results.count == 1)
            #expect(report.results.allSatisfy { $0.outcome.isSuccess })
            let doc = try JSONCDocument(text: #require(home.read(Self.settings)))
            #expect(doc.value(forKey: "font_size") == .number(14))
            let names: [(String, Appearance)]
            if mode == .system {
                #expect(doc.value(forKey: "theme") == .object([JSONMember("light", .string("scene-light")), JSONMember("dark", .string("scene-dark"))]))
                names = [("scene-dark", .dark), ("scene-light", .light)]
            } else {
                #expect(doc.value(forKey: "theme") == .string("scene"))
                names = [("scene", request.effectiveAppearance)]
            }
            for (name, appearance) in names {
                let file = try #require(home.read(Self.folder + "/themes/\(name).json"))
                let json = try #require(JSONSerialization.jsonObject(with: Data(file.utf8)) as? [String: Any])
                let variant = request.variant(appearance)
                #expect(json["background"] as? String == variant.terminal.background.description)
                #expect((json["ansi"] as? [String])?.count == 16)
                #expect((json["colors"] as? [String: String])?["accent"] == variant.interface.accent.description)
            }
            _ = await engine.restoreOriginal()
            #expect(home.read(Self.settings) == original)
            #expect(home.read(Self.folder + "/themes/scene.json") == "previous theme")
            #expect(home.read(Self.folder + "/themes/scene-dark.json") == nil)
        }
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: true)
        _ = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["herdr-app"])
        try home.write(Self.settings, "{\"theme\":\"moss\"}")
        _ = await engine.restoreOriginal()
        #expect(try JSONCDocument(text: #require(home.read(Self.settings))).value(forKey: "theme") == .string("moss"))
        #expect(services.calls.isEmpty) // Herdr was not running
    }

    @Test func runningHerdrPicksSceneThemesOnTheShownLayout() async throws {
        let home = try FixtureHome()
        let (env, services) = try setup(home)
        services.running = [HerdrAppIntegration.bundleID: [4242]]
        let engine = Engine(env: env, services: services, integrations: [HerdrAppIntegration()])
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .system, systemIsDark: true)
        _ = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["herdr-app"])
        #expect(services.calls == ["run Herdr do app.theme {\"name\":\"scene-light\"}", "run Herdr do app.theme {\"name\":\"scene-dark\"}"])
    }

    @Test func malformedSettingsAreBlockedAndMissingAppIsNotInstalled() async throws {
        let home = try FixtureHome()
        let (env, services) = try setup(home)
        try home.write(Self.settings, "{broken")
        guard case .blocked = await HerdrAppIntegration().detect(env, services).setup else {
            Issue.record("Malformed settings should be blocked before planning")
            return
        }
        #expect(home.read(Self.settings) == "{broken")
        let absent = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { _ in nil })
        #expect(await HerdrAppIntegration().detect(absent, services).installed == false)
    }
}
