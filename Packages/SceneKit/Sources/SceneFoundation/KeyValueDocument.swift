import Foundation

/// Edits one key in a TOML-style `key = value` file (TOML files, and btop.conf) and keeps every other line
/// byte-identical. A value is raw TOML text, such as `"scene"` or `["/path/a.toml"]`.
/// A key is dotted and names its table: `general.import` matches `import` under `[general]`
/// and a root line `general.import = …`.
public struct KeyValueDocument: Sendable {
    public private(set) var text: String

    public init(text: String) { self.text = text }

    struct Entry {
        var fullKey: String
        /// The table the line sits in. Nil for the root.
        var table: String?
        /// The key as written, such as `theme` or `general.import`.
        var spelling: String
        var indent: String
        var lines: ClosedRange<Int>
        var value: String
        /// A comment after the value on its last line, with its leading space.
        var comment: String
    }

    struct Header {
        var line: Int
        var name: String
        var isArray: Bool
    }

    /// The raw value of a dotted key, or nil when the file does not set it. The last line wins, as in TOML.
    public func value(forKey key: String) -> String? {
        scan().entries.last { $0.fullKey == key }?.value
    }

    /// The dotted keys the file sets, in order.
    public var keys: [String] { scan().entries.map(\.fullKey) }

    /// Sets `key` in `table` (nil for the root) to a raw value, or removes it when `value` is nil.
    /// A new root key goes before the first table. A new key in a missing table appends that table,
    /// unless the file defines the table with dotted keys, which a `[table]` header must not repeat.
    public mutating func set(_ value: String?, forKey key: String, inTable table: String? = nil) {
        let fullKey = (table.map { $0 + "." } ?? "") + key
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        let (scanned, entries, headers) = scan()
        var lines = scanned
        if let entry = entries.last(where: { $0.fullKey == fullKey }) {
            if let value {
                lines.replaceSubrange(entry.lines, with: [entry.indent + entry.spelling + " = " + value + entry.comment])
            } else {
                lines.removeSubrange(entry.lines)
                if let table = entry.table { Self.removeEmptyTable(table, from: &lines) }
            }
        } else if let value {
            if let table {
                if let header = headers.first(where: { !$0.isArray && $0.name == table }) {
                    let last = entries.filter { $0.table == table && $0.lines.lowerBound > header.line }.map(\.lines.upperBound)
                        .filter { line in !headers.contains { $0.line > header.line && $0.line < line } }.max()
                    lines.insert(key + " = " + value, at: (last ?? header.line) + 1)
                } else if let dotted = entries.last(where: { $0.table == nil && $0.fullKey.hasPrefix(table + ".") }) {
                    lines.insert(fullKey + " = " + value, at: dotted.lines.upperBound + 1)
                } else {
                    if let last = lines.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { lines.append("") }
                    lines += ["[\(table)]", key + " = " + value]
                }
            } else {
                lines.insert(key + " = " + value, at: headers.first?.line ?? lines.count)
            }
        } else {
            return
        }
        let trailing = text.hasSuffix("\n") || text.isEmpty
        text = lines.joined(separator: newline) + (trailing && !lines.isEmpty ? newline : "")
    }

    /// A TOML basic string.
    public static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { out += String(format: "\\u%04X", scalar.value) }
                else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// The strings of a one-level TOML array of strings, such as `["a", 'b']`. Nil for anything else.
    public static func stringArray(_ raw: String) -> [String]? {
        var text = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard text.hasPrefix("["), text.hasSuffix("]") else { return nil }
        text = text.dropFirst().dropLast()
        var items: [String] = []
        var index = text.startIndex
        func skip() {
            while index < text.endIndex {
                if text[index].isWhitespace || text[index] == "," { index = text.index(after: index) }
                else if text[index] == "#" { while index < text.endIndex, !text[index].isNewline { index = text.index(after: index) } }
                else { return }
            }
        }
        skip()
        while index < text.endIndex {
            let quote = text[index]
            guard quote == "\"" || quote == "'" else { return nil }
            index = text.index(after: index)
            var item = ""
            var closed = false
            while index < text.endIndex {
                let c = text[index]
                index = text.index(after: index)
                if c == quote { closed = true; break }
                if c == "\\", quote == "\"" {
                    guard index < text.endIndex else { return nil }
                    let escaped = text[index]
                    index = text.index(after: index)
                    switch escaped {
                    case "\"", "\\": item.append(escaped)
                    case "n": item.append("\n")
                    case "t": item.append("\t")
                    default: return nil
                    }
                } else {
                    item.append(c)
                }
            }
            guard closed else { return nil }
            items.append(item)
            skip()
        }
        return items
    }

    // MARK: Scanning

    func scan() -> (lines: [String], entries: [Entry], headers: [Header]) {
        let lines = Self.split(text)
        var entries: [Entry] = []
        var headers: [Header] = []
        var table: String?
        var isArrayTable = false
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { index += 1; continue }
            if trimmed.hasPrefix("[") {
                let isArray = trimmed.hasPrefix("[[")
                var inner = Substring(trimmed.dropFirst(isArray ? 2 : 1))
                if let close = inner.firstIndex(of: "]") { inner = inner[..<close] }
                let name = Self.normalize(String(inner))
                headers.append(Header(line: index, name: name, isArray: isArray))
                table = name
                isArrayTable = isArray
                index += 1
                continue
            }
            guard let equals = Self.assignment(in: line) else { index += 1; continue }
            let spelling = String(line[..<equals]).trimmingCharacters(in: .whitespaces)
            var valueText = String(line[line.index(after: equals)...])
            var last = index
            while !Self.isComplete(valueText), last + 1 < lines.count {
                last += 1
                valueText += "\n" + lines[last]
            }
            let (value, comment) = Self.splitComment(valueText)
            let owner = isArrayTable ? table.map { "[[\($0)]]" } : table
            entries.append(Entry(fullKey: (owner.map { $0 + "." } ?? "") + Self.normalize(spelling), table: owner, spelling: spelling,
                                 indent: String(line.prefix { $0 == " " || $0 == "\t" }), lines: index...last,
                                 value: value.trimmingCharacters(in: .whitespaces), comment: comment))
            index = last + 1
        }
        return (lines, entries, headers)
    }

    /// Removes a `[table]` header that has nothing but blank lines under it, and the blank line before it.
    static func removeEmptyTable(_ table: String, from lines: inout [String]) {
        guard let header = lines.firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") && normalize(String(trimmed.dropFirst().prefix { $0 != "]" })) == table
        }) else { return }
        var end = header + 1
        while end < lines.count, lines[end].trimmingCharacters(in: .whitespaces).isEmpty { end += 1 }
        guard end == lines.count || lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") else { return }
        var start = header
        if start > 0, lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty { start -= 1 }
        lines.removeSubrange(start..<(end == lines.count ? end : header + 1))
    }

    /// `a . "b.c"` becomes `a.b.c`: segments trimmed, quotes dropped.
    static func normalize(_ key: String) -> String {
        var segments: [String] = []
        var current = ""
        var quote: Character?
        for c in key {
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "." {
                segments.append(current.trimmingCharacters(in: .whitespaces)); current = ""
            } else {
                current.append(c)
            }
        }
        segments.append(current.trimmingCharacters(in: .whitespaces))
        return segments.joined(separator: ".")
    }

    /// The index of the `=` that assigns a value, outside quoted keys.
    static func assignment(in line: String) -> String.Index? {
        var quote: Character?
        for index in line.indices {
            let c = line[index]
            if let q = quote { if c == q { quote = nil } }
            else if c == "\"" || c == "'" { quote = c }
            else if c == "#" { return nil }
            else if c == "=" { return index }
        }
        return nil
    }

    /// True when brackets and braces are closed and no multi-line string is open.
    static func isComplete(_ value: String) -> Bool {
        var depth = 0
        var i = value.startIndex
        while i < value.endIndex {
            let rest = value[i...]
            if rest.hasPrefix("\"\"\"") || rest.hasPrefix("'''") {
                let delimiter = String(rest.prefix(3))
                guard let close = value.range(of: delimiter, range: value.index(i, offsetBy: 3)..<value.endIndex) else { return false }
                i = close.upperBound
                continue
            }
            let c = value[i]
            if c == "\"" || c == "'" {
                var j = value.index(after: i)
                while j < value.endIndex, value[j] != c, !value[j].isNewline {
                    if c == "\"", value[j] == "\\" { j = value.index(after: j); if j == value.endIndex { break } }
                    j = value.index(after: j)
                }
                i = j < value.endIndex ? value.index(after: j) : j
                continue
            }
            if c == "#" {
                while i < value.endIndex, !value[i].isNewline { i = value.index(after: i) }
                continue
            }
            if c == "[" || c == "{" { depth += 1 } else if c == "]" || c == "}" { depth -= 1 }
            i = value.index(after: i)
        }
        return depth <= 0
    }

    /// Splits a trailing comment off a value. Comments inside a multi-line array stay in the value.
    static func splitComment(_ value: String) -> (String, String) {
        var depth = 0
        var i = value.startIndex
        while i < value.endIndex {
            let rest = value[i...]
            if rest.hasPrefix("\"\"\"") || rest.hasPrefix("'''") {
                let delimiter = String(rest.prefix(3))
                guard let close = value.range(of: delimiter, range: value.index(i, offsetBy: 3)..<value.endIndex) else { return (value, "") }
                i = close.upperBound
                continue
            }
            let c = value[i]
            if c == "\"" || c == "'" {
                var j = value.index(after: i)
                while j < value.endIndex, value[j] != c, !value[j].isNewline {
                    if c == "\"", value[j] == "\\" { j = value.index(after: j); if j == value.endIndex { break } }
                    j = value.index(after: j)
                }
                i = j < value.endIndex ? value.index(after: j) : j
                continue
            }
            if c == "#" {
                if depth == 0 {
                    var start = i
                    while start > value.startIndex, value[value.index(before: start)] == " " || value[value.index(before: start)] == "\t" {
                        start = value.index(before: start)
                    }
                    return (String(value[..<start]), String(value[start...]))
                }
                while i < value.endIndex, !value[i].isNewline { i = value.index(after: i) }
                continue
            }
            if c == "[" || c == "{" { depth += 1 } else if c == "]" || c == "}" { depth -= 1 }
            i = value.index(after: i)
        }
        return (value, "")
    }

    static func split(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }
}
