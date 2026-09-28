import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// End-to-end apply, undo, and restore against a fixture home folder.
@Suite("Engine", .serialized)
struct EngineTests {
    static let ghosttyConfig = """
    # My Ghostty config
    font-family = JetBrains Mono
    theme = light:Catppuccin Latte,dark:Cobalt2
    palette = 4=#3D52E2

    """
    static let vscodeSettings = """
    {
      // Editor
      "editor.fontSize": 14, /* keep */
      "workbench.colorTheme": "Default Dark Modern",
      "files.trimTrailingWhitespace": true,
    }

    """

    struct Setup {
        let home: FixtureHome
        let services: FakeServices
        let engine: Engine
        let store: EngineStore
    }

    func setup(ghosttySymlink: Bool = false) throws -> Setup {
        let home = try FixtureHome()
        let ghostty = try home.fakeApp("Ghostty", version: "1.3.1")
        let iterm = try home.fakeApp("iTerm", version: "3.7.3")
        let vscode = try home.fakeApp("Visual Studio Code", version: "1.136.2", executables: ["Contents/Resources/app/bin/code"])
        let nvim = home.path("bin/nvim")
        try home.write("bin/nvim", "#!/bin/sh\n")
        if ghosttySymlink {
            try home.write("dotfiles/ghostty/config", Self.ghosttyConfig)
            try FileManager.default.createDirectory(at: home.path(".config/ghostty"), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: home.path(".config/ghostty/config"), withDestinationURL: home.path("dotfiles/ghostty/config"))
        } else {
            try home.write(".config/ghostty/config", Self.ghosttyConfig)
        }
        try home.write("Library/Application Support/Code/User/settings.json", Self.vscodeSettings)
        try home.write(".config/nvim/init.lua", "vim.cmd.colorscheme('habamax')\n")
        let env = Fixtures.environment(home, apps: [GhosttyIntegration.bundleID: ghostty, ITermIntegration.bundleID: iterm, "com.microsoft.VSCode": vscode], nvim: nvim)
        let services = FakeServices()
        services.prefs["com.googlecode.iterm2#Default Bookmark Guid"] = .string("USER-DEFAULT-GUID")
        services.wallpapers = [1: try home.write("Pictures/original-1.heic", "x").path, 2: try home.write("Pictures/original-2.jpg", "y").path]
        let integrations: [Integration] = [WallpaperIntegration(), AppearanceIntegration(), AccentColorIntegration(), IconStyleIntegration(),
                                           GhosttyIntegration(), ITermIntegration(), NeovimIntegration()] + VSCodeFamilyIntegration.all
        let store = EngineStore(root: env.appSupport)
        return Setup(home: home, services: services, engine: Engine(env: env, services: services, integrations: integrations, store: store), store: store)
    }

    func apply(_ s: Setup, _ folder: String, mode: AppearanceMode = .system, wallpaper: Bool = false) async throws -> ApplyReport {
        let theme = wallpaper ? try Fixtures.themeWithWallpaper(folder, in: s.home) : try Fixtures.theme(folder)
        let request = ApplyRequest(theme: theme, mode: mode, systemIsDark: false)
        let detections = await s.engine.detectAll()
        let planned = await s.engine.plan(request, detections: detections)
        return await s.engine.apply(request, planned: planned, selected: Set(planned.map(\.id)))
    }

    func outcome(_ report: ApplyReport, _ id: String) -> Outcome? { report.results.first { $0.id == id }?.outcome }

    @Test func applyWritesOnlyOwnedResourcesAndReportsPerApp() async throws {
        let s = try setup()
        let report = try await apply(s, "tokyo-night")
        // Tokyo Night is dark-only, so Scene switches macOS to Dark.
        #expect(s.services.appearanceState.dark)
        #expect(outcome(report, "appearance") == .applied)
        #expect(outcome(report, "wallpaper") == .applied || outcome(report, "wallpaper") == .skipped("This theme has no wallpaper for dark mode"))
        // Ghostty: user lines untouched, one block appended, overrides reported.
        let ghostty = try #require(s.home.read(".config/ghostty/config"))
        #expect(ghostty.hasPrefix(Self.ghosttyConfig))
        #expect(ghostty.contains("config-file = ?\""))
        if case .appliedPartlyOverridden? = outcome(report, "ghostty") {} else { Issue.record("expected Ghostty partly overridden, got \(String(describing: outcome(report, "ghostty")))") }
        #expect(s.home.read(".config/ghostty/themes/scene-dark")?.contains("background = #1a1b26") == true)
        // VS Code: only the theme key changed; comments and other keys stay.
        let settings = try #require(s.home.read("Library/Application Support/Code/User/settings.json"))
        #expect(settings.contains("\"workbench.colorTheme\": \"Scene Dark\""))
        #expect(settings.contains("// Editor") && settings.contains("/* keep */") && settings.contains("\"files.trimTrailingWhitespace\": true,"))
        #expect(s.services.extensions[VSCodeRenderer.extensionID] != nil)
        // iTerm2 needs the one-time default-profile step.
        if case .needsAction? = outcome(report, "iterm2") {} else { Issue.record("expected iTerm2 needs action") }
        // Neovim: plugin files added, init.lua untouched.
        #expect(s.home.read(".config/nvim/init.lua") == "vim.cmd.colorscheme('habamax')\n")
        #expect(FileManager.default.fileExists(atPath: s.home.path(".config/nvim/plugin/scene.lua").path))
        // Experimental tweaks ran.
        #expect(s.services.tweaks["accent"] == .number(Double(AccentPreset.blue.rawValue)))
        #expect(await s.engine.unfinishedRuns().isEmpty)
    }

    @Test func restoreReturnsFilesToTheirOriginalBytes() async throws {
        let s = try setup()
        _ = try await apply(s, "catppuccin", mode: .dark, wallpaper: true)
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-catppuccin-dark-1.png") == true)
        _ = try await apply(s, "gruvbox", mode: .light, wallpaper: true)
        let items = await s.engine.restoreOriginal()
        #expect(!items.isEmpty)
        #expect(s.home.read(".config/ghostty/config") == Self.ghosttyConfig)
        #expect(s.home.read("Library/Application Support/Code/User/settings.json") == Self.vscodeSettings)
        #expect(!FileManager.default.fileExists(atPath: s.home.path(".config/ghostty/scene.conf").path))
        #expect(!FileManager.default.fileExists(atPath: s.home.path(".config/ghostty/themes/scene-dark").path))
        #expect(!FileManager.default.fileExists(atPath: s.home.path(".config/nvim/plugin/scene.lua").path))
        #expect(!FileManager.default.fileExists(atPath: s.home.path("Library/Application Support/iTerm2/DynamicProfiles/scene.json").path))
        #expect(s.services.extensions[VSCodeRenderer.extensionID] == nil)
        #expect(s.services.appearanceState == AppearanceState(dark: false, auto: false))
        #expect(s.services.wallpapers[1] == s.home.path("Pictures/original-1.heic").path)
        #expect(s.services.wallpapers[2] == s.home.path("Pictures/original-2.jpg").path)
        #expect(s.services.tweaks["accent"] == .number(4))
        #expect(await s.engine.ledgerEntries().isEmpty)
    }

    @Test func restoreKeepsChangesMadeAfterScene() async throws {
        let s = try setup()
        _ = try await apply(s, "rose-pine", mode: .dark)
        // The user edits VS Code's theme and adds a line to Ghostty's config after Scene applied.
        var doc = try JSONCDocument(text: s.home.read("Library/Application Support/Code/User/settings.json")!)
        try doc.set(.string("Solarized Light"), forKey: "workbench.colorTheme")
        try doc.text.write(to: s.home.path("Library/Application Support/Code/User/settings.json"), atomically: true, encoding: .utf8)
        let ghostty = s.home.read(".config/ghostty/config")! + "window-padding-x = 8\n"
        try ghostty.write(to: s.home.path(".config/ghostty/config"), atomically: true, encoding: .utf8)
        s.services.appearanceState = AppearanceState(dark: false, auto: false)   // user switched back to Light

        let items = await s.engine.restoreOriginal()
        #expect(items.contains { $0.resource.hasPrefix("json:") && $0.keptUserChange })
        #expect(items.contains { $0.resource == "appearance" && !$0.keptUserChange })
        #expect(s.home.read("Library/Application Support/Code/User/settings.json")!.contains("Solarized Light"))
        // The Scene block is gone, the user's new line stays.
        #expect(s.home.read(".config/ghostty/config") == Self.ghosttyConfig + "window-padding-x = 8\n")
    }

    @Test func failedAppIsRolledBackAndOthersSucceed() async throws {
        let s = try setup()
        s.services.failWallpaper = true
        let report = try await apply(s, "catppuccin", mode: .dark, wallpaper: true)
        if case .failed? = outcome(report, "wallpaper") {} else { Issue.record("expected wallpaper failure, got \(String(describing: outcome(report, "wallpaper")))") }
        #expect(outcome(report, "ghostty")?.isSuccess == true)
        // The wallpaper copy written before the failure was removed again.
        let copies = (try? FileManager.default.contentsOfDirectory(atPath: s.home.path("Library/Application Support/Scene/Wallpapers").path)) ?? []
        #expect(copies.isEmpty)
        #expect(await s.engine.ledgerEntries().allSatisfy { $0.integration != "wallpaper" })
    }

    @Test func chosenWallpaperIsShownAndUndoShowsThePreviousOne() async throws {
        let s = try setup()
        let theme = try Fixtures.themeWithWallpaper("catppuccin", in: s.home)
        func show(_ name: String?, only: Set<String>? = nil) async {
            var request = ApplyRequest(theme: theme, mode: .dark, systemIsDark: false)
            request.wallpaperName = name
            let planned = await s.engine.plan(request, detections: await s.engine.detectAll())
            _ = await s.engine.apply(request, planned: planned, selected: only ?? Set(planned.map(\.id)))
        }
        await show(nil)
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-catppuccin-dark-1.png") == true)
        await show("dark-2.png", only: ["wallpaper"])   // what Next Background does
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-catppuccin-dark-2.png") == true)
        #expect(await s.engine.history().last?.wallpaper == "dark-2.png")
        _ = await s.engine.undo(resolveTheme: { _, _ in theme }, systemIsDark: false)
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-catppuccin-dark-1.png") == true)
        _ = await s.engine.restoreOriginal()
        #expect(s.services.wallpapers[1] == s.home.path("Pictures/original-1.heic").path)
        let copies = (try? FileManager.default.contentsOfDirectory(atPath: s.home.path("Library/Application Support/Scene/Wallpapers").path)) ?? []
        #expect(copies.isEmpty, "\(copies)")
    }

    @Test func undoReturnsToThePreviousTheme() async throws {
        let s = try setup()
        _ = try await apply(s, "gruvbox", mode: .dark)
        let gruvboxGhostty = s.home.read(".config/ghostty/themes/scene-dark")
        _ = try await apply(s, "tokyo-night")
        #expect(s.home.read(".config/ghostty/themes/scene-dark") != gruvboxGhostty)
        let report = await s.engine.undo(resolveTheme: { id, _ in try? Fixtures.theme(String(id.split(separator: "/").last!)) }, systemIsDark: false)
        #expect(report?.themeName == "Gruvbox")
        #expect(s.home.read(".config/ghostty/themes/scene-dark") == gruvboxGhostty)
        _ = await s.engine.undo(resolveTheme: { _, _ in nil }, systemIsDark: false)   // nothing before Gruvbox: restores original
        #expect(s.home.read(".config/ghostty/config") == Self.ghosttyConfig)
    }

    @Test func symlinkedConfigIsEditedInPlace() async throws {
        let s = try setup(ghosttySymlink: true)
        _ = try await apply(s, "catppuccin", mode: .dark)
        let link = s.home.path(".config/ghostty/config").path
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil)
        #expect(s.home.read("dotfiles/ghostty/config")?.contains(">>> Scene") == true)
        _ = await s.engine.restoreOriginal()
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil)
        #expect(s.home.read("dotfiles/ghostty/config") == Self.ghosttyConfig)
    }

    @Test func interruptedRunIsDetected() async throws {
        let s = try setup()
        let run = JournalRun(id: "crashed", themeID: "scene/catppuccin", themeName: "Catppuccin", started: Date(), completed: false,
                             steps: [JournalStep(integration: "ghostty", resource: "file:/x", summary: "Write /x", state: "pending")])
        try s.store.save(run)
        let engine = Engine(env: s.engine.env, services: s.services, integrations: s.engine.integrations, store: s.store)
        #expect(await engine.unfinishedRuns().map(\.id) == ["crashed"])
    }

    @Test func settingsFileCreatedBySceneIsRemovedOnRestore() async throws {
        let s = try setup()
        try FileManager.default.removeItem(at: s.home.path("Library/Application Support/Code/User/settings.json"))
        _ = try await apply(s, "catppuccin", mode: .dark)
        #expect(s.home.read("Library/Application Support/Code/User/settings.json")?.contains("Scene Dark") == true)
        _ = await s.engine.restoreOriginal()
        #expect(!FileManager.default.fileExists(atPath: s.home.path("Library/Application Support/Code/User/settings.json").path))
    }

    @Test func autoAppearanceIsRestored() async throws {
        let s = try setup()
        s.services.appearanceState = AppearanceState(dark: false, auto: true)
        _ = try await apply(s, "tokyo-night")   // dark-only theme forces Dark
        #expect(s.services.appearanceState == AppearanceState(dark: true, auto: false))
        _ = await s.engine.restoreOriginal()
        #expect(s.services.appearanceState.auto)
    }
}
