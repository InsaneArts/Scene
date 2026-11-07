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

    /// Display 1 and 2 have their own entries in Space S1, the one on screen. S2 has none, so both show its Default.
    func addWallpaperStore(_ s: Setup) throws {
        let one = s.services.wallpapers[1]!, two = s.services.wallpapers[2]!
        func entry(_ path: String) -> [String: Any] { ["Desktop": ["Content": FakeServices.wallpaperContent(path)]] }
        let store: [String: Any] = [
            "SystemDefault": entry(one),
            "Displays": ["UUID-1": entry(one), "UUID-2": entry(two)],
            "Spaces": [
                "S1": ["Default": entry(one), "Displays": ["UUID-1": entry(one), "UUID-2": entry(two)]],
                "S2": ["Default": entry("/Users/me/Pictures/s2.jpg")],
            ],
        ]
        s.services.wallpaperStoreData = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
    }

    func spaceImages(_ s: Setup) throws -> [String: String] {
        let data = try #require(s.services.wallpaperStoreData)
        return try #require(WallpaperStore.images(data, displays: ["UUID-1", "UUID-2"]))
    }

    @Test func everySpaceGetsTheWallpaperAndRestoreBringsEachOneBack() async throws {
        let s = try setup()
        try addWallpaperStore(s)
        let before = try spaceImages(s)
        let report = try await apply(s, "catppuccin", mode: .dark, wallpaper: true)
        #expect(outcome(report, "wallpaper") == .applied)
        #expect(report.results.first { $0.id == "wallpaper" }?.operations.last?.contains("every Space") == true)
        let applied = try spaceImages(s)
        #expect(applied.count == 6 && applied.values.allSatisfy { $0.hasSuffix("scene-catppuccin-dark-1.png") }, "\(applied)")
        #expect(s.services.wallpaperAgentRestarts == 1)

        _ = try await apply(s, "gruvbox", mode: .light, wallpaper: true)
        #expect(try spaceImages(s).values.allSatisfy { $0.hasSuffix("scene-gruvbox-light-1.png") })
        _ = await s.engine.restoreOriginal()
        #expect(try spaceImages(s) == before)
        #expect(s.services.wallpapers[1] == s.home.path("Pictures/original-1.heic").path)
        #expect(await s.engine.ledgerEntries().isEmpty)
    }

    @Test func restoreKeepsASpaceChangedAfterScene() async throws {
        let s = try setup()
        try addWallpaperStore(s)
        _ = try await apply(s, "catppuccin", mode: .dark, wallpaper: true)
        let data = try #require(s.services.wallpaperStoreData)
        var root = try #require(try WallpaperStore.read(data))
        root = WallpaperStore.setting(root, "Spaces/S2/Default", ["Desktop": ["Content": FakeServices.wallpaperContent("/Users/me/Pictures/mine.jpg")]])
        s.services.wallpaperStoreData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)

        let items = await s.engine.restoreOriginal()
        #expect(items.contains { $0.resource == "wallpaper:spaces" && $0.keptUserChange })
        let images = try spaceImages(s)
        #expect(images["Spaces/S2/Default"] == "/Users/me/Pictures/mine.jpg")
        #expect(images["Spaces/S1/Displays/UUID-1"] == s.home.path("Pictures/original-1.heic").path)
        #expect(images["Displays/UUID-2"] == s.home.path("Pictures/original-2.jpg").path)
    }

    @Test func aFailedStoreWritePutsTheSpaceOnScreenBack() async throws {
        let s = try setup()
        try addWallpaperStore(s)
        s.services.failWallpaperStore = true
        let report = try await apply(s, "catppuccin", mode: .dark, wallpaper: true)
        if case .failed? = outcome(report, "wallpaper") {} else { Issue.record("expected wallpaper failure, got \(String(describing: outcome(report, "wallpaper")))") }
        #expect(s.services.wallpapers[1] == s.home.path("Pictures/original-1.heic").path)
        #expect(s.services.wallpapers[2] == s.home.path("Pictures/original-2.jpg").path)
        #expect(await s.engine.ledgerEntries().allSatisfy { $0.integration != "wallpaper" })
    }

    @Test func everySpaceStaysOffWhenTheTweakIsOff() async throws {
        let s = try setup()
        try addWallpaperStore(s)
        s.services.tweaksAvailable = false
        let planned = await s.engine.plan(ApplyRequest(theme: try Fixtures.themeWithWallpaper("catppuccin", in: s.home), mode: .dark, systemIsDark: false),
                                          detections: await s.engine.detectAll())
        let wallpaper = try #require(planned.first { $0.id == "wallpaper" }?.plan)
        #expect(!wallpaper.operations.contains { if case .setWallpaperOnAllSpaces = $0 { true } else { false } })
        #expect(wallpaper.notes == ["macOS changes the current Space of each display"])
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

    @Test func followingMacOSReplacesTheNewestHistoryEntry() async throws {
        let s = try setup()
        let theme = try Fixtures.theme("catppuccin")
        func apply(systemIsDark: Bool, replacing: Bool) async {
            let request = ApplyRequest(theme: theme, mode: .system, systemIsDark: systemIsDark)
            let planned = await s.engine.plan(request, detections: await s.engine.detectAll())
            let newest = await s.engine.history().last?.id
            _ = await s.engine.apply(request, planned: planned, selected: ["ghostty"], replacing: replacing ? newest : nil)
        }
        _ = try await self.apply(s, "gruvbox", mode: .dark)
        await apply(systemIsDark: false, replacing: false)
        #expect(await s.engine.history().last?.appearance == .light)
        let entry = try #require(await s.engine.history().last)
        #expect(entry.needsOtherLook(available: theme.availableAppearances, systemIsDark: true))
        #expect(!entry.needsOtherLook(available: theme.availableAppearances, systemIsDark: false))
        #expect(!entry.needsOtherLook(available: [.dark], systemIsDark: false))
        // macOS turned Dark: the theme shows its dark look, and Undo still goes back to Gruvbox.
        await apply(systemIsDark: true, replacing: true)
        let history = await s.engine.history()
        #expect(history.map(\.themeName) == ["Gruvbox", "Catppuccin"])
        #expect(history.last?.appearance == .dark)
    }

    /// Set as Wallpaper with another theme's wallpaper, then macOS turns Light. The theme's apps and the wallpaper
    /// each switch look in their own history entry, and Undo still steps back through both.
    @Test func followingMacOSKeepsAWallpaperFromAnotherTheme() async throws {
        let s = try setup()
        let gruvbox = try Fixtures.themeWithWallpaper("gruvbox", in: s.home)
        let catppuccin = try Fixtures.themeWithWallpaper("catppuccin", in: s.home)
        let themes = [gruvbox.id: gruvbox, catppuccin.id: catppuccin]
        func apply(_ theme: Theme, systemIsDark: Bool, only: Set<String>? = nil, without: String? = nil, replacing: String? = nil) async {
            let request = ApplyRequest(theme: theme, mode: .system, systemIsDark: systemIsDark)
            let planned = await s.engine.plan(request, detections: await s.engine.detectAll())
            let selected = (only ?? Set(planned.filter { $0.plan != nil }.map(\.id))).subtracting([without].compactMap { $0 })
            _ = await s.engine.apply(request, planned: planned, selected: selected, replacing: replacing)
        }
        await apply(gruvbox, systemIsDark: true)
        await apply(catppuccin, systemIsDark: true, only: ["wallpaper"])
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-catppuccin-dark-1.png") == true)
        var history = await s.engine.history()
        #expect(history.currentTheme?.themeName == "Gruvbox")

        // macOS turns Light: Gruvbox's apps without the wallpaper, then Catppuccin's light wallpaper.
        let steps = history.followSteps(systemIsDark: false) { themes[$0]?.availableAppearances }
        #expect(steps.map(\.apps) == [.rememberedWithoutWallpaper, .wallpaperOnly])
        #expect(steps.map(\.entry.themeName) == ["Gruvbox", "Catppuccin"])
        for step in steps {
            let theme = try #require(themes[step.entry.themeID])
            switch step.apps {
            case .remembered: await apply(theme, systemIsDark: false, replacing: step.entry.id)
            case .rememberedWithoutWallpaper: await apply(theme, systemIsDark: false, without: "wallpaper", replacing: step.entry.id)
            case .wallpaperOnly: await apply(theme, systemIsDark: false, only: ["wallpaper"], replacing: step.entry.id)
            }
        }
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-catppuccin-light-1.png") == true)
        #expect(s.home.read(".config/ghostty/themes/scene-light")?.contains("Managed by Scene: Gruvbox") == true)
        history = await s.engine.history()
        #expect(history.map(\.themeName) == ["Gruvbox", "Catppuccin"])
        #expect(history.map(\.appearance) == [.light, .light])
        #expect(history.first?.integrations.contains("wallpaper") == true, "Undo to Gruvbox must show its wallpaper again")
        let followedAgain = history.followSteps(systemIsDark: false) { themes[$0]?.availableAppearances }
        #expect(followedAgain.isEmpty)

        // Undo goes back to Gruvbox, with its own wallpaper.
        _ = await s.engine.undo(resolveTheme: { id, _ in themes[id] }, systemIsDark: false)
        #expect(s.services.wallpapers[1]?.hasSuffix("scene-gruvbox-light-1.png") == true)
        #expect(await s.engine.history().map(\.themeName) == ["Gruvbox"])
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
