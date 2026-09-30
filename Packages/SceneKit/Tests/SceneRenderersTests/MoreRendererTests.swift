import AppKit
import Foundation
@testable import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// Output of the renderers added after the MVP, read back by each app's own parser where it is installed.
/// Every run uses its own folders, and tmux its own server, so nothing touches the real setup.
@Suite("More renderers")
struct MoreRendererTests {
    static let kitty = "/Applications/kitty.app/Contents/MacOS/kitty"
    static let tmux = Processes.findExecutable("tmux")
    static let bat = Processes.findExecutable("bat")
    static let delta = Processes.findExecutable("delta")

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: kitty)))
    func kittyLoadsTheRenderedColors() throws {
        let home = try FixtureHome()
        let v = try #require(try Fixtures.theme("tokyo-night").variants[.dark])
        try home.write("kitty/scene-theme.conf", KittyRenderer.themeFile(v))
        try home.write("kitty/kitty.conf", "font_size 13\ninclude scene-theme.conf\n")
        let probe = "from kitty.config import load_config; import sys; o = load_config(sys.argv[-1]); print(o.background, o.color4, o.active_tab_background)"
        let result = try Processes.run(Self.kitty, ["+runpy", probe, home.path("kitty/kitty.conf").path],
                                       environment: ["KITTY_CONFIG_DIRECTORY": home.path("kitty").path])
        func color(_ c: RGBA) -> String { "Color(\(c.r), \(c.g), \(c.b))" }
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                == [v.terminal.background, v.terminal.ansi[4], v.interface.accent].map(color).joined(separator: " "),
                "stdout: \(result.stdout) stderr: \(result.stderr)")
    }

    @Test(.enabled(if: tmux != nil))
    func tmuxAcceptsEveryOption() throws {
        let home = try FixtureHome()
        let v = try #require(try Fixtures.theme("gruvbox").variants[.light])
        let file = try home.write("scene.conf", TmuxRenderer.configFile(v))
        let socket = "scene-test-\(UUID().uuidString.prefix(8))"
        let tmux = Self.tmux!.path
        defer {
            _ = try? Processes.run(tmux, ["-L", socket, "kill-server"])
            try? FileManager.default.removeItem(atPath: "/private/tmp/tmux-\(getuid())/\(socket)")
        }
        #expect(try Processes.run(tmux, ["-L", socket, "-f", "/dev/null", "new-session", "-d"]).status == 0)
        // Without -q, an option this tmux does not know would fail here.
        let strict = TmuxRenderer.configFile(v).replacingOccurrences(of: "set -gq ", with: "set -g ")
        try home.write("strict.conf", strict)
        let source = try Processes.run(tmux, ["-L", socket, "source-file", home.path("strict.conf").path])
        #expect(source.status == 0, "\(source.stderr)")
        _ = try Processes.run(tmux, ["-L", socket, "source-file", file.path])
        let shown = try Processes.run(tmux, ["-L", socket, "show", "-gv", "status-style"])
        #expect(shown.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "bg=\(v.interface.surface.hex),fg=\(v.interface.foreground.hex)")
        let current = try Processes.run(tmux, ["-L", socket, "show", "-gwv", "window-status-current-style"])
        #expect(current.stdout.contains("bg=\(v.interface.accent.hex)"))
    }

    @Test(.enabled(if: bat != nil))
    func batAndDeltaLoadTheThemes() throws {
        let home = try FixtureHome()
        let theme = try Fixtures.theme("catppuccin")
        for (appearance, name) in BatRenderer.names {
            try FileOps.write(try BatRenderer.tmTheme(theme.variants[appearance]!, name: name), to: home.path(".config/bat/themes/\(name).tmTheme"))
        }
        let env = ["HOME": home.url.path, "XDG_CONFIG_HOME": home.path(".config").path, "XDG_CACHE_HOME": home.path(".cache").path,
                   "BAT_CONFIG_DIR": home.path(".config/bat").path, "BAT_CACHE_PATH": home.path(".cache/bat").path,
                   "BAT_CONFIG_PATH": home.path(".config/bat/config").path, "GIT_CONFIG_NOSYSTEM": "1", "COLORTERM": "truecolor"]
        let build = try Processes.run(Self.bat!.path, ["cache", "--build"], environment: env)
        #expect(build.status == 0, "\(build.stderr)")
        let list = try Processes.run(Self.bat!.path, ["--list-themes", "--color=never"], environment: env)
        #expect(list.stdout.contains("scene-dark") && list.stdout.contains("scene-light"), "\(list.stdout)")
        // The syntax colors reach the terminal: a Rust keyword in catppuccin's keyword color.
        try home.write("a.rs", "fn main() {}\n")
        let shown = try Processes.run(Self.bat!.path, ["--color=always", "--paging=never", "--style=plain", "--theme=scene-dark", home.path("a.rs").path],
                                      environment: env)
        let keyword = theme.variants[.dark]!.syntax.keyword.color
        #expect(shown.stdout.contains("38;2;\(keyword.r);\(keyword.g);\(keyword.b)m"), "\(shown.stdout.debugDescription)")

        guard let delta = Self.delta else { return }
        try home.write(".config/git/scene-delta.gitconfig", BatRenderer.deltaConfig(theme.variants[.dark]!))
        try home.write(".gitconfig", "[include]\n\tpath = \"\(home.path(".config/git/scene-delta.gitconfig").path)\"\n")
        let config = try Processes.run(delta.path, ["--show-config"], environment: env)
        #expect(config.stdout.contains("syntax-theme                  = scene-dark"), "\(config.stdout)")
        #expect(!config.stderr.contains("Unknown theme"), "\(config.stderr)")
    }

    /// A Python with tomllib, to read TOML the way a TOML parser does. Helix and Alacritty are not installed on the test Mac.
    static let python: String? = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3"].first { path in
        FileManager.default.isExecutableFile(atPath: path) && (try? Processes.run(path, ["-c", "import tomllib"]).status) == 0
    }

    static func parseTOML(_ text: String) throws -> [String: Any] {
        let home = try FixtureHome()
        let file = try home.write("x.toml", text)
        let result = try Processes.run(python!, ["-c", "import tomllib, json, sys; print(json.dumps(tomllib.load(open(sys.argv[1], 'rb'))))", file.path])
        guard result.status == 0 else { throw SceneError.failed(result.stderr) }
        return try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] ?? [:]
    }

    @Test(.enabled(if: python != nil))
    func alacrittyAndHelixFilesAreValidTOML() throws {
        let v = try #require(try Fixtures.theme("everforest").variants[.dark])
        let alacritty = try Self.parseTOML(AlacrittyRenderer.themeFile(v))
        let colors = try #require(alacritty["colors"] as? [String: Any])
        #expect((colors["primary"] as? [String: String])?["background"] == v.terminal.background.hex)
        #expect((colors["bright"] as? [String: String])?["white"] == v.terminal.ansi[15].hex)
        #expect(((colors["search"] as? [String: Any])?["focused_match"] as? [String: String])?["background"] == v.interface.accent.hex)
        let helix = try Self.parseTOML(HelixRenderer.themeFile(v))
        #expect((helix["ui.background"] as? [String: String])?["bg"] == v.interface.background.hex)
        #expect(((helix["diagnostic.error"] as? [String: Any])?["underline"] as? [String: String])?["style"] == "curl")
        #expect(helix["keyword"] != nil && helix["ui.statusline.normal"] != nil)
        // An edited user config stays valid TOML, with the import in the [general] table.
        var doc = KeyValueDocument(text: "[general]\nlive_config_reload = true\n\n[font]\nsize = 13\n")
        doc.set("[\"/a/scene.toml\"]", forKey: "import", inTable: "general")
        let config = try Self.parseTOML(doc.text)
        #expect((config["general"] as? [String: Any])?["import"] as? [String] == ["/a/scene.toml"])
    }

    @Test(.enabled(if: python != nil))
    func warpSettingsStayValidTOML() throws {
        var doc = KeyValueDocument(text: "[appearance.text]\nfont_name = \"JetBrains Mono\"\n")
        let entry = { (look: String) in
            "{ custom = { name = \(KeyValueDocument.quoted("Scene: scene/nord (\(look))")), path = \(KeyValueDocument.quoted("/Users/me/.warp/themes/scene/scene-nord-\(look).yaml")) } }"
        }
        doc.set(entry("dark"), forKey: "theme", inTable: "appearance.themes")
        doc.set("true", forKey: "system_theme", inTable: "appearance.themes")
        doc.set("{ light = \(entry("light")), dark = \(entry("dark")) }", forKey: "selected_system_themes", inTable: "appearance.themes")
        let parsed = try Self.parseTOML(doc.text)
        let themes = try #require((parsed["appearance"] as? [String: Any])?["themes"] as? [String: Any])
        #expect(themes["system_theme"] as? Bool == true)
        let custom = ((themes["selected_system_themes"] as? [String: Any])?["light"] as? [String: Any])?["custom"] as? [String: String]
        #expect(custom?["name"] == "Scene: scene/nord (light)")
        #expect((((parsed["appearance"] as? [String: Any])?["text"] as? [String: String])?["font_name"]) == "JetBrains Mono")
    }

    @Test func btopThemeHasEveryKey() throws {
        let v = try #require(try Fixtures.theme("nord").variants[.dark])
        let lines = BtopRenderer.themeFile(v).split(separator: "\n").dropFirst()
        #expect(lines.count == 42)
        #expect(lines.allSatisfy { $0.range(of: ##"^theme\[[a-z_]+\]="#[0-9a-f]{6}"$"##, options: .regularExpression) != nil })
        #expect(lines.contains("theme[main_bg]=\"\(v.interface.background.hex)\""))
    }

    @Test func xcodeThemeIsAPropertyListXcodeCanRead() throws {
        let v = try #require(try Fixtures.theme("rose-pine").variants[.dark])
        let data = try XcodeRenderer.theme(v, base: ["DVTMarkupTextNormalFont": "Avenir - 13.0", "DVTSourceTextSyntaxColors": ["xcode.syntax.future": "1 0 0 1"]])
        let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["DVTSourceTextBackground"] as? String == XcodeRenderer.string(v.interface.background))
        #expect(plist["DVTMarkupTextNormalFont"] as? String == "Avenir - 13.0")
        let syntax = try #require(plist["DVTSourceTextSyntaxColors"] as? [String: String])
        #expect(syntax["xcode.syntax.keyword"] == XcodeRenderer.string(v.syntax.keyword.color))
        #expect(syntax["xcode.syntax.future"] == XcodeRenderer.string(v.interface.foreground))
        // Every color is four numbers from 0 to 1, as in Xcode's own themes.
        for value in syntax.values {
            let parts = value.split(separator: " ").compactMap { Double($0) }
            #expect(parts.count == 4 && parts.allSatisfy { (0...1).contains($0) }, "\(value)")
        }
        let home = try FixtureHome()
        let file = try home.write("t.xccolortheme", String(decoding: data, as: UTF8.self))
        #expect(try Processes.run("/usr/bin/plutil", ["-lint", file.path]).status == 0)
    }

    @Test func terminalColorsAreNSColorArchives() throws {
        let v = try #require(try Fixtures.theme("nord").variants[.dark])
        let colors = try TerminalAppRenderer.colors(v)
        #expect(colors.count == 21)
        let background = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colors["BackgroundColor"]!))
        let srgb = try #require(background.usingColorSpace(.sRGB))
        #expect(abs(srgb.redComponent - v.terminal.background.red) < 0.002 && abs(srgb.blueComponent - v.terminal.background.blue) < 0.002)
    }

    @Test func zedFamilyHasBothThemes() throws {
        let data = try ZedRenderer.themeFile(variants: Fixtures.theme("gruvbox").variants)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let themes = try #require(json["themes"] as? [[String: Any]])
        #expect(themes.compactMap { $0["name"] as? String } == ["Scene Dark", "Scene Light"])
        #expect(themes.compactMap { $0["appearance"] as? String } == ["dark", "light"])
        let style = try #require(themes[0]["style"] as? [String: Any])
        #expect((style["editor.background"] as? String)?.count == 9)
        #expect(((style["syntax"] as? [String: Any])?["keyword"] as? [String: Any])?["color"] != nil)
        #expect((style["players"] as? [[String: String]])?.first?["selection"] != nil)
        // A dark-only theme still names both, so a setting for either one resolves.
        let single = try ZedRenderer.themeFile(variants: Fixtures.theme("tokyo-night").variants)
        let names = ((try JSONSerialization.jsonObject(with: single) as? [String: Any])?["themes"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["Scene Dark", "Scene Light"])
    }
}
