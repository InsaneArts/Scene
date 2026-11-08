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

    /// A child left running in the background keeps the pipe open. The process has exited, so the call returns.
    @Test func returnsWhenABackgroundChildKeepsThePipe() throws {
        let start = Date()
        let result = try Processes.run("/bin/sh", ["-c", "sleep 5 & echo started"], timeout: 3)
        #expect(result.status == 0)
        #expect(result.stdout == "started\n")
        #expect(Date().timeIntervalSince(start) < 2.5)
    }
}
