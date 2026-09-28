import Foundation
@testable import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("Colors")
struct ColorTests {
    @Test func parsesHex() {
        #expect(RGBA(hex: "#1a1b26") == RGBA(r: 0x1a, g: 0x1b, b: 0x26))
        #expect(RGBA(hex: "#1a1b2680")?.a == 0x80)
        #expect(RGBA(hex: "#1A1B26")?.hex == "#1a1b26")
    }

    @Test(arguments: ["1a1b26", "#1a1b2", "#1a1b26f", "#gggggg", "#１２３４５６", "", "#1a1b26\n", "@background"])
    func rejectsInvalidHex(_ value: String) { #expect(RGBA(hex: value) == nil) }

    @Test func contrastAndMix() {
        let black = RGBA(hex: "#000000")!, white = RGBA(hex: "#ffffff")!
        #expect(abs(black.contrast(with: white) - 21) < 0.01)
        #expect(white.mixed(over: black, amount: 0.5).hex == "#808080")
    }

    @Test func nearestAccent() {
        #expect(ThemeLoader.nearestAccent(to: RGBA(hex: "#7aa2f7")!) == .blue)
        #expect(ThemeLoader.nearestAccent(to: RGBA(hex: "#f38ba8")!) == .pink)
        #expect(ThemeLoader.nearestAccent(to: RGBA(hex: "#a9b665")!) == .green)
        #expect(ThemeLoader.nearestAccent(to: RGBA(hex: "#808080")!) == .graphite)
    }
}

@Suite("Bundled themes")
struct BundledThemeTests {
    static let folders = ((try? FileManager.default.contentsOfDirectory(atPath: Repo.themes.path)) ?? [])
        .filter { FileManager.default.fileExists(atPath: Repo.themes.appendingPathComponent("\($0)/theme.json").path) }
        .sorted()

    @Test func bundlesTwentyOneThemes() {
        #expect(Self.folders.count == 21, "\(Self.folders)")
    }

    @Test(arguments: folders)
    func loads(_ folder: String) throws {
        let theme = try Fixtures.theme(folder)
        #expect(!theme.variants.isEmpty)
        #expect(theme.warnings.filter { $0.contains("license") || $0.contains("attribution") }.isEmpty, "\(theme.warnings)")
        for variant in theme.variants.values {
            #expect(variant.wallpapers.count == 3, "\(folder) \(variant.appearance) has \(variant.wallpapers.count) wallpapers")
            #expect(variant.terminal.ansi.count == 16)
            #expect(variant.interface.foreground.contrast(with: variant.interface.background) >= 4.5)
            #expect(variant.system.accent != nil)
        }
    }

    @Test func catppuccinHasBothVariants() throws {
        let theme = try Fixtures.theme("catppuccin")
        #expect(theme.availableAppearances == [.light, .dark])
        #expect(theme.variants[.dark]?.interface.background.hex == "#1e1e2e")
        #expect(theme.variants[.light]?.interface.background.hex == "#eff1f5")
    }
}

@Suite("Theme validation")
struct ValidationTests {
    static let minimal = """
    {"format":1,"id":"test/min","version":"1.0.0","name":"Min","authors":[{"name":"T"}],"license":"MIT",
     "variants":{"dark":{"palette":{"background":"#101010","foreground":"#e0e0e0","accent":"#3a86ff"},
       "terminal":{"ansi":{"black":"#000000","red":"#ff0000","green":"#00ff00","yellow":"#ffff00","blue":"#0000ff","magenta":"#ff00ff","cyan":"#00ffff","white":"#ffffff"}},
       "syntax":{}}}}
    """

    func load(_ manifest: String, files: [String: String] = [:]) throws -> Theme {
        let home = try FixtureHome()
        try home.write("theme/theme.json", manifest)
        for (path, text) in files { try home.write("theme/\(path)", text) }
        return try ThemeLoader.load(folder: home.path("theme"))
    }

    func errors(_ manifest: String, files: [String: String] = [:]) -> [String] {
        do { _ = try load(manifest, files: files); return [] }
        catch let e as ThemeLoadError { return e.errors }
        catch { return ["\(error)"] }
    }

    @Test func minimalThemeDerivesMissingRoles() throws {
        let theme = try load(Self.minimal)
        let v = try #require(theme.variants[.dark])
        #expect(v.terminal.ansi[8] == v.terminal.ansi[0])            // bright falls back to normal
        #expect(v.syntax.parameter == v.syntax.variable)             // parameter → variable
        #expect(v.interface.error == v.terminal.ansi[1])             // error → ANSI red
        #expect(theme.warnings.contains { $0.contains("derived") })
    }

    @Test func rejectsBadColorsAndReferences() {
        let bad = Self.minimal.replacingOccurrences(of: "\"accent\":\"#3a86ff\"", with: "\"accent\":\"blue\"")
        #expect(errors(bad).contains { $0.contains("palette.accent") })
        let badRef = Self.minimal.replacingOccurrences(of: "\"syntax\":{}", with: "\"syntax\":{\"string\":\"@nope\"}")
        #expect(errors(badRef).contains { $0.contains("not a palette role") })
    }

    @Test func rejectsInjectionAttempts() {
        // A newline in a color can never reach a config file: it fails to parse as a color.
        let injected = Self.minimal.replacingOccurrences(of: "\"#e0e0e0\"", with: "\"#e0e0e0\\ncommand = /bin/sh\"")
        #expect(!errors(injected).isEmpty)
        let traversal = Self.minimal.replacingOccurrences(of: "\"syntax\":{}", with: "\"syntax\":{},\"wallpapers\":[{\"file\":\"wallpapers/../../etc/passwd\"}]")
        #expect(errors(traversal).contains { $0.contains("wallpapers/<name>") })
    }

    /// A theme folder, `theme/`, whose dark variant lists `list` (JSON array items) and whose wallpapers/ holds generated `images`.
    func themeWithWallpapers(_ list: String, images: [String]) throws -> FixtureHome {
        let home = try FixtureHome()
        try FileManager.default.createDirectory(at: home.path("theme/wallpapers"), withIntermediateDirectories: true)
        for name in images { try Fixtures.png(width: 1600, height: 900).write(to: home.path("theme/wallpapers/\(name)")) }
        try home.write("theme/theme.json", Self.minimal.replacingOccurrences(of: "\"syntax\":{}", with: "\"syntax\":{},\"wallpapers\":[\(list)]"))
        return home
    }

    @Test func wallpapersKeepTheirOrderAndCycle() throws {
        let home = try themeWithWallpapers(#"{"file":"wallpapers/b.png"},{"file":"wallpapers/a.png","fit":"fit"},{"file":"wallpapers/c.png"}"#,
                                             images: ["a.png", "b.png", "c.png"])
        let v = try #require(try ThemeLoader.load(folder: home.path("theme")).variants[.dark])
        #expect(v.wallpapers.map(\.name) == ["b.png", "a.png", "c.png"])
        #expect(v.wallpapers[1].fit == .fit)
        #expect(v.wallpaper(named: nil)?.name == "b.png")           // the first one is the default
        #expect(v.wallpaper(named: "gone.png")?.name == "b.png")    // a choice the theme no longer has falls back to it
        #expect(v.wallpaper(after: nil)?.name == "a.png")
        #expect(v.wallpaper(after: "c.png")?.name == "b.png")       // after the last comes the first
    }

    @Test func rejectsAWallpaperListedTwice() throws {
        let home = try themeWithWallpapers(#"{"file":"wallpapers/a.png"},{"file":"wallpapers/a.png"}"#, images: ["a.png"])
        do { _ = try ThemeLoader.load(folder: home.path("theme")); Issue.record("expected an error") }
        catch let error as ThemeLoadError { #expect(error.errors.contains { $0.contains("listed twice") }, "\(error.errors)") }
    }

    @Test func rejectsUnexpectedFiles() {
        #expect(errors(Self.minimal, files: ["hook.sh": "rm -rf ~"]).contains { $0.contains("not allowed") })
        #expect(errors(Self.minimal, files: ["apps/neovim.lua": "os.execute()"]).contains { $0.contains("not allowed") })
    }

    @Test func rejectsSymlinks() throws {
        let home = try FixtureHome()
        try home.write("theme/theme.json", Self.minimal)
        try FileManager.default.createDirectory(at: home.path("theme/wallpapers"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home.path("theme/wallpapers/x.png").path, withDestinationPath: "/etc/hosts")
        #expect(throws: ThemeLoadError.self) { try ThemeLoader.load(folder: home.path("theme")) }
    }

    @Test func rejectsNewerFormatAndBadIdentity() {
        #expect(errors(Self.minimal.replacingOccurrences(of: "\"format\":1", with: "\"format\":9")).contains { $0.contains("newer version") })
        #expect(errors(Self.minimal.replacingOccurrences(of: "test/min", with: "../min")).contains { $0.contains("creator/slug") })
        #expect(errors(Self.minimal.replacingOccurrences(of: "\"Min\"", with: "\"Min\\u202e\"")).contains { $0.contains("bidirectional") })
    }

    @Test func overrideValidator() {
        let good = ##"{"colors":{"editor.background":"#101010"},"tokenColors":[{"scope":"comment","settings":{"foreground":"#808080","fontStyle":"italic"}}]}"##
        #expect(OverrideValidator.validate(Data(good.utf8), integration: "vscode").isEmpty)
        let include = #"{"include":"../../secret.json"}"#
        #expect(!OverrideValidator.validate(Data(include.utf8), integration: "vscode").isEmpty)
        let lua = ##"{"groups":{"Normal":{"fg":"#ffffff","callback":"os.execute('x')"}}}"##
        #expect(!OverrideValidator.validate(Data(lua.utf8), integration: "neovim").isEmpty)
    }
}
