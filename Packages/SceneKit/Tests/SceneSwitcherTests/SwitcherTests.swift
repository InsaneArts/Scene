import Foundation
@testable import SceneSwitcher
import Testing

@Suite("Theme switcher")
struct SwitcherTests {
    @Test func selectionStopsAtTheEnds() {
        var s = CarouselSelection(count: 4, index: 0)
        s.move(-1)
        #expect(s.index == 0)
        s.move(1); s.move(1); s.move(1); s.move(1)
        #expect(s.index == 3)
        s.jump(toNumber: 2)
        #expect(s.index == 1)
        s.jump(toNumber: 9)          // beyond the last theme: ignored
        #expect(s.index == 1)
        s.select(7)
        #expect(s.index == 1)
    }

    @Test func emptyAndOutOfRangeStartAreSafe() {
        var empty = CarouselSelection(count: 0, index: 3)
        empty.move(1)
        #expect(empty.index == 0)
        #expect(CarouselSelection(count: 3, index: 10).index == 2)
    }

    @Test func omarchyDefaultShortcut() {
        let spec = HotKeySpec.omarchyDefault
        #expect(spec.display == "⌃⇧⌘Space")
        #expect(spec.keyCode == 49)
        #expect(spec.isAllowed)
    }

    @Test func nextBackgroundDefaultShortcut() {
        let spec = HotKeySpec.nextBackgroundDefault
        #expect(spec.display == "⌃⌥⌘Space")
        #expect(spec.isAllowed)
        #expect(spec != HotKeySpec.omarchyDefault)
    }

    @Test func shortcutsNeedCommandOrControl() {
        #expect(!HotKeySpec(keyCode: 17, option: true, keyLabel: "T").isAllowed)
        #expect(!HotKeySpec(keyCode: 17, option: true, shift: true, keyLabel: "T").isAllowed)
        #expect(HotKeySpec(keyCode: 17, control: true, option: true, keyLabel: "T").isAllowed)
        #expect(HotKeySpec(keyCode: 17, control: true, option: true, keyLabel: "T").display == "⌃⌥T")
    }

    @Test func shortcutSurvivesStorage() throws {
        let spec = HotKeySpec(keyCode: 17, command: true, option: true, keyLabel: "T")
        let decoded = try JSONDecoder().decode(HotKeySpec.self, from: JSONEncoder().encode(spec))
        #expect(decoded == spec)
    }
}

@Suite("Switcher search")
struct SwitcherSearchTests {
    @Test func lettersTypeAndOtherKeysKeepTheirJobs() {
        #expect(SwitcherSearch.text(for: "n") == "n")
        #expect(SwitcherSearch.text(for: "É") == "É")
        #expect(SwitcherSearch.text(for: " ") == " ")
        #expect(SwitcherSearch.text(for: "-") == "-")
        for key in ["1", "9", "\t", "\r", "\u{1b}", "\u{7f}", "\u{F700}", "\u{F703}", ""] {
            #expect(SwitcherSearch.text(for: key) == nil, "\(key.debugDescription)")
        }
    }
}
