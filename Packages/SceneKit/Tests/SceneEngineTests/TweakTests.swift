import Foundation
@testable import SceneEngine
import SceneFoundation
import SceneTestSupport
import Testing

@Suite("Experimental tier")
struct TweakTests {
    /// A stand-in helper: a shell script that answers `check` and then behaves as `body` says.
    func helper(_ home: FixtureHome, body: String) throws -> URL {
        let url = try home.write("helper.sh", """
        #!/bin/sh
        if [ "$1" = "check" ]; then echo '{"ok":true,"value":{"accent":true,"appearance":true,"iconStyle":true}}'; exit 0; fi
        \(body)
        """)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func untestedBuildStaysOffAndSaysWhy() throws {
        let home = try FixtureHome()
        let runner = TweakRunner(helper: try helper(home, body: "exit 0"), build: "99Z999")
        #expect(runner.availability("accent") == .disabled("Not yet tested on macOS \(Processes.osVersion) (99Z999)"))
        runner.policy = TweakPolicy(enabled: true, allowUntested: true)
        #expect(runner.availability("accent") == .available)
        runner.policy = TweakPolicy(enabled: false, allowUntested: true)
        if case .disabled = runner.availability("accent") {} else { Issue.record("expected disabled when experimental settings are off") }
    }

    @Test func missingPrivateCallTurnsTweakOff() throws {
        let home = try FixtureHome()
        let url = try home.write("helper.sh", "#!/bin/sh\necho '{\"ok\":true,\"value\":{\"accent\":false,\"appearance\":true,\"iconStyle\":true}}'\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let runner = TweakRunner(helper: url, build: "X", policy: TweakPolicy(enabled: true, allowUntested: true))
        if case .disabled(let reason) = runner.availability("accent") { #expect(reason.contains("missing or changed")) }
        else { Issue.record("expected accent to be off") }
        #expect(runner.availability("appearance") == .available)
    }

    @Test func helperCrashBecomesAnError() async throws {
        let home = try FixtureHome()
        let runner = TweakRunner(helper: try helper(home, body: "kill -SEGV $$"), build: "X", policy: TweakPolicy(enabled: true, allowUntested: true))
        await #expect(throws: SceneError.self) { _ = try await runner.set("accent", .number(5)) }
    }

    @Test func helperErrorIsReported() async throws {
        let home = try FixtureHome()
        let runner = TweakRunner(helper: try helper(home, body: "echo '{\"ok\":false,\"error\":\"accent read back 4, expected 5; reverted\"}'; exit 1"),
                                 build: "X", policy: TweakPolicy(enabled: true, allowUntested: true))
        do { _ = try await runner.set("accent", .number(5)); Issue.record("expected an error") }
        catch { #expect("\(error)".contains("reverted")) }
    }

    @Test func realHelperResolvesOnThisMac() throws {
        guard let helper = Repo.tweakHelper else { return }
        // Read-only: `check` and `get` never change anything.
        let check = try Processes.run(helper.path, ["check"])
        #expect(check.stdout.contains("\"ok\":true"), "\(check.stdout)")
        let accent = try Processes.run(helper.path, ["get", "accent"])
        #expect(accent.stdout.contains("\"ok\":true"))
    }
}
