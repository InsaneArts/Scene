import AppKit
import Observation
import SceneEngine
import SceneIntegrations
import SceneSwitcher
import SceneThemes
import ServiceManagement
import SwiftUI

/// App state and actions. Views read it; only these methods change the system, through the engine.
@MainActor @Observable
final class AppModel {
    var themes: [Theme] = []
    var problems: [ThemeLibrary.Problem] = []
    var selectedThemeID: Theme.ID?
    var previewAppearance: [Theme.ID: Appearance] = [:]
    var detections: [String: Detection] = [:]
    var history: [HistoryEntry] = []
    var ledger: [LedgerEntry] = []
    var changedOutside: [String: [String]] = [:]
    var unfinished: [JournalRun] = []
    var isWorking = false
    var progress = ""
    var lastReport: ApplyReport?
    var lastRestore: [RestoreItem]?
    var alert: String?

    let env: SceneEnvironment
    let library: ThemeLibrary
    let tweaks: TweakRunner
    let engine: Engine

    var experimentalEnabled: Bool {
        didSet { UserDefaults.standard.set(experimentalEnabled, forKey: "experimentalEnabled"); applyPolicy() }
    }
    var allowUntested: Bool {
        didSet { UserDefaults.standard.set(allowUntested, forKey: "allowUntested"); applyPolicy() }
    }
    var showMenuBarExtra: Bool {
        didSet { UserDefaults.standard.set(showMenuBarExtra, forKey: "showMenuBarExtra") }
    }
    var disabledIntegrations: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledIntegrations), forKey: "disabledIntegrations") }
    }
    /// Themes you starred. They come first in the sidebar, the switcher, and the menu bar panel.
    var favoriteThemes: Set<String> {
        didSet { UserDefaults.standard.set(Array(favoriteThemes), forKey: "favoriteThemes") }
    }
    /// The GitHub repository of each theme installed from one, by theme id. Update downloads it again.
    var themeSources: [String: String] {
        didSet { UserDefaults.standard.set(themeSources, forKey: "themeSources") }
    }
    /// When macOS switches Light/Dark, the current theme switches to its other look.
    var followSystemAppearance: Bool {
        didSet { UserDefaults.standard.set(followSystemAppearance, forKey: "followSystemAppearance") }
    }
    /// The sidebar's search text.
    var searchText = ""
    /// The Install from GitHub sheet is open.
    var installingFromGitHub = false
    /// The wallpaper you picked for each theme and appearance, by file name. Keys are "<theme id>#<appearance>".
    var backgroundChoices: [String: String] {
        didSet { UserDefaults.standard.set(backgroundChoices, forKey: "backgroundChoices") }
    }
    /// The global shortcut that opens the theme switcher. Nil turns it off.
    var switcherShortcut: HotKeySpec? {
        didSet { Self.save(switcherShortcut, "switcherShortcut"); registerShortcuts() }
    }
    /// The global shortcut that shows the current theme's next wallpaper. Nil turns it off.
    var nextBackgroundShortcut: HotKeySpec? {
        didSet { Self.save(nextBackgroundShortcut, "nextBackgroundShortcut"); registerShortcuts() }
    }
    var shortcutError: String?
    /// The Settings tab on screen.
    var settingsTab = SettingsTab.general

    func registerShortcuts() {
        var messages: [String] = []
        let shortcuts: [(UInt32, HotKeySpec?, () -> Void)] = [
            (1, switcherShortcut, { ThemeSwitcher.shared.toggle() }),
            (2, nextBackgroundShortcut, { [weak self] in Task { await self?.nextBackground() } }),
        ]
        for (id, spec, action) in shortcuts {
            if let spec {
                if let message = HotKeyCenter.shared.register(spec, id: id, action: action) { messages.append(message) }
            } else {
                HotKeyCenter.shared.unregister(id)
            }
        }
        shortcutError = messages.isEmpty ? nil : messages.joined(separator: " ")
    }

    /// No stored value means the default. Empty data means the shortcut is off.
    static func loadShortcut(_ key: String, default spec: HotKeySpec) -> HotKeySpec? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return spec }
        return data.isEmpty ? nil : (try? JSONDecoder().decode(HotKeySpec.self, from: data)) ?? spec
    }

    static func save(_ spec: HotKeySpec?, _ key: String) {
        UserDefaults.standard.set(spec.flatMap { try? JSONEncoder().encode($0) } ?? Data(), forKey: key)
    }

    /// Scene must run for the shortcut to work, so it can open at login.
    var openAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { alert = "Scene could not change its login item: \(error.localizedDescription)" }
            loginItemVersion += 1
        }
    }
    /// Changes when the login item changes, so views that read `openAtLogin` refresh.
    var loginItemVersion = 0

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: ["experimentalEnabled": true, "allowUntested": false, "showMenuBarExtra": false, "followSystemAppearance": false])
        experimentalEnabled = defaults.bool(forKey: "experimentalEnabled")
        allowUntested = defaults.bool(forKey: "allowUntested")
        showMenuBarExtra = defaults.bool(forKey: "showMenuBarExtra")
        disabledIntegrations = Set(defaults.stringArray(forKey: "disabledIntegrations") ?? [])
        favoriteThemes = Set(defaults.stringArray(forKey: "favoriteThemes") ?? [])
        themeSources = defaults.dictionary(forKey: "themeSources") as? [String: String] ?? [:]
        followSystemAppearance = defaults.bool(forKey: "followSystemAppearance")
        backgroundChoices = defaults.dictionary(forKey: "backgroundChoices") as? [String: String] ?? [:]
        switcherShortcut = Self.loadShortcut("switcherShortcut", default: .omarchyDefault)
        nextBackgroundShortcut = Self.loadShortcut("nextBackgroundShortcut", default: .nextBackgroundDefault)

        env = .live()
        library = ThemeLibrary(bundledFolder: Locations.bundledThemes, installedFolder: env.appSupport.appendingPathComponent("Themes"))
        tweaks = TweakRunner(helper: Locations.tweakHelper,
                             policy: TweakPolicy(enabled: defaults.bool(forKey: "experimentalEnabled"), allowUntested: defaults.bool(forKey: "allowUntested")))
        let integrations: [Integration] = [WallpaperIntegration(), AppearanceIntegration(), BordersIntegration(), AccentColorIntegration(),
                                           IconStyleIntegration(), GhosttyIntegration(), ITermIntegration(), KittyIntegration(),
                                           AlacrittyIntegration(), WarpIntegration(), TerminalAppIntegration(), NeovimIntegration()] + VSCodeFamilyIntegration.all
            + [ZedIntegration(), XcodeIntegration(), HelixIntegration(), TmuxIntegration(), BatIntegration(), BtopIntegration()]
        engine = Engine(env: env, services: LiveSystemServices(tweaks: tweaks), integrations: integrations)
    }

    func applyPolicy() {
        tweaks.policy = TweakPolicy(enabled: experimentalEnabled, allowUntested: allowUntested)
        Task { await refreshSystemState() }
    }

    var selectedTheme: Theme? { themes.first { $0.id == selectedThemeID } }

    /// Every theme, favorites first.
    var orderedThemes: [Theme] { ThemeSearch.ordered(themes, favorites: favoriteThemes) }

    func toggleFavorite(_ theme: Theme) {
        if favoriteThemes.contains(theme.id) { favoriteThemes.remove(theme.id) } else { favoriteThemes.insert(theme.id) }
    }

    var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    func appearance(for theme: Theme) -> Appearance {
        if let chosen = previewAppearance[theme.id], theme.variants[chosen] != nil { return chosen }
        let preferred: Appearance = systemIsDark ? .dark : .light
        return theme.variants[preferred] != nil ? preferred : (theme.availableAppearances.first ?? .dark)
    }

    /// The variant Scene shows for a theme: the one you picked, or the one that matches macOS.
    func variant(for theme: Theme) -> ResolvedVariant {
        theme.variants[appearance(for: theme)] ?? theme.variants.values.first!
    }

    var currentThemeID: String? { history.last?.themeID }

    // MARK: Loading

    func reload() async {
        let result = library.loadAll()
        themes = result.themes
        problems = result.problems
        if selectedThemeID == nil || !themes.contains(where: { $0.id == selectedThemeID }) { selectedThemeID = currentThemeID ?? themes.first?.id }
        await refreshSystemState()
    }

    func refreshSystemState() async {
        detections = await engine.detectAll()
        history = await engine.history()
        ledger = await engine.ledgerEntries()
        unfinished = await engine.unfinishedRuns()
        changedOutside = await engine.changesOutsideScene()
    }

    // MARK: Apply, undo, restore

    func plan(_ theme: Theme, mode: AppearanceMode) async -> (ApplyRequest, [PlannedIntegration]) {
        var request = ApplyRequest(theme: theme, mode: mode, systemIsDark: systemIsDark)
        request.wallpaperName = wallpaper(for: request.current)?.name
        let detections = await engine.detectAll()
        self.detections = detections
        return (request, await engine.plan(request, detections: detections))
    }

    func apply(_ request: ApplyRequest, planned: [PlannedIntegration], selected: Set<String>, replacingLastHistory: Bool = false) async {
        isWorking = true
        defer { isWorking = false; progress = "" }
        lastReport = await engine.apply(request, planned: planned, selected: selected, replacingLastHistory: replacingLastHistory) { message in
            Task { @MainActor in self.progress = message }
        }
        await refreshSystemState()
    }

    /// Applies a theme with the remembered app choices. Used by the theme switcher and the menu bar extra.
    func quickApply(_ theme: Theme, mode: AppearanceMode = .system, replacingLastHistory: Bool = false) async {
        let (request, planned) = await plan(theme, mode: mode)
        let selected = Set(planned.filter { $0.plan != nil && !disabledIntegrations.contains($0.id) }.map(\.id))
        await apply(request, planned: planned, selected: selected, replacingLastHistory: replacingLastHistory)
    }

    // MARK: Following macOS Light/Dark

    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var followTask: Task<Void, Never>?

    /// Watches macOS Light/Dark while Scene runs. Snapshot mode never applies, so it does not watch.
    func startFollowingAppearance() {
        guard appearanceObservation == nil, Snapshot.folder == nil else { return }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.appearanceChanged() }
        }
    }

    private func appearanceChanged() {
        followTask?.cancel()
        followTask = Task { @MainActor in
            // Wait until macOS has finished switching, and until Scene is idle.
            try? await Task.sleep(for: .seconds(1))
            while isWorking, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            await followAppearance()
        }
    }

    /// Applies the current theme's other look when macOS shows the other appearance. It replaces the newest
    /// history entry, so Undo goes back to the theme before. A theme with one look never switches macOS back.
    func followAppearance() async {
        guard followSystemAppearance else { return }
        if themes.isEmpty { await reload() }
        guard let entry = history.last, let theme = themes.first(where: { $0.id == entry.themeID }),
              entry.needsOtherLook(available: theme.availableAppearances, systemIsDark: systemIsDark) else { return }
        await quickApply(theme, mode: .system, replacingLastHistory: true)
    }

    func undo() async {
        isWorking = true
        defer { isWorking = false; progress = "" }
        let library = self.library
        lastReport = await engine.undo(resolveTheme: { id, _ in library.find(id: id) }, systemIsDark: systemIsDark) { message in
            Task { @MainActor in self.progress = message }
        }
        await refreshSystemState()
        // The wallpaper on screen is the picked one again.
        if let entry = history.last, let theme = themes.first(where: { $0.id == entry.themeID }) {
            let variant = ApplyRequest(theme: theme, mode: entry.mode, systemIsDark: systemIsDark).current
            if let shown = variant.wallpapers.first(where: { $0.name == entry.wallpaper }) { choose(shown, for: variant) }
        }
    }

    func restoreOriginal(only integrations: Set<String>? = nil) async {
        isWorking = true
        defer { isWorking = false; progress = "" }
        lastRestore = await engine.restoreOriginal(only: integrations) { message in
            Task { @MainActor in self.progress = message }
        }
        await refreshSystemState()
    }

    func dismissUnfinished(_ run: JournalRun) async {
        await engine.discard(run)
        unfinished = await engine.unfinishedRuns()
    }

    // MARK: Backgrounds

    /// The wallpaper Scene shows for this variant: your pick, or the theme's first one.
    func wallpaper(for variant: ResolvedVariant) -> Wallpaper? {
        variant.wallpaper(named: backgroundChoices["\(variant.themeID)#\(variant.appearance.rawValue)"])
    }

    func choose(_ wallpaper: Wallpaper, for variant: ResolvedVariant) {
        backgroundChoices["\(variant.themeID)#\(variant.appearance.rawValue)"] = wallpaper.name
    }

    /// Shows the current theme's next wallpaper, like Omarchy's Super + Ctrl + Space. Only the wallpaper changes.
    func nextBackground() async {
        if themes.isEmpty { await reload() }
        guard !isWorking, let entry = history.last, let theme = themes.first(where: { $0.id == entry.themeID }) else { NSSound.beep(); return }
        let variant = ApplyRequest(theme: theme, mode: entry.mode, systemIsDark: systemIsDark).current
        guard variant.wallpapers.count > 1, let next = variant.wallpaper(after: wallpaper(for: variant)?.name) else { NSSound.beep(); return }
        choose(next, for: variant)
        let (request, planned) = await plan(theme, mode: entry.mode)
        await apply(request, planned: planned, selected: ["wallpaper"])
        if case .failed(let reason)? = lastReport?.results.first?.outcome { alert = "Scene could not change the wallpaper: \(reason)" }
    }

    // MARK: Library

    func importTheme(from url: URL) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let theme = try library.importPackage(at: url)
            await reload()
            selectedThemeID = theme.id
        } catch let error as ThemeLoadError {
            alert = "Scene could not import this theme:\n\n" + error.errors.prefix(8).joined(separator: "\n")
        } catch {
            alert = "Scene could not import this theme: \(error)"
        }
    }

    func export(_ theme: Theme, to url: URL) {
        do { try library.export(theme, to: url) } catch { alert = "Export failed: \(error)" }
    }

    func remove(_ theme: Theme) async {
        do {
            try library.remove(theme)
            themeSources[theme.id] = nil
            await reload()
        } catch { alert = "\(error)" }
    }

    /// Downloads a theme from a GitHub repository and installs it. Returns nil when it worked, otherwise the reason.
    func installFromGitHub(_ text: String) async -> String? {
        guard let repository = GitHubRepository(text) else { return "Enter a GitHub repository, such as https://github.com/owner/theme." }
        do {
            let archive = try await repository.download()
            let theme = try library.installRepository(archive: archive, repository: repository)
            themeSources[theme.id] = repository.url.absoluteString
            await reload()
            selectedThemeID = theme.id
            return nil
        } catch let error as ThemeLoadError {
            return error.errors.prefix(8).joined(separator: "\n")
        } catch let error as URLError {
            return error.localizedDescription
        } catch {
            return "\(error)"
        }
    }

    /// Downloads a theme installed from GitHub again.
    func updateFromGitHub(_ theme: Theme) async {
        guard let source = themeSources[theme.id] else { return }
        isWorking = true
        progress = "Updating \(theme.manifest.name)…"
        defer { isWorking = false; progress = "" }
        if let error = await installFromGitHub(source) { alert = "Scene could not update \(theme.manifest.name):\n\n\(error)" }
    }
}

/// Where the bundled themes and the helper live in the app bundle.
enum Locations {
    static var bundledThemes: URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Themes")
        return bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
    }

    static var tweakHelper: URL? {
        let inBundle = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/scene-tweak")
        return FileManager.default.isExecutableFile(atPath: inBundle.path) ? inBundle : nil
    }
}
