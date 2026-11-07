import Foundation
@testable import SceneEngine
import Testing

@Suite("Wallpaper on every Space")
struct WallpaperStoreTests {
    func image(_ node: Any?) throws -> String? {
        let desktop = (node as? [String: Any])?["Desktop"] as? [String: Any]
        let choice = ((desktop?["Content"] as? [String: Any])?["Choices"] as? [[String: Any]])?.first
        guard let data = choice?["Configuration"] as? Data else { return nil }
        let config = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return (config?["url"] as? [String: Any])?["relative"] as? String
    }

    @Test func setsEverySpaceOfTheDisplayAndLeavesOtherDisplays() throws {
        let old: [String: Any] = ["Desktop": ["Content": ["Choices": [Any]()]]]
        let store: [String: Any] = [
            "SystemDefault": old,
            "Displays": ["D1": old, "D2": old],
            "Spaces": [
                "S1": ["Default": old, "Displays": ["D1": old, "D2": old]],
                "S2": ["Default": old, "Displays": ["D2": old]],
            ],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
        let url = URL(fileURLWithPath: "/tmp/a b.heic")
        let out = try #require(try WallpaperStore.spreading(data, displayUUID: "D1", image: url))
        let root = try #require(try PropertyListSerialization.propertyList(from: out, format: nil) as? [String: Any])
        let spaces = try #require(root["Spaces"] as? [String: [String: Any]])
        let s1 = try #require(spaces["S1"]?["Displays"] as? [String: Any])
        let s2 = try #require(spaces["S2"]?["Displays"] as? [String: Any])

        #expect(try image(s1["D1"]) == url.absoluteString)
        #expect(try image(s1["D2"]) == nil)
        #expect(try image(spaces["S1"]?["Default"]) == nil)
        // S2 has no entry for D1, so D1 shows S2's Default there.
        #expect(try image(spaces["S2"]?["Default"]) == url.absoluteString)
        #expect(try image(s2["D2"]) == nil)
        #expect(try image((root["Displays"] as? [String: Any])?["D1"]) == url.absoluteString)
        #expect(try image(root["SystemDefault"]) == url.absoluteString)
    }

    @Test func unknownStoreIsLeftAlone() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Other": 1], format: .binary, options: 0)
        #expect(try WallpaperStore.spreading(data, displayUUID: "D1", image: URL(fileURLWithPath: "/x.jpg")) == nil)
    }
}
