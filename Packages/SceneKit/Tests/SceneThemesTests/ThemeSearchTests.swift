import Foundation
import SceneThemes
import SceneTestSupport
import Testing

@Suite("Theme search")
struct ThemeSearchTests {
    static let themes = ["catppuccin", "gruvbox", "nord", "tokyo-night", "rose-pine"].compactMap { try? Fixtures.theme($0) }
        .sorted { $0.manifest.name < $1.manifest.name }

    @Test func matchesNameTagsAndLooksWithoutCaseOrAccents() throws {
        let nord = try #require(Self.themes.first { $0.manifest.name == "Nord" })
        #expect(ThemeSearch.matches(nord, "nor"))
        #expect(ThemeSearch.matches(nord, "NORD"))
        #expect(ThemeSearch.matches(nord, "  "))
        #expect(!ThemeSearch.matches(nord, "gruv"))
        #expect(!ThemeSearch.matches(nord, "ord"))
        #expect(!ThemeSearch.matches(nord, "arctic"))   // summaries are not searched
        let rose = try #require(Self.themes.first { $0.id.hasSuffix("rose-pine") })
        #expect(ThemeSearch.matches(rose, "rosé"))
        #expect(ThemeSearch.matches(rose, "rose pi"))
        let tokyo = try #require(Self.themes.first { $0.id.hasSuffix("tokyo-night") })
        #expect(ThemeSearch.matches(tokyo, "night dark"))
        #expect(!ThemeSearch.matches(tokyo, "night light"))
    }

    @Test func favoritesComeFirstAndEachGroupKeepsItsOrder() {
        let favorites: Set = [Self.themes[3].id, Self.themes[1].id]
        let ordered = ThemeSearch.ordered(Self.themes, favorites: favorites)
        #expect(ordered.map(\.id) == [Self.themes[1].id, Self.themes[3].id, Self.themes[0].id, Self.themes[2].id, Self.themes[4].id])
        #expect(ThemeSearch.ordered(Self.themes, favorites: favorites, query: "zzz").isEmpty)
    }
}
