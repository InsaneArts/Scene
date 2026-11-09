import Foundation
import SceneEngine
import SceneFoundation
import SceneIntegrations
import SceneRenderers
import SceneThemes
import SceneTestSupport
import Testing

@Suite("ZapFast")
struct ZapFastTests {
    static let folder = "Library/Application Support/me.paolino.zapfast"

    @Test func applyRestoreAndUserEdits() async throws {
        let home = try FixtureHome()
        let app = try home.fakeApp("ZapFast", version: "0.21.1")
        let env = SceneEnvironment(home: home.url, locateApp: { $0 == ZapFastIntegration.bundleID ? app : nil }, locateExecutable: { _ in nil })
        let settings = Self.folder + "/settings.json"
        let original = "{\n  \"custom_theme\": \"mine.json\",\n  \"enter_sends\": false\n}\n"
        try home.write(settings, original)
        try home.write(Self.folder + "/themes/scene.json", "previous palette")
        let services = FakeServices()
        services.running = [ZapFastIntegration.bundleID: [1234]]
        let engine = Engine(env: env, services: services, integrations: [ZapFastIntegration()])
        for mode in [AppearanceMode.dark, .light, .system] {
            let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: mode, systemIsDark: false)
            let planned = await engine.plan(request, detections: await engine.detectAll())
            let report = await engine.apply(request, planned: planned, selected: ["zapfast"])
            #expect(report.results.count == 1)
            #expect(report.results.allSatisfy { $0.outcome.isSuccess })
            let doc = try JSONCDocument(text: #require(home.read(settings)))
            #expect(doc.value(forKey: "custom_theme") == .string("scene.json"))
            #expect(doc.value(forKey: "enter_sends") == .bool(false))
            let palette = try #require(home.read(Self.folder + "/themes/scene.json"))
            let json = try #require(JSONSerialization.jsonObject(with: Data(palette.utf8)) as? [String: Any])
            #expect(json["base"] as? String == request.current.appearance.rawValue)
            let colors = try #require(json["colors"] as? [String: String])
            #expect(colors.count == 21)
            #expect(colors["window"] == request.current.interface.background.description)
            #expect(colors["bubble_in"] == request.current.interface.surface.description)
            #expect(colors.values.allSatisfy { RGBA(hex: $0) != nil })
            _ = await engine.restoreOriginal()
            #expect(home.read(settings) == original)
            #expect(home.read(Self.folder + "/themes/scene.json") == "previous palette")
        }
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: true)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        _ = await engine.apply(request, planned: planned, selected: ["zapfast"])
        try home.write(settings, "{\"custom_theme\":\"user-choice.json\",\"enter_sends\":true}")
        _ = await engine.restoreOriginal()
        let edited = try JSONCDocument(text: #require(home.read(settings)))
        #expect(edited.value(forKey: "custom_theme") == .string("user-choice.json"))
        #expect(edited.value(forKey: "enter_sends") == .bool(true))
        #expect(services.calls.isEmpty) // no control commands or launches
    }

    @Test func reloadsLiveWhenScenesPaletteIsAlreadySelected() async throws {
        let home = try FixtureHome()
        let app = try home.fakeApp("ZapFast", version: "0.21.1")
        let env = SceneEnvironment(home: home.url, locateApp: { $0 == ZapFastIntegration.bundleID ? app : nil }, locateExecutable: { _ in nil })
        try home.write(Self.folder + "/settings.json", "{\"custom_theme\":\"scene.json\"}")
        let services = FakeServices()
        let engine = Engine(env: env, services: services, integrations: [ZapFastIntegration()])
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: true)
        // Closed: nothing to reload, and nothing is started.
        var report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["zapfast"])
        #expect(report.results.first?.outcome == .applied)
        #expect(services.calls.isEmpty)
        // Running with scene.json selected: reload-themes, no restart.
        services.running = [ZapFastIntegration.bundleID: [1234]]
        report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["zapfast"])
        #expect(report.results.first?.outcome == .applied)
        #expect(services.calls == ["run zapfast reload-themes"])
        // Running with another palette selected: reload-themes would keep it, so ZapFast needs a restart.
        try home.write(Self.folder + "/settings.json", "{\"custom_theme\":\"Nord.json\"}")
        report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["zapfast"])
        guard case .appliedRestartNeeded? = report.results.first?.outcome else { Issue.record("expected a restart"); return }
        #expect(services.calls == ["run zapfast reload-themes"])
    }

    @Test func malformedSettingsAreBlocked() async throws {
        let home = try FixtureHome()
        let app = try home.fakeApp("ZapFast", version: "0.21.1")
        try home.write(Self.folder + "/settings.json", "{broken")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in app }, locateExecutable: { _ in nil })
        let detection = await ZapFastIntegration().detect(env, FakeServices())
        guard case .blocked = detection.setup else {
            Issue.record("Malformed settings should be blocked before planning")
            return
        }
        #expect(home.read(Self.folder + "/settings.json") == "{broken")
    }

    @Test func missingSettingsAndDetection() async throws {
        let home = try FixtureHome()
        let app = try home.fakeApp("ZapFast", version: "0.21.1")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in app }, locateExecutable: { _ in nil })
        let services = FakeServices()
        let integration = ZapFastIntegration()
        let detection = await integration.detect(env, services)
        #expect(detection.installed)
        #expect(detection.version == "0.21.1")
        #expect(await integration.reload(detection, env, services) == .notRunning)
        services.running = ["zapfast": [1234]]
        #expect(await integration.reload(detection, env, services) == .needsRestart("Quit and reopen ZapFast to load the selected theme."))
        let engine = Engine(env: env, services: services, integrations: [integration])
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: true)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        _ = await engine.apply(request, planned: planned, selected: ["zapfast"])
        _ = await engine.restoreOriginal()
        #expect(home.read(Self.folder + "/settings.json") == nil)
        #expect(home.read(Self.folder + "/themes/scene.json") == nil)
        let absent = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { _ in nil })
        #expect(await integration.detect(absent, services).installed == false)
    }
}
