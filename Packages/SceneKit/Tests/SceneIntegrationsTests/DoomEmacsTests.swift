import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// Apply and restore for Doom Emacs, against a fixture home folder.
@Suite("Doom Emacs", .serialized)
struct DoomEmacsTests {
    static let config = "(setq doom-theme 'doom-one)\n(setq display-line-numbers-type 'relative)\n"

    func setup(configFolder: String = ".config/doom") throws -> (home: FixtureHome, services: FakeServices, engine: Engine) {
        let home = try FixtureHome()
        var found: [String: URL] = [:]
        for name in ["emacs", "emacsclient"] { found[name] = try home.write("bin/\(name)", "#!/bin/sh\n") }
        let tools = found
        try home.write("\(configFolder)/init.el", "(doom! :ui doom)\n")
        try home.write("\(configFolder)/config.el", Self.config)
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { tools[$0] })
        let services = FakeServices()
        services.responses["emacs --version"] = CLIResult(status: 0, stdout: "GNU Emacs 30.2\nCopyright\n", stderr: "")
        return (home, services, Engine(env: env, services: services, integrations: [DoomEmacsIntegration()]))
    }

    func apply(_ engine: Engine, mode: AppearanceMode) async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: mode, systemIsDark: false)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        return await engine.apply(request, planned: planned, selected: Set(planned.map(\.id)))
    }

    @Test func applyThenRestoreGivesBackTheConfig() async throws {
        let s = try setup()
        let report = try await apply(s.engine, mode: .system)
        for result in report.results { #expect(result.outcome.isSuccess, "\(result.id): \(result.outcome)") }

        let themes = s.home.path(".config/doom/themes")
        for look in ["dark", "light"] {
            let theme = try #require(s.home.read(".config/doom/themes/scene-\(look)-theme.el"))
            #expect(theme.contains("(deftheme scene-\(look)") && theme.contains("(provide-theme 'scene-\(look)"))
        }
        let variant = try Fixtures.theme("catppuccin").variants[.dark]!
        #expect(s.home.read(".config/doom/themes/scene-dark-theme.el")?.contains("(default ((t (:foreground \"\(variant.interface.foreground.hex)\"") == true)
        let loader = try #require(s.home.read(".config/doom/themes/scene.el"))
        #expect(loader.contains("(defvar scene-theme-forced nil") && loader.contains("(add-to-list 'custom-theme-load-path \"\(themes.path)\")"))

        #expect(loader.contains("(add-hook 'doom-init-ui-hook #'scene-theme-apply 90)"))

        // The user's lines stay, and one marked block at the end loads the loader and names doom-theme.
        let config = try #require(s.home.read(".config/doom/config.el"))
        #expect(config.hasPrefix(Self.config) && config.contains("(load \"\(themes.path)/scene.el\" nil t)"))
        #expect(config.contains("(setq doom-theme (scene-theme-name))"))

        // A running Emacs with a server loads the theme through emacsclient.
        let client = try #require(s.services.calls.first { $0.hasPrefix("run emacsclient --eval") })
        #expect(client.contains("(scene-theme-apply)"))

        let items = await s.engine.restoreOriginal()
        #expect(!items.isEmpty && items.allSatisfy { !$0.keptUserChange })
        #expect(s.home.read(".config/doom/config.el") == Self.config)
        for look in ["dark", "light"] {
            #expect(!FileManager.default.fileExists(atPath: s.home.path(".config/doom/themes/scene-\(look)-theme.el").path))
        }
        #expect(!FileManager.default.fileExists(atPath: s.home.path(".config/doom/themes/scene.el").path))
        // After a restore, the running Emacs gets Doom's own theme back.
        #expect(s.services.calls.last?.contains("(load-theme doom-theme t)") == true)
        #expect(await s.engine.ledgerEntries().isEmpty)
    }

    /// A forced look has one variant. Both files must still declare their own theme name, or Emacs loads neither.
    @Test func forcedLookStillNamesBothThemesRight() async throws {
        let s = try setup()
        _ = try await apply(s.engine, mode: .light)
        for look in ["dark", "light"] {
            let theme = try #require(s.home.read(".config/doom/themes/scene-\(look)-theme.el"))
            #expect(theme.contains("(deftheme scene-\(look) ") && theme.contains("(provide-theme 'scene-\(look))"))
        }
    }

    @Test func forcedAppearancePinsTheLook() async throws {
        let s = try setup()
        _ = try await apply(s.engine, mode: .dark)
        #expect(s.home.read(".config/doom/themes/scene.el")?.contains("(defvar scene-theme-forced 'dark") == true)
    }

    @Test func oldDoomFolderIsFound() async throws {
        let s = try setup(configFolder: ".doom.d")
        let report = try await apply(s.engine, mode: .system)
        #expect(report.results.allSatisfy { $0.outcome.isSuccess })
        #expect(s.home.read(".doom.d/config.el")?.contains("scene.el") == true)
    }

    @Test func doomIsNotInstalledWithoutAConfigFolder() async throws {
        let home = try FixtureHome()
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { _ in nil })
        let detection = await DoomEmacsIntegration().detect(env, FakeServices())
        #expect(!detection.installed)
    }

    @Test func aConfigThatLoadsThemesItselfIsReportedAsAConflict() async throws {
        let s = try setup()
        try s.home.write(".config/doom/config.el", Self.config + "(add-hook 'ns-system-appearance-change-functions #'my/switch)\n")
        let detection = await DoomEmacsIntegration().detect(
            SceneEnvironment(home: s.home.url, locateApp: { _ in nil }, locateExecutable: { _ in nil }), s.services)
        #expect(detection.conflicts.count == 1)
    }

    @Test func themeFilesNeverCarryThemeTextIntoCode() throws {
        var v = try #require(try Fixtures.theme("catppuccin").variants[.dark])
        v.themeName = "x\n(shell-command \"evil\")"
        let text = EmacsRenderer.themeFile(v, slot: .dark)
        #expect(!text.contains("\n(shell-command"))
        #expect(throws: (any Error).self) { try EmacsRenderer.loader(folder: "/a\"b", forced: nil) }
    }
}
