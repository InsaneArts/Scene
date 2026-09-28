import Foundation
@testable import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// Each renderer's output is checked by the target app's own parser where the app is installed.
@Suite("Renderers")
struct RendererTests {
    static let ghostty = "/Applications/Ghostty.app/Contents/MacOS/ghostty"
    static let code = "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    static let nvim = Processes.findExecutable("nvim")

    @Test func ghosttyThemeHasEveryColor() throws {
        let v = try #require(try Fixtures.theme("tokyo-night").variants[.dark])
        let text = GhosttyRenderer.themeFile(v, version: SemanticVersion(1, 3, 1))
        #expect(text.contains("background = #1a1b26"))
        #expect((0..<16).allSatisfy { text.contains("palette = \($0)=") })
        #expect(!GhosttyRenderer.themeFile(v, version: SemanticVersion(1, 2, 0)).contains("search-background"))
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: ghostty)))
    func ghosttyAcceptsRenderedFiles() throws {
        let home = try FixtureHome()
        let theme = try Fixtures.theme("catppuccin")
        for (appearance, variant) in theme.variants {
            try home.write(".config/ghostty/themes/\(GhosttyRenderer.themeNames[appearance]!)", GhosttyRenderer.themeFile(variant, version: SemanticVersion(1, 3, 1)))
        }
        try home.write(".config/ghostty/scene.conf", GhosttyRenderer.includeFile(appearances: [.dark, .light], forced: nil))
        try home.write(".config/ghostty/config", "font-size = 14\n\n" + Anchor.block(lines: ["config-file = ?\"\(home.path(".config/ghostty/scene.conf").path)\""], comment: "#") + "\n")
        let validate = try Processes.run(Self.ghostty, ["+validate-config", "--config-file=\(home.path(".config/ghostty/themes/scene-dark").path)"])
        #expect(validate.status == 0, "validate-config: \(validate.stdout) \(validate.stderr)")
        let show = try Processes.run(Self.ghostty, ["+show-config"], environment: ["XDG_CONFIG_HOME": home.path(".config").path, "HOME": home.url.path])
        #expect(show.stdout.contains("theme = light:scene-light,dark:scene-dark"), "show-config: \(show.stdout)")
    }

    @Test func vscodeThemeIsCompleteJSON() throws {
        let v = try #require(try Fixtures.theme("gruvbox").variants[.light])
        let json = try #require(try JSONSerialization.jsonObject(with: VSCodeRenderer.theme(v)) as? [String: Any])
        #expect(json["type"] as? String == "light")
        #expect((json["colors"] as? [String: String])?["editor.background"] == v.interface.background.hex)
        #expect(((json["tokenColors"] as? [[String: Any]])?.count ?? 0) > 15)
    }

    @Test func vscodeExtensionVersionFollowsContent() throws {
        let a = try VSCodeRenderer.extensionFiles(variants: Fixtures.theme("catppuccin").variants)
        let b = try VSCodeRenderer.extensionFiles(variants: Fixtures.theme("gruvbox").variants)
        let a2 = try VSCodeRenderer.extensionFiles(variants: Fixtures.theme("catppuccin").variants)
        #expect(a.version != b.version)
        #expect(a.version == a2.version)
        #expect(try ZipArchive.create(files: a.files) == ZipArchive.create(files: a2.files))   // deterministic package
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: code)))
    func vscodeInstallsGeneratedExtensionIntoIsolatedProfile() throws {
        let home = try FixtureHome()
        let (files, version) = try VSCodeRenderer.extensionFiles(variants: Fixtures.theme("rose-pine").variants)
        let vsix = home.path("scene.vsix")
        try ZipArchive.create(files: files).write(to: vsix)
        let isolation = ["--extensions-dir", home.path("ext").path, "--user-data-dir", home.path("ud").path]
        let install = try Processes.run(Self.code, isolation + ["--install-extension", vsix.path], timeout: 120)
        #expect(install.status == 0, "\(install.stderr)")
        let list = try Processes.run(Self.code, isolation + ["--list-extensions", "--show-versions"], timeout: 120)
        #expect(list.stdout.contains("\(VSCodeRenderer.extensionID)@\(version)"), "\(list.stdout)")
    }

    @Test func itermProfileHasLightAndDarkKeys() throws {
        let data = try ITermRenderer.dynamicProfile(variants: Fixtures.theme("catppuccin").variants, parentGUID: "ABC")
        let profile = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["Profiles"] as? [[String: Any]]).first
        #expect(profile?["Guid"] as? String == ITermRenderer.profileGUID)
        #expect(profile?["Dynamic Profile Parent GUID"] as? String == "ABC")
        #expect(profile?["Use Separate Colors for Light and Dark Mode"] as? Bool == true)
        #expect(profile?["Background Color (Dark)"] != nil && profile?["Background Color (Light)"] != nil)
        #expect(profile?["Ansi 15 Color (Light)"] != nil)
    }

    @Test(.enabled(if: nvim != nil))
    func neovimShimAppliesAndFollowsDataFile() throws {
        let home = try FixtureHome()
        let theme = try Fixtures.theme("catppuccin")
        let dataPath = home.path("support/Neovim/theme.json")
        try home.write(".config/nvim/plugin/scene.lua", try NeovimRenderer.shim(dataPath: dataPath.path))
        try home.write(".config/nvim/colors/scene.lua", NeovimRenderer.colorsFile)
        try FileOps.write(try NeovimRenderer.dataFile(variants: [.dark: theme.variants[.dark]!]), to: dataPath)
        let env = ["XDG_CONFIG_HOME": home.path(".config").path, "XDG_DATA_HOME": home.path(".local/share").path,
                   "XDG_STATE_HOME": home.path(".local/state").path, "XDG_CACHE_HOME": home.path(".cache").path]
        let probe = "lua io.stdout:write(vim.g.colors_name .. ' ' .. string.format('#%06x', vim.api.nvim_get_hl(0, {name='Normal'}).bg) .. ' ' .. vim.o.background)"
        let result = try Processes.run(Self.nvim!.path, ["--headless", "-c", probe, "-c", "qa!"], environment: env)
        #expect(result.stdout == "scene #1e1e2e dark", "stdout: \(result.stdout) stderr: \(result.stderr)")
    }
}
