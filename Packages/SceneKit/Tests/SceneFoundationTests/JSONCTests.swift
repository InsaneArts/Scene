import Foundation
@testable import SceneFoundation
import Testing

private func edited(_ text: String, _ key: String, _ value: JSONValue?) throws -> String {
    var document = try JSONCDocument(text: text)
    try document.set(value, forKey: key)
    return document.text
}

private func object(_ members: (String, JSONValue)...) -> JSONValue {
    .object(members.map { JSONMember($0.0, $0.1) })
}

// MARK: - Replace

@Suite struct Replace {
    @Test func stringValueInCommentedFile() throws {
        let original = """
        // Global settings
        {
          /* colors */ "workbench.colorTheme": "Default Dark Modern", // picked in 2024
          "editor.fontSize": 13 /* px */
        }

        """
        let expected = """
        // Global settings
        {
          /* colors */ "workbench.colorTheme": "Solarized Light", // picked in 2024
          "editor.fontSize": 13 /* px */
        }

        """
        #expect(try edited(original, "workbench.colorTheme", .string("Solarized Light")) == expected)
    }

    @Test func keyTextInCommentsAndStringsNeverMatches() throws {
        let original = #"""
        {
          // "editor.fontSize": 99,
          /* "editor.fontSize": 98 */
          "note": "\"editor.fontSize\": 97",
          "editor.fontSize": 14
        }
        """#
        let document = try JSONCDocument(text: original)
        #expect(document.keys == ["note", "editor.fontSize"])
        #expect(document.value(forKey: "editor.fontSize") == .number(14))
        let expected = #"""
        {
          // "editor.fontSize": 99,
          /* "editor.fontSize": 98 */
          "note": "\"editor.fontSize\": 97",
          "editor.fontSize": 16
        }
        """#
        #expect(try edited(original, "editor.fontSize", .number(16)) == expected)
    }

    @Test func keyOnlyInCommentsAndStringsIsInserted() throws {
        let original = #"""
        {
          // "editor.fontSize": 99,
          "note": "\"editor.fontSize\": 97"
        }
        """#
        #expect(try JSONCDocument(text: original).value(forKey: "editor.fontSize") == nil)
        let expected = #"""
        {
          // "editor.fontSize": 99,
          "note": "\"editor.fontSize\": 97",
          "editor.fontSize": 16
        }
        """#
        #expect(try edited(original, "editor.fontSize", .number(16)) == expected)
    }

    @Test func sameValueLeavesTextUntouched() throws {
        let original = "{\n  \"a\": 1.0, \"b\": [ 1 , /* x */ 2 ]\n}"
        #expect(try edited(original, "a", .number(1)) == original)
        #expect(try edited(original, "b", .array([.number(1), .number(2)])) == original)
    }

    @Test func zedThemeObjectUsesMemberIndentation() throws {
        let original = """
        // Zed settings
        {
          "ui_font_size": 16,
          "theme": "One Dark", // dark only
          "vim_mode": false
        }

        """
        let theme = object(("mode", .string("system")), ("light", .string("One Light")), ("dark", .string("One Dark")))
        let expected = """
        // Zed settings
        {
          "ui_font_size": 16,
          "theme": {
            "mode": "system",
            "light": "One Light",
            "dark": "One Dark"
          }, // dark only
          "vim_mode": false
        }

        """
        var document = try JSONCDocument(text: original)
        try document.set(theme, forKey: "theme")
        #expect(document.text == expected)
        #expect(document.value(forKey: "theme") == theme)
        try document.set(.string("One Dark"), forKey: "theme")
        #expect(document.text == original)
    }

    @Test func nestedValueInFourSpaceFile() throws {
        let value = object(("x", .array([.number(1), object(("y", .null))])))
        let expected = """
        {
            "a": 1,
            "b": {
                "x": [
                    1,
                    {
                        "y": null
                    }
                ]
            }
        }
        """
        #expect(try edited("{\n    \"a\": 1\n}", "b", value) == expected)
    }
}

// MARK: - Insert

@Suite struct Insert {
    @Test func intoEmptyObject() throws {
        #expect(try edited("{}", "a", .number(1)) == "{\n  \"a\": 1\n}")
        #expect(try edited("{ }", "a", .number(1)) == "{\n  \"a\": 1\n}")
        #expect(try edited("{\n}\n", "a", .number(1)) == "{\n  \"a\": 1\n}\n")
    }

    @Test func intoEmptyText() throws {
        #expect(try edited("", "a", .bool(true)) == "{\n  \"a\": true\n}")
    }

    @Test func intoWhitespaceOnlyText() throws {
        #expect(try edited("\n", "a", .bool(true)) == "{\n  \"a\": true\n}\n")
        #expect(try edited(" \r\n", "a", .bool(true)) == "{\r\n  \"a\": true\r\n} \r\n")
    }

    @Test func intoCommentOnlyText() throws {
        let original = "// Place your settings in this file to overwrite the default settings\n"
        let expected = "// Place your settings in this file to overwrite the default settings\n{\n  \"a\": \"x\"\n}\n"
        #expect(try edited(original, "a", .string("x")) == expected)
        #expect(try edited("/*\n\tSettings\n*/", "a", .number(1)) == "/*\n\tSettings\n*/\n{\n\t\"a\": 1\n}")
    }

    @Test func intoObjectWithTrailingComma() throws {
        #expect(try edited("{\n  \"a\": 1,\n}", "b", .number(2)) == "{\n  \"a\": 1,\n  \"b\": 2,\n}")
    }

    @Test func intoTabIndentedObject() throws {
        let value = object(("c", .bool(true)))
        #expect(try edited("{\n\t\"a\": 1\n}", "b", value) == "{\n\t\"a\": 1,\n\t\"b\": {\n\t\t\"c\": true\n\t}\n}")
        #expect(try edited("{\n\t// settings\n}", "a", .number(1)) == "{\n\t// settings\n\t\"a\": 1\n}")
    }

    @Test func intoCRLFText() throws {
        let original = "{\r\n  \"a\": 1\r\n}\r\n"
        let expected = "{\r\n  \"a\": 1,\r\n  \"b\": [\r\n    1,\r\n    2\r\n  ]\r\n}\r\n"
        #expect(try edited(original, "b", .array([.number(1), .number(2)])) == expected)
    }

    @Test func afterLastMemberAndBeforeTrailingComments() throws {
        let original = """
        {
          "a": 1 // about a
          // "b": 2
        }
        """
        let expected = """
        {
          "a": 1, // about a
          "c": 3
          // "b": 2
        }
        """
        #expect(try edited(original, "c", .number(3)) == expected)
    }

    @Test func intoSingleLineObject() throws {
        #expect(try edited("{ \"a\": 1 }", "b", .number(2)) == "{ \"a\": 1, \"b\": 2 }")
        #expect(try edited("{\"a\": 1,}", "b", .number(2)) == "{\"a\": 1, \"b\": 2,}")
    }

    @Test func escapesTheKey() throws {
        #expect(try edited("{}", "say \"hi\"", .null) == "{\n  \"say \\\"hi\\\"\": null\n}")
    }
}

// MARK: - Remove

@Suite struct Remove {
    let three = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"c\": 3\n}"

    @Test func firstMember() throws {
        #expect(try edited(three, "a", nil) == "{\n  \"b\": 2,\n  \"c\": 3\n}")
    }

    @Test func middleMember() throws {
        #expect(try edited(three, "b", nil) == "{\n  \"a\": 1,\n  \"c\": 3\n}")
    }

    @Test func lastMember() throws {
        #expect(try edited(three, "c", nil) == "{\n  \"a\": 1,\n  \"b\": 2\n}")
    }

    @Test func onlyMember() throws {
        #expect(try edited("{\n  \"a\": 1\n}\n", "a", nil) == "{\n}\n")
    }

    @Test func memberWithTrailingComment() throws {
        let original = """
        {
          "a": 1, // about a
          // keep me
          "b": 2
        }
        """
        let expected = """
        {
          // keep me
          "b": 2
        }
        """
        #expect(try edited(original, "a", nil) == expected)
    }

    @Test func lastMemberWithTrailingComment() throws {
        let original = """
        {
          "a": 1, // about a
          "b": 2 // about b
        }
        """
        #expect(try edited(original, "b", nil) == "{\n  \"a\": 1 // about a\n}")
    }

    @Test func lastMemberKeepsTrailingCommaStyle() throws {
        #expect(try edited("{\n  \"a\": 1,\n  \"b\": 2,\n}", "b", nil) == "{\n  \"a\": 1,\n}")
    }

    @Test func multiLineValue() throws {
        let original = """
        {
          "theme": {
            "mode": "system" // follows macOS
          },
          "vim_mode": false
        }
        """
        #expect(try edited(original, "theme", nil) == "{\n  \"vim_mode\": false\n}")
    }

    @Test func onSingleLine() throws {
        #expect(try edited("{ \"a\": 1, \"b\": 2 }", "a", nil) == "{ \"b\": 2 }")
        #expect(try edited("{ \"a\": 1, \"b\": 2 }", "b", nil) == "{ \"a\": 1 }")
        #expect(try edited("{\"a\": 1}", "a", nil) == "{}")
    }

    @Test func inCRLFText() throws {
        #expect(try edited("{\r\n  \"a\": 1,\r\n  \"b\": 2\r\n}\r\n", "b", nil) == "{\r\n  \"a\": 1\r\n}\r\n")
    }

    @Test func missingKeyChangesNothing() throws {
        #expect(try edited(three, "z", nil) == three)
        #expect(try edited("", "z", nil) == "")
    }
}

// MARK: - Duplicate keys

@Suite struct DuplicateKeys {
    let original = "{\n  \"a\": 1,\n  \"b\": 2,\n  \"a\": 3\n}"

    @Test func lastOneIsRead() throws {
        let document = try JSONCDocument(text: original)
        #expect(document.value(forKey: "a") == .number(3))
        #expect(document.keys == ["a", "b"])
    }

    @Test func lastOneIsEdited() throws {
        #expect(try edited(original, "a", .number(4)) == "{\n  \"a\": 1,\n  \"b\": 2,\n  \"a\": 4\n}")
    }

    @Test func lastOneIsRemoved() throws {
        var document = try JSONCDocument(text: original)
        try document.set(nil, forKey: "a")
        #expect(document.text == "{\n  \"a\": 1,\n  \"b\": 2\n}")
        #expect(document.value(forKey: "a") == .number(1))
    }
}

// MARK: - Real-world round trips

private let userSettings = """
// Place your settings in this file to overwrite the default settings
{
    // Editor
    "editor.fontFamily": "'JetBrains Mono', Menlo, monospace",
    "editor.fontSize": 13,
    "editor.fontLigatures": true, // needs a font with ligatures
    "editor.rulers": [80, 120],
    /* Format on save is slow on large files. */
    "editor.formatOnSave": false,
    "workbench.colorTheme": "Default Dark Modern",
    "files.exclude": {
        "**/.git": true,
        "**/node_modules": true, // huge
    },
    "[swift]": {
        "editor.tabSize": 4
    },
    "terminal.integrated.fontSize": 12.5,
    // "window.zoomLevel": 1,
    "search.exclude": {"**/dist": true},
}

"""

/// Tab-indented, CRLF line endings, escapes in strings, no trailing comma.
private let workspaceSettings = [
    #"{"#,
    #"\#t"window.title": "${activeEditorShort}${separator}${rootName}","#,
    #"\#t"editor.wordSeparators": "`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?","#,
    #"\#t"files.associations": {"#,
    #"\#t\#t"*.jsonc": "jsonc","#,
    #"\#t\#t"settings.json": "jsonc""#,
    #"\#t},"#,
    #"\#t/*"#,
    #"\#t * The theme follows the macOS appearance."#,
    #"\#t */"#,
    #"\#t"window.autoDetectColorScheme": true,"#,
    #"\#t"workbench.preferredDarkColorTheme": "Default Dark Modern","#,
    #"\#t"workbench.preferredLightColorTheme": "Default Light Modern","#,
    #"\#t"editor.minimap.enabled": false, // distracting"#,
    #"\#t"git.confirmSync": false,"#,
    #"\#t"emmet.includeLanguages": { "erb": "html" },"#,
    #"\#t"remote.SSH.remotePlatform": { "build-\u00e9t\u00e9": "linux" }"#,
    #"}"#,
    "",
].joined(separator: "\r\n")

@Suite struct RoundTrip {
    @Test(arguments: [userSettings, workspaceSettings])
    func setSameValuesThenInsertAndRemove(original: String) throws {
        var document = try JSONCDocument(text: original)
        for key in document.keys {
            try document.set(document.value(forKey: key), forKey: key)
        }
        #expect(document.text == original)

        let appearance = object(("mode", .string("system")), ("light", .string("A")), ("dark", .string("B")))
        try document.set(appearance, forKey: "scene.appearance")
        #expect(document.keys.last == "scene.appearance")
        #expect(document.value(forKey: "scene.appearance") == appearance)
        try document.set(nil, forKey: "scene.appearance")
        #expect(document.text == original)
    }

    @Test func userSettingsFixture() throws {
        var document = try JSONCDocument(text: userSettings)
        #expect(document.keys == [
            "editor.fontFamily", "editor.fontSize", "editor.fontLigatures", "editor.rulers", "editor.formatOnSave",
            "workbench.colorTheme", "files.exclude", "[swift]", "terminal.integrated.fontSize", "search.exclude",
        ])
        #expect(document.value(forKey: "editor.rulers") == .array([.number(80), .number(120)]))
        #expect(document.value(forKey: "files.exclude") == object(("**/.git", .bool(true)), ("**/node_modules", .bool(true))))
        #expect(document.value(forKey: "terminal.integrated.fontSize") == .number(12.5))
        #expect(document.value(forKey: "window.zoomLevel") == nil)

        try document.set(.string("Solarized Dark"), forKey: "workbench.colorTheme")
        try document.set(.number(14), forKey: "editor.fontSize")
        #expect(document.text == userSettings
            .replacingOccurrences(of: "\"Default Dark Modern\"", with: "\"Solarized Dark\"")
            .replacingOccurrences(of: "\"editor.fontSize\": 13", with: "\"editor.fontSize\": 14"))
        try document.set(.string("Default Dark Modern"), forKey: "workbench.colorTheme")
        try document.set(.number(13), forKey: "editor.fontSize")
        #expect(document.text == userSettings)

        for key in document.keys {
            try document.set(nil, forKey: key)
        }
        #expect(document.text == """
        // Place your settings in this file to overwrite the default settings
        {
            // Editor
            /* Format on save is slow on large files. */
            // "window.zoomLevel": 1,
        }

        """)
    }

    @Test func workspaceSettingsFixture() throws {
        var document = try JSONCDocument(text: workspaceSettings)
        #expect(document.keys.count == 10)
        #expect(document.value(forKey: "editor.wordSeparators") == .string("`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?"))
        #expect(document.value(forKey: "remote.SSH.remotePlatform") == object(("build-été", .string("linux"))))

        try document.set(.bool(true), forKey: "editor.minimap.enabled")
        #expect(document.text == workspaceSettings.replacingOccurrences(
            of: "\"editor.minimap.enabled\": false", with: "\"editor.minimap.enabled\": true"))

        for key in document.keys {
            try document.set(nil, forKey: key)
        }
        #expect(document.text == "{\r\n\t/*\r\n\t * The theme follows the macOS appearance.\r\n\t */\r\n}\r\n")
    }
}

// MARK: - Parsing

@Suite struct Parsing {
    @Test func stringEscapes() throws {
        let document = try JSONCDocument(text: #"""
        {"s": "\u00e9\ud83d\ude00\n\"\\\/\b\f\r\t", "lone": "\ud800x\udc00", "notPair": "\ud83d\u0041"}
        """#)
        #expect(document.value(forKey: "s") == .string("é😀\n\"\\/\u{08}\u{0C}\r\t"))
        #expect(document.value(forKey: "lone") == .string("\u{FFFD}x\u{FFFD}"))
        #expect(document.value(forKey: "notPair") == .string("\u{FFFD}A"))
    }

    @Test func numbersLiteralsAndTrailingCommas() throws {
        let document = try JSONCDocument(text: """
        {
          "n": [-0.5e+3, 0, 1E2, 123.456, -7,],
          "o": {"t": true, "f": false, "z": null,},
        }
        """)
        #expect(document.keys == ["n", "o"])
        #expect(document.value(forKey: "n") == .array([.number(-500), .number(0), .number(100), .number(123.456), .number(-7)]))
        #expect(document.value(forKey: "o") == object(("t", .bool(true)), ("f", .bool(false)), ("z", .null)))
    }

    @Test(arguments: ["", "  \n\t", "// only a comment", "/* block */\r\n// line\r\n"])
    func emptyTextIsAnEmptyObject(text: String) throws {
        let document = try JSONCDocument(text: text)
        #expect(document.keys.isEmpty)
        #expect(document.value(forKey: "a") == nil)
    }

    @Test(arguments: [
        ("{\n  \"a\": 1\n  \"b\": 2\n}", 3, 3, "Expected ',' or '}'"),
        ("{\n  \"a\": tru\n}", 2, 8, "Expected a value"),
        ("{\n  /* never closed\n}", 2, 3, "Unterminated block comment"),
        ("{\"é\": x}", 1, 7, "Expected a value"),
        ("{\r\n  \"a\" 1\r\n}", 2, 7, "Expected ':'"),
        ("{\n  \"a\": \"abc\n}", 2, 8, "Unterminated string"),
        ("{\"a\": \"\u{01}\"}", 1, 8, "Control character in string"),
        ("{\"a\": 01}", 1, 8, "Expected ',' or '}'"),
        ("{\"a\": 1.}", 1, 9, "Expected a digit"),
        ("{\"a\": -}", 1, 8, "Expected a digit"),
        ("{\"a\": +1}", 1, 7, "Expected a value"),
        ("{\"a\": \"\\x\"}", 1, 8, "Invalid escape sequence"),
        ("{\"a\": \"\\u12G4\"}", 1, 8, "Invalid unicode escape"),
        ("{\"a\": 1,,}", 1, 9, "Expected a property name or '}'"),
        ("{\"a\": [1 2]}", 1, 10, "Expected ',' or ']'"),
        ("{} x", 1, 4, "Unexpected content after the top-level value"),
        ("[1,", 1, 4, "Expected a value"),
        ("{", 1, 2, "Expected a property name or '}'"),
    ])
    func syntaxErrors(text: String, line: Int, column: Int, message: String) {
        #expect(throws: JSONCError.syntax(line: line, column: column, message: message)) {
            _ = try JSONCDocument(text: text)
        }
    }

    @Test(arguments: ["[1, 2]", "\"text\"", "// comment\n42", "null"])
    func topLevelNotObject(text: String) {
        #expect(throws: JSONCError.topLevelNotObject) {
            _ = try JSONCDocument(text: text)
        }
    }

    @Test func deepNestingIsAnError() {
        let text = "{\"a\": " + String(repeating: "[", count: 600) + String(repeating: "]", count: 600) + "}"
        #expect(throws: JSONCError.syntax(line: 1, column: 134, message: "Nesting is too deep")) {
            _ = try JSONCDocument(text: text)
        }
    }
}

// MARK: - Serialization

@Suite struct Serialization {
    @Test func escapesStrings() {
        let value = JSONValue.string("say \"hi\" \\ / \n\r\t\u{08}\u{0C}\u{01}\u{1F} é 😀")
        #expect(value.serialized() == #""say \"hi\" \\ / \n\r\t\b\f\u0001\u001f é 😀""#)
    }

    @Test(arguments: [
        (1.0, "1"), (-0.0, "0"), (42, "42"), (-2.5, "-2.5"), (0.1, "0.1"), (1e21, "1e+21"), (1e-7, "1e-07"),
        (9_007_199_254_740_992, "9007199254740992"), (.nan, "null"), (.infinity, "null"),
    ] as [(Double, String)])
    func numbers(number: Double, text: String) {
        #expect(JSONValue.number(number).serialized() == text)
    }

    @Test func nestedWithIndentAndLevel() {
        let value = object(("a", .array([.number(1), .bool(true), .null])), ("b", .object([])), ("c", .array([])))
        #expect(value.serialized() == "{\n  \"a\": [\n    1,\n    true,\n    null\n  ],\n  \"b\": {},\n  \"c\": []\n}")
        #expect(value.serialized(indent: "\t", level: 1)
            == "{\n\t\t\"a\": [\n\t\t\t1,\n\t\t\ttrue,\n\t\t\tnull\n\t\t],\n\t\t\"b\": {},\n\t\t\"c\": []\n\t}")
    }

    @Test func outputParsesBack() throws {
        let value = object(("s", .string("a\"b\\c\n\u{01}é😀")), ("n", .number(-1.25e-8)), ("l", .array([.null, .bool(false)])))
        let document = try JSONCDocument(text: value.serialized())
        #expect(document.value(forKey: "s") == .string("a\"b\\c\n\u{01}é😀"))
        #expect(document.value(forKey: "n") == .number(-1.25e-8))
        #expect(document.value(forKey: "l") == .array([.null, .bool(false)]))
    }
}
