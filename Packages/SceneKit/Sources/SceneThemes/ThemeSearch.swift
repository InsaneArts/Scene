import Foundation

/// Search and order for the theme lists: the sidebar, the switcher, and the menu bar panel.
public enum ThemeSearch {
    /// True when every word of the query starts a word of the theme's name, tags, authors, or looks ("light", "dark").
    /// Case and accents do not count, so "rose" finds Rosé Pine.
    public static func matches(_ theme: Theme, _ query: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return true }
        let m = theme.manifest
        let have = words(([m.name] + (m.tags ?? []) + m.authors.map(\.name) + theme.availableAppearances.map(\.rawValue)).joined(separator: " "))
        return wanted.allSatisfy { word in have.contains { $0.hasPrefix(word) } }
    }

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The themes that match the query, favorites first. Each group keeps the library's order.
    public static func ordered(_ themes: [Theme], favorites: Set<String>, query: String = "") -> [Theme] {
        let matching = themes.filter { matches($0, query) }
        return matching.filter { favorites.contains($0.id) } + matching.filter { !favorites.contains($0.id) }
    }
}
