import Foundation
@testable import SceneEngine
import SceneTestSupport
import Testing

@Suite("Wallpaper on every Space")
struct WallpaperStoreTests {
    static let old = "/Users/me/Pictures/old.jpg"
    static let scene = "/Users/me/Library/Application Support/Scene/Wallpapers/scene-amber-dark.png"

    static func desktop(_ path: String) -> [String: Any] { ["Desktop": ["Content": FakeServices.wallpaperContent(path)]] }

    /// Two displays. S1 has entries for both; S2 has one for D2 only, so D1 shows S2's Default there; S3 is new and has
    /// no Default yet.
    static func store() throws -> Data {
        let root: [String: Any] = [
            "SystemDefault": desktop(old),
            "Displays": ["D1": desktop(old), "D2": desktop(old)],
            "Spaces": [
                "S1": ["Default": desktop(old), "Displays": ["D1": desktop(old), "D2": desktop(old)]],
                "S2": ["Default": desktop("/Users/me/Pictures/s2.jpg"), "Displays": ["D2": desktop(old)]],
                "S3": [String: Any](),
            ],
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    /// The store after macOS set `scene` on S1 of D1 with the theme's placement.
    static func afterMacOSSetTheSpaceOnScreen() throws -> Data {
        var root = try #require(try PropertyListSerialization.propertyList(from: store(), format: nil) as? [String: Any])
        root = WallpaperStore.setting(root, "Spaces/S1/Displays/D1", ["Desktop": ["Content": FakeServices.wallpaperContent(scene, fit: .center)]])
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }

    @Test func spreadsTheSpaceOnScreenToEveryEntryOfTheDisplay() throws {
        let out = try #require(try WallpaperStore.spreading(Self.afterMacOSSetTheSpaceOnScreen(), displays: ["D1"], imagePath: Self.scene))
        let images = try #require(WallpaperStore.images(out, displays: ["D1"]))
        #expect(images == ["Spaces/S1/Displays/D1": Self.scene, "Spaces/S2/Default": Self.scene, "Spaces/S3/Default": Self.scene,
                           "Displays/D1": Self.scene, "SystemDefault": Self.scene])
        // The other display keeps its own wallpaper, and every copy keeps the placement macOS chose.
        #expect(WallpaperStore.images(out, displays: ["D2"])?["Spaces/S1/Displays/D2"] == Self.old)
        let root = try #require(try WallpaperStore.read(out))
        let content = WallpaperStore.node(root, "Spaces/S2/Default")?["Desktop"].flatMap { ($0 as? [String: Any])?["Content"] as? [String: Any] }
        #expect(content?["EncodedOptionValues"] as? Data == Data("placement center".utf8))
    }

    @Test func waitsUntilMacOSHasSetTheSpaceOnScreen() throws {
        #expect(try WallpaperStore.spreading(Self.store(), displays: ["D1"], imagePath: Self.scene) == nil)
    }

    @Test func unknownStoreIsLeftAlone() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["Other": 1], format: .binary, options: 0)
        #expect(WallpaperStore.images(data, displays: ["D1"]) == nil)
        #expect(try WallpaperStore.spreading(data, displays: ["D1"], imagePath: "/x.jpg") == nil)
    }

    @Test func restoreBringsBackEachSpaceAndKeepsTheOnesSomeoneChanged() throws {
        let before = try Self.store()
        let backup = try #require(try WallpaperStore.backup(before, displays: ["D1"]))
        var spread = try #require(try WallpaperStore.spreading(Self.afterMacOSSetTheSpaceOnScreen(), displays: ["D1"], imagePath: Self.scene))
        // After Scene, the user picks a wallpaper for S2.
        var root = try #require(try WallpaperStore.read(spread))
        root = WallpaperStore.setting(root, "Spaces/S2/Default", Self.desktop("/Users/me/Pictures/mine.jpg"))
        spread = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)

        let restored = try #require(try WallpaperStore.restoring(spread, displays: ["D1"], sceneImage: Self.scene, backup: backup))
        let images = try #require(WallpaperStore.images(restored, displays: ["D1"]))
        #expect(images["Spaces/S1/Displays/D1"] == Self.old)
        #expect(images["Spaces/S2/Default"] == "/Users/me/Pictures/mine.jpg")
        #expect(images["Displays/D1"] == Self.old && images["SystemDefault"] == Self.old)
        // S3 had no wallpaper before Scene, so it has none again.
        #expect(images["Spaces/S3/Default"] == nil)
        let restoredRoot = try #require(try WallpaperStore.read(restored))
        #expect(WallpaperStore.node(restoredRoot, "Spaces/S3") != nil)
    }
}
