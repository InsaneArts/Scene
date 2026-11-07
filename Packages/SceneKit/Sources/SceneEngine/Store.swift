import Foundation
import SceneThemes
import SceneFoundation

/// One resource Scene has touched, with its value before Scene and the value Scene last wrote.
public struct LedgerEntry: Codable, Sendable {
    public var sequence: Int
    public var resource: String
    public var integration: String
    /// The last operation for this resource, with file contents removed.
    public var operation: Operation
    public var original: ResourceState
    public var applied: ResourceState
    public var firstTouched: Date
    public var lastApplied: Date
}

public struct JournalStep: Codable, Sendable {
    public var integration: String
    public var resource: String
    public var summary: String
    public var state: String   // pending, applied, failed, rolledBack
}

public struct JournalRun: Codable, Sendable, Identifiable {
    public var id: String
    public var themeID: String
    public var themeName: String
    public var started: Date
    public var completed: Bool
    public var steps: [JournalStep]
}

public struct HistoryEntry: Codable, Sendable, Identifiable {
    public var id: String
    public var themeID: String
    public var themeVersion: String
    public var themeName: String
    public var mode: AppearanceMode
    public var integrations: [String]
    public var date: Date
    /// The file name of the wallpaper this apply showed. Undo shows it again.
    public var wallpaper: String?
    /// The look this apply showed. Nil in entries from before Scene recorded it.
    public var appearance: Appearance?

    /// Following macOS Light/Dark applies the theme again when it has both looks and shows the other one.
    /// A theme with one look never changes macOS back.
    public func needsOtherLook(available: [Appearance], systemIsDark: Bool) -> Bool {
        available.count == 2 && appearance != (systemIsDark ? .dark : .light)
    }

    /// The apply changed only the wallpaper: Next Background, Set as Wallpaper, or an Apply with only Wallpaper checked.
    public var isWallpaperOnly: Bool { integrations == ["wallpaper"] }
}

/// One apply that following macOS Light/Dark makes. It takes the place of `entry` in the history.
public struct FollowStep: Sendable {
    public enum Apps: Sendable, Equatable {
        /// The apps you chose to change with themes.
        case remembered
        /// Those apps without the wallpaper, because the wallpaper on screen came from another theme.
        case rememberedWithoutWallpaper
        case wallpaperOnly
    }
    public var entry: HistoryEntry
    public var apps: Apps
}

extension Array where Element == HistoryEntry {
    /// The newest entry that changed more than the wallpaper: the theme your apps show. Nil when Scene has only changed wallpapers.
    public var currentTheme: HistoryEntry? { last { !$0.isWallpaperOnly } }

    /// What following macOS Light/Dark applies. When the wallpaper came from another theme, the current theme's apps
    /// and that wallpaper each switch look on their own, so the wallpaper stays and the apps keep following macOS.
    /// - Parameter available: The looks of a theme, by id. Nil for a theme that is no longer installed.
    public func followSteps(systemIsDark: Bool, available: (String) -> [Appearance]?) -> [FollowStep] {
        func needsOtherLook(_ entry: HistoryEntry) -> Bool {
            available(entry.themeID).map { entry.needsOtherLook(available: $0, systemIsDark: systemIsDark) } ?? false
        }
        guard let newest = last else { return [] }
        let theme = currentTheme
        if !newest.isWallpaperOnly || theme?.themeID == newest.themeID {
            return needsOtherLook(newest) ? [FollowStep(entry: newest, apps: .remembered)] : []
        }
        var steps: [FollowStep] = []
        if let theme, needsOtherLook(theme) { steps.append(FollowStep(entry: theme, apps: .rememberedWithoutWallpaper)) }
        if needsOtherLook(newest) { steps.append(FollowStep(entry: newest, apps: .wallpaperOnly)) }
        return steps
    }
}

/// Persistence under ~/Library/Application Support/Scene. Every write is atomic.
public final class EngineStore: @unchecked Sendable {
    public let root: URL
    public var backups: URL { root.appendingPathComponent("Backups") }
    var ledgerURL: URL { root.appendingPathComponent("Ledger.json") }
    var historyURL: URL { root.appendingPathComponent("History.json") }
    var journalDir: URL { root.appendingPathComponent("Journal") }

    public init(root: URL) { self.root = root }

    let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }()
    let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()

    public func loadLedger() -> [String: LedgerEntry] {
        guard let data = FileOps.read(ledgerURL), let list = try? decoder.decode([LedgerEntry].self, from: data) else { return [:] }
        return Dictionary(list.map { ($0.resource, $0) }, uniquingKeysWith: { $1 })
    }

    public func saveLedger(_ ledger: [String: LedgerEntry]) throws {
        try FileOps.write(encoder.encode(ledger.values.sorted { $0.sequence < $1.sequence }), to: ledgerURL)
    }

    public func loadHistory() -> [HistoryEntry] {
        guard let data = FileOps.read(historyURL) else { return [] }
        return (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    public func saveHistory(_ history: [HistoryEntry]) throws {
        try FileOps.write(encoder.encode(Array(history.suffix(50))), to: historyURL)
    }

    public func save(_ run: JournalRun) throws {
        try FileOps.write(encoder.encode(run), to: journalDir.appendingPathComponent("\(run.id).json"))
    }

    public func unfinishedRuns() -> [JournalRun] {
        let files = (try? FileManager.default.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { FileOps.read($0).flatMap { try? decoder.decode(JournalRun.self, from: $0) } }
            .filter { !$0.completed }
            .sorted { $0.started < $1.started }
    }

    public func discard(_ run: JournalRun) {
        try? FileManager.default.removeItem(at: journalDir.appendingPathComponent("\(run.id).json"))
    }
}
