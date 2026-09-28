import Foundation
import SceneThemes
import SceneFoundation

/// The experimental tier (§6.8 of the design doc): private macOS calls that run in the
/// `scene-tweak` helper process, only on macOS builds where they passed a test.
public struct TweakCatalog: Sendable {
    /// macOS builds on which each tweak passed the apply-and-restore suite.
    /// 25G83 (macOS 26.6.2): Scripts/verify-tweaks.sh passed 7 of 7 checks, with every original value restored.
    public static let testedBuilds: [String: Set<String>] = [
        "appearance": ["25G83"],
        "accent": ["25G83"],
        "iconStyle": ["25G83"],
    ]

    public static func isTested(_ id: String, build: String) -> Bool {
        testedBuilds[id]?.contains(build) ?? false
    }
}

public struct TweakPolicy: Sendable {
    public var enabled: Bool
    public var allowUntested: Bool
    public init(enabled: Bool = true, allowUntested: Bool = false) { self.enabled = enabled; self.allowUntested = allowUntested }
}

public final class TweakRunner: @unchecked Sendable {
    public let helper: URL?
    public let build: String
    private let lock = NSLock()
    private var _policy: TweakPolicy
    private var symbolCheck: [String: Bool]?

    public init(helper: URL?, build: String = Processes.osBuild, policy: TweakPolicy = .init()) {
        self.helper = helper; self.build = build; self._policy = policy
    }

    public var policy: TweakPolicy {
        get { lock.withLock { _policy } }
        set { lock.withLock { _policy = newValue } }
    }

    public func availability(_ id: String) -> TweakAvailability {
        let policy = self.policy
        guard policy.enabled else { return .disabled("Experimental settings are off in Settings") }
        guard let helper, FileManager.default.isExecutableFile(atPath: helper.path) else { return .disabled("The scene-tweak helper is missing") }
        guard TweakCatalog.isTested(id, build: build) || policy.allowUntested else {
            return .disabled("Not yet tested on macOS \(Processes.osVersion) (\(build))")
        }
        let checks = lock.withLock { symbolCheck } ?? {
            let result = (try? runHelper(["check"])).flatMap { value -> [String: Bool]? in
                guard case .object(let members) = value else { return nil }
                return Dictionary(uniqueKeysWithValues: members.compactMap { m in
                    if case .bool(let b) = m.value { return (m.key, b) } else { return nil }
                })
            } ?? [:]
            lock.withLock { symbolCheck = result }
            return result
        }()
        guard checks[id] == true else { return .disabled("The private call for \(id) is missing or changed on this macOS build") }
        return .available
    }

    public func get(_ id: String) async throws -> JSONValue {
        try await Task.detached { try self.runHelper(["get", id]) }.value
    }

    public func set(_ id: String, _ value: JSONValue) async throws -> JSONValue {
        try await Task.detached { try self.runHelper(["set", id, value.serialized(indent: "", level: 0).replacingOccurrences(of: "\n", with: "")]) }.value
    }

    func runHelper(_ arguments: [String]) throws -> JSONValue {
        guard let helper else { throw SceneError.failed("scene-tweak helper is missing") }
        let result = try Processes.run(helper.path, arguments, timeout: 20)
        if result.status != 0 && result.stdout.isEmpty {
            throw SceneError.failed("scene-tweak exited with status \(result.status)\(result.status > 128 ? " (crashed)" : ""): \(result.stderr.prefix(200))")
        }
        let document = try JSONCDocument(text: result.stdout)
        guard document.value(forKey: "ok") == .bool(true) else {
            if case .string(let message)? = document.value(forKey: "error") { throw SceneError.failed(message) }
            throw SceneError.failed("scene-tweak failed")
        }
        return document.value(forKey: "value") ?? .null
    }
}
