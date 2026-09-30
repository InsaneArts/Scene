import Foundation
@testable import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("GitHub themes")
struct GitHubTests {
    @Test func parsesTheWaysPeopleWriteARepository() {
        let expected = GitHubRepository(owner: "bjarneo", name: "omarchy-aura-theme")
        for text in ["https://github.com/bjarneo/omarchy-aura-theme", "https://github.com/bjarneo/omarchy-aura-theme.git",
                     "github.com/bjarneo/omarchy-aura-theme/", "  bjarneo/omarchy-aura-theme\n",
                     "https://github.com/bjarneo/omarchy-aura-theme/tree/main/backgrounds", "http://www.github.com/bjarneo/omarchy-aura-theme"] {
            #expect(GitHubRepository(text) == expected, "\(text)")
        }
        for text in ["https://gitlab.com/a/b", "bjarneo", "https://github.com/bjarneo", "../../etc/passwd", "a b/c", "https://github.com/-x/y"] {
            #expect(GitHubRepository(text) == nil, "\(text)")
        }
        #expect(expected.themeName == "aura")
        #expect(GitHubRepository(owner: "a", name: "Kanagawa").themeName == "kanagawa")
        #expect(expected.archiveURL.absoluteString == "https://github.com/bjarneo/omarchy-aura-theme/archive/HEAD.zip")
    }

    @Test func installsAnOmarchyThemeFromARepositoryArchive() throws {
        let home = try FixtureHome()
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let colors = """
        accent = "#7aa2f7"
        background = "#1a1b26"
        foreground = "#c0caf5"
        color0 = "#15161e"
        color1 = "#f7768e"
        color2 = "#9ece6a"
        color3 = "#e0af68"
        color4 = "#7aa2f7"
        color5 = "#bb9af7"
        color6 = "#7dcfff"
        color7 = "#a9b1d6"
        """
        let archive = try ZipArchive.create(files: [
            ("omarchy-aura-theme-main/colors.toml", Data(colors.utf8)),
            ("omarchy-aura-theme-main/backgrounds/1-dunes.png", try Fixtures.png(width: 1600, height: 900)),
            ("omarchy-aura-theme-main/hyprland.conf", Data("exec = rm -rf ~\n".utf8)),
            ("omarchy-aura-theme-main/neovim.lua", Data("os.execute('x')\n".utf8)),
        ])
        let theme = try library.installRepository(archive: archive, repository: GitHubRepository(owner: "bjarneo", name: "omarchy-aura-theme"))
        #expect(theme.id == "omarchy/aura")
        #expect(theme.manifest.name == "Aura")
        #expect(theme.variants[.dark]?.interface.accent == RGBA(hex: "#7aa2f7"))
        #expect(theme.variants[.dark]?.wallpapers.map(\.name) == ["1-dunes.png"])
        // Only colors and images were read. The config files and code never reach the library.
        let installed = try FileManager.default.subpathsOfDirectory(atPath: theme.folder.path).sorted()
        #expect(installed == ["theme.json", "wallpapers", "wallpapers/1-dunes.png"])
        #expect(library.loadAll().themes.map(\.id) == ["omarchy/aura"])
    }

    @Test func installsASceneThemeAndSkipsEverythingElse() throws {
        let home = try FixtureHome()
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let source = Repo.themes.appendingPathComponent("nord")
        var files: [(path: String, data: Data)] = [("nord-abc123/theme.json", try Data(contentsOf: source.appendingPathComponent("theme.json")))]
        for name in try FileManager.default.contentsOfDirectory(atPath: source.appendingPathComponent("wallpapers").path) {
            files.append(("nord-abc123/wallpapers/\(name)", try Data(contentsOf: source.appendingPathComponent("wallpapers/\(name)"))))
        }
        files.append(("nord-abc123/scripts/install.sh", Data("#!/bin/sh\n".utf8)))
        let theme = try library.installRepository(archive: try ZipArchive.create(files: files), repository: GitHubRepository(owner: "x", name: "nord"))
        #expect(theme.id == (try Fixtures.theme("nord")).id)
        #expect(!FileManager.default.fileExists(atPath: theme.folder.appendingPathComponent("scripts").path))
    }

    @Test func olderColorsTomlKeysMapAsOmarchyMapsThem() throws {
        var lines = ["accent = \"#989898\"  # Neutral accent", "foreground = \"#FFFFFF\"", "background = \"#000000\""]
        let hex = ["#262626", "#646464", "#8E8E8E", "#B9B9B9", "#989898", "#747474", "#585858", "#D4D4D4",
                   "#303030", "#747474", "#9E9E9E", "#C9C9C9", "#A8A8A8", "#848484", "#686868", "#E4E4E4"]
        for (index, color) in hex.enumerated() { lines.append("color\(index) = \"\(color)\"  # base") }
        let home = try FixtureHome()
        try home.write("black-arch/colors.toml", lines.joined(separator: "\n") + "\n")
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let v = try #require(try library.importOmarchy(folder: home.path("black-arch")).variants[.dark])
        #expect(v.terminal.ansi[9] == RGBA(hex: "#747474"))    // color9, not the normal red
        #expect(v.terminal.ansi[8] == RGBA(hex: "#303030"))    // color8 is muted
        #expect(v.terminal.ansi[15] == RGBA(hex: "#E4E4E4"))   // color15 is the bright foreground
    }

    @Test func installsAThemeThatHasOnlyAnAlacrittyFile() throws {
        let home = try FixtureHome()
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let alacritty = """
        [colors.primary]
        background = "#1e1e2e"
        foreground = "#cdd6f4"

        [colors.normal]
        black = "0x45475a"
        red = "#f38ba8"
        green = "#a6e3a1"
        yellow = "#f9e2af"
        blue = "#89b4fa"
        magenta = "#f5c2e7"
        cyan = "#94e2d5"
        white = "#bac2de"

        [colors.bright]
        black = "#585b70"
        red = "#f37799"
        green = "#89d88b"
        yellow = "#ebd391"
        blue = "#74a8fc"
        magenta = "#f2aede"
        cyan = "#6bd7ca"
        white = "#a6adc8"
        """
        let archive = try ZipArchive.create(files: [
            ("omarchy-all-hallows-eve-theme-main/alacritty.toml", Data(alacritty.utf8)),
            ("omarchy-all-hallows-eve-theme-main/backgrounds/1.png", try Fixtures.png(width: 1600, height: 900)),
            ("omarchy-all-hallows-eve-theme-main/kitty.conf", Data("background #000000\n".utf8)),
        ])
        let theme = try library.installRepository(archive: archive, repository: GitHubRepository(owner: "guilhermetk", name: "omarchy-all-hallows-eve-theme"))
        #expect(theme.id == "omarchy/all-hallows-eve")
        let v = try #require(theme.variants[.dark])
        #expect(v.terminal.background == RGBA(hex: "#1e1e2e"))
        #expect(v.terminal.ansi[1] == RGBA(hex: "#f38ba8") && v.terminal.ansi[9] == RGBA(hex: "#f37799"))
    }

    /// Imports every colors.toml in a folder, such as the files of Omarchy's community themes.
    /// Opt in with SCENE_OMARCHY_CORPUS=<folder>.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCENE_OMARCHY_CORPUS"] != nil))
    func importsAFolderOfOmarchyColorFiles() throws {
        let corpus = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SCENE_OMARCHY_CORPUS"]!)
        let home = try FixtureHome()
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        var failures: [String] = []
        let files = try FileManager.default.contentsOfDirectory(atPath: corpus.path).filter { $0.hasSuffix(".toml") }.sorted()
        for file in files {
            let folder = home.path("in/\(file.replacingOccurrences(of: ".toml", with: ""))")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: corpus.appendingPathComponent(file), to: folder.appendingPathComponent("colors.toml"))
            do { _ = try library.importOmarchy(folder: folder) } catch { failures.append("\(file): \(error)") }
        }
        #expect(failures.isEmpty, "\(failures.count) of \(files.count) failed:\n\(failures.joined(separator: "\n"))")
        print("Imported \(files.count - failures.count) of \(files.count) colors.toml files")
    }

    @Test func refusesARepositoryWithoutATheme() throws {
        let home = try FixtureHome()
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let archive = try ZipArchive.create(files: [("repo-main/README.md", Data("# Hi\n".utf8)), ("repo-main/src/main.c", Data())])
        #expect(throws: SceneError.self) { try library.installRepository(archive: archive, repository: GitHubRepository(owner: "a", name: "repo")) }
    }

    /// Downloads a real repository into a fixture library. Opt in with SCENE_NETWORK=1 and, optionally,
    /// SCENE_NETWORK_REPO=owner/repo.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCENE_NETWORK"] == "1"))
    func downloadsARealRepository() async throws {
        let home = try FixtureHome()
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let text = ProcessInfo.processInfo.environment["SCENE_NETWORK_REPO"] ?? "https://github.com/bjarneo/omarchy-aura-theme"
        let repository = try #require(GitHubRepository(text))
        let archive = try await repository.download()
        let theme = try library.installRepository(archive: archive, repository: repository)
        #expect(theme.variants.values.first?.wallpapers.isEmpty == false, "no backgrounds were installed")
        print("Installed \(theme.id) (\(theme.manifest.name)) from \(archive.count) bytes, \(theme.variants.values.first?.wallpapers.count ?? 0) backgrounds")
    }

    @Test func zipReaderSkipsEntriesTheCallerDoesNotWant() throws {
        let archive = try ZipArchive.create(files: [("a/keep.txt", Data("k".utf8)), ("a/skip.bin", Data(count: 5_000_000))])
        // The skipped entry would break these limits if it were counted.
        let limits = ZipLimits(maxEntries: 2, maxEntryUncompressedBytes: 10, maxTotalUncompressedBytes: 10)
        let files = try ZipArchive.read(archive, limits: limits) { $0.hasSuffix(".txt") }
        #expect(files == ["a/keep.txt": Data("k".utf8)])
    }
}
