import Foundation
@testable import SceneEngine
import SceneThemes
import Testing

/// What following macOS Light/Dark applies, read from the history alone.
@Suite("Following macOS Light/Dark")
struct FollowTests {
    func entry(_ theme: String, _ integrations: [String], _ appearance: Appearance = .dark) -> HistoryEntry {
        HistoryEntry(id: UUID().uuidString, themeID: theme, themeVersion: "1", themeName: theme, mode: .system,
                     integrations: integrations, date: Date(), wallpaper: nil, appearance: appearance)
    }
    let full = ["wallpaper", "appearance", "ghostty"]
    func looks(_ id: String) -> [Appearance]? { id == "one-look" ? [.dark] : id == "gone" ? nil : [.dark, .light] }
    func steps(_ history: [HistoryEntry], systemIsDark: Bool = false) -> [String] {
        history.followSteps(systemIsDark: systemIsDark, available: looks).map { "\($0.entry.themeID) \($0.apps)" }
    }

    @Test func aThemeFollowsWithTheRememberedApps() {
        #expect(steps([entry("a", full)]) == ["a remembered"])
        #expect(steps([entry("a", full)], systemIsDark: true).isEmpty)
        #expect(steps([entry("one-look", full)]).isEmpty)
        #expect(steps([entry("gone", full)]).isEmpty)
    }

    @Test func nextBackgroundStillFollowsWithTheWholeTheme() {
        #expect(steps([entry("a", full), entry("a", ["wallpaper"])]) == ["a remembered"])
    }

    @Test func aWallpaperFromAnotherThemeStaysWhileTheAppsFollow() {
        let history = [entry("a", full), entry("b", ["wallpaper"])]
        #expect(steps(history) == ["a rememberedWithoutWallpaper", "b wallpaperOnly"])
        #expect(history.followSteps(systemIsDark: false, available: looks).map(\.entry.id) == history.map(\.id))
        // A wallpaper with one look keeps it. A theme with one look keeps its apps.
        #expect(steps([entry("a", full), entry("one-look", ["wallpaper"])]) == ["a rememberedWithoutWallpaper"])
        #expect(steps([entry("one-look", full), entry("b", ["wallpaper"])]) == ["b wallpaperOnly"])
        // Only the parts that show the other look apply again.
        #expect(steps([entry("a", full, .light), entry("b", ["wallpaper"])]) == ["b wallpaperOnly"])
    }

    @Test func onlyWallpapersNeverChangeTheApps() {
        let history = [entry("a", ["wallpaper"]), entry("b", ["wallpaper"])]
        #expect(history.currentTheme == nil)
        #expect(steps(history) == ["b wallpaperOnly"])
    }

    @Test func theCurrentThemeIsTheNewestThatChangedMoreThanTheWallpaper() {
        let history = [entry("a", full), entry("b", full), entry("c", ["wallpaper"]), entry("b", ["wallpaper"])]
        #expect(history.currentTheme?.id == history[1].id)
        #expect(history.last?.isWallpaperOnly == true && history[1].isWallpaperOnly == false)
    }
}
