import Foundation

/// Edits keys in the block mappings of a YAML file, such as lazygit's `config.yml`, and keeps every other line
/// byte-identical. Every mapping on a key's path must be in block style: `key:` alone on its line (a comment may
/// follow), with its children indented below. Any other shape on the path is refused, so Scene never guesses.
/// A value is raw YAML text as it follows the colon, with its leading space, such as ` ['#1a1b26', bold]`.
/// A value read from the file can span lines, as a block sequence does; writing it back gives the same bytes.
public struct YAMLDocument: Sendable {
    public enum Problem: Error, Equatable, CustomStringConvertible {
        case tabs
        case severalDocuments
        /// The key on the path holds something other than a block mapping, such as `gui: {…}` or an anchor.
        case notABlockMapping(String)

        public var description: String {
            switch self {
            case .tabs: "it indents with tabs"
            case .severalDocuments: "it holds more than one YAML document"
            case .notABlockMapping(let key): "\(key) is not a plain block of keys"
            }
        }
    }

    public var text: String { lines.joined(separator: "\n") + (endsWithNewline && !lines.isEmpty ? "\n" : "") }

    var lines: [String]
    var endsWithNewline: Bool
    /// The first line that can hold content: 1 when the file starts with `---`.
    let start: Int

    public init(text: String) throws {
        endsWithNewline = text.hasSuffix("\n")
        var lines = text.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        if text.isEmpty { lines = [] }
        self.lines = lines
        start = (lines.first?.hasPrefix("---") ?? false) ? 1 : 0
        for (index, line) in lines.enumerated() {
            if line.prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") { throw Problem.tabs }
            if index >= start, line.hasPrefix("---") || line.hasPrefix("...") { throw Problem.severalDocuments }
        }
    }

    struct Entry {
        var line: Int
        var indent: Int
        var key: String
        /// The line up to and including the colon.
        var prefix: String
        /// What follows the colon on its line.
        var rest: String
        /// The last line of the entry's value: its last deeper line with content, or `line`.
        var last: Int
    }

    static func indent(_ line: String) -> Int { line.prefix { $0 == " " }.count }

    static func isContent(_ line: String) -> Bool {
        let trimmed = line.drop { $0 == " " }
        return !trimmed.isEmpty && !trimmed.hasPrefix("#")
    }

    /// `key:` at the start of a line, with a plain or quoted key, and what follows the colon.
    static func parseKey(_ line: String) -> (key: String, prefix: String, rest: String)? {
        let pattern = #"^ *("[^"]*"|'[^']*'|[A-Za-z0-9_][A-Za-z0-9_.\-]*) *:(?= |$)"#
        guard let match = line.range(of: pattern, options: .regularExpression) else { return nil }
        let prefix = String(line[match])
        var key = prefix.dropLast().trimmingCharacters(in: .whitespaces)
        if key.count >= 2, let first = key.first, first == "\"" || first == "'", key.last == first { key = String(key.dropFirst().dropLast()) }
        return (key, prefix, String(line[match.upperBound...]))
    }

    /// The child entries of the block that spans `range`, whose parent sits at `parentIndent` (-1 for the root).
    func children(in range: Range<Int>, parentIndent: Int) throws -> [Entry] {
        let content = range.filter { Self.isContent(lines[$0]) }
        guard let first = content.first else { return [] }
        let childIndent = Self.indent(lines[first])
        guard childIndent > parentIndent else { return [] }
        var entries: [Entry] = []
        for index in content {
            let indent = Self.indent(lines[index])
            if indent == childIndent {
                // A line at the children's level that is not `key:` means the block is not a mapping.
                guard let parsed = Self.parseKey(lines[index]) else { throw Problem.notABlockMapping("the block on line \(first + 1)") }
                entries.append(Entry(line: index, indent: indent, key: parsed.key, prefix: parsed.prefix, rest: parsed.rest, last: index))
            } else if indent > childIndent, !entries.isEmpty {
                entries[entries.count - 1].last = index
            } else if indent < childIndent {
                break
            }
        }
        return entries
    }

    /// A key whose value is a block mapping: nothing after the colon but a comment.
    static func holdsBlock(_ entry: Entry) -> Bool {
        let rest = entry.rest.trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest.hasPrefix("#")
    }

    /// Walks `path`. Returns the entries found, one per key, until the first missing key.
    func walk(_ path: [String]) throws -> [Entry] {
        var found: [Entry] = []
        var range = start..<lines.count, indent = -1
        for (depth, key) in path.enumerated() {
            guard let entry = try children(in: range, parentIndent: indent).last(where: { $0.key == key }) else { break }
            if depth < path.count - 1, !Self.holdsBlock(entry) { throw Problem.notABlockMapping(path[...depth].joined(separator: ".")) }
            found.append(entry)
            range = (entry.line + 1)..<(entry.last + 1)
            indent = entry.indent
        }
        return found
    }

    /// Throws when Scene would not edit `path`.
    public func check(_ path: [String]) throws { _ = try walk(path) }

    /// The raw value of `path`, or nil when the file does not set it.
    public func value(at path: [String]) throws -> String? {
        let found = try walk(path)
        guard found.count == path.count, let entry = found.last else { return nil }
        return ([entry.rest] + lines[(entry.line + 1)..<(entry.last + 1)]).joined(separator: "\n")
    }

    /// Sets `path` to a raw value, adding the mappings on the way, or removes it when `value` is nil.
    /// Removing the last key of a mapping removes that mapping too, when nothing else is on its line.
    public mutating func set(_ value: String?, at path: [String]) throws {
        let found = try walk(path)
        if found.count == path.count, let entry = found.last {
            if let value {
                let parts = value.components(separatedBy: "\n")
                lines.replaceSubrange(entry.line...entry.last, with: [entry.prefix + parts[0]] + parts.dropFirst())
            } else {
                lines.removeSubrange(entry.line...entry.last)
                try removeEmptyParents(path)
            }
            return
        }
        guard let value else { return }
        // Add the missing keys at the end of the deepest mapping that exists.
        let parent = found.last
        let siblings = try children(in: parent.map { ($0.line + 1)..<($0.last + 1) } ?? start..<lines.count, parentIndent: parent?.indent ?? -1)
        var indent = siblings.first?.indent ?? parent.map { $0.indent + 2 } ?? 0
        var added: [String] = []
        for (depth, key) in path.enumerated().dropFirst(found.count) {
            let pad = String(repeating: " ", count: indent)
            if depth == path.count - 1 {
                let parts = value.components(separatedBy: "\n")
                added.append(pad + key + ":" + parts[0])
                added += parts.dropFirst()
            } else {
                added.append(pad + key + ":")
            }
            indent += 2
        }
        let wasEmpty = lines.isEmpty
        lines.insert(contentsOf: added, at: parent.map { $0.last + 1 } ?? lines.count)
        // A new file ends with a newline. An existing file keeps its last line as it was.
        if wasEmpty { endsWithNewline = true }
    }

    mutating func removeEmptyParents(_ path: [String]) throws {
        for depth in stride(from: path.count - 2, through: 0, by: -1) {
            let found = try walk(Array(path[...depth]))
            guard found.count == depth + 1, let entry = found.last, entry.last == entry.line,
                  entry.rest.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            lines.remove(at: entry.line)
        }
    }
}
