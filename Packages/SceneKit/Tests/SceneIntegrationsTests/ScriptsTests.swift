import Foundation
@testable import SceneIntegrations
@testable import SceneRenderers
import SceneEngine
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// The user's own scripts: the theme file, the variables, which files Scene runs, and apply and restore.
@Suite("Your scripts")
struct ScriptsTests {
    static func isHex(_ value: Any?) -> Bool { (value as? String).map(ThemeFileRenderer.isHex) ?? false }

    @Test func themeFileHasBothLooksAsTypedColors() throws {
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .system, systemIsDark: false)
        let data = try ThemeFileRenderer.file(variants: request.nativeVariants, appearance: request.effectiveAppearance, mode: request.mode.rawValue)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["format"] as? Int == 1)
        #expect(root["mode"] as? String == "system")
        #expect(root["appearance"] as? String == "light")
        #expect((root["theme"] as? [String: Any])?["id"] as? String == request.theme.id)
        #expect(!String(decoding: data, as: UTF8.self).contains("\\/"))
        let variants = try #require(root["variants"] as? [String: [String: Any]])
        #expect(Set(variants.keys) == ["dark", "light"])
        for variant in variants.values {
            let interface = try #require(variant["interface"] as? [String: String])
            #expect(interface.count == 15 && interface.values.allSatisfy(Self.isHex))
            let terminal = try #require(variant["terminal"] as? [String: Any])
            let ansi = try #require(terminal["ansi"] as? [String])
            #expect(ansi.count == 16 && ansi.allSatisfy(Self.isHex))
            #expect(Self.isHex(terminal["background"]) && Self.isHex(terminal["selectionForeground"]))
        }
    }

    @Test func forcedLookWritesOneVariantAndItsVariables() throws {
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: false)
        let data = try ThemeFileRenderer.file(variants: request.nativeVariants, appearance: request.effectiveAppearance, mode: request.mode.rawValue)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((root["variants"] as? [String: Any])?.keys.sorted() == ["dark"])

        let environment = try #require(ThemeFileRenderer.environment(file: data))
        let dark = request.variant(.dark)
        #expect(environment["SCENE_APPEARANCE"] == "dark")
        #expect(environment["SCENE_THEME_ID"] == request.theme.id)
        #expect(environment["SCENE_BACKGROUND"] == dark.interface.background.hex)
        #expect(environment["SCENE_ACCENT"] == ThemeFileRenderer.hex(dark.interface.accent))
        #expect(environment["SCENE_CURRENT_LINE"] != nil)
        #expect(environment["SCENE_ANSI_1"] == dark.terminal.ansi[1].hex)
        #expect(environment["SCENE_ANSI_15"] != nil)
        #expect(environment.count == 2 + 15 + 16)
    }

    /// Every value is checked again before it reaches a script, so an edited file cannot pass text through.
    @Test func variablesComeOnlyFromAFileSceneWrote() throws {
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: false)
        let data = try ThemeFileRenderer.file(variants: request.nativeVariants, appearance: request.effectiveAppearance, mode: "dark")
        let text = String(decoding: data, as: UTF8.self)
        let accent = ThemeFileRenderer.hex(request.variant(.dark).interface.accent)
        #expect(ThemeFileRenderer.environment(file: Data(text.replacingOccurrences(of: "\"\(accent)\"", with: "\"$(touch x)\"").utf8)) == nil)
        var root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        root["theme"] = ["id": "x; touch y"]
        #expect(ThemeFileRenderer.environment(file: try JSONSerialization.data(withJSONObject: root)) == nil)
        #expect(ThemeFileRenderer.environment(file: Data("{}".utf8)) == nil)
    }

    // MARK: Which files run

    func script(_ home: FixtureHome, _ name: String, mode: Int = 0o755) throws -> String {
        let url = try home.write("bin/\(name)", "#!/bin/sh\nexit 0\n")
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
        return url.path
    }

    @Test func runsOnlyExecutableFilesThatOnlyTheUserCanChange() throws {
        let home = try FixtureHome()
        #expect(ScriptsIntegration.problem(try script(home, "ok.sh")) == nil)
        #expect(ScriptsIntegration.problem(try script(home, "plain.sh", mode: 0o644))?.contains("not executable") == true)
        #expect(ScriptsIntegration.problem(try script(home, "shared.sh", mode: 0o775))?.contains("writable by other users") == true)
        #expect(ScriptsIntegration.problem(home.path("bin/missing.sh").path)?.contains("does not exist") == true)
        #expect(ScriptsIntegration.problem("bin/ok.sh")?.contains("full path") == true)
        #expect(ScriptsIntegration.problem(home.path("bin").path)?.contains("not a file") == true)

        // A link is judged by its target.
        let link = home.path("link.sh")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: home.path("bin/shared.sh").path)
        #expect(ScriptsIntegration.problem(link.path)?.contains("writable by other users") == true)

        // So is a folder others can write to.
        let open = try home.write("open/hook.sh", "#!/bin/sh\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: open.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: open.deletingLastPathComponent().path)
        #expect(ScriptsIntegration.problem(open.path)?.contains("writable by other users") == true)
    }

    // MARK: Apply and restore

    struct Setup {
        let home: FixtureHome
        let services: FakeServices
        let engine: Engine
        let env: SceneEnvironment
    }

    func setup(_ scripts: @escaping @Sendable (FixtureHome) throws -> [String]) throws -> Setup {
        let home = try FixtureHome()
        let paths = try scripts(home)
        let env = Fixtures.environment(home, apps: [:])
        let services = FakeServices()
        return Setup(home: home, services: services,
                     engine: Engine(env: env, services: services, integrations: [ScriptsIntegration(scripts: { paths })]), env: env)
    }

    func apply(_ s: Setup, mode: AppearanceMode = .dark) async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: mode, systemIsDark: false)
        let planned = await s.engine.plan(request, detections: await s.engine.detectAll())
        return await s.engine.apply(request, planned: planned, selected: Set(planned.map(\.id)))
    }

    @Test func notListedWithoutScripts() async throws {
        let s = try setup { _ in [] }
        #expect(await s.engine.detectAll()["scripts"]?.installed == false)
    }

    @Test func applyWritesTheFileAndRunsTheScriptsRestoreRunsThemAgain() async throws {
        let s = try setup { [try self.script($0, "bar.sh"), try self.script($0, "browser.sh"), try self.script($0, "loose.sh", mode: 0o666)] }
        let planned = await s.engine.plan(ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: false),
                                          detections: await s.engine.detectAll())
        let plan = try #require(planned.first?.plan)
        #expect(plan.operations.map(\.summary) == ["Write \(Operation.tilde(ScriptsIntegration.file(s.env).path))"])
        #expect(plan.notes == ["Runs bar.sh, browser.sh with the theme's colors in SCENE_ variables."])
        #expect(plan.conflicts.count == 1 && plan.conflicts[0].contains("loose.sh"))

        let report = try await apply(s)
        #expect(report.results.first?.outcome == .applied)
        #expect(FileManager.default.fileExists(atPath: ScriptsIntegration.file(s.env).path))
        #expect(s.services.calls == ["run bar.sh ", "run browser.sh "])
        let environment = try #require(s.services.environments["bar.sh"] ?? nil)
        #expect(environment["SCENE_EVENT"] == "apply")
        #expect(environment["SCENE_APPEARANCE"] == "dark")
        #expect(environment["SCENE_THEME_FILE"] == ScriptsIntegration.file(s.env).path)
        #expect(environment["SCENE_ACCENT"].map(ThemeFileRenderer.isHex) == true)

        _ = await s.engine.restoreOriginal()
        #expect(!FileManager.default.fileExists(atPath: ScriptsIntegration.file(s.env).path))
        let restored = try #require(s.services.environments["browser.sh"] ?? nil)
        #expect(restored["SCENE_EVENT"] == "restore")
        #expect(restored["SCENE_ACCENT"] == nil)
        #expect(s.services.calls.count == 4)
    }

    @Test func restoreGivesBackAThemeFileTheUserHad() async throws {
        let s = try setup { [try self.script($0, "bar.sh")] }
        try s.home.write(".config/scene/theme.json", "{\"mine\": true}\n")
        _ = try await apply(s)
        _ = await s.engine.restoreOriginal()
        #expect(s.home.read(".config/scene/theme.json") == "{\"mine\": true}\n")
    }

    @Test func aFailingScriptAsksForAction() async throws {
        let s = try setup { [try self.script($0, "fail.sh"), try self.script($0, "ok.sh")] }
        s.services.responses["fail.sh "] = CLIResult(status: 2, stdout: "", stderr: "Helium is not running\n")
        let report = try await apply(s)
        #expect(report.results.first?.outcome == .needsAction("fail.sh exited with 2: Helium is not running"))
        #expect(s.services.calls.contains("run ok.sh "))
    }

    @Test func noScriptRunsWhenAllAreRefused() async throws {
        let s = try setup { [try self.script($0, "loose.sh", mode: 0o666)] }
        let report = try await apply(s)
        guard case .skipped(let reason)? = report.results.first?.outcome else { Issue.record("\(report.results)"); return }
        #expect(reason.contains("loose.sh"))
        #expect(s.services.calls.isEmpty)
    }
}
