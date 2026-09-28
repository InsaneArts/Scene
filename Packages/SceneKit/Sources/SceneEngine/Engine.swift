import Foundation
import SceneThemes
import SceneFoundation

public struct PlannedIntegration: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: IntegrationKind
    public var detection: Detection
    public var plan: IntegrationPlan?
    public var error: String?
}

/// Applies plans, records originals, journals every step, verifies results, and restores.
/// There is no transaction across apps: each app succeeds, or is rolled back, on its own.
public actor Engine {
    public nonisolated let env: SceneEnvironment
    public nonisolated let services: SystemServices
    public nonisolated let integrations: [Integration]
    let store: EngineStore
    var ledger: [String: LedgerEntry]
    var nextSequence: Int

    public init(env: SceneEnvironment, services: SystemServices, integrations: [Integration], store: EngineStore? = nil) {
        self.env = env
        self.services = services
        self.integrations = integrations
        self.store = store ?? EngineStore(root: env.appSupport)
        let loaded = self.store.loadLedger()
        self.ledger = loaded
        self.nextSequence = (loaded.values.map(\.sequence).max() ?? 0) + 1
    }

    // MARK: Detect and plan

    public func detectAll() async -> [String: Detection] {
        await withTaskGroup(of: (String, Detection).self) { group in
            for integration in integrations {
                group.addTask { [env, services] in (integration.id, await integration.detect(env, services)) }
            }
            var out: [String: Detection] = [:]
            for await (id, detection) in group { out[id] = detection }
            return out
        }
    }

    public func plan(_ request: ApplyRequest, detections: [String: Detection]) -> [PlannedIntegration] {
        integrations.map { integration in
            let detection = detections[integration.id] ?? .notInstalled()
            var item = PlannedIntegration(id: integration.id, name: integration.displayName, kind: integration.kind, detection: detection)
            guard detection.installed else { return item }
            if case .blocked(let reason) = detection.setup { item.error = reason; return item }
            do { item.plan = try integration.plan(request, detection, env) } catch { item.error = "\(error)" }
            return item
        }
    }

    // MARK: Apply

    public func apply(_ request: ApplyRequest, planned: [PlannedIntegration], selected: Set<String>,
                      progress: @escaping @Sendable (String) -> Void = { _ in }) async -> ApplyReport {
        run = JournalRun(id: UUID().uuidString, themeID: request.theme.id, themeName: request.theme.manifest.name,
                         started: Date(), completed: false, steps: [])
        saveRun()
        // Apps are independent, so they apply in parallel. Engine state changes stay serialized on this actor.
        let items = planned.filter { selected.contains($0.id) }
        var results: [String: IntegrationResult] = [:]
        await withTaskGroup(of: IntegrationResult?.self) { group in
            for item in items {
                group.addTask { await self.applyOne(item, progress: progress) }
            }
            for await result in group { if let result { results[result.id] = result } }
        }
        let ordered = items.compactMap { results[$0.id] }

        run?.completed = true
        saveRun()
        if let run { store.discard(run) }
        run = nil
        let succeeded = ordered.filter { $0.outcome.isSuccess || { if case .needsAction = $0.outcome { true } else { false } }($0) }.map(\.id)
        if !succeeded.isEmpty {
            var history = store.loadHistory()
            history.append(HistoryEntry(id: UUID().uuidString, themeID: request.theme.id, themeVersion: request.theme.manifest.version,
                                        themeName: request.theme.manifest.name, mode: request.mode, integrations: succeeded, date: Date(),
                                        wallpaper: request.wallpaper?.name))
            try? store.saveHistory(history)
        }
        return ApplyReport(themeName: request.theme.manifest.name, results: ordered, date: Date())
    }

    var run: JournalRun?

    func saveRun() { if let run { try? store.save(run) } }

    func journal(_ step: JournalStep) -> Int {
        run?.steps.append(step)
        saveRun()
        return (run?.steps.count ?? 1) - 1
    }

    func journal(_ index: Int, state: String) {
        guard let run, run.steps.indices.contains(index) else { return }
        self.run?.steps[index].state = state
        saveRun()
    }

    /// Applies one app: operations in order, each journaled; on failure, that app's operations are undone.
    func applyOne(_ item: PlannedIntegration, progress: @escaping @Sendable (String) -> Void) async -> IntegrationResult? {
        guard let plan = item.plan, let integration = integrations.first(where: { $0.id == item.id }) else {
            guard let error = item.error else { return nil }
            if case .blocked = item.detection.setup { return IntegrationResult(id: item.id, name: item.name, outcome: .skipped(error), operations: [], notes: []) }
            return IntegrationResult(id: item.id, name: item.name, outcome: .failed(error), operations: [], notes: [])
        }
        if plan.operations.isEmpty {
            return IntegrationResult(id: item.id, name: item.name, outcome: .skipped(plan.notes.first ?? "Nothing to change"), operations: [], notes: plan.notes)
        }
        progress("Applying \(item.name)…")
        var executed: [(Operation, ResourceState, Data?)] = []
        var failure: String?
        for op in plan.operations {
            let resource = op.resource
            let before = await state(of: op)
            let beforeBytes = fileBytes(for: op)
            let firstTouch = ledger[resource] == nil
            var step = -1
            do {
                if firstTouch {
                    let original = try await captureOriginal(op, current: before)
                    ledger[resource] = LedgerEntry(sequence: nextSequence, resource: resource, integration: item.id, operation: op.stripped,
                                                   original: original, applied: before, firstTouched: Date(), lastApplied: Date())
                    nextSequence += 1
                    try store.saveLedger(ledger)
                }
                step = journal(JournalStep(integration: item.id, resource: resource, summary: op.summary, state: "pending"))
                let applied = try await execute(op)
                ledger[resource]?.applied = applied
                ledger[resource]?.operation = op.stripped
                ledger[resource]?.lastApplied = Date()
                try store.saveLedger(ledger)
                journal(step, state: "applied")
                executed.append((op, before, beforeBytes))
            } catch {
                failure = "\(op.summary): \(error)"
                // Nothing was applied for this resource, so a record created for it now is dropped.
                if firstTouch { ledger[resource] = nil; try? store.saveLedger(ledger) }
                journal(step, state: "failed")
                break
            }
        }

        if let failure {
            for (op, before, bytes) in executed.reversed() {
                try? await revert(op, to: before, fileBytes: bytes)
                if let entry = ledger[op.resource] {
                    if entry.original == before { ledger[op.resource] = nil } else { ledger[op.resource]?.applied = before }
                }
            }
            try? store.saveLedger(ledger)
            return IntegrationResult(id: item.id, name: item.name, outcome: .failed(failure + " Scene undid this app's changes."),
                                     operations: plan.operations.map(\.summary), notes: plan.notes)
        }

        let reload = await integration.reload(item.detection, env, services)
        let verification = await integration.verify(plan, item.detection, env, services)
        var outcome: Outcome = .applied
        switch verification {
        case .mismatch(let reason): outcome = .failed(reason)
        case .overridden(let keys): outcome = .appliedPartlyOverridden(keys)
        case .matches: break
        }
        if outcome.isSuccess {
            switch reload {
            case .needsRestart(let why): outcome = .appliedRestartNeeded(why)
            case .needsUserAction(let what): outcome = .needsAction(what)
            case .failed(let why): outcome = .appliedRestartNeeded("Could not reload it (\(why)). Restart the app to see the theme.")
            default: break
            }
            for requirement in plan.requirements {
                if case .oneTimeSetup(let step) = requirement, case .applied = outcome { outcome = .needsAction(step) }
            }
        }
        return IntegrationResult(id: item.id, name: item.name, outcome: outcome, operations: plan.operations.map(\.summary), notes: plan.notes)
    }

    // MARK: Restore

    /// Restores what Scene changed, using the three-way rule: a value Scene wrote goes back to the
    /// original; a value someone changed after Scene stays as it is.
    public func restoreOriginal(only integrationIDs: Set<String>? = nil,
                                progress: @escaping @Sendable (String) -> Void = { _ in }) async -> [RestoreItem] {
        var items: [RestoreItem] = []
        let entries = ledger.values
            .filter { integrationIDs == nil || integrationIDs!.contains($0.integration) }
            .sorted { $0.sequence > $1.sequence }
        for entry in entries {
            progress("Restoring \(entry.integration)…")
            let op = entry.operation
            let current = await state(of: op)
            var result = "Restored"
            var kept = false
            do {
                if Self.matches(current, entry.applied) {
                    try await revert(op, to: entry.original, fileBytes: nil, fromBackups: true)
                } else if Self.matches(current, entry.original) {
                    result = "Already as before"
                } else {
                    kept = true
                    result = "Changed after Scene applied its theme. Scene kept your change."
                }
                ledger[entry.resource] = nil
            } catch {
                result = "Could not restore: \(error)"
            }
            items.append(RestoreItem(resource: entry.resource, integration: entry.integration, result: result, keptUserChange: kept))
        }
        try? store.saveLedger(ledger)
        if integrationIDs == nil {
            var history = store.loadHistory()
            history.removeAll()
            try? store.saveHistory(history)
        }
        // Running apps must reload, or they keep showing the theme until their next restart.
        for id in Set(entries.map(\.integration)) {
            guard let integration = integrations.first(where: { $0.id == id }) else { continue }
            let detection = await integration.detect(env, services)
            if detection.installed { _ = await integration.reload(detection, env, services) }
        }
        return items
    }

    /// Goes back to the previous theme in the history, or to the original setup if there is none.
    public func undo(resolveTheme: @Sendable (String, String) -> Theme?, systemIsDark: Bool,
                     progress: @escaping @Sendable (String) -> Void = { _ in }) async -> ApplyReport? {
        var history = store.loadHistory()
        guard !history.isEmpty else { return nil }
        history.removeLast()
        try? store.saveHistory(history)
        guard let previous = history.last, let theme = resolveTheme(previous.themeID, previous.themeVersion) else {
            let restored = await restoreOriginal(progress: progress)
            return ApplyReport(themeName: "Original setup", results: restored.map {
                IntegrationResult(id: $0.resource, name: $0.integration, outcome: $0.keptUserChange ? .skipped($0.result) : .applied, operations: [$0.resource], notes: [])
            }, date: Date())
        }
        var request = ApplyRequest(theme: theme, mode: previous.mode, systemIsDark: systemIsDark)
        request.wallpaperName = previous.wallpaper
        let detections = await detectAll()
        let planned = plan(request, detections: detections)
        history.removeLast()
        try? store.saveHistory(history)
        return await apply(request, planned: planned, selected: Set(previous.integrations), progress: progress)
    }

    // MARK: Queries

    public func history() -> [HistoryEntry] { store.loadHistory() }
    public func ledgerEntries() -> [LedgerEntry] { ledger.values.sorted { $0.sequence < $1.sequence } }
    public func unfinishedRuns() -> [JournalRun] { store.unfinishedRuns() }
    public func discard(_ run: JournalRun) { store.discard(run) }

    /// Resources whose current value differs from what Scene last wrote, grouped by integration.
    public func changesOutsideScene() async -> [String: [String]] {
        var out: [String: [String]] = [:]
        for entry in ledger.values {
            let current = await state(of: entry.operation)
            if !Self.matches(current, entry.applied) { out[entry.integration, default: []].append(entry.resource) }
        }
        return out
    }

    // MARK: Operation mechanics

    func state(of op: Operation) async -> ResourceState {
        switch op {
        case .writeManagedFile(let path, _):
            guard let hash = FileOps.sha256(fileAt: URL(fileURLWithPath: path)) else { return .absent }
            return .file(sha256: hash, backup: nil)
        case .ensureAnchor(let path, _, _):
            let url = URL(fileURLWithPath: path)
            guard let data = FileOps.read(FileOps.resolvedTarget(url)) else { return .anchor(block: nil, fileBackup: nil, fileExisted: false) }
            return .anchor(block: Anchor.existingBlock(in: String(decoding: data, as: UTF8.self)), fileBackup: nil, fileExisted: true)
        case .setJSONValue(let path, let key, _):
            guard let data = FileOps.read(URL(fileURLWithPath: path)) else { return .absent }
            guard let document = try? JSONCDocument(text: String(decoding: data, as: UTF8.self)) else { return .json(.string("<unreadable>")) }
            return .json(document.value(forKey: key))
        case .setPreference(let domain, let key, _):
            return .plist(services.preference(domain: domain, key: key))
        case .setWallpaper(let id, _, _):
            return .wallpaper(path: await services.wallpaper(displayID: id))
        case .setAppearance:
            let a = await services.appearance()
            return .appearance(dark: a.dark, auto: a.auto)
        case .installEditorExtension(let cli, _, let id, _):
            return .extensionVersion(await installedExtensionVersion(cli: cli, id: id))
        case .setTweak(let id, _):
            return .tweak((try? await services.tweakGet(id)) ?? .null)
        }
    }

    func fileBytes(for op: Operation) -> Data? {
        switch op {
        case .writeManagedFile(let path, _), .ensureAnchor(let path, _, _), .setJSONValue(let path, _, _):
            return FileOps.read(FileOps.resolvedTarget(URL(fileURLWithPath: path)))
        default: return nil
        }
    }

    func captureOriginal(_ op: Operation, current: ResourceState) async throws -> ResourceState {
        switch (op, current) {
        case (.writeManagedFile(let path, _), .file(let hash, _)):
            return .file(sha256: hash, backup: try FileOps.backup(URL(fileURLWithPath: path), into: store.backups))
        case (.ensureAnchor(let path, _, _), .anchor(let block, _, let existed)):
            let backup = existed ? try FileOps.backup(URL(fileURLWithPath: path), into: store.backups) : nil
            return .anchor(block: block, fileBackup: backup, fileExisted: existed)
        default:
            return current
        }
    }

    func execute(_ op: Operation) async throws -> ResourceState {
        switch op {
        case .writeManagedFile(let path, let contents):
            try FileOps.write(contents, to: URL(fileURLWithPath: path))
            return .file(sha256: FileOps.sha256(contents), backup: nil)
        case .ensureAnchor(let path, let block, let placement):
            let url = URL(fileURLWithPath: path)
            let existed = FileOps.exists(FileOps.resolvedTarget(url))
            guard FileOps.isWritable(url) else { throw SceneError.failed("\(Operation.tilde(path)) is read-only") }
            let text = FileOps.read(FileOps.resolvedTarget(url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            let updated = Anchor.insert(block, into: text, placement: placement)
            if updated != text { try FileOps.write(updated, to: url) }
            return .anchor(block: block, fileBackup: nil, fileExisted: existed)
        case .setJSONValue(let path, let key, let value):
            let url = URL(fileURLWithPath: path)
            let text = FileOps.read(FileOps.resolvedTarget(url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            var document = try JSONCDocument(text: text)
            try document.set(value, forKey: key)
            if document.text != text { try FileOps.write(document.text, to: url) }
            return .json(value)
        case .setPreference(let domain, let key, let value):
            try services.setPreference(domain: domain, key: key, value: value)
            return .plist(value)
        case .setWallpaper(let id, let path, let fit):
            try await services.setWallpaper(displayID: id, path: path, fit: fit)
            return .wallpaper(path: path)
        case .setAppearance(let dark):
            try await services.setAppearance(dark: dark)
            return .appearance(dark: dark, auto: false)
        case .installEditorExtension(let cli, let packagePath, let id, let version):
            let result = try await services.run(cli, ["--install-extension", packagePath, "--force"], environment: nil)
            guard result.status == 0 else { throw SceneError.failed("install failed: \(result.stderr.prefix(300))") }
            guard await installedExtensionVersion(cli: cli, id: id) == version else {
                throw SceneError.failed("the editor did not report Scene Themes \(version) as installed")
            }
            return .extensionVersion(version)
        case .setTweak(let id, let value):
            let readBack = try await services.tweakSet(id, value)
            return .tweak(readBack)
        }
    }

    /// Puts a resource into `target`. `fileBytes` carries the in-memory copy taken before a failed apply;
    /// `fromBackups` uses the backup folder for originals.
    func revert(_ op: Operation, to target: ResourceState, fileBytes: Data?, fromBackups: Bool = false) async throws {
        switch (op, target) {
        case (.writeManagedFile(let path, _), .absent):
            try FileOps.delete(URL(fileURLWithPath: path))
        case (.writeManagedFile(let path, _), .file(_, let backup)):
            if let bytes = fileBytes { try FileOps.write(bytes, to: URL(fileURLWithPath: path)) }
            else if fromBackups, let backup, let bytes = FileOps.read(store.backups.appendingPathComponent(backup)) {
                try FileOps.write(bytes, to: URL(fileURLWithPath: path))
            }
        case (.ensureAnchor(let path, _, _), .anchor(let block, _, let existed)):
            let url = URL(fileURLWithPath: path)
            let text = FileOps.read(FileOps.resolvedTarget(url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
            if let block {
                try FileOps.write(Anchor.insert(block, into: text, placement: .end), to: url)
            } else {
                let removed = Anchor.remove(from: text)
                if removed.isEmpty && !existed { try FileOps.delete(url) }
                else if removed != text { try FileOps.write(removed, to: url) }
            }
        case (.setJSONValue(let path, let key, _), .json(let value)):
            let url = URL(fileURLWithPath: path)
            if let bytes = fileBytes { try FileOps.write(bytes, to: url); return }
            guard let data = FileOps.read(FileOps.resolvedTarget(url)) else { return }
            var document = try JSONCDocument(text: String(decoding: data, as: UTF8.self))
            try document.set(value, forKey: key)
            try FileOps.write(document.text, to: url)
        case (.setJSONValue(let path, let key, _), .absent):
            // The file did not exist before Scene. Remove the key, and the file once nothing else is in it.
            let url = URL(fileURLWithPath: path)
            guard let data = FileOps.read(FileOps.resolvedTarget(url)) else { return }
            var document = try JSONCDocument(text: String(decoding: data, as: UTF8.self))
            try document.set(nil, forKey: key)
            if document.keys.isEmpty { try FileOps.delete(url) } else { try FileOps.write(document.text, to: url) }
        case (.setPreference(let domain, let key, _), .plist(let value)):
            try services.setPreference(domain: domain, key: key, value: value)
        case (.setWallpaper(let id, _, let fit), .wallpaper(let path)):
            guard let path, FileManager.default.fileExists(atPath: path) else {
                throw SceneError.failed("the previous wallpaper file no longer exists")
            }
            try await services.setWallpaper(displayID: id, path: path, fit: fit)
        case (.setAppearance, .appearance(let dark, let auto)):
            try await services.setAppearance(dark: dark)
            if auto {
                if services.canRestoreAuto() { try await services.setAutoAppearance() }
                else { throw SceneError.failed("Scene set \(dark ? "Dark" : "Light") but cannot turn Auto back on without the experimental appearance setting") }
            }
        case (.installEditorExtension(let cli, _, let id, _), .extensionVersion(let version)):
            if version == nil {
                let result = try await services.run(cli, ["--uninstall-extension", id], environment: nil)
                if result.status != 0 { throw SceneError.failed("uninstall failed: \(result.stderr.prefix(200))") }
            }
        case (.setTweak(let id, _), .tweak(let value)):
            _ = try await services.tweakSet(id, value)
        default:
            throw SceneError.failed("cannot restore \(op.resource) to \(target)")
        }
    }

    func installedExtensionVersion(cli: String, id: String) async -> String? {
        guard let result = try? await services.run(cli, ["--list-extensions", "--show-versions"], environment: nil) else { return nil }
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: "@", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].lowercased() == id.lowercased() { return parts[1] }
        }
        return nil
    }

    /// Compares states, ignoring backup bookkeeping.
    static func matches(_ a: ResourceState, _ b: ResourceState) -> Bool {
        switch (a, b) {
        case let (.file(h1, _), .file(h2, _)): h1 == h2
        case let (.anchor(b1, _, _), .anchor(b2, _, _)): b1 == b2
        default: a == b
        }
    }
}

extension Operation {
    /// The operation without file contents, for the ledger.
    var stripped: Operation {
        if case let .writeManagedFile(path, _) = self { return .writeManagedFile(path: path, contents: Data()) }
        return self
    }
}
