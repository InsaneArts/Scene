import Foundation
import SceneFoundation
import Testing

@Suite("YAML documents")
struct YAMLDocumentTests {
    static let config = "# lazygit\ngui:\n  # my settings\n  showIcons: true\n  theme:\n    activeBorderColor:\n      - green\n      - bold\n"
        + "    authorColors:\n      'John': '#ff0000'\n\n  nerdFontsVersion: \"3\"\ngit:\n  paging:\n    colorArg: always # keep\n"
    let border = ["gui", "theme", "activeBorderColor"], selected = ["gui", "theme", "selectedLineBgColor"]

    @Test func setsKeysAndPutsThemBackByteForByte() throws {
        var doc = try YAMLDocument(text: Self.config)
        let original = try doc.value(at: border)
        #expect(original == "\n      - green\n      - bold")
        #expect(try doc.value(at: ["git", "paging", "colorArg"]) == " always # keep")
        #expect(try doc.value(at: selected) == nil)
        try doc.set(" ['#7aa2f7', bold]", at: border)
        try doc.set(" ['#283457']", at: selected)
        #expect(doc.text.contains("  theme:\n    activeBorderColor: ['#7aa2f7', bold]\n    authorColors:\n"))
        #expect(doc.text.contains("      'John': '#ff0000'\n    selectedLineBgColor: ['#283457']\n\n  nerdFontsVersion"))
        #expect(try doc.value(at: border) == " ['#7aa2f7', bold]")
        try doc.set(original, at: border)
        try doc.set(nil, at: selected)
        #expect(doc.text == Self.config)
    }

    @Test(arguments: ["git:\n  paging:\n    colorArg: always\n", "git:\n  paging:\n    colorArg: always", "---\nos:\n  editPreset: vim\n"])
    func addsTheMappingsAndRemovesThemAgain(_ text: String) throws {
        var doc = try YAMLDocument(text: text)
        try doc.set(" ['#7aa2f7', bold]", at: border)
        try doc.set(" ['#283457']", at: selected)
        #expect(doc.text.contains("gui:\n  theme:\n    activeBorderColor: ['#7aa2f7', bold]\n    selectedLineBgColor: ['#283457']"))
        try doc.set(nil, at: selected)
        try doc.set(nil, at: border)
        #expect(doc.text == text)
    }

    @Test func aNewFileEndsWithANewlineAndEmptiesAgain() throws {
        var doc = try YAMLDocument(text: "")
        try doc.set(" ['#7aa2f7', bold]", at: border)
        #expect(doc.text == "gui:\n  theme:\n    activeBorderColor: ['#7aa2f7', bold]\n")
        try doc.set(nil, at: border)
        #expect(doc.text == "")
    }

    @Test func keepsAMappingThatHasAComment() throws {
        var doc = try YAMLDocument(text: "gui:\n  theme: # mine\n")
        try doc.set(" ['#7aa2f7']", at: border)
        try doc.set(nil, at: border)
        #expect(doc.text == "gui:\n  theme: # mine\n")
    }

    @Test(arguments: ["gui: {theme: {}}\n", "gui: &base\n  theme: {}\n", "gui:\n  - showIcons\n", "gui:\n  theme: []\n"])
    func refusesAPathThatIsNotABlockOfKeys(_ text: String) throws {
        let doc = try YAMLDocument(text: text)
        #expect(throws: YAMLDocument.Problem.self) { try doc.check(border) }
    }

    @Test func refusesTabsAndSeveralDocuments() {
        #expect(throws: YAMLDocument.Problem.tabs) { try YAMLDocument(text: "gui:\n\tshowIcons: true\n") }
        #expect(throws: YAMLDocument.Problem.severalDocuments) { try YAMLDocument(text: "a: 1\n---\nb: 2\n") }
    }

    /// PyYAML reads what Scene wrote as the same data, with Scene's keys added.
    @Test(.enabled(if: (try? Processes.run("/usr/bin/env", ["python3", "-c", "import yaml"]))?.status == 0))
    func pyyamlReadsTheResult() throws {
        var doc = try YAMLDocument(text: Self.config)
        try doc.set(" ['#7aa2f7', bold]", at: border)
        try doc.set(" ['#283457']", at: selected)
        let script = "import sys, yaml, json; print(json.dumps(yaml.safe_load(sys.argv[1]), sort_keys=True))"
        let result = try Processes.run("/usr/bin/env", ["python3", "-c", script, doc.text])
        #expect(result.stdout.contains(##""theme": {"activeBorderColor": ["#7aa2f7", "bold"], "authorColors": {"John": "#ff0000"}, "selectedLineBgColor": ["#283457"]}"##), "\(result.stdout) \(result.stderr)")
        #expect(result.stdout.contains(#""nerdFontsVersion": "3""#) && result.stdout.contains(#""colorArg": "always""#))
    }
}
