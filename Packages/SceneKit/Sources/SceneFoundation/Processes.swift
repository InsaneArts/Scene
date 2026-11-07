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
        // Read while the command runs, so a full pipe cannot block it.
        let outReader = PipeReader(out.fileHandleForReading), errReader = PipeReader(err.fileHandleForReading)
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = outReader.finish(by: .now()); _ = errReader.finish(by: .now())
            throw SceneError.failed("\(URL(fileURLWithPath: executable).lastPathComponent) timed out")
        }
        // A child the command left running keeps the pipes open, so wait for the rest of the output only briefly.
        let deadline = DispatchTime.now() + 0.5
        return CLIResult(status: process.terminationStatus,
                         stdout: String(decoding: outReader.finish(by: deadline), as: UTF8.self),
                         stderr: String(decoding: errReader.finish(by: deadline), as: UTF8.self))
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

/// Collects what a pipe delivers until it closes.
private final class PipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()
    private let closed = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [lock, closed] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                closed.signal()
            } else {
                lock.withLock { self.data.append(chunk) }
            }
        }
    }

    /// The output so far, after waiting until `deadline` at most for the pipe to close.
    func finish(by deadline: DispatchTime) -> Data {
        _ = closed.wait(timeout: deadline)
        handle.readabilityHandler = nil
        return lock.withLock { data }
    }
}
