import Foundation
@testable import SceneIntegrations
@testable import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("k9s", .serialized)
struct K9sTests {
    static let support = "Library/Application Support/k9s"
    static let config = "k9s:\n  refreshRate: 2\n  ui:\n    #skin: tokyo-night\n    skin: omarchy\n    enableMouse: false\n  readOnly: false\n"

    func setup(_ home: FixtureHome) throws -> Engine {
        let k9s = try home.write("bin/k9s", "#!/bin/sh\n")
        let env = SceneEnvironment(home: home.url, locateApp: { _ in nil }, locateExecutable: { $0 == "k9s" ? k9s : nil })
        return Engine(env: env, services: FakeServices(), integrations: [K9sIntegration()], store: EngineStore(root: env.appSupport))
    }

    func apply(_ engine: Engine) async throws -> ApplyReport {
        let request = ApplyRequest(theme: try Fixtures.theme("tokyo-night"), mode: .system, systemIsDark: true)
        return await engine.apply(request, planned: await engine.plan(request, detections: await engine.detectAll()), selected: ["k9s"])
    }

    @Test func writesTheSkinSelectsItAndRestoreGivesBackTheConfig() async throws {
        let home = try FixtureHome()
        try home.write("\(Self.support)/config.yaml", Self.config)
        let engine = try setup(home)
        let report = try await apply(engine)
        #expect(report.results.first?.outcome == .applied, "\(String(describing: report.results.first?.outcome))")
        let ui = try #require(try Fixtures.theme("tokyo-night").variants[.dark]).interface
        #expect(home.read("\(Self.support)/config.yaml") == Self.config.replacingOccurrences(of: "skin: omarchy", with: "skin: scene"))
        let skin = try #require(home.read("\(Self.support)/skins/scene.yaml"))
        #expect(skin.contains("focusColor: \"\(ui.accent.hex)\"") && skin.contains("k9s:\n  body:"))
        _ = await engine.restoreOriginal()
        #expect(home.read("\(Self.support)/config.yaml") == Self.config)
        #expect(!FileManager.default.fileExists(atPath: home.path("\(Self.support)/skins/scene.yaml").path))
    }

    @Test func writesThroughLinksAndKeepsThem() async throws {
        let home = try FixtureHome()
        try home.write("\(Self.support)/config.yaml", Self.config)
        try FileManager.default.createDirectory(at: home.path("\(Self.support)/skins"), withIntermediateDirectories: true)
        let xdg = home.path(".config/k9s")
        try FileManager.default.createDirectory(at: xdg, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: xdg.appendingPathComponent("config.yaml"), withDestinationURL: home.path("\(Self.support)/config.yaml"))
        try FileManager.default.createSymbolicLink(at: xdg.appendingPathComponent("skins"), withDestinationURL: home.path("\(Self.support)/skins"))
        let engine = try setup(home)
        #expect(K9sIntegration.folder(engine.env).path == xdg.path)
        _ = try await apply(engine)
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: xdg.appendingPathComponent("config.yaml").path)
        #expect(link == home.path("\(Self.support)/config.yaml").path)
        #expect(home.read("\(Self.support)/config.yaml")?.contains("skin: scene\n") == true)
        #expect(FileManager.default.fileExists(atPath: home.path("\(Self.support)/skins/scene.yaml").path))
        _ = await engine.restoreOriginal()
        #expect(home.read("\(Self.support)/config.yaml") == Self.config)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: xdg.appendingPathComponent("config.yaml").path)) == link)
    }

    @Test func aNewConfigIsRemovedAgain() async throws {
        let home = try FixtureHome()
        let engine = try setup(home)
        _ = try await apply(engine)
        #expect(home.read("\(Self.support)/config.yaml") == "k9s:\n  ui:\n    skin: scene\n")
        _ = await engine.restoreOriginal()
        #expect(!FileManager.default.fileExists(atPath: home.path("\(Self.support)/config.yaml").path))
    }

    @Test func aConfigSceneCanNotEditBlocksSetup() async throws {
        let home = try FixtureHome()
        try home.write("\(Self.support)/config.yaml", "k9s: {ui: {skin: omarchy}}\n")
        let engine = try setup(home)
        let detection = await K9sIntegration().detect(engine.env, FakeServices())
        guard case .blocked(let reason) = detection.setup else { Issue.record("\(detection.setup)"); return }
        #expect(reason.contains("k9s is not a plain block of keys"))
    }
}
