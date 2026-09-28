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
