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
}
