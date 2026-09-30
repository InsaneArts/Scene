import Foundation
@testable import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("Palette recipes")
struct PaletteRecipeTests {
    /// Resolves a look's colors the way a theme would, for the palette check.
    static func variant(_ colors: [String: String], _ appearance: Appearance) throws -> ResolvedVariant {
        var draft = ThemeDraft(name: "Probe", author: "Probe")
        draft.setLook(ThemeDraft.Look(colors: colors), for: appearance)
        return try #require(try draft.preview().variants[appearance])
    }

    @Test func matchesScenesPythonBuilder() throws {
        let cases: [(Appearance, OKLCH, OKLCH)] = [
            (.dark, OKLCH(0.2, 0.02, 250), OKLCH(0.8, 0.15, 200)),
            (.dark, OKLCH(0.17, 0.045, 30), OKLCH(0.78, 0.17, 60)),
            (.light, OKLCH(0.97, 0.012, 90), OKLCH(0.55, 0.16, 255)),
        ]
        for (appearance, ground, accent) in cases {
            let look = appearance.rawValue
            let script = """
            import json, sys; sys.path.insert(0, "\(Repo.root.appendingPathComponent("Scripts").path)")
            from themekit import build_palette
            p = build_palette("\(look)", (\(ground.l), \(ground.c), \(ground.h)), (\(accent.l), \(accent.c), \(accent.h)))
            print(json.dumps({k: v for k, v in p.items() if k not in ("mode", "darker_background")}))
            """
            let result = try Processes.run("/usr/bin/python3", ["-c", script])
            let python = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: String], "\(result.stderr)")
            let swift = PaletteRecipe(appearance: appearance, ground: ground, accent: accent).colors(readable: false)
            #expect(swift == python, "\(look): \(swift.filter { python[$0.key] != $0.value })")
        }
    }

    @Test func everySliderSettingStaysReadable() throws {
        for appearance in [Appearance.dark, .light] {
            let r = PaletteRecipe.ranges(appearance)
            var failures: [String] = []
            for groundL in stride(from: r.groundLightness.lowerBound, through: r.groundLightness.upperBound, by: (r.groundLightness.upperBound - r.groundLightness.lowerBound) / 3) {
                for text in stride(from: r.text.lowerBound, through: r.text.upperBound, by: (r.text.upperBound - r.text.lowerBound) / 3) {
                    for level in [r.level.lowerBound, r.level.upperBound] {
                        for hue in stride(from: 0.0, to: 360, by: 90) {
                            let recipe = PaletteRecipe(appearance: appearance, ground: OKLCH(groundL, 0.03, hue), text: text,
                                                       accent: OKLCH(appearance == .dark ? 0.8 : 0.55, 0.15, hue + 120), level: level)
                            let errors = PaletteCheck.check(try Self.variant(recipe.colors(), appearance)).errors
                            if !errors.isEmpty { failures.append("L \(groundL) text \(text) level \(level) hue \(hue): \(errors)") }
                        }
                    }
                }
            }
            #expect(failures.isEmpty, "\(appearance): \(failures.count) failing settings, for example \(failures.prefix(3))")
        }
    }

    @Test func fittingATheme() throws {
        let theme = try Fixtures.theme("gruvbox")
        for (appearance, variant) in theme.variants {
            let colors = ThemeDraft(theme: theme, author: "x").look(appearance)!.colors
            let recipe = PaletteRecipe(fitting: colors, appearance: appearance)
            #expect(recipe.ground.rgba == variant.interface.background)
            let rebuilt = recipe.colors()
            // Each hue keeps its angle, so the rebuilt palette stays close to the theme.
            for role in PaletteRecipe.hueOrder {
                let a = OKLCH(RGBA(hex: rebuilt[role]!)!), b = OKLCH(RGBA(hex: colors[role]!)!)
                #expect(abs(PaletteExtraction.gap(a.h, b.h)) < 3, "\(appearance) \(role): \(a.h) vs \(b.h)")
            }
        }
    }

    @Test func aWallpaperGivesAReadablePaletteEveryTime() throws {
        let theme = try Fixtures.theme("amber")
        let wallpapers = theme.variants[.dark]!.wallpapers.map(\.url)
        let first = try #require(PaletteExtraction.palette(from: wallpapers, appearance: .dark))
        let again = try #require(PaletteExtraction.palette(from: wallpapers, appearance: .dark))
        #expect(first == again)
        // Amber's art is orange on near-black: the accent comes out warm, and the palette reads well.
        #expect(first.recipe.accent.h > 20 && first.recipe.accent.h < 100, "accent hue \(first.recipe.accent.h)")
        #expect(first.recipe.ground.l <= 0.23)
        #expect(PaletteCheck.check(try Self.variant(first.recipe.colors(), .dark)).errors.isEmpty)
        let light = try #require(PaletteExtraction.palette(from: wallpapers, appearance: .light))
        #expect(light.recipe.ground.l >= 0.94)
        #expect(PaletteCheck.check(try Self.variant(light.recipe.colors(), .light)).errors.isEmpty)
    }
}
