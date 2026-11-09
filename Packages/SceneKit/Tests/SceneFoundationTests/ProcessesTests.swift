import Foundation
import Testing
@testable import SceneFoundation

@Suite struct ProcessesTests {
    @Test func capturesOutputAndStatus() throws {
        let result = try Processes.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"], environment: ["SCENE_X": "1"])
        #expect(result.status == 3)
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
    }

    @Test func passesEnvironment() throws {
        let result = try Processes.run("/bin/sh", ["-c", "printf %s \"$SCENE_X\""], environment: ["SCENE_X": "#1c1b19"])
        #expect(result.stdout == "#1c1b19")
    }

    /// More output than a pipe holds must not block the child.
    @Test func readsLargeOutput() throws {
        let result = try Processes.run("/bin/sh", ["-c", "head -c 1000000 /dev/zero"])
        #expect(result.stdout.utf8.count == 1_000_000)
    }

    @Test func timesOutWhileTheProcessRuns() throws {
        let start = Date()
        #expect(throws: SceneError.self) { try Processes.run("/bin/sleep", ["5"], timeout: 0.5) }
        #expect(Date().timeIntervalSince(start) < 2)
    }

    /// mise puts tools where a GUI app's PATH does not reach (#21).
    @Test func findsToolsThatMiseInstalled() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("scene-mise-\(UUID().uuidString.prefix(6))")
        defer { try? FileManager.default.removeItem(at: home) }
        func tool(_ path: String) throws {
            let url = home.appendingPathComponent(".local/share/mise/\(path)")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try tool("installs/neovim/0.10.4/bin/nvim")
        try tool("installs/neovim/0.11.5/bin/nvim")
        try tool("installs/helix/latest/bin/hx")
        try tool("installs/helix/25.07.1/bin/hx")
        #expect(Processes.miseExecutable("nvim", home: home.path)?.path.hasSuffix("installs/neovim/0.11.5/bin/nvim") == true)
        #expect(Processes.miseExecutable("hx", home: home.path)?.path.hasSuffix("installs/helix/latest/bin/hx") == true)
        #expect(Processes.miseExecutable("btop", home: home.path) == nil)
        try tool("shims/nvim")
        #expect(Processes.miseExecutable("nvim", home: home.path)?.path.hasSuffix("shims/nvim") == true)
    }

    /// A child left running in the background keeps the pipe open. The process has exited, so the call returns.
    @Test func returnsWhenABackgroundChildKeepsThePipe() throws {
        let start = Date()
        let result = try Processes.run("/bin/sh", ["-c", "sleep 5 & echo started"], timeout: 3)
        #expect(result.status == 0)
        #expect(result.stdout == "started\n")
        #expect(Date().timeIntervalSince(start) < 2.5)
    }
}
