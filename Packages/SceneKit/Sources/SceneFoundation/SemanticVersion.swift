import Foundation

/// Minimal semantic version for app version gates.
public struct SemanticVersion: Comparable, Sendable, CustomStringConvertible {
    public var major: Int, minor: Int, patch: Int
    public init(_ major: Int, _ minor: Int, _ patch: Int) { self.major = major; self.minor = minor; self.patch = patch }
    public init?(_ string: String) {
        let parts = string.split(whereSeparator: { !$0.isNumber }).prefix(3).compactMap { Int($0) }
        guard !parts.isEmpty else { return nil }
        self.init(parts[0], parts.count > 1 ? parts[1] : 0, parts.count > 2 ? parts[2] : 0)
    }
    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }
    public var description: String { "\(major).\(minor).\(patch)" }
}
