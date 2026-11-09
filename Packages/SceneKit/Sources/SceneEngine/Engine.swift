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

    /// - Parameter replacing: The id of a history entry this apply takes the place of, instead of adding one.
    ///   Following macOS Light/Dark uses it, so Undo still goes back to the theme before. The new entry keeps the
    ///   old entry's apps as well, so Undo to it changes them all, even those this apply left out.
    public func apply(_ request: ApplyRequest, planned: [PlannedIntegration], selected: Set<String>, replacing: String? = nil,
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
            var entry = HistoryEntry(id: UUID().uuidString, themeID: request.theme.id, themeVersion: request.theme.manifest.version,
                                     themeName: request.theme.manifest.name, mode: request.mode, integrations: succeeded, date: Date(),
                                     wallpaper: request.wallpaper?.name, appearance: request.effectiveAppearance)
            if let replacing, let index = history.firstIndex(where: { $0.id == replacing }) {
                let kept = history[index].integrations
                entry.integrations = kept + succeeded.filter { !kept.contains($0) }
                history[index] = entry
            } else {
                history.append(entry)
            }
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
            if case .pause(let milliseconds) = op {
                try? await Task.sleep(for: .milliseconds(milliseconds))
                continue
            }
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
    /// Some apps keep a setting in memory and write their own value back over Scene's, as a running Xcode does with its
    /// theme when Scene selects a theme it has not loaded yet. After such an app quits, Scene sets its value again where
    /// the setting is back at its value from before Scene, or at one of `appDefaults`. A value the user picked stays.
    /// Only preferences count. Returns the resources it set.
    public func reassert(_ integrationID: String, appDefaults: Set<String> = []) async -> [String] {
        var resources: [String] = []
        for entry in ledger.values.sorted(by: { $0.sequence < $1.sequence }) where entry.integration == integrationID {
            guard case .setPreference = entry.operation else { continue }
            let current = await state(of: entry.operation)
            var stale = Self.matches(current, entry.original)
            if case .plist(.string(let value)?) = current, appDefaults.contains(value) { stale = true }
            guard stale, !Self.matches(current, entry.applied) else { continue }
            do {
                try await revert(entry.operation, to: entry.applied, fileBytes: nil)
                resources.append(entry.resource)
            } catch {
                continue
            }
        }
        return resources
    }

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
                } else if case .setWallpaperOnAllSpaces = op {
                    // Each Space that still shows Scene's wallpaper goes back. A Space someone changed keeps its wallpaper.
                    try await revert(op, to: entry.original, fileBytes: nil, fromBackups: true)
                    kept = true
                    result = "Restored the Spaces that still showed Scene's wallpaper. Scene kept the Spaces you changed."
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
    /// An app the undone theme changed but the previous entry did not (one added to Scene since, or switched off then)
    /// goes back to the last earlier entry that had it, or to how it was before Scene.
    public func undo(resolveTheme: @Sendable (String, String) -> Theme?, systemIsDark: Bool,
                     progress: @escaping @Sendable (String) -> Void = { _ in }) async -> ApplyReport? {
        var history = store.loadHistory()
        guard let undone = history.popLast() else { return nil }
        try? store.saveHistory(history)
        guard let previous = history.last, let theme = resolveTheme(previous.themeID, previous.themeVersion) else {
            let restored = await restoreOriginal(progress: progress)
            return ApplyReport(themeName: "Original setup", results: restored.map {
                IntegrationResult(id: $0.resource, name: $0.integration, outcome: $0.keptUserChange ? .skipped($0.result) : .applied, operations: [$0.resource], notes: [])
            }, date: Date())
        }
        var extra: [IntegrationResult] = []
        var untouched = Set(undone.integrations).subtracting(previous.integrations)
        for entry in history.dropLast().reversed() where !untouched.isEmpty {
            let ids = untouched.intersection(entry.integrations)
            guard !ids.isEmpty, let earlier = resolveTheme(entry.themeID, entry.themeVersion) else { continue }
            var request = ApplyRequest(theme: earlier, mode: entry.mode, systemIsDark: systemIsDark)
            request.wallpaperName = entry.wallpaper
            let report = await apply(request, planned: plan(request, detections: await detectAll()), selected: ids, progress: progress)
            // This apply goes back in time, so it adds no history entry.
            try? store.saveHistory(history)
            extra += report.results
            untouched.subtract(ids)
        }
        if !untouched.isEmpty {
            let restored = await restoreOriginal(only: untouched, progress: progress)
            extra += restored.map {
                IntegrationResult(id: $0.integration, name: $0.integration, outcome: $0.keptUserChange ? .skipped($0.result) : .applied, operations: [$0.resource], notes: [])
            }
        }
        var request = ApplyRequest(theme: theme, mode: previous.mode, systemIsDark: systemIsDark)
        request.wallpaperName = previous.wallpaper
        let detections = await detectAll()
        let planned = plan(request, detections: detections)
        history.removeLast()
        try? store.saveHistory(history)
        var report = await apply(request, planned: planned, selected: Set(previous.integrations), progress: progress)
        report.results += extra
        return report
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
        case .setPreferenceEntry(let domain, let key, let entry, _):
            guard case .dictionary(let dictionary)? = services.preference(domain: domain, key: key) else { return .plist(nil) }
            return .plist(dictionary[entry])
        case .setConfigValue(let path, let table, let key, _):
            guard let data = FileOps.read(FileOps.resolvedTarget(URL(fileURLWithPath: path))) else { return .absent }
            let document = KeyValueDocument(text: String(decoding: data, as: UTF8.self))
            return .configValue(document.value(forKey: (table.map { $0 + "." } ?? "") + key))
        case .setYAMLValue(let path, let keyPath, _):
            guard let data = FileOps.read(FileOps.resolvedTarget(URL(fileURLWithPath: path))) else { return .absent }
            // A key the file does not set is nil, which `try?` would mix up with an unreadable file.
            do { return .configValue(try YAMLDocument(text: String(decoding: data, as: UTF8.self)).value(at: keyPath)) }
            catch { return .configValue("<unreadable>") }
        case .setWallpaper(let id, _, _):
            return .wallpaper(path: await services.wallpaper(displayID: id))
        case .setWallpaperOnAllSpaces(_, let uuids, _, _):
            guard let data = services.wallpaperStore(), let images = WallpaperStore.images(data, displays: uuids) else { return .absent }
            return .wallpaperSpaces(images: images, backup: nil)
        case .setAppearance:
            let a = await services.appearance()
            return .appearance(dark: a.dark, auto: a.auto)
        case .installEditorExtension(let cli, _, let id, _):
            return .extensionVersion(await installedExtensionVersion(cli: cli, id: id))
        case .importRexTheme(_, _, let appearance):
            return .plist(services.preference(domain: Self.rexDomain, key: Self.rexKey(appearance)))
        case .setBbTheme(let cli, _):
            // A theme id or nil, which is an unreadable answer: bb is not running, or its answer changed.
            return .configValue(await bbThemeID(cli: cli) ?? "<unreadable>")
        case .setTweak(let id, _):
            return .tweak((try? await services.tweakGet(id)) ?? .null)
        case .pause:
            return .absent
        }
    }

    func fileBytes(for op: Operation) -> Data? {
        switch op {
        case .writeManagedFile(let path, _), .ensureAnchor(let path, _, _), .setJSONValue(let path, _, _), .setConfigValue(let path, _, _, _),
             .setYAMLValue(let path, _, _):
            return FileOps.read(FileOps.resolvedTarget(URL(fileURLWithPath: path)))
        case .setWallpaperOnAllSpaces: return services.wallpaperStore()
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
        case (.setWallpaperOnAllSpaces(_, let uuids, _, _), .wallpaperSpaces(let images, _)):
            guard let data = services.wallpaperStore(), let desktops = try WallpaperStore.backup(data, displays: uuids) else {
                throw SceneError.failed("macOS's wallpaper store has a format Scene does not know")
            }
            return .wallpaperSpaces(images: images, backup: try FileOps.backup(desktops, named: "wallpaper-spaces.plist", into: store.backups))
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
        case .setPreferenceEntry(let domain, let key, let entry, let value):
            try setEntry(domain: domain, key: key, entry: entry, value: value)
            return .plist(value)
        case .setConfigValue(let path, let table, let key, let value):
            try setConfig(path: path, table: table, key: key, value: value, deleteWhenEmpty: false)
            return .configValue(value)
        case .setYAMLValue(let path, let keyPath, let value):
            try setYAML(path: path, keyPath: keyPath, value: value, deleteWhenEmpty: false)
            return .configValue(value)
        case .setWallpaper(let id, let path, let fit):
            try await services.setWallpaper(displayID: id, path: path, fit: fit)
            return .wallpaper(path: path)
        case .setWallpaperOnAllSpaces(let displays, let uuids, let path, let fit):
            var shown: [UInt32: String] = [:]
            for id in displays { shown[id] = await services.wallpaper(displayID: id) }
            do {
                for id in displays { try await services.setWallpaper(displayID: id, path: path, fit: fit) }
                // macOS saves the Space on screen in its store with the placement it chose. Copy that to every other Space.
                for _ in 0..<20 {
                    if let data = services.wallpaperStore(), let spread = try WallpaperStore.spreading(data, displays: uuids, imagePath: path) {
                        try await services.setWallpaperStore(spread)
                        return await state(of: op)
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                throw SceneError.failed("macOS did not save the new wallpaper in its wallpaper store")
            } catch {
                // The engine records nothing for a failed operation, so put the Space on screen back here. The store
                // is as it was: `setWallpaperStore` keeps the old store when it fails.
                for (id, previous) in shown where FileManager.default.fileExists(atPath: previous) {
                    try? await services.setWallpaper(displayID: id, path: previous, fit: fit)
                }
                throw error
            }
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
        case .importRexTheme(let cli, let path, let appearance):
            try await runRex(cli, ["do", "client.theme.import", "path=\(path)"])
            // Rex saves the import in its preferences. Wait until the look names the imported theme with the file's background.
            let name = (path as NSString).lastPathComponent
            let background = FileOps.read(URL(fileURLWithPath: path)).flatMap { data in
                String(decoding: data, as: UTF8.self).split(separator: "\n").first { $0.hasPrefix("background = ") }
                    .map { $0.dropFirst("background = ".count).lowercased() }
            }
            for _ in 0..<30 {
                if let theme = rexTheme(appearance), theme.name == name, theme.background == background { return .plist(.string(theme.id)) }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw SceneError.failed("Rex did not select \(name) as its \(appearance.rawValue) theme")
        case .setBbTheme(let cli, let id):
            try await setBbTheme(cli: cli, id: id)
            return .configValue(id)
        case .setTweak(let id, let value):
            let readBack = try await services.tweakSet(id, value)
            return .tweak(readBack)
        case .pause:
            return .absent
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
        case (.setPreferenceEntry(let domain, let key, let entry, _), .plist(let value)):
            try setEntry(domain: domain, key: key, entry: entry, value: value)
        case (.setConfigValue(let path, _, _, _), _) where fileBytes != nil:
            try FileOps.write(fileBytes!, to: URL(fileURLWithPath: path))
        case (.setConfigValue(let path, let table, let key, _), .configValue(let value)):
            try setConfig(path: path, table: table, key: key, value: value, deleteWhenEmpty: false)
        case (.setConfigValue(let path, let table, let key, _), .absent):
            // The file did not exist before Scene. Remove the key, and the file once nothing else is in it.
            try setConfig(path: path, table: table, key: key, value: nil, deleteWhenEmpty: true)
        case (.setYAMLValue(let path, _, _), _) where fileBytes != nil:
            try FileOps.write(fileBytes!, to: URL(fileURLWithPath: path))
        case (.setYAMLValue(let path, let keyPath, _), .configValue(let value)):
            try setYAML(path: path, keyPath: keyPath, value: value, deleteWhenEmpty: false)
        case (.setYAMLValue(let path, let keyPath, _), .absent):
            try setYAML(path: path, keyPath: keyPath, value: nil, deleteWhenEmpty: true)
        case (.setWallpaper(let id, _, let fit), .wallpaper(let path)):
            guard let path, FileManager.default.fileExists(atPath: path) else {
                throw SceneError.failed("the previous wallpaper file no longer exists")
            }
            try await services.setWallpaper(displayID: id, path: path, fit: fit)
        case (.setWallpaperOnAllSpaces(_, let uuids, let path, _), .wallpaperSpaces(_, let backup)):
            if let bytes = fileBytes { try await services.setWallpaperStore(bytes); return }
            guard fromBackups, let backup, let saved = FileOps.read(store.backups.appendingPathComponent(backup)) else {
                throw SceneError.failed("Scene has no copy of the Spaces' wallpapers from before")
            }
            guard let data = services.wallpaperStore(),
                  let restored = try WallpaperStore.restoring(data, displays: uuids, sceneImage: path, backup: saved) else {
                throw SceneError.failed("macOS's wallpaper store has a format Scene does not know")
            }
            try await services.setWallpaperStore(restored)
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
        case (.importRexTheme(let cli, _, let appearance), .plist(let value)):
            guard case .string(let id)? = value else {
                throw SceneError.failed("Rex had no \(appearance.rawValue) theme before Scene. Pick one in Rex Settings → Themes.")
            }
            try await runRex(cli, ["do", "client.theme.change", "name=\(id)"])
            for _ in 0..<30 {
                if services.preference(domain: Self.rexDomain, key: Self.rexKey(appearance)) == .string(id) { return }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw SceneError.failed("Rex did not switch back to \(id)")
        case (.setBbTheme(let cli, _), .configValue(let value)):
            guard let value, value != "<unreadable>" else { throw SceneError.failed("Scene could not read bb's theme before it changed it. Pick one with bb theme set.") }
            try await setBbTheme(cli: cli, id: value)
        case (.setTweak(let id, _), .tweak(let value)):
            _ = try await services.tweakSet(id, value)
        default:
            throw SceneError.failed("cannot restore \(op.resource) to \(target)")
        }
    }

    /// Changes one entry of a dictionary preference and keeps the other entries.
    func setEntry(domain: String, key: String, entry: String, value: PlistValue?) throws {
        var dictionary: [String: PlistValue] = [:]
        if case .dictionary(let current)? = services.preference(domain: domain, key: key) { dictionary = current }
        dictionary[entry] = value
        try services.setPreference(domain: domain, key: key, value: dictionary.isEmpty ? nil : .dictionary(dictionary))
    }

    func setConfig(path: String, table: String?, key: String, value: String?, deleteWhenEmpty: Bool) throws {
        let url = URL(fileURLWithPath: path)
        guard let data = FileOps.read(FileOps.resolvedTarget(url)) else {
            if let value {
                var document = KeyValueDocument(text: "")
                document.set(value, forKey: key, inTable: table)
                try FileOps.write(document.text, to: url)
            }
            return
        }
        let text = String(decoding: data, as: UTF8.self)
        var document = KeyValueDocument(text: text)
        document.set(value, forKey: key, inTable: table)
        if deleteWhenEmpty, document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try FileOps.delete(url) }
        else if document.text != text { try FileOps.write(document.text, to: url) }
    }

    func setYAML(path: String, keyPath: [String], value: String?, deleteWhenEmpty: Bool) throws {
        let url = URL(fileURLWithPath: path)
        let text = FileOps.read(FileOps.resolvedTarget(url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        var document = try YAMLDocument(text: text)
        try document.set(value, at: keyPath)
        if deleteWhenEmpty, document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { try FileOps.delete(url) }
        else if document.text != text { try FileOps.write(document.text, to: url) }
    }

    /// The id of the theme bb shows, from `bb theme show --json`, or nil when bb does not answer.
    func bbThemeID(cli: String) async -> String? {
        guard let result = try? await services.run(cli, ["theme", "show", "--json"], environment: nil), result.status == 0,
              let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any] else { return nil }
        return root["themeId"] as? String
    }

    /// Selects a bb theme and reads it back. bb applies the theme live in every open window.
    func setBbTheme(cli: String, id: String) async throws {
        let result = try await services.run(cli, ["theme", "set", id], environment: nil)
        guard result.status == 0 else {
            throw SceneError.failed("bb theme set \(id) failed: \((result.stderr + result.stdout).trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))")
        }
        guard await bbThemeID(cli: cli) == id else { throw SceneError.failed("bb did not report \(id) as its theme") }
    }

    func installedExtensionVersion(cli: String, id: String) async -> String? {
        guard let result = try? await services.run(cli, ["--list-extensions", "--show-versions"], environment: nil) else { return nil }
        for line in result.stdout.split(separator: "\n") {
            let parts = line.split(separator: "@", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].lowercased() == id.lowercased() { return parts[1] }
        }
        return nil
    }

    static let rexDomain = "com.superlogical.rex"
    static func rexKey(_ appearance: Appearance) -> String { "Workspace.\(appearance.rawValue)ThemeID" }

    /// Runs an action in the Rex app. It fails when Rex is not open, and never starts a Rex server.
    /// Rex refuses a client action when more than one app is connected to its server, so Scene names this Mac's.
    func runRex(_ cli: String, _ arguments: [String]) async throws {
        let target = await rexAppClient(cli).map { ["-C", $0] } ?? []
        let result = try await services.run(cli, target + arguments + ["--autostart=false"], environment: nil)
        guard result.status == 0 else {
            throw SceneError.failed("rex \(arguments[1]) failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))")
        }
    }

    /// The client id of the Rex app on this Mac, when more than one app is connected to the server: an app client on
    /// the local socket whose process is the running Rex, the newest one if it connected more than once. Nil otherwise.
    func rexAppClient(_ cli: String) async -> String? {
        guard let result = try? await services.run(cli, ["client", "list", "--json", "--autostart=false"], environment: nil), result.status == 0,
              let root = try? JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any],
              let clients = root["clients"] as? [[String: Any]] else { return nil }
        let apps = clients.filter { ($0["info"] as? [String: Any])?["kind"] as? String == "app" }
        guard apps.count > 1 else { return nil }
        let running = Set(services.processes(bundleID: Self.rexDomain))
        let here = apps.filter { client in
            guard let principal = client["principal"] as? [String: Any], let pid = principal["pid"] as? Int else { return false }
            return principal["transport"] as? String == "unix" && running.contains(pid_t(pid))
        }
        return here.max { ($0["connected_at"] as? String ?? "") < ($1["connected_at"] as? String ?? "") }?["client_id"] as? String
    }

    /// The custom theme Rex shows for a look, from Rex's preferences, with its background as #rrggbb.
    func rexTheme(_ appearance: Appearance) -> (id: String, name: String, background: String)? {
        guard case .string(let id)? = services.preference(domain: Self.rexDomain, key: Self.rexKey(appearance)),
              case .data(let data)? = services.preference(domain: Self.rexDomain, key: "Workspace.customThemes"),
              let themes = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let theme = themes.first(where: { $0["id"] as? String == id }), let name = theme["name"] as? String,
              let color = (theme["palette"] as? [String: Any])?["background"] as? [String: Any],
              let r = color["red"] as? Double, let g = color["green"] as? Double, let b = color["blue"] as? Double else { return nil }
        let byte = { (value: Double) in Int((value * 255).rounded()) }
        return (id, name, String(format: "#%02x%02x%02x", byte(r), byte(g), byte(b)))
    }

    /// Compares states, ignoring backup bookkeeping.
    static func matches(_ a: ResourceState, _ b: ResourceState) -> Bool {
        switch (a, b) {
        case let (.file(h1, _), .file(h2, _)): h1 == h2
        case let (.anchor(b1, _, _), .anchor(b2, _, _)): b1 == b2
        case let (.wallpaperSpaces(i1, _), .wallpaperSpaces(i2, _)): i1 == i2
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
