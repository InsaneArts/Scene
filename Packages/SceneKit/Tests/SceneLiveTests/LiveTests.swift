import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

/// Applies a bundled theme to this Mac's real apps and restores it. Opt-in only: SCENE_LIVE=1.
/// It uses its own ledger folder, so the app's history is untouched. Private calls stay off unless SCENE_LIVE_TWEAKS=1.
@Suite("Live on this Mac (opt-in)", .enabled(if: ProcessInfo.processInfo.environment["SCENE_LIVE"] == "1"), .serialized)
struct LiveTests {
    @Test func applyAndRestoreCatppuccin() async throws {
        let env = SceneEnvironment.live()
        let watched = [".config/ghostty/config", "Library/Application Support/Code/User/settings.json",
                       "Library/Application Support/Cursor/User/settings.json", ".config/nvim/init.lua"].map { env.home.appendingPathComponent($0) }
        let before = watched.map { FileOps.read($0) }
        let helper = Repo.tweakHelper
        let allowTweaks = ProcessInfo.processInfo.environment["SCENE_LIVE_TWEAKS"] == "1"
        let services = LiveSystemServices(tweaks: TweakRunner(helper: helper, policy: TweakPolicy(enabled: allowTweaks, allowUntested: allowTweaks)))
        let wallpapersBefore = await withTaskGroup(of: (UInt32, String?).self) { group in
            for id in await services.displays() { group.addTask { (id, await services.wallpaper(displayID: id)) } }
            var out: [UInt32: String?] = [:]; for await (id, path) in group { out[id] = path }; return out
        }
        let store = EngineStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("scene-live-\(UUID().uuidString.prefix(6))"))
        let integrations: [Integration] = [WallpaperIntegration(), AppearanceIntegration(), AccentColorIntegration(), IconStyleIntegration(),
                                           GhosttyIntegration(), ITermIntegration(), NeovimIntegration()] + VSCodeFamilyIntegration.all
        let engine = Engine(env: env, services: services, integrations: integrations, store: store)
        let theme = try Fixtures.theme("catppuccin")
        let appearance = await services.appearance()
        // Match macOS: the Light/Dark setting itself is not changed.
        let request = ApplyRequest(theme: theme, mode: .system, systemIsDark: appearance.dark)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        let started = Date()
        let report = await engine.apply(request, planned: planned, selected: Set(planned.map(\.id)))
        let elapsed = Date().timeIntervalSince(started)
        for result in report.results { print("LIVE apply \(result.name): \(result.outcome)") }
        print("LIVE apply took \(String(format: "%.2f", elapsed)) s")
        try await Task.sleep(for: .seconds(4))   // time to look at the running apps

        let restored = await engine.restoreOriginal()
        for item in restored { print("LIVE restore \(item.integration) \(item.resource): \(item.result)") }
        let after = watched.map { FileOps.read($0) }
        for (url, (a, b)) in zip(watched, zip(before, after)) where a != b {
            let first = zip(a ?? Data(), b ?? Data()).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            Issue.record("\(url.path) differs after restore: \(a?.count ?? -1) → \(b?.count ?? -1) bytes, first difference at \(first.map(String.init) ?? "end")")
            print("LIVE before: \(String(decoding: a ?? Data(), as: UTF8.self).debugDescription)")
            print("LIVE after:  \(String(decoding: b ?? Data(), as: UTF8.self).debugDescription)")
        }
        for (id, path) in wallpapersBefore { #expect(await services.wallpaper(displayID: id) == path, "wallpaper \(id) not restored") }
        #expect(report.results.allSatisfy { if case .failed = $0.outcome { false } else { true } }, "a live apply failed")
        #expect(elapsed < 3, "apply took \(elapsed) s")
    }

    /// Rex only, while the Rex app is open. Its theme files and the ledger stay in a temporary folder.
    @Test func applyAndRestoreRex() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("scene-live-rex-\(UUID().uuidString.prefix(6))")
        let live = SceneEnvironment.live()
        let env = SceneEnvironment(home: live.home, appSupport: folder, xdgConfigHome: live.xdgConfigHome,
                                   locateApp: live.locateApp, locateExecutable: live.locateExecutable)
        let services = LiveSystemServices(tweaks: TweakRunner(helper: nil, policy: TweakPolicy(enabled: false, allowUntested: false)))
        let engine = Engine(env: env, services: services, integrations: [RexIntegration()], store: EngineStore(root: folder))
        let domain = "com.superlogical.rex"
        let before = Appearance.allCases.map { services.preference(domain: domain, key: "Workspace.\($0.rawValue)ThemeID") }
        let theme = try Fixtures.theme("catppuccin")
        let request = ApplyRequest(theme: theme, mode: .system, systemIsDark: await services.appearance().dark)
        let report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["rex"])
        for result in report.results { print("LIVE apply \(result.name): \(result.outcome) \(result.operations)") }
        #expect(report.results.first?.outcome == .applied)
        for appearance in Appearance.allCases {
            let shown = await engine.rexTheme(appearance)
            print("LIVE Rex \(appearance): \(String(describing: shown))")
            #expect(shown?.name == "scene-\(appearance.rawValue)" && shown?.background == theme.variants[appearance]!.terminal.background.hex)
        }
        try await Task.sleep(for: .seconds(3))   // time to look at Rex

        for item in await engine.restoreOriginal() { print("LIVE restore \(item.resource): \(item.result)") }
        #expect(Appearance.allCases.map { services.preference(domain: domain, key: "Workspace.\($0.rawValue)ThemeID") } == before)
    }

    /// The wallpaper of every Space, through macOS's wallpaper store. Needs SCENE_LIVE_TWEAKS=1 too, and restarts
    /// WallpaperAgent twice. On success, add this Mac's build to `TweakCatalog.testedBuilds["wallpaperSpaces"]`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SCENE_LIVE_TWEAKS"] == "1"))
    func applyAndRestoreEverySpace() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("scene-live-spaces-\(UUID().uuidString.prefix(6))")
        let live = SceneEnvironment.live()
        let env = SceneEnvironment(home: live.home, appSupport: folder, xdgConfigHome: live.xdgConfigHome,
                                   locateApp: live.locateApp, locateExecutable: live.locateExecutable)
        let services = LiveSystemServices(tweaks: TweakRunner(helper: nil, policy: TweakPolicy(enabled: true, allowUntested: true)))
        let engine = Engine(env: env, services: services, integrations: [WallpaperIntegration()], store: EngineStore(root: folder))
        let uuids = await services.displays().compactMap { services.displayUUID($0) }
        let before = try #require(services.wallpaperStore().flatMap { WallpaperStore.images($0, displays: uuids) })
        print("LIVE \(before.count) Space entries on \(uuids.count) displays, build \(Processes.osBuild)")
        let home = try FixtureHome()
        let theme = try Fixtures.themeWithWallpaper("catppuccin", in: home)
        let request = ApplyRequest(theme: theme, mode: .dark, systemIsDark: true)
        let report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["wallpaper"])
        for result in report.results { print("LIVE apply \(result.name): \(result.outcome) \(result.operations)") }
        #expect(report.results.first?.outcome == .applied)
        let applied = try #require(services.wallpaperStore().flatMap { WallpaperStore.images($0, displays: uuids) })
        #expect(Set(applied.values).count == 1, "\(applied)")
        try await Task.sleep(for: .seconds(4))   // time to switch Spaces and look

        for item in await engine.restoreOriginal() { print("LIVE restore \(item.resource): \(item.result)") }
        let restored = try #require(services.wallpaperStore().flatMap { WallpaperStore.images($0, displays: uuids) })
        #expect(restored == before)
    }

    /// ZapFast only, while it runs with Scene's palette selected: the new palette shows through `zapfast reload-themes`,
    /// without a restart. The ledger stays in a temporary folder.
    @Test func applyAndRestoreZapFast() async throws {
        let live = SceneEnvironment.live()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("scene-live-zapfast-\(UUID().uuidString.prefix(6))")
        let env = SceneEnvironment(home: live.home, appSupport: folder, xdgConfigHome: live.xdgConfigHome,
                                   locateApp: live.locateApp, locateExecutable: live.locateExecutable)
        let services = LiveSystemServices(tweaks: TweakRunner(helper: nil, policy: TweakPolicy(enabled: false, allowUntested: false)))
        guard !services.processes(bundleID: ZapFastIntegration.bundleID).isEmpty else { return }
        let palette = live.home.appendingPathComponent("Library/Application Support/me.paolino.zapfast/themes/scene.json")
        let before = FileOps.read(palette)
        let engine = Engine(env: env, services: services, integrations: [ZapFastIntegration()], store: EngineStore(root: folder))
        let request = ApplyRequest(theme: try Fixtures.theme("catppuccin"), mode: .dark, systemIsDark: true)
        let report = await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["zapfast"])
        for result in report.results { print("LIVE apply \(result.name): \(result.outcome)") }
        #expect(report.results.first?.outcome == .applied)
        try await Task.sleep(for: .seconds(5))   // time to look at ZapFast
        for item in await engine.restoreOriginal() { print("LIVE restore \(item.resource): \(item.result)") }
        #expect(FileOps.read(palette) == before)
    }
}
