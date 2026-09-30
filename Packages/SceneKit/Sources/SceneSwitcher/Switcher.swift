import Foundation

/// The selection in the theme carousel. Movement stops at the ends, so the strip never jumps.
public struct CarouselSelection: Sendable, Equatable {
    public private(set) var index: Int
    public let count: Int

    public init(count: Int, index: Int = 0) {
        self.count = count
        self.index = count == 0 ? 0 : min(max(index, 0), count - 1)
    }

    public mutating func move(_ delta: Int) {
        guard count > 0 else { return }
        index = min(max(index + delta, 0), count - 1)
    }

    /// Number keys 1 to 9 pick a card directly.
    public mutating func jump(toNumber number: Int) {
        guard (1...9).contains(number), number <= count else { return }
        index = number - 1
    }

    public mutating func select(_ newIndex: Int) {
        guard (0..<count).contains(newIndex) else { return }
        index = newIndex
    }
}

/// A global keyboard shortcut, stored with the virtual key code and modifier keys.
public struct HotKeySpec: Codable, Sendable, Equatable {
    public var keyCode: UInt32
    public var command: Bool
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    /// The key's printed name, captured when the shortcut was recorded (for example "Space" or "T").
    public var keyLabel: String

    public init(keyCode: UInt32, command: Bool = false, control: Bool = false, option: Bool = false, shift: Bool = false, keyLabel: String) {
        self.keyCode = keyCode; self.command = command; self.control = control; self.option = option; self.shift = shift; self.keyLabel = keyLabel
    }

    /// Omarchy's theme menu is Super + Ctrl + Shift + Space. On a Mac, Super is Command.
    public static let omarchyDefault = HotKeySpec(keyCode: 49, command: true, control: true, shift: true, keyLabel: "Space")

    /// Omarchy's next background is Super + Ctrl + Space. On a Mac, ⌃⌘Space opens Emoji & Symbols, so Scene adds ⌥.
    public static let nextBackgroundDefault = HotKeySpec(keyCode: 49, command: true, control: true, option: true, keyLabel: "Space")

    /// In Apple's order: ⌃ ⌥ ⇧ ⌘, then the key.
    public var display: String {
        (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "") + keyLabel
    }

    /// Since macOS 15, shortcuts whose only modifiers are Option, or Option and Shift, cannot be global.
    /// Scene also asks for Command or Control, so a shortcut never swallows ordinary typing.
    public var isAllowed: Bool { command || control }
}

/// Typing in the switcher searches. Digits jump to a card instead, and arrows, Tab, Return, and Esc keep their jobs.
public enum SwitcherSearch {
    /// The text a key adds to the search, or nil when the key does something else.
    public static func text(for characters: String) -> String? {
        guard !characters.isEmpty else { return nil }
        for scalar in characters.unicodeScalars {
            // Arrow and function keys arrive as private-use characters (NSUpArrowFunctionKey and the rest).
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            }
        }
        return characters
    }
}
