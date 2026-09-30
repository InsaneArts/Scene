import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// Apply and restore for the apps added after the MVP, against a fixture home folder.
@Suite("More apps", .serialized)
struct MoreAppsTests {
    static let zedSettings = """
    // Zed settings
    {
      "ui_font_size": 16,
      "theme": "One Dark", // mine
    }

    """
    static let kittyConfig = "font_size 13\n# BEGIN_KITTY_THEME\ninclude current-theme.conf\n# END_KITTY_THEME\n"
    static let tmuxConfig = "set -g mouse on\nset -g status-style bg=blue\n"
    static let batConfig = "--style=numbers\n--theme=\"Monokai Extended\"\n"
    static let gitconfig = "[user]\n\tname = Me\n[core]\n\tpager = delta\n"
    static let alacrittyConfig = "[general]\nlive_config_reload = true\nimport = [\"~/.config/alacritty/themes/gruvbox.toml\"]\n\n[font]\nsize = 13\n"
    static let helixConfig = "theme = \"onedark\" # mine\n\n[editor]\nline-number = \"relative\"\n"
    static var myXcodeTheme: [String: Any] { [
        "DVTFontAndColorVersion": 1, "DVTLineSpacing": 1.3, "DVTSourceTextBackground": "0 0 0 1",
        "DVTSourceTextSyntaxFonts": ["xcode.syntax.plain": "Menlo-Regular - 14.0"], "DVTMarkupTextNormalFont": ".AppleSystemUIFont - 11.0",
    ] }

    struct Setup {
        let home: FixtureHome
        let services: FakeServices
        let engine: Engine
    }

    func setup() throws -> Setup {
        let home = try FixtureHome()
        let apps = [
            "dev.zed.Zed": try home.fakeApp("Zed", version: "1.20.2"),
            XcodeIntegration.bundleID: try home.fakeApp("Xcode", version: "26.6"),
            KittyIntegration.bundleID: try home.fakeApp("kitty", version: "0.44.0"),
            TerminalAppIntegration.bundleID: try home.fakeApp("Terminal", version: "2.15"),
            AlacrittyIntegration.bundleID: try home.fakeApp("Alacritty", version: "0.16.1"),
        ]
        var found: [String: URL] = [:]
        for name in ["tmux", "bat", "delta", "hx", "btop"] { found[name] = try home.write("bin/\(name)", "#!/bin/sh\n") }
        let tools = found
        try home.write(".config/zed/settings.json", Self.zedSettings)
        try home.write(".config/kitty/kitty.conf", Self.kittyConfig)
        try home.write(".config/kitty/dark-theme.auto.conf", "background #000000\n")
        try home.write(".tmux.conf", Self.tmuxConfig)
        try home.write(".config/bat/config", Self.batConfig)
        try home.write(".gitconfig", Self.gitconfig)
        try home.write(".config/alacritty/alacritty.toml", Self.alacrittyConfig)
        try home.write(".config/helix/config.toml", Self.helixConfig)
        let theme = try PropertyListSerialization.data(fromPropertyList: Self.myXcodeTheme, format: .xml, options: 0)
        try theme.write(to: home.path("Library/Developer/Xcode/UserData/FontAndColorThemes/Mine.xccolortheme").creatingFolder())
        let env = SceneEnvironment(home: home.url, locateApp: { apps[$0] }, locateExecutable: { tools[$0] })
        let services = FakeServices()
        services.prefs["com.apple.dt.Xcode#XCFontAndColorCurrentTheme"] = .string("Mine.xccolortheme")
        services.prefs["com.apple.Terminal#Default Window Settings"] = .string("Pro")
        services.prefs["com.apple.Terminal#Startup Window Settings"] = .string("Pro")
        services.prefs["com.apple.Terminal#Window Settings"] = .dictionary([
            "Pro": .dictionary(["name": .string("Pro"), "Font": .data(Data([1, 2, 3])), "columnCount": .int(120)]),
            "Basic": .dictionary(["name": .string("Basic")]),
        ])
        services.responses["bat --version"] = CLIResult(status: 0, stdout: "bat 0.26.1 (979ba22)\n", stderr: "")
        services.responses["tmux -V"] = CLIResult(status: 0, stdout: "tmux 3.6b\n", stderr: "")
        services.running = [KittyIntegration.bundleID: [4242], "hx": [4343], "btop": [4444], XcodeIntegration.bundleID: [4545]]
        services.responses["hx --version"] = CLIResult(status: 0, stdout: "helix 25.07.1 (a05c151b)\n", stderr: "")
        services.responses["btop --version"] = CLIResult(status: 0, stdout: "btop version: \u{1b}[1m1.4.5\u{1b}[0m\n", stderr: "")
        let integrations: [Integration] = [ZedIntegration(), XcodeIntegration(), KittyIntegration(), TerminalAppIntegration(), TmuxIntegration(),
                                           BatIntegration(), AlacrittyIntegration(), HelixIntegration(), BtopIntegration()]
        return Setup(home: home, services: services, engine: Engine(env: env, services: services, integrations: integrations))
    }

    func apply(_ s: Setup, _ folder: String, mode: AppearanceMode) async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme(folder), mode: mode, systemIsDark: false)
        let planned = await s.engine.plan(request, detections: await s.engine.detectAll())
        return await s.engine.apply(request, planned: planned, selected: Set(planned.map(\.id)))
    }

    @Test func applyThenRestoreGivesBackEveryFile() async throws {
        let s = try setup()
        let report = try await apply(s, "catppuccin", mode: .system)
        for result in report.results { #expect(result.outcome.isSuccess, "\(result.id): \(result.outcome)") }

        // Zed: the theme family and a setting that follows macOS. The comments stay.
        let zed = try #require(s.home.read(".config/zed/settings.json"))
        #expect(zed.contains("// Zed settings") && zed.contains("\"ui_font_size\": 16"))
        let doc = try JSONCDocument(text: zed)
        #expect(doc.value(forKey: "theme") == ZedRenderer.setting(forced: nil))
        #expect(FileManager.default.fileExists(atPath: s.home.path(".config/zed/themes/scene.json").path))

        // Xcode: both themes keep the user's fonts, and both settings point at them.
        let xcode = try #require(FileOps.read(s.home.path("Library/Developer/Xcode/UserData/FontAndColorThemes/Scene (Light).xccolortheme")))
        let plist = try #require(try PropertyListSerialization.propertyList(from: xcode, format: nil) as? [String: Any])
        #expect((plist["DVTSourceTextSyntaxFonts"] as? [String: String])?["xcode.syntax.plain"] == "Menlo-Regular - 14.0")
        #expect(plist["DVTLineSpacing"] as? Double == 1.3)
        #expect(s.services.prefs["com.apple.dt.Xcode#XCFontAndColorCurrentTheme"] == .string("Scene (Light).xccolortheme"))
        #expect(s.services.prefs["com.apple.dt.Xcode#XCFontAndColorCurrentDarkTheme"] == .string("Scene (Dark).xccolortheme"))

        // kitty: an include at the end, and the auto file the user already had.
        let kitty = try #require(s.home.read(".config/kitty/kitty.conf"))
        #expect(kitty.hasPrefix(Self.kittyConfig) && kitty.contains("include scene-theme.conf"))
        let darkVariant = try Fixtures.theme("catppuccin").variants[.dark]!
        #expect(s.home.read(".config/kitty/dark-theme.auto.conf") == KittyRenderer.themeFile(darkVariant))
        #expect(!FileManager.default.fileExists(atPath: s.home.path(".config/kitty/light-theme.auto.conf").path))

        // Terminal: a Scene profile that copies the default profile, selected for new and startup windows.
        guard case .dictionary(let profiles)? = s.services.prefs["com.apple.Terminal#Window Settings"],
              case .dictionary(let scene)? = profiles["Scene"] else { Issue.record("no Scene profile"); return }
        #expect(scene["Font"] == .data(Data([1, 2, 3])) && scene["columnCount"] == .int(120))
        #expect(scene["BackgroundColor"] != nil && scene["ANSIBrightWhiteColor"] != nil)
        #expect(profiles["Pro"] != nil && profiles["Basic"] != nil)
        #expect(s.services.prefs["com.apple.Terminal#Default Window Settings"] == .string("Scene"))

        // tmux: the user's file sources Scene's, and the running server loads it.
        #expect(s.home.read(".tmux.conf")?.contains("source-file -q '\(s.home.path(".config/tmux/scene.conf").path)'") == true)
        #expect(s.services.calls.contains("run tmux source-file -q \(s.home.path(".config/tmux/scene.conf").path)"))

        // bat follows macOS with both themes. delta gets an include in ~/.gitconfig.
        let bat = try #require(s.home.read(".config/bat/config"))
        #expect(bat.hasPrefix(Self.batConfig) && bat.contains("--theme=auto:system") && bat.contains("--theme-light=scene-light"))
        #expect(s.home.read(".gitconfig")?.contains("path = \"\(s.home.path(".config/git/scene-delta.gitconfig").path)\"") == true)
        #expect(s.services.calls.contains("run bat cache --build"))

        // Running apps reload: kitty and Helix on SIGUSR1, btop on SIGUSR2. Xcode needs a restart.
        #expect(s.services.calls.contains("signal \(SIGUSR1) 4242") && s.services.calls.contains("signal \(SIGUSR1) 4343"))
        #expect(s.services.calls.contains("signal \(SIGUSR2) 4444"))
        #expect(report.results.first { $0.id == "xcode" }?.outcome == .appliedRestartNeeded("Quit and reopen Xcode to see the theme."))

        // Alacritty: Scene's file goes last in the user's own import list.
        let alacritty = try #require(s.home.read(".config/alacritty/alacritty.toml"))
        #expect(alacritty.contains("import = [\"~/.config/alacritty/themes/gruvbox.toml\", \"\(s.home.path(".config/alacritty/scene.toml").path)\"]"))
        #expect(alacritty.hasSuffix("[font]\nsize = 13\n"))
        // Helix and btop: a theme file, and one key in the config. btop had no config, so Scene starts one.
        #expect(s.home.read(".config/helix/config.toml") == Self.helixConfig.replacingOccurrences(of: "\"onedark\"", with: "\"scene\""))
        #expect(FileManager.default.fileExists(atPath: s.home.path(".config/helix/themes/scene.toml").path))
        #expect(s.home.read(".config/btop/btop.conf") == "color_theme = \"scene\"\n")

        let items = await s.engine.restoreOriginal()
        #expect(!items.isEmpty && items.allSatisfy { !$0.keptUserChange })
        #expect(s.home.read(".config/zed/settings.json") == Self.zedSettings)
        #expect(s.home.read(".config/kitty/kitty.conf") == Self.kittyConfig)
        #expect(s.home.read(".config/kitty/dark-theme.auto.conf") == "background #000000\n")
        #expect(s.home.read(".tmux.conf") == Self.tmuxConfig)
        #expect(s.home.read(".config/bat/config") == Self.batConfig)
        #expect(s.home.read(".gitconfig") == Self.gitconfig)
        #expect(s.home.read(".config/alacritty/alacritty.toml") == Self.alacrittyConfig)
        #expect(s.home.read(".config/helix/config.toml") == Self.helixConfig)
        for path in [".config/btop/btop.conf", ".config/btop/themes/scene.theme", ".config/helix/themes/scene.toml", ".config/alacritty/scene.toml",
                     ".config/zed/themes/scene.json", ".config/kitty/scene-theme.conf", ".config/tmux/scene.conf",
                     ".config/bat/themes/scene-dark.tmTheme", ".config/git/scene-delta.gitconfig",
                     "Library/Developer/Xcode/UserData/FontAndColorThemes/Scene (Dark).xccolortheme"] {
            #expect(!FileManager.default.fileExists(atPath: s.home.path(path).path), "\(path) is still there")
        }
        #expect(s.services.prefs["com.apple.dt.Xcode#XCFontAndColorCurrentTheme"] == .string("Mine.xccolortheme"))
        #expect(s.services.prefs["com.apple.dt.Xcode#XCFontAndColorCurrentDarkTheme"] == nil)
        guard case .dictionary(let restored)? = s.services.prefs["com.apple.Terminal#Window Settings"] else { Issue.record("profiles gone"); return }
        #expect(restored["Scene"] == nil && restored["Pro"] != nil)
        #expect(s.services.prefs["com.apple.Terminal#Default Window Settings"] == .string("Pro"))
        // The running tmux server drops Scene's styles and loads the user's config again.
        #expect(s.services.calls.contains { $0.hasPrefix("run tmux set -gqu status-style ; ") && $0.hasSuffix("source-file -q \(s.home.path(".tmux.conf").path)") })
        #expect(await s.engine.ledgerEntries().isEmpty)
    }

    @Test func forcedAppearancePinsTheLook() async throws {
        let s = try setup()
        _ = try await apply(s, "catppuccin", mode: .dark)
        let doc = try JSONCDocument(text: try #require(s.home.read(".config/zed/settings.json")))
        #expect(doc.value(forKey: "theme") == ZedRenderer.setting(forced: .dark))
        let bat = try #require(s.home.read(".config/bat/config"))
        #expect(bat.contains("--theme=scene-dark") && !bat.contains("auto:system"))
    }

    @Test func oldBatGetsOneTheme() async throws {
        let s = try setup()
        s.services.responses["bat --version"] = CLIResult(status: 0, stdout: "bat 0.24.0\n", stderr: "")
        _ = try await apply(s, "catppuccin", mode: .system)
        let bat = try #require(s.home.read(".config/bat/config"))
        #expect(bat.contains("--theme=scene-light") && !bat.contains("--theme-dark"))
    }

    @Test func bordersGetsAColorLineAndTheRunningInstanceUpdates() async throws {
        let home = try FixtureHome()
        let borders = try home.write("bin/borders", "#!/bin/sh\n")
        let rc = """
        #!/bin/bash
        options=(
          style=round
          width=6.0
          active_color=0xffe1e3e4
          inactive_color=0xff494d64
        )
        borders "${options[@]}"

        """
        try home.write(".config/borders/bordersrc", rc)
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { $0 == "borders" ? borders : nil })
        let services = FakeServices()
        services.running = ["borders": [4646]]
        let engine = Engine(env: env, services: services, integrations: [BordersIntegration()])
        let theme = try Fixtures.theme("tokyo-night")
        let request = ApplyRequest(theme: theme, mode: .system, systemIsDark: true)
        let report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["borders"])
        #expect(report.results.first?.outcome == .applied, "\(String(describing: report.results.first?.outcome))")
        let arguments = BordersRenderer.arguments(theme.variants[.dark]!)
        #expect(home.read(".config/borders/bordersrc")?.hasSuffix("borders " + arguments.joined(separator: " ") + "\n# <<< Scene <<<\n") == true)
        #expect(services.calls.contains("run borders " + arguments.joined(separator: " ")))
        // Restore takes the block out and sends the user's own colors again.
        _ = await engine.restoreOriginal()
        #expect(home.read(".config/borders/bordersrc") == rc)
        #expect(services.calls.last == "run borders active_color=0xffe1e3e4 inactive_color=0xff494d64")
    }

    @Test func bordersIsLeftAloneWhenItDoesNotRun() async throws {
        let home = try FixtureHome()
        let borders = try home.write("bin/borders", "#!/bin/sh\n")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { $0 == "borders" ? borders : nil })
        let services = FakeServices()
        let engine = Engine(env: env, services: services, integrations: [BordersIntegration()])
        let request = ApplyRequest(theme: try Fixtures.theme("nord"), mode: .system, systemIsDark: true)
        _ = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["borders"])
        // Without a running instance, `borders` with arguments would start one, so Scene only writes the file.
        #expect(!services.calls.contains { $0.hasPrefix("run borders") })
        #expect(home.read(".config/borders/bordersrc")?.contains("borders active_color=0xff") == true)
        _ = await engine.restoreOriginal()
        #expect(!FileManager.default.fileExists(atPath: home.path(".config/borders/bordersrc").path))
    }

    @Test func warpGetsAFilePerThemeAndWaitsBeforeTheSettingWhileItRuns() async throws {
        let home = try FixtureHome()
        let warp = try home.fakeApp("Warp", version: "0.2026.09.24")
        let original = "[appearance.themes]\ntheme = \"dracula\"\n\n[appearance.text]\nfont_name = \"JetBrains Mono\"\n"
        try home.write(".warp/settings.toml", original)
        let env = SceneEnvironment(home: home.url, locateApp: { $0 == WarpIntegration.bundleID ? warp : nil }, locateExecutable: { _ in nil })
        let services = FakeServices()
        services.running = [WarpIntegration.bundleID: [4848]]
        let engine = Engine(env: env, services: services, integrations: [WarpIntegration()])
        let two = try Fixtures.theme("catppuccin")
        let request = ApplyRequest(theme: two, mode: .system, systemIsDark: false)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        // Both theme files first, then the wait, then the settings.
        let ops = try #require(planned.first?.plan?.operations)
        #expect(ops.firstIndex { if case .pause = $0 { true } else { false } } == 2)
        let started = Date()
        let report = await engine.apply(request, planned: planned, selected: ["warp"])
        #expect(Date().timeIntervalSince(started) >= 1)
        #expect(report.results.first?.outcome == .applied, "\(String(describing: report.results.first?.outcome))")
        func file(_ theme: Theme, _ look: String) -> String {
            home.path(".warp/themes/scene/\(theme.id.replacingOccurrences(of: "/", with: "-"))-\(look).yaml").path
        }
        var doc = KeyValueDocument(text: try #require(home.read(".warp/settings.toml")))
        #expect(doc.value(forKey: "appearance.themes.system_theme") == "true")
        #expect(doc.value(forKey: "appearance.themes.selected_system_themes")?.contains(file(two, "dark")) == true)
        #expect(doc.value(forKey: "appearance.themes.theme")?.contains(file(two, "light")) == true)
        #expect(home.read(".warp/settings.toml")?.hasSuffix("[appearance.text]\nfont_name = \"JetBrains Mono\"\n") == true)
        #expect(home.read(".warp/themes/scene/\((file(two, "dark") as NSString).lastPathComponent)")?.contains("name: 'Scene: \(two.id) (dark)'") == true)

        // A theme with one look turns off Warp's own Light/Dark switching.
        let one = try Fixtures.theme("tokyo-night")
        let second = ApplyRequest(theme: one, mode: .system, systemIsDark: false)
        _ = await engine.apply(second, planned: await engine.plan(second, detections: await engine.detectAll()), selected: ["warp"])
        doc = KeyValueDocument(text: try #require(home.read(".warp/settings.toml")))
        #expect(doc.value(forKey: "appearance.themes.system_theme") == "false")
        #expect(doc.value(forKey: "appearance.themes.theme")?.contains(file(one, "dark")) == true)

        _ = await engine.restoreOriginal()
        #expect(home.read(".warp/settings.toml") == original)
        #expect(!FileManager.default.fileExists(atPath: file(two, "dark")) && !FileManager.default.fileExists(atPath: file(one, "dark")))
    }

    @Test func warpWithoutASettingsFileIsLeftAlone() async throws {
        let home = try FixtureHome()
        let warp = try home.fakeApp("Warp", version: "0.2026.03.01")
        let env = SceneEnvironment(home: home.url, locateApp: { $0 == WarpIntegration.bundleID ? warp : nil }, locateExecutable: { _ in nil })
        let engine = Engine(env: env, services: FakeServices(), integrations: [WarpIntegration()])
        let request = ApplyRequest(theme: try Fixtures.theme("nord"), mode: .system, systemIsDark: false)
        let report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["warp"])
        if case .skipped? = report.results.first?.outcome {} else { Issue.record("expected skipped, got \(String(describing: report.results.first?.outcome))") }
        #expect(!FileManager.default.fileExists(atPath: home.path(".warp").path))
    }

    @Test func userChangeToTerminalProfilesIsKeptOnRestore() async throws {
        let s = try setup()
        _ = try await apply(s, "gruvbox", mode: .dark)
        // The user edits the Scene profile in Terminal after Scene applied.
        guard case .dictionary(var profiles)? = s.services.prefs["com.apple.Terminal#Window Settings"],
              case .dictionary(var scene)? = profiles["Scene"] else { Issue.record("no Scene profile"); return }
        scene["columnCount"] = .int(80)
        profiles["Scene"] = .dictionary(scene)
        s.services.prefs["com.apple.Terminal#Window Settings"] = .dictionary(profiles)
        let items = await s.engine.restoreOriginal()
        #expect(items.contains { $0.resource.hasSuffix("Window Settings/Scene") && $0.keptUserChange })
        #expect(s.services.prefs["com.apple.Terminal#Default Window Settings"] == .string("Pro"))
    }
}

extension URL {
    /// Creates the parent folder and returns the URL, for writing a fixture file.
    func creatingFolder() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
