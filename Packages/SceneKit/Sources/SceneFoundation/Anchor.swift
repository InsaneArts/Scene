import Foundation

public enum Placement: String, Codable, Sendable { case start, end }

/// The one marked block Scene may add to a user's config file. Scene edits only between its markers.
public enum Anchor {
    public static func begin(_ comment: String) -> String { "\(comment) >>> Scene: managed include. Remove this block to detach Scene. >>>" }
    public static func end(_ comment: String) -> String { "\(comment) <<< Scene <<<" }

    public static func block(lines: [String], comment: String) -> String {
        ([begin(comment)] + lines + [end(comment)]).joined(separator: "\n")
    }

    /// Line range of an existing Scene block, including both markers.
    static func find(in lines: [String]) -> ClosedRange<Int>? {
        guard let start = lines.firstIndex(where: { $0.contains(">>> Scene: managed include") }),
              let stop = lines[start...].firstIndex(where: { $0.contains("<<< Scene <<<") }) else { return nil }
        return start...stop
    }

    public static func existingBlock(in text: String) -> String? {
        let lines = split(text)
        guard let range = find(in: lines) else { return nil }
        return lines[range].joined(separator: "\n")
    }

    /// Inserts the block, or replaces an existing Scene block in place. Other lines stay byte-identical.
    public static func insert(_ block: String, into text: String, placement: Placement) -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = split(text)
        let blockLines = block.components(separatedBy: "\n")
        if let range = find(in: lines) {
            lines.replaceSubrange(range, with: blockLines)
            return join(lines, newline: newline, trailing: text.hasSuffix("\n") || text.isEmpty)
        }
        let trimmedEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if trimmedEmpty { return blockLines.joined(separator: newline) + newline }
        switch placement {
        case .end:
            var result = text
            if !result.hasSuffix("\n") { result += newline }
            return result + newline + blockLines.joined(separator: newline) + newline
        case .start:
            return blockLines.joined(separator: newline) + newline + newline + text
        }
    }

    /// Removes the Scene block and the blank line Scene added next to it.
    public static func remove(from text: String) -> String {
        let newline = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = split(text)
        guard let range = find(in: lines) else { return text }
        var lower = range.lowerBound, upper = range.upperBound
        if lower > 0, lines[lower - 1].trimmingCharacters(in: .whitespaces).isEmpty { lower -= 1 }
        else if upper + 1 < lines.count, lines[upper + 1].trimmingCharacters(in: .whitespaces).isEmpty { upper += 1 }
        lines.removeSubrange(lower...upper)
        if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { return "" }
        return join(lines, newline: newline, trailing: text.hasSuffix("\n"))
    }

    static func split(_ text: String) -> [String] {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func join(_ lines: [String], newline: String, trailing: Bool) -> String {
        lines.joined(separator: newline) + (trailing && !lines.isEmpty ? newline : "")
    }
}
