import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
@testable import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("Your scripts", .serialized)
struct UserScriptsTests {
    /// A script that saves its `SCENE_*` environment, one run per line, so the test can read what each run got.
    func script(_ home: FixtureHome, _ name: String, exit status: Int = 0) throws -> String {
        let log = home.path("\(name).log").path
        let url = try home.write("bin/\(name)", """
        #!/bin/sh
        env | grep '^SCENE_' | sort | tr '\\n' ' ' >> '\(log)'
        echo >> '\(log)'
        echo "it broke" >&2
        exit \(status)
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    func runs(_ home: FixtureHome, _ name: String) -> [[String: String]] {
        (home.read("\(name).log") ?? "").split(separator: "\n").map { line in
            Dictionary(line.split(separator: " ").compactMap { pair -> (String, String)? in
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }, uniquingKeysWith: { $1 })
        }
    }

    func engine(_ home: FixtureHome, scripts: [String]) -> Engine {
        let env = Fixtures.environment(home, apps: [:])
        let services = LiveSystemServices(tweaks: TweakRunner(helper: nil, policy: TweakPolicy(enabled: false)))
        return Engine(env: env, services: services, integrations: [UserScriptsIntegration(scripts: { scripts })],
                      store: EngineStore(root: env.appSupport))
    }

    func apply(_ engine: Engine, _ folder: String, mode: AppearanceMode) async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme(folder), mode: mode, systemIsDark: false)
        let planned = await engine.plan(request, detections: await engine.detectAll())
        return await engine.apply(request, planned: planned, selected: Set(planned.map(\.id)))
    }

    @Test func applyWritesTheFileAndRunsEachScriptWithTheColors() async throws {
        let home = try FixtureHome()
        let engine = engine(home, scripts: [try script(home, "recolor.sh"), try script(home, "menubar.sh")])
        let report = try await apply(engine, "catppuccin", mode: .dark)
        #expect(report.results.first?.outcome == .applied)

        let theme = try Fixtures.theme("catppuccin")
        let dark = try #require(theme.variants[.dark])
        let file = try #require(home.read(".config/scene/theme.json"))
        #expect(file.contains("\"appearance\" : \"dark\"") && file.contains("\"id\" : \"\(theme.id)\""))
        for name in ["recolor.sh", "menubar.sh"] {
            let run = try #require(runs(home, name).first)
            #expect(run["SCENE_EVENT"] == "apply")
            #expect(run["SCENE_THEME_FILE"] == home.path(".config/scene/theme.json").path)
            #expect(run["SCENE_THEME_ID"] == theme.id && run["SCENE_APPEARANCE"] == "dark")
            #expect(run["SCENE_BACKGROUND"] == dark.interface.background.hex)
            #expect(run["SCENE_CURRENT_LINE"] == dark.interface.currentLine.hex)
            #expect(run["SCENE_ANSI_15"] == dark.terminal.ansi[15].hex)
            #expect(run.count == 4 + 15 + 16, "\(run.keys.sorted())")
        }
    }

    @Test func restoreDeletesTheFileAndRunsTheScriptsAgain() async throws {
        let home = try FixtureHome()
        let engine = engine(home, scripts: [try script(home, "recolor.sh")])
        _ = try await apply(engine, "catppuccin", mode: .light)
        _ = await engine.restoreOriginal()
        #expect(home.read(".config/scene/theme.json") == nil)
        let restore = try #require(runs(home, "recolor.sh").last)
        #expect(restore == ["SCENE_EVENT": "restore", "SCENE_THEME_FILE": home.path(".config/scene/theme.json").path])
    }

    @Test func aFailingScriptNeedsYourAction() async throws {
        let home = try FixtureHome()
        let engine = engine(home, scripts: [try script(home, "recolor.sh", exit: 3)])
        let report = try await apply(engine, "catppuccin", mode: .dark)
        #expect(report.results.first?.outcome == .needsAction("recolor.sh exited with status 3: it broke"))
    }

    @Test func aScriptThatHangsIsStopped() async throws {
        let home = try FixtureHome()
        let url = try home.write("bin/hang.sh", "#!/bin/sh\nsleep 30\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let started = Date()
        let report = try await apply(engine(home, scripts: [url.path]), "catppuccin", mode: .dark)
        #expect(Date().timeIntervalSince(started) < UserScriptsIntegration.timeout + 3)
        if case .needsAction(let what)? = report.results.first?.outcome { #expect(what.contains("timed out")) }
        else { Issue.record("expected needs action, got \(String(describing: report.results.first?.outcome))") }
    }

    @Test func withoutScriptsNothingIsPlanned() async throws {
        let home = try FixtureHome()
        let engine = engine(home, scripts: [])
        #expect(await engine.detectAll()["scripts"]?.installed == false)
    }

    @Test func environmentKeepsOnlyCheckedValues() throws {
        let file: [String: Any] = [
            "format": 1, "appearance": "dark", "theme": ["id": "x; rm -rf ~"],
            "variants": ["dark": ["interface": ["background": "#112233", "accent": "$(whoami)", "bad-name": "#000000"],
                                  "terminal": ["ansi": ["#000000", "red"]]]],
        ]
        let env = try #require(ThemeFileRenderer.environment(try JSONSerialization.data(withJSONObject: file)))
        #expect(env == ["SCENE_APPEARANCE": "dark", "SCENE_BACKGROUND": "#112233", "SCENE_ANSI_0": "#000000"])
    }
}
