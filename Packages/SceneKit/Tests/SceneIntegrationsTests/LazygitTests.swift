import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("lazygit", .serialized)
struct LazygitTests {
    static let support = "Library/Application Support/lazygit"
    static let config = "# mine\ngui:\n  showIcons: true\n  theme:\n    activeBorderColor:\n      - green\n      - bold\n    authorColors:\n      'Ana': '#ff0000'\ngit:\n  autoFetch: false\n"

    func setup(_ home: FixtureHome) throws -> (FakeServices, Engine) {
        let lazygit = try home.write("bin/lazygit", "#!/bin/sh\n")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { $0 == "lazygit" ? lazygit : nil })
        let services = FakeServices()
        return (services, Engine(env: env, services: services, integrations: [LazygitIntegration()], store: EngineStore(root: env.appSupport)))
    }

    func apply(_ engine: Engine, _ folder: String = "tokyo-night") async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme(folder), mode: .system, systemIsDark: true)
        return await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["lazygit"])
    }

    @Test func setsTheThemeKeysAndRestoreGivesBackTheFile() async throws {
        let home = try FixtureHome()
        try home.write("\(Self.support)/state.yml", "lastversion: 0.57.0\n")
        try home.write("\(Self.support)/config.yml", Self.config)
        let (_, engine) = try setup(home)
        let report = try await apply(engine)
        #expect(report.results.first?.outcome == .applied, "\(String(describing: report.results.first?.outcome))")
        let ui = try #require(try Fixtures.theme("tokyo-night").variants[.dark]).interface
        let text = try #require(home.read("\(Self.support)/config.yml"))
        #expect(text.hasPrefix("# mine\ngui:\n  showIcons: true\n  theme:\n    activeBorderColor: ['\(ui.accent.hex)', bold]\n    authorColors:\n      'Ana': '#ff0000'\n"))
        #expect(text.contains("    selectedLineBgColor: ['\(ui.selection.hex)']\n") && text.hasSuffix("git:\n  autoFetch: false\n"))
        _ = try await apply(engine, "catppuccin")
        _ = await engine.restoreOriginal()
        #expect(home.read("\(Self.support)/config.yml") == Self.config)
    }

    @Test func aNewConfigIsRemovedAgain() async throws {
        let home = try FixtureHome()
        let (_, engine) = try setup(home)
        _ = try await apply(engine)
        #expect(home.read("\(Self.support)/config.yml")?.hasPrefix("gui:\n  theme:\n    activeBorderColor: [") == true)
        _ = await engine.restoreOriginal()
        #expect(!FileManager.default.fileExists(atPath: home.path("\(Self.support)/config.yml").path))
    }

    @Test func takesTheFolderLazygitUses() throws {
        let home = try FixtureHome()
        let env = Fixtures.environment(home, apps: [:])
        #expect(LazygitIntegration.folder(env).path == home.path(Self.support).path)
        try home.write(".config/lazygit/config.yml", "gui: {}\n")
        #expect(LazygitIntegration.folder(env).path == home.path(".config/lazygit").path)
        // lazygit keeps its state where it reads its config, which wins over a config.yml somewhere else.
        try home.write("\(Self.support)/state.yml", "lastversion: 0.57.0\n")
        #expect(LazygitIntegration.folder(env).path == home.path(Self.support).path)
    }

    @Test func aConfigSceneCanNotEditBlocksSetup() async throws {
        let home = try FixtureHome()
        try home.write("\(Self.support)/config.yml", "gui: {theme: {activeBorderColor: [green]}}\n")
        let (services, engine) = try setup(home)
        let detection = await LazygitIntegration().detect(engine.env, services)
        guard case .blocked(let reason) = detection.setup else { Issue.record("\(detection.setup)"); return }
        #expect(reason.contains("gui is not a plain block of keys"))
    }

    /// lazygit reads its config before it opens the terminal: a bad file stops it with "failed to parse".
    /// The check runs lazygit 0.57 from Homebrew when it is installed.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/lazygit")))
    func lazygitReadsTheResult() async throws {
        let home = try FixtureHome()
        try home.write("\(Self.support)/config.yml", Self.config)
        let (_, engine) = try setup(home)
        _ = try await apply(engine)
        let repo = home.path("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        _ = try Processes.run("/usr/bin/git", ["init", "-q", repo.path])
        let result = try Processes.run("/opt/homebrew/bin/lazygit", ["-ucd", home.path(Self.support).path, "-p", repo.path], timeout: 10)
        let output = result.stdout + result.stderr
        // lazygit rewrites a config with outdated keys, and says so; Scene's keys must not need that.
        // Past the config, lazygit stops where it needs a terminal: at /dev/tty, or at TERM in Xcode's test run.
        let reachedTheTerminal = output.contains("/dev/tty") || output.contains("terminal not cursor addressable")
        #expect(!output.contains("failed to parse") && !output.contains("must be migrated") && reachedTheTerminal, "\(output)")
    }
}
