import Foundation
@testable import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("Theme drafts")
struct ThemeDraftTests {
    /// A complete two-look draft whose wallpapers are generated PNG files in `home`.
    static func draft(in home: FixtureHome) throws -> ThemeDraft {
        func wallpapers(_ look: String) throws -> [ThemeDraft.Wallpaper] {
            try (1...3).map { index in
                let file = try home.write("images/\(look)-\(index).png", "")
                try Fixtures.png(width: 1600, height: 900).write(to: file)
                return ThemeDraft.Wallpaper(file: file.path, license: "CC0-1.0", attribution: "Test \(index)")
            }
        }
        let dark = ThemeDraft.Look(colors: [
            "background": "#16161e", "foreground": "#c0caf5", "accent": "#7aa2f7", "selection": "#2e3c64",
            "red": "#f7768e", "orange": "#ff9e64", "yellow": "#e0af68", "green": "#9ece6a", "cyan": "#7dcfff", "blue": "#7aa2f7", "magenta": "#bb9af7",
        ], accentColor: "blue", iconStyle: "tinted", iconTint: "accent", wallpapers: try wallpapers("dark"))
        let light = ThemeDraft.Look(colors: [
            "background": "#f5f5f0", "foreground": "#2a2a33", "accent": "#2e59c9", "selection": "#cdd7f0",
            "red": "#b3243c", "orange": "#a8521a", "yellow": "#8a6a00", "green": "#3a7a1e", "cyan": "#0f7285", "blue": "#2e59c9", "magenta": "#8a3fa8",
        ], wallpapers: try wallpapers("light"))
        return ThemeDraft(name: "Night Shift", summary: "Blue hour over a quiet city.", author: "Test Author", dark: dark, light: light)
    }

    @Test func aBundledThemeComesBackWithTheSameColors() throws {
        for folder in ["amber", "catppuccin", "gruvbox"] {
            let theme = try Fixtures.theme(folder)
            let draft = ThemeDraft(theme: theme, author: "Someone Else")
            #expect(draft.name == theme.manifest.name + " Copy")
            let rebuilt = try draft.preview()
            for (appearance, original) in theme.variants {
                let copy = try #require(rebuilt.variants[appearance])
                // Shades Scene mixes itself may differ by 1 in a channel: Python rounds a 50% mix the other way.
                let mirror = { (colors: InterfaceColors) in Mirror(reflecting: colors).children.compactMap { $0.value as? RGBA } }
                for (a, b) in zip(mirror(copy.interface), mirror(original.interface)) {
                    #expect(abs(Int(a.r) - Int(b.r)) <= 1 && abs(Int(a.g) - Int(b.g)) <= 1 && abs(Int(a.b) - Int(b.b)) <= 1,
                            "\(folder) \(appearance): \(a) is not \(b)")
                }
                #expect(copy.terminal == original.terminal, "\(folder) \(appearance) terminal")
                #expect(copy.syntax == original.syntax, "\(folder) \(appearance) syntax")
            }
            // The macOS look and the wallpapers with their credits come along.
            let look = try #require(draft.dark ?? draft.light)
            #expect(look.wallpapers.count == 3)
            #expect(look.wallpapers.allSatisfy { !$0.license.isEmpty && FileManager.default.fileExists(atPath: $0.file) })
        }
        let amber = try #require(ThemeDraft(theme: try Fixtures.theme("amber"), author: "x").dark)
        #expect(amber.accentColor == "orange" && amber.iconStyle == "tinted" && amber.iconTint == "accent")
    }

    @Test func aCompleteDraftPassesAndEachGapIsNamed() throws {
        let home = try FixtureHome()
        var draft = try Self.draft(in: home)
        #expect(draft.check().filter(\.isError).isEmpty, "\(draft.check())")
        #expect(draft.id == "test-author/night-shift")

        draft.dark!.wallpapers.removeLast()
        draft.light!.wallpapers[0].license = ""            // credits are optional
        draft.license = ""
        draft.dark!.iconTint = nil
        draft.light!.colors["foreground"] = "#e8e8e3"       // almost the background
        draft.light!.colors["red"] = "red"
        draft.author = " "
        let errors = draft.check().filter(\.isError).map(\.message)
        #expect(errors.contains("Add the author's name."))
        #expect(errors.contains("Dark look: add 1 more wallpaper. A theme has 3 for each look."))
        #expect(!errors.contains { $0.localizedCaseInsensitiveContains("license") })
        #expect(errors.contains { $0.hasPrefix("Dark look: tinted icons need a tint") })
        #expect(errors.contains("Light look: Red is “red”, not a color such as #1a1b26."))
        draft.light!.colors["red"] = "#b3243c"
        #expect(draft.check().filter(\.isError).map(\.message).contains { $0.hasPrefix("Light look: Text #e8e8e3 on Background") })
    }

    @Test func writingMakesAThemeSceneLoadsAndKeepsARepositorysFiles() throws {
        let home = try FixtureHome()
        let draft = try Self.draft(in: home)
        let folder = home.path("out/night-shift")
        try home.write("out/night-shift/.git/HEAD", "ref: refs/heads/main\n")
        try home.write("out/night-shift/theme.json", "{}")        // an older export
        try home.write("out/night-shift/LICENSE", "MIT\n")
        try home.write("out/night-shift/wallpapers/dark-4.png", "stale")
        try draft.write(to: folder)

        let names = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("wallpapers").path).sorted()
        #expect(names == ["dark-1.png", "dark-2.png", "dark-3.png", "light-1.png", "light-2.png", "light-3.png"])
        #expect(home.read("out/night-shift/LICENSE") == "MIT\n" && home.read("out/night-shift/.git/HEAD") != nil)
        let readme = try #require(home.read("out/night-shift/README.md"))
        #expect(readme.contains("# Night Shift") && readme.contains("![Night Shift](wallpapers/dark-1.png)"))
        #expect(readme.contains("- `wallpapers/light-3.png`: Test 3.") && !readme.contains("CC0"))

        // Scene installs the folder, .git and all, and gets both looks with their wallpapers and credits.
        let library = ThemeLibrary(bundledFolder: nil, installedFolder: home.path("Themes"))
        let theme = try library.importPackage(at: folder)
        #expect(theme.id == "test-author/night-shift")
        #expect(theme.variants[.dark]?.wallpapers.count == 3 && theme.variants[.light]?.wallpapers.count == 3)
        #expect(theme.variants[.dark]?.system.iconStyle == .tinted && theme.variants[.dark]?.system.accent == .blue)
        #expect(theme.manifest.assets?.count == 6)
        // Opening it again in the Theme Maker gives back the same draft, so saving it replaces the theme.
        let again = ThemeDraft(theme: theme, author: "Test Author")
        #expect(again.name == "Night Shift" && again.id == draft.id)
    }

    @Test func wallpapersWithoutCreditsBuildAndThePreviewKeepsTheMacOSLook() throws {
        let home = try FixtureHome()
        var draft = try Self.draft(in: home)
        draft.license = ""
        for index in 0..<3 {
            draft.dark!.wallpapers[index] = ThemeDraft.Wallpaper(file: draft.dark!.wallpapers[index].file)
            draft.light!.wallpapers[index] = ThemeDraft.Wallpaper(file: draft.light!.wallpapers[index].file)
        }
        #expect(draft.check().filter(\.isError).isEmpty, "\(draft.check())")
        try draft.write(to: home.path("plain"))
        let theme = try ThemeLoader.load(folder: home.path("plain"))
        #expect(theme.manifest.license == "MIT" && theme.manifest.assets == nil)
        #expect(home.read("plain/README.md")?.contains("wallpapers/dark-1.png`:") == false)
        // The preview shows the chosen accent and icon style, so the Theme Maker can draw them.
        let preview = try #require(try draft.preview(only: .dark).variants[.dark])
        #expect(preview.system.accent == .blue && preview.system.iconStyle == .tinted)
        draft.dark!.iconTint = nil
        #expect(try draft.preview(only: .dark).variants[.dark]?.system.iconStyle == nil)
    }

    @Test func aFolderWithOtherFilesIsNotOverwritten() throws {
        let home = try FixtureHome()
        try home.write("Documents/notes.txt", "mine")
        #expect(throws: SceneError.self) { try Self.draft(in: home).write(to: home.path("Documents")) }
        #expect(home.read("Documents/notes.txt") == "mine")
    }

    @Test func commandLineChecksBuildsAndInstalls() throws {
        let home = try FixtureHome()
        // An agent writes the draft with paths relative to the file.
        var draft = try Self.draft(in: home)
        for index in 0..<3 {
            draft.dark!.wallpapers[index].file = "images/dark-\(index + 1).png"
            draft.light!.wallpapers[index].file = "images/light-\(index + 1).png"
        }
        let file = home.path("draft.json")
        try JSONEncoder().encode(draft).write(to: file)

        var output: [String] = []
        var installed: [URL] = []
        #expect(ThemeTool.run(["Scene"], install: { _ in }, print: { output.append($0) }) == nil)
        #expect(ThemeTool.run(["Scene", "--check-theme", file.path], install: { _ in }, print: { output.append($0) }) == 0)
        #expect(output.last == "ok      Night Shift is ready to build")
        let status = ThemeTool.run(["Scene", "--build-theme", file.path, home.path("night-shift").path, "--install"],
                                   install: { installed.append($0) }, print: { output.append($0) })
        #expect(status == 0, "\(output)")
        #expect(installed.map(\.standardizedFileURL.path) == [home.path("night-shift").standardizedFileURL.path])
        #expect(FileManager.default.fileExists(atPath: home.path("night-shift/wallpapers/light-3.png").path))

        draft.light = nil
        draft.dark!.wallpapers.removeFirst()
        try JSONEncoder().encode(draft).write(to: file)
        output = []
        #expect(ThemeTool.run(["Scene", "--build-theme", file.path, home.path("other").path], install: { _ in }, print: { output.append($0) }) == 1)
        #expect(output.contains("error   Dark look: add 1 more wallpaper. A theme has 3 for each look."))
        #expect(!FileManager.default.fileExists(atPath: home.path("other").path))
        #expect(ThemeTool.run(["Scene", "--build-theme", file.path], install: { _ in }, print: { output.append($0) }) == 2)
    }

    @Test func bundledThemesReadWell() throws {
        for folder in ["tokyo-night", "catppuccin", "nord", "amber"] {
            for (appearance, variant) in try Fixtures.theme(folder).variants {
                #expect(PaletteCheck.check(variant).errors.isEmpty, "\(folder) \(appearance): \(PaletteCheck.check(variant).errors)")
            }
        }
    }
}
