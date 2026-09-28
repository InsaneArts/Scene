import Foundation

// MARK: - Values

public struct JSONMember: Equatable, Sendable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

public indirect enum JSONValue: Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([JSONMember])

    /// Serializes with the given indentation unit and starting indentation level.
    /// The first line has no indentation. Nested lines get `level + 1` units, the closing bracket `level` units.
    /// Integral doubles print without ".0". Non-finite numbers print as `null`, as `JSON.stringify` does.
    /// Strings are escaped per RFC 8259 (escape ", \, control chars; keep non-ASCII as-is).
    public func serialized(indent: String = "  ", level: Int = 0) -> String {
        var out = ""
        write(into: &out, indent: indent, level: level)
        return out
    }

    private func write(into out: inout String, indent: String, level: Int) {
        switch self {
        case .null:
            out += "null"
        case .bool(let flag):
            out += flag ? "true" : "false"
        case .number(let number):
            if !number.isFinite {
                out += "null"
            } else if let integer = Int64(exactly: number) {
                out += String(integer)
            } else {
                out += number.description
            }
        case .string(let string):
            Self.quote(string, into: &out)
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            out += "["
            for (n, item) in items.enumerated() {
                out += (n == 0 ? "\n" : ",\n") + String(repeating: indent, count: level + 1)
                item.write(into: &out, indent: indent, level: level + 1)
            }
            out += "\n" + String(repeating: indent, count: level) + "]"
        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            out += "{"
            for (n, member) in members.enumerated() {
                out += (n == 0 ? "\n" : ",\n") + String(repeating: indent, count: level + 1)
                Self.quote(member.key, into: &out)
                out += ": "
                member.value.write(into: &out, indent: indent, level: level + 1)
            }
            out += "\n" + String(repeating: indent, count: level) + "}"
        }
    }

    private static func quote(_ string: String, into out: inout String) {
        out += "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where scalar.value < 0x20:
                let hex = String(scalar.value, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        out += "\""
    }
}

public enum JSONCError: Error, Equatable, Sendable {
    /// `line` and `column` are 1-based. `column` counts Unicode scalars.
    case syntax(line: Int, column: Int, message: String)
    case topLevelNotObject
}

// MARK: - Document

/// A JSONC text whose top-level keys can be edited without touching comments or formatting elsewhere.
public struct JSONCDocument: Sendable {
    public private(set) var text: String
    private var members: [Member]
    private var braces: (open: Int, close: Int)?

    /// Empty or whitespace/comment-only text is treated as an empty object.
    public init(text: String) throws {
        self.text = text
        let parsed = try parseDocument(Array(text.utf8))
        members = parsed.members
        braces = parsed.braces
    }

    /// Top-level key lookup. Comments are ignored. The last duplicate wins, as in VS Code.
    public func value(forKey key: String) -> JSONValue? {
        members.last { $0.key == key }?.value
    }

    /// Top-level keys in order. A duplicated key is listed once, at its first position.
    public var keys: [String] {
        var seen: Set<String> = []
        return members.compactMap { seen.insert($0.key).inserted ? $0.key : nil }
    }

    /// Sets (value != nil) or removes (value == nil) a top-level key, changing as little text as possible.
    /// If the key appears more than once, the last occurrence is edited and the others stay.
    public mutating func set(_ value: JSONValue?, forKey key: String) throws {
        let bytes = Array(text.utf8)
        let edits: [Edit]
        if let index = members.lastIndex(where: { $0.key == key }) {
            if let value {
                let member = members[index]
                guard value != member.value else { return }
                let indent = indentation(bytes, member.valueRange.lowerBound)
                edits = [(member.valueRange, render(value, bytes, indent: indent))]
            } else {
                edits = removal(of: index, bytes)
            }
        } else if let value {
            edits = insertion(of: key, value, bytes)
        } else {
            return
        }
        let result = apply(edits, to: bytes)
        let parsed = try parseDocument(result)
        text = String(decoding: result, as: UTF8.self)
        members = parsed.members
        braces = parsed.braces
    }
}

// MARK: - Editing

/// Replaces `range` (UTF-8 offsets) with `text`.
private typealias Edit = (range: Range<Int>, text: String)

extension JSONCDocument {
    /// Serializes `value` for a line indented with `indent`, in the document's indentation unit and line ending.
    private func render(_ value: JSONValue, _ b: [UInt8], indent: String) -> String {
        value.serialized(indent: indentUnit(b))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .joined(separator: lineEnding(b) + indent)
    }

    /// The indentation of the first member on a line below "{". Otherwise a tab if a line starts with one, else two spaces.
    private func indentUnit(_ b: [UInt8]) -> String {
        if let open = braces?.open, let member = members.first(where: { lineStart(b, $0.start) > open }) {
            let indent = indentation(b, member.start)
            if !indent.isEmpty { return indent }
        }
        let tabs = b.indices.contains { b[$0] == 0x09 && ($0 == 0 || isLineBreak(b[$0 - 1])) }
        return tabs ? "\t" : "  "
    }

    private func insertion(of key: String, _ value: JSONValue, _ b: [UInt8]) -> [Edit] {
        let eol = lineEnding(b)
        let unit = indentUnit(b)
        func member(indent: String) -> String {
            JSONValue.string(key).serialized() + ": " + render(value, b, indent: indent)
        }
        guard let braces else {
            // Empty or comment-only text: add an object after the last comment.
            let p = endOfLastComment(b, 0..<b.count)
            return [(p..<p, (p > 0 ? eol : "") + "{" + eol + unit + member(indent: unit) + eol + "}")]
        }
        let braceIndent = indentation(b, braces.open)
        guard let last = members.last else {
            // Empty object: insert after any comments in it, and keep "}" on its own line.
            let p = endOfLastComment(b, braces.open + 1..<braces.close)
            let indent = braceIndent + unit
            let text = eol + indent + member(indent: indent)
            if b[p..<braces.close].contains(where: isLineBreak) { return [(p..<p, text)] }
            return [(p..<braces.close, text + eol + braceIndent)]
        }
        // After the last member and the comments on its line, before comments on later lines.
        let anchor = last.comma.map { $0 + 1 } ?? last.valueRange.upperBound
        let p = sameLineTrivia(b, from: anchor).end
        let text: String
        if b[braces.open..<braces.close].contains(where: isLineBreak) {
            let indent = lineStart(b, last.start) > braces.open ? indentation(b, last.start) : braceIndent + unit
            text = eol + indent + member(indent: indent)
        } else {
            text = " " + member(indent: braceIndent)  // A single-line object stays on one line.
        }
        // Keep the trailing-comma style of the last member.
        if last.comma != nil { return [(p..<p, text + ",")] }
        return [(anchor..<anchor, ","), (p..<p, text)]
    }

    private func removal(of index: Int, _ b: [UInt8]) -> [Edit] {
        let member = members[index]
        var edits: [Edit] = []
        // The last member has no comma of its own to remove, so the previous member loses its comma.
        if index == members.count - 1, member.comma == nil, index > 0, let comma = members[index - 1].comma {
            edits.append((comma..<comma + 1, ""))
        }
        let end = member.comma.map { $0 + 1 } ?? member.valueRange.upperBound
        let rest = sameLineTrivia(b, from: end)
        let lineBegin = lineStart(b, member.start)
        if rest.atLineEnd, b[lineBegin..<member.start].allSatisfy(isSpaceOrTab) {
            // Alone on its line: delete the line, with any comment at its end.
            edits.append((lineBegin..<afterLineBreak(b, rest.end), ""))
        } else {
            var e = end
            while e < b.count, isSpaceOrTab(b[e]) { e += 1 }
            edits.append((member.start..<e, ""))
        }
        return edits
    }
}

/// Applies edits that are sorted by position and do not overlap.
private func apply(_ edits: [Edit], to b: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var k = 0
    for edit in edits {
        out += b[k..<edit.range.lowerBound]
        out += edit.text.utf8
        k = edit.range.upperBound
    }
    return out + b[k...]
}

// MARK: - Text helpers (UTF-8 offsets into parsed text)

private func isSpaceOrTab(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 }
private func isLineBreak(_ c: UInt8) -> Bool { c == 0x0A || c == 0x0D }

private func lineStart(_ b: [UInt8], _ pos: Int) -> Int {
    var k = pos
    while k > 0, !isLineBreak(b[k - 1]) { k -= 1 }
    return k
}

/// The spaces and tabs at the start of the line that contains `pos`.
private func indentation(_ b: [UInt8], _ pos: Int) -> String {
    let start = lineStart(b, pos)
    let end = b[start...].firstIndex { !isSpaceOrTab($0) } ?? b.count
    return String(decoding: b[start..<end], as: UTF8.self)
}

/// The offset after the line break at `k` (CRLF counts as one), or `k` at the end of the text.
private func afterLineBreak(_ b: [UInt8], _ k: Int) -> Int {
    guard k < b.count else { return k }
    return b[k] == 0x0D && k + 1 < b.count && b[k + 1] == 0x0A ? k + 2 : k + 1
}

/// "\r\n" if the first line break is CRLF, else "\n".
private func lineEnding(_ b: [UInt8]) -> String {
    guard let n = b.firstIndex(of: 0x0A), n > 0, b[n - 1] == 0x0D else { return "\n" }
    return "\r\n"
}

/// The offset after the comment that starts at `k`. For a line comment, the offset of its line break.
private func commentEnd(_ b: [UInt8], _ k: Int) -> Int {
    var e = k + 2
    if b[k + 1] == UInt8(ascii: "/") {
        while e < b.count, !isLineBreak(b[e]) { e += 1 }
        return e
    }
    while !(b[e] == UInt8(ascii: "*") && b[e + 1] == UInt8(ascii: "/")) { e += 1 }
    return e + 2
}

/// Skips spaces, tabs and comments from `pos` along its line.
/// If nothing else is on the line, returns the line break offset (or the text end) and `atLineEnd == true`.
/// Otherwise returns the end of the last comment skipped, or `pos`.
private func sameLineTrivia(_ b: [UInt8], from pos: Int) -> (end: Int, atLineEnd: Bool) {
    var end = pos, k = pos
    while true {
        while k < b.count, isSpaceOrTab(b[k]) { k += 1 }
        if k == b.count || isLineBreak(b[k]) { return (k, true) }
        guard b[k] == UInt8(ascii: "/") else { return (end, false) }  // After a value, "/" starts a comment.
        k = commentEnd(b, k)
        end = k
    }
}

/// The end of the last comment in `range`, which holds only whitespace and comments. `range.lowerBound` if none.
private func endOfLastComment(_ b: [UInt8], _ range: Range<Int>) -> Int {
    var end = range.lowerBound, k = range.lowerBound
    while k < range.upperBound {
        if b[k] == UInt8(ascii: "/") {
            k = commentEnd(b, k)
            end = k
        } else {
            k += 1
        }
    }
    return end
}

// MARK: - Parsing

/// A top-level member and the UTF-8 offsets of its parts.
private struct Member: Sendable {
    var key: String
    var value: JSONValue
    var start: Int  // The key's opening quote.
    var valueRange: Range<Int>
    var comma: Int?  // The comma after the value.
}

private func parseDocument(_ b: [UInt8]) throws -> (members: [Member], braces: (open: Int, close: Int)?) {
    var parser = Parser(b: b)
    try parser.skipTrivia()
    if parser.i == b.count { return ([], nil) }
    let open = parser.i
    let value = try parser.parseValue(depth: 0)
    let close = parser.i - 1
    try parser.skipTrivia()
    guard parser.i == b.count else { throw parser.error("Unexpected content after the top-level value") }
    guard case .object = value else { throw JSONCError.topLevelNotObject }
    return (parser.members, (open, close))
}

private struct Parser {
    let b: [UInt8]
    var i = 0
    var members: [Member] = []  // Members of the top-level object.

    func peek(_ c: Unicode.Scalar) -> Bool { i < b.count && b[i] == UInt8(ascii: c) }

    func error(_ message: String, at position: Int? = nil) -> JSONCError {
        let end = position ?? i
        var line = 1, lineBegin = 0
        for k in 0..<end where b[k] == 0x0A || (b[k] == 0x0D && (k + 1 == b.count || b[k + 1] != 0x0A)) {
            line += 1
            lineBegin = k + 1
        }
        let column = b[lineBegin..<end].filter { ($0 & 0xC0) != 0x80 }.count + 1
        return .syntax(line: line, column: column, message: message)
    }

    mutating func skipTrivia() throws {
        while i < b.count {
            if isSpaceOrTab(b[i]) || isLineBreak(b[i]) {
                i += 1
            } else if peek("/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "/") {
                while i < b.count, !isLineBreak(b[i]) { i += 1 }
            } else if peek("/"), i + 1 < b.count, b[i + 1] == UInt8(ascii: "*") {
                let start = i
                i += 2
                while !(i + 1 < b.count && b[i] == UInt8(ascii: "*") && b[i + 1] == UInt8(ascii: "/")) {
                    guard i < b.count else { throw error("Unterminated block comment", at: start) }
                    i += 1
                }
                i += 2
            } else {
                return
            }
        }
    }

    mutating func parseValue(depth: Int) throws -> JSONValue {
        // Parsing recurses per level (about 2.3 KB of stack in debug builds), so a 512 KB thread stack needs a limit.
        guard depth < 128 else { throw error("Nesting is too deep") }
        guard i < b.count else { throw error("Expected a value") }
        switch b[i] {
        case UInt8(ascii: "{"): return .object(try parseObject(depth: depth))
        case UInt8(ascii: "["): return .array(try parseArray(depth: depth))
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .number(try parseNumber())
        default:
            for (word, value) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)]
            where b[i...].starts(with: word.utf8) {
                i += word.utf8.count
                return value
            }
            throw error("Expected a value")
        }
    }

    mutating func parseObject(depth: Int) throws -> [JSONMember] {
        i += 1
        var result: [JSONMember] = []
        while true {
            try skipTrivia()
            if peek("}") { i += 1; return result }
            guard peek("\"") else { throw error("Expected a property name or '}'") }
            let start = i
            let key = try parseString()
            try skipTrivia()
            guard peek(":") else { throw error("Expected ':'") }
            i += 1
            try skipTrivia()
            let valueStart = i
            let value = try parseValue(depth: depth + 1)
            let valueRange = valueStart..<i
            result.append(JSONMember(key, value))
            try skipTrivia()
            let comma = peek(",") ? i : nil
            if depth == 0 {
                members.append(Member(key: key, value: value, start: start, valueRange: valueRange, comma: comma))
            }
            guard comma != nil else { break }
            i += 1
        }
        guard peek("}") else { throw error("Expected ',' or '}'") }
        i += 1
        return result
    }

    mutating func parseArray(depth: Int) throws -> [JSONValue] {
        i += 1
        var result: [JSONValue] = []
        while true {
            try skipTrivia()
            if peek("]") { i += 1; return result }
            result.append(try parseValue(depth: depth + 1))
            try skipTrivia()
            guard peek(",") else { break }
            i += 1
        }
        guard peek("]") else { throw error("Expected ',' or ']'") }
        i += 1
        return result
    }

    mutating func parseString() throws -> String {
        let start = i
        i += 1
        var bytes: [UInt8] = []
        while true {
            guard i < b.count, !isLineBreak(b[i]) else { throw error("Unterminated string", at: start) }
            switch b[i] {
            case UInt8(ascii: "\""):
                i += 1
                return String(decoding: bytes, as: UTF8.self)
            case UInt8(ascii: "\\"):
                try parseEscape(into: &bytes)
            case ..<0x20:
                throw error("Control character in string")
            default:
                bytes.append(b[i])
                i += 1
            }
        }
    }

    mutating func parseEscape(into bytes: inout [UInt8]) throws {
        let start = i
        i += 1
        guard i < b.count else { throw error("Invalid escape sequence", at: start) }
        let c = b[i]
        i += 1
        switch c {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): bytes.append(c)
        case UInt8(ascii: "b"): bytes.append(0x08)
        case UInt8(ascii: "f"): bytes.append(0x0C)
        case UInt8(ascii: "n"): bytes.append(0x0A)
        case UInt8(ascii: "r"): bytes.append(0x0D)
        case UInt8(ascii: "t"): bytes.append(0x09)
        case UInt8(ascii: "u"):
            var code = try hex4(escapeStart: start)
            // A high surrogate followed by a low one is one scalar. Lone surrogates become U+FFFD.
            if (0xD800..<0xDC00).contains(code), b[i...].starts(with: "\\u".utf8) {
                let next = i
                i += 2
                let low = try hex4(escapeStart: next)
                if (0xDC00..<0xE000).contains(low) {
                    code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                } else {
                    i = next
                }
            }
            bytes += (Unicode.Scalar(code) ?? "\u{FFFD}").utf8
        default:
            throw error("Invalid escape sequence", at: start)
        }
    }

    mutating func hex4(escapeStart: Int) throws -> UInt32 {
        var code: UInt32 = 0
        for _ in 0..<4 {
            guard i < b.count, let digit = Character(Unicode.Scalar(b[i])).hexDigitValue else {
                throw error("Invalid unicode escape", at: escapeStart)
            }
            code = code << 4 | UInt32(digit)
            i += 1
        }
        return code
    }

    mutating func parseNumber() throws -> Double {
        let start = i
        if peek("-") { i += 1 }
        if peek("0") { i += 1 } else { try digits() }
        if peek(".") { i += 1; try digits() }
        if peek("e") || peek("E") {
            i += 1
            if peek("+") || peek("-") { i += 1 }
            try digits()
        }
        // The JSON number grammar is a subset of what Double parses. Out-of-range values become ±infinity.
        return Double(String(decoding: b[start..<i], as: UTF8.self))!
    }

    mutating func digits() throws {
        let start = i
        while i < b.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(b[i]) { i += 1 }
        guard i > start else { throw error("Expected a digit") }
    }
}
