import Foundation

public enum SceneError: Error, CustomStringConvertible, Sendable {
    case invalid(String)
    case failed(String)
    public var description: String {
        switch self {
        case .invalid(let s), .failed(let s): s
        }
    }
}
