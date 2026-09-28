import AppKit
import Foundation
import SceneThemes
import SceneFoundation

/// Paths and lookups an integration may use. Tests point `home` at a fixture folder.
public struct SceneEnvironment: Sendable {
    public var home: URL
    public var appSupport: URL
    public var xdgConfigHome: URL
    public var locateApp: @Sendable (String) -> URL?
    public var locateExecutable: @Sendable (String) -> URL?

    public init(home: URL, appSupport: URL? = nil, xdgConfigHome: URL? = nil,
                locateApp: @escaping @Sendable (String) -> URL?, locateExecutable: @escaping @Sendable (String) -> URL?) {
        self.home = home
        self.appSupport = appSupport ?? home.appendingPathComponent("Library/Application Support/Scene")
        self.xdgConfigHome = xdgConfigHome ?? home.appendingPathComponent(".config")
        self.locateApp = locateApp
        self.locateExecutable = locateExecutable
    }

    public static func live() -> SceneEnvironment {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(fileURLWithPath: $0) }
        return SceneEnvironment(home: home, xdgConfigHome: xdg,
                                locateApp: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
                                locateExecutable: { Processes.findExecutable($0) })
    }

    public func path(_ relative: String) -> URL { home.appendingPathComponent(relative) }
}

/// A built-in integration for one app or system surface.
/// Integrations describe changes. The engine performs, records, verifies, and undoes them.
public protocol Integration: Sendable {
    var id: String { get }
    var displayName: String { get }
    var kind: IntegrationKind { get }

    /// Read-only and fast. Installed? Version? Config files? Conflicts? Setup needed?
    func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection

    /// Pure: maps the request to operations on resources this integration owns.
    func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan

    /// Best effort: make running instances load the new state.
    func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult

    /// Read back the effective state and compare it with the plan.
    func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification
}

public extension Integration {
    func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult { .notNeeded }

    func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        Self.verifyFiles(plan)
    }

    /// Checks that every managed file holds exactly what the plan wrote.
    static func verifyFiles(_ plan: IntegrationPlan) -> Verification {
        for op in plan.operations {
            if case let .writeManagedFile(path, contents) = op,
               FileOps.sha256(fileAt: URL(fileURLWithPath: path)) != FileOps.sha256(contents) {
                return .mismatch("\(Operation.tilde(path)) does not contain what Scene wrote")
            }
        }
        return .matches
    }
}
