import AppKit
import Foundation

public struct CLIResult: Sendable {
    public var status: Int32
    public var stdout: String
    public var stderr: String

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum Processes {
    /// Runs an executable with a timeout. Output is captured; nothing inherits Scene's terminal.
    public static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil,
                           timeout: TimeInterval = 60) throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 } }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        try process.run()
        // Read before waiting so a full pipe cannot block the child.
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw SceneError.failed("\(URL(fileURLWithPath: executable).lastPathComponent) timed out")
        }
        return CLIResult(status: process.terminationStatus,
                         stdout: String(decoding: outData, as: UTF8.self),
                         stderr: String(decoding: errData, as: UTF8.self))
    }

    /// PIDs of running GUI apps with a bundle identifier.
    public static func pids(bundleID: String) -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
    }

    /// PIDs of this user's processes with an executable name, such as "hx". Names longer than 15 characters are cut.
    public static func pids(named name: String) -> [pid_t] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var all = [pid_t](repeating: 0, count: capacity)
        let count = Int(proc_listallpids(&all, Int32(capacity * MemoryLayout<pid_t>.size)))
        let uid = getuid()
        var buffer = [CChar](repeating: 0, count: 64)
        return all.prefix(max(0, count)).filter { pid in
            guard pid > 0, proc_name(pid, &buffer, UInt32(buffer.count)) > 0,
                  String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == String(name.prefix(15)) else { return false }
            var info = proc_bsdshortinfo()
            let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            return proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size && info.pbsi_uid == uid
        }
    }

    @discardableResult
    public static func signal(_ sig: Int32, to pids: [pid_t]) -> Int {
        pids.filter { kill($0, sig) == 0 }.count
    }

    /// Finds an executable in the usual install locations. Apps launched from Finder have a minimal PATH.
    public static func findExecutable(_ name: String, extraPaths: [String] = []) -> URL? {
        let paths = extraPaths + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                                  NSHomeDirectory() + "/.local/bin", NSHomeDirectory() + "/bin"]
            + (ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? [])
        for dir in paths {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    /// Bundle version of an installed app.
    public static func appVersion(at appURL: URL) -> String? {
        Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The macOS build number, for example "25G83".
    public static var osBuild: String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    public static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}
