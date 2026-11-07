import Foundation
import SceneFoundation
import Testing

@Suite("Processes")
struct ProcessesTests {
    @Test func capturesOutputAndStatus() throws {
        let result = try Processes.run("/bin/sh", ["-c", "echo out; echo err >&2; head -c 300000 /dev/zero | tr '\\0' x; exit 3"])
        #expect(result.status == 3)
        #expect(result.stdout.hasPrefix("out\n") && result.stdout.count == 4 + 300_000)
        #expect(result.stderr == "err\n")
    }

    @Test func aCommandThatHangsTimesOut() throws {
        let started = Date()
        #expect(throws: SceneError.self) { try Processes.run("/bin/sh", ["-c", "sleep 5"], timeout: 0.5) }
        #expect(Date().timeIntervalSince(started) < 2)
    }

    /// A child left running keeps the pipes open. The result comes when the command exits, with its output.
    @Test func aChildLeftRunningDoesNotHoldTheResult() throws {
        let started = Date()
        let result = try Processes.run("/bin/sh", ["-c", "echo started; sleep 5 & exit 0"], timeout: 3)
        #expect(Date().timeIntervalSince(started) < 2)
        #expect(result.status == 0 && result.stdout == "started\n")
    }
}
