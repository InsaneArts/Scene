import Foundation

/// Lets the ledger and journal store JSON values. Objects keep their key order, so they are
/// stored as `{"$object": [{"key": …, "value": …}]}`.
extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        if let box = try? ObjectBox(from: decoder) {
            self = .object(box.members.map { JSONMember($0.key, $0.value) })
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let v = try? single.decode(Bool.self) { self = .bool(v); return }
        if let v = try? single.decode(Double.self) { self = .number(v); return }
        if let v = try? single.decode(String.self) { self = .string(v); return }
        self = .array(try single.decode([JSONValue].self))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .object(let members):
            try ObjectBox(members: members.map { Pair(key: $0.key, value: $0.value) }).encode(to: encoder)
        default:
            var single = encoder.singleValueContainer()
            switch self {
            case .null: try single.encodeNil()
            case .bool(let v): try single.encode(v)
            case .number(let v): try single.encode(v)
            case .string(let v): try single.encode(v)
            case .array(let v): try single.encode(v)
            case .object: break
            }
        }
    }

    private struct Pair: Codable {
        var key: String
        var value: JSONValue
    }

    private struct ObjectBox: Codable {
        var members: [Pair]
        enum CodingKeys: String, CodingKey { case members = "$object" }
    }
}
