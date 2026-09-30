import Foundation
@testable import SceneFoundation
import Testing

@Suite("KeyValueDocument")
struct KeyValueDocumentTests {
    static let helix = """
    # Helix
    theme = "onedark" # the old one

    [editor]
    line-number = "relative"

    [editor.cursor-shape]
    insert = "bar"

    """

    @Test func readsAndReplacesARootKeyAndKeepsItsComment() {
        var doc = KeyValueDocument(text: Self.helix)
        #expect(doc.value(forKey: "theme") == "\"onedark\"")
        #expect(doc.value(forKey: "editor.line-number") == "\"relative\"")
        #expect(doc.value(forKey: "editor.cursor-shape.insert") == "\"bar\"")
        doc.set("\"scene\"", forKey: "theme")
        #expect(doc.text == Self.helix.replacingOccurrences(of: "\"onedark\"", with: "\"scene\""))
        doc.set("\"onedark\"", forKey: "theme")
        #expect(doc.text == Self.helix)
    }

    @Test func newRootKeyGoesBeforeTheFirstTableAndRemovingItRestoresTheBytes() {
        let original = "[editor]\nline-number = \"relative\"\n"
        var doc = KeyValueDocument(text: original)
        doc.set("\"scene\"", forKey: "theme")
        #expect(doc.text == "theme = \"scene\"\n[editor]\nline-number = \"relative\"\n")
        doc.set(nil, forKey: "theme")
        #expect(doc.text == original)
    }

    @Test func keyInAnExistingTableGoesAfterItsLastKey() {
        let original = "font.size = 12\n\n[general]\nlive_config_reload = true\n\n[colors.primary]\nbackground = \"#000000\"\n"
        var doc = KeyValueDocument(text: original)
        doc.set("[\"/a/scene.toml\"]", forKey: "import", inTable: "general")
        #expect(doc.text == "font.size = 12\n\n[general]\nlive_config_reload = true\nimport = [\"/a/scene.toml\"]\n\n[colors.primary]\nbackground = \"#000000\"\n")
        #expect(doc.value(forKey: "general.import") == "[\"/a/scene.toml\"]")
        doc.set(nil, forKey: "import", inTable: "general")
        #expect(doc.text == original)
    }

    @Test func missingTableIsAppendedAndRemovedAgain() {
        let original = "[window]\nopacity = 0.9\n"
        var doc = KeyValueDocument(text: original)
        doc.set("{ custom = { name = \"Scene\" } }", forKey: "theme", inTable: "appearance.themes")
        #expect(doc.text == "[window]\nopacity = 0.9\n\n[appearance.themes]\ntheme = { custom = { name = \"Scene\" } }\n")
        doc.set(nil, forKey: "theme", inTable: "appearance.themes")
        #expect(doc.text == original)
    }

    @Test func tableDefinedByDottedKeysGetsADottedKey() {
        // Omarchy's alacritty.toml style. A [general] header after `general.x` would be invalid TOML.
        let original = "general.live_config_reload = true\n\n[font]\nsize = 12\n"
        var doc = KeyValueDocument(text: original)
        doc.set("[\"/s.toml\"]", forKey: "import", inTable: "general")
        #expect(doc.text == "general.live_config_reload = true\ngeneral.import = [\"/s.toml\"]\n\n[font]\nsize = 12\n")
        #expect(doc.value(forKey: "general.import") == "[\"/s.toml\"]")
    }

    @Test func multiLineArrayIsReplacedAndRestoredVerbatim() {
        let original = "[general]\nimport = [\n  \"~/a.toml\", # mine\n  \"~/b.toml\",\n]\nworking_directory = \"None\"\n"
        var doc = KeyValueDocument(text: original)
        let old = doc.value(forKey: "general.import")
        #expect(old == "[\n  \"~/a.toml\", # mine\n  \"~/b.toml\",\n]")
        #expect(KeyValueDocument.stringArray(old!) == ["~/a.toml", "~/b.toml"])
        doc.set("[\"~/a.toml\", \"~/b.toml\", \"/s.toml\"]", forKey: "import", inTable: "general")
        #expect(doc.text == "[general]\nimport = [\"~/a.toml\", \"~/b.toml\", \"/s.toml\"]\nworking_directory = \"None\"\n")
        doc.set(old, forKey: "import", inTable: "general")
        #expect(doc.text == original)
    }

    @Test func arrayTablesAndHashesInStringsAreNotConfused() {
        let text = "color_theme = \"Default\"\ntheme_background = True\n[[hints.enabled]]\nregex = \"a#b\"\n"
        let doc = KeyValueDocument(text: text)
        #expect(doc.value(forKey: "color_theme") == "\"Default\"")
        #expect(doc.value(forKey: "theme_background") == "True")
        #expect(doc.value(forKey: "hints.enabled.regex") == nil)
        #expect(doc.keys.last == "[[hints.enabled]].regex")
    }

    @Test func crlfAndMissingTrailingNewlineAreKept() {
        var doc = KeyValueDocument(text: "a = 1\r\ncolor_theme = \"x\"")
        doc.set("\"scene\"", forKey: "color_theme")
        #expect(doc.text == "a = 1\r\ncolor_theme = \"scene\"")
    }

    @Test func emptyFileGetsTheKey() {
        var doc = KeyValueDocument(text: "")
        doc.set("\"scene\"", forKey: "theme")
        #expect(doc.text == "theme = \"scene\"\n")
        doc.set(nil, forKey: "theme")
        #expect(doc.text.isEmpty)
    }

    @Test func quotingEscapesEverythingTOMLNeeds() {
        #expect(KeyValueDocument.quoted("a \"b\" \\ c") == #""a \"b\" \\ c""#)
        #expect(KeyValueDocument.quoted("line\nbreak") == #""line\nbreak""#)
        #expect(KeyValueDocument.stringArray(#"["a \"q\"", 'lit\eral']"#) == ["a \"q\"", "lit\\eral"])
        #expect(KeyValueDocument.stringArray("[1, 2]") == nil)
        #expect(KeyValueDocument.stringArray("[]") == [])
    }
}
