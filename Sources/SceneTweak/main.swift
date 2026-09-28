// scene-tweak: runs one experimental private macOS call per launch, so a crash here
// becomes a "Failed" row in Scene instead of a crashed app.
//
//   scene-tweak check                  → which tweaks resolve on this macOS build
//   scene-tweak get <id>               → current value
//   scene-tweak set <id> '<json>'      → applies, reads back, reverts on mismatch
//
// Output is one JSON object: {"ok": true, "value": …} or {"ok": false, "error": "…"}.
import AppKit
import Foundation

func emit(_ object: [String: Any]) -> Never {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{\"ok\":false}".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(object["ok"] as? Bool == true ? 0 : 1)
}
func succeed(_ value: Any) -> Never { emit(["ok": true, "value": value]) }
func fail(_ message: String) -> Never { emit(["ok": false, "error": message]) }

let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
let appKit = dlopen("/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit", RTLD_NOW)

func symbol<T>(_ handle: UnsafeMutableRawPointer?, _ name: String, as type: T.Type) -> T? {
    guard let handle, let pointer = dlsym(handle, name) else { return nil }
    return unsafeBitCast(pointer, to: type)
}

// MARK: - Appearance (SkyLight)

typealias GetInt32 = @convention(c) () -> Int32
typealias GetBool = @convention(c) () -> Bool
typealias SetTheme = @convention(c) (Int32, Int32) -> Void
typealias SetBool = @convention(c) (Bool) -> Void

enum AppearanceTweak {
    static let getTheme = symbol(skyLight, "SLSGetAppearanceThemeLegacy", as: GetInt32.self)
    static let setTheme = symbol(skyLight, "SLSSetAppearanceThemeNotifying", as: SetTheme.self)
    static let getAuto = symbol(skyLight, "SLSGetAppearanceThemeSwitchesAutomatically", as: GetBool.self)
    static let setAuto = symbol(skyLight, "SLSSetAppearanceThemeSwitchesAutomatically", as: SetBool.self)

    static var resolves: Bool { getTheme != nil && setTheme != nil && getAuto != nil && setAuto != nil }

    static func current() -> [String: Any] {
        ["dark": getTheme!() == 1, "auto": getAuto!()]
    }

    static func set(_ value: [String: Any]) {
        guard let dark = value["dark"] as? Bool, let auto = value["auto"] as? Bool else { fail("appearance needs dark and auto") }
        let before = current()
        if auto {
            setAuto!(true)
        } else {
            setAuto!(false)
            // System Settings passes 1 for Dark and a second argument of 0.
            setTheme!(dark ? 1 : 0, 0)
        }
        usleep(150_000)
        let after = current()
        guard after["auto"] as? Bool == auto, auto || after["dark"] as? Bool == dark else {
            setAuto!(before["auto"] as! Bool)
            if !(before["auto"] as! Bool) { setTheme!((before["dark"] as! Bool) ? 1 : 0, 0) }
            fail("appearance read back \(after), expected dark=\(dark) auto=\(auto); reverted")
        }
        succeed(after)
    }
}

// MARK: - Accent color (AppKit)

typealias GetAccent = @convention(c) () -> Int
typealias SetAccent = @convention(c) (Int, Bool) -> Void

enum AccentTweak {
    static let getter = symbol(appKit, "NSColorGetUserAccentColor", as: GetAccent.self)
    static let setter = symbol(appKit, "NSColorSetUserAccentColor", as: SetAccent.self)
    static var resolves: Bool { getter != nil && setter != nil }

    static func apply(_ value: Int) {
        // -3 hardware color, -2 multicolor, -1 graphite, 0 red … 6 pink. System Settings passes 1 as the second argument.
        guard (-2...6).contains(value) else { fail("accent must be between -2 and 6") }
        let before = getter!()
        setter!(value, true)
        usleep(150_000)
        let after = readBack()
        guard after == value else {
            setter!(before, true)
            fail("accent read back \(after), expected \(value); reverted")
        }
        succeed(after)
    }

    /// Reads the stored key in a fresh way; the getter caches its value inside this process.
    static func readBack() -> Int {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        if let stored = CFPreferencesCopyAppValue("AppleAccentColor" as CFString, kCFPreferencesAnyApplication) as? Int { return stored }
        return getter!()
    }
}

// MARK: - Icon and widget style (SkyLight Objective-C class)

enum IconTweak {
    static let styles = ["RegularAutomatic", "RegularLight", "RegularDark", "ClearAutomatic", "ClearLight", "ClearDark", "TintedAutomatic", "TintedLight", "TintedDark"]
    /// Index 0 is "no tint" (the key is absent); the named tints follow in SkyLight's string-table order.
    /// Checked on 25G83: index 9 stores "Graphite" in AppleIconAppearanceTintColor.
    static let tints = ["None", "Hardware", "Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Pink", "Graphite", "Other"]

    /// Type encodings seen on macOS 26.6.2. Any difference turns the tweak off.
    static let expected: [String: String] = [
        "iconAppearanceTheme": "I16@0:8", "setIconAppearanceTheme:": "v20@0:8I16",
        "iconTintColorName": "I16@0:8", "setIconTintColorName:": "v20@0:8I16",
        "otherIconTintColor": "^{CGColor=}16@0:8", "setOtherIconTintColor:": "v24@0:8^{CGColor=}16",
        "save": "v16@0:8",
    ]

    static var configClass: NSObject.Type? { NSClassFromString("SLSIconAppearanceConfiguration") as? NSObject.Type }

    static var resolves: Bool {
        guard let cls = configClass,
              let fetch = class_getClassMethod(cls, NSSelectorFromString("fetchCurrentIconAppearanceConfiguration")),
              String(cString: method_getTypeEncoding(fetch)!) == "@16@0:8" else { return false }
        return expected.allSatisfy { name, encoding in
            guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
                  let actual = method_getTypeEncoding(method) else { return false }
            return String(cString: actual) == encoding
        }
    }

    static func fetch() -> NSObject {
        guard let cls = configClass,
              let config = (cls as AnyObject).perform(NSSelectorFromString("fetchCurrentIconAppearanceConfiguration"))?.takeUnretainedValue() as? NSObject
        else { fail("could not read the icon configuration") }
        return config
    }

    static func getUInt(_ object: NSObject, _ name: String) -> UInt32 {
        let sel = NSSelectorFromString(name)
        return unsafeBitCast(object.method(for: sel), to: (@convention(c) (AnyObject, Selector) -> UInt32).self)(object, sel)
    }

    static func setUInt(_ object: NSObject, _ name: String, _ value: UInt32) {
        let sel = NSSelectorFromString(name)
        unsafeBitCast(object.method(for: sel), to: (@convention(c) (AnyObject, Selector, UInt32) -> Void).self)(object, sel, value)
    }

    static func customColor(_ object: NSObject) -> CGColor? {
        let sel = NSSelectorFromString("otherIconTintColor")
        return unsafeBitCast(object.method(for: sel), to: (@convention(c) (AnyObject, Selector) -> Unmanaged<CGColor>?).self)(object, sel)?.takeUnretainedValue()
    }

    static func setCustomColor(_ object: NSObject, _ color: CGColor?) {
        let sel = NSSelectorFromString("setOtherIconTintColor:")
        unsafeBitCast(object.method(for: sel), to: (@convention(c) (AnyObject, Selector, CGColor?) -> Void).self)(object, sel, color)
    }

    static func save(_ object: NSObject) {
        let sel = NSSelectorFromString("save")
        unsafeBitCast(object.method(for: sel), to: (@convention(c) (AnyObject, Selector) -> Void).self)(object, sel)
    }

    static func hex(_ color: CGColor?) -> Any {
        guard let color, let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let c = srgb.components, c.count >= 3 else { return NSNull() }
        return String(format: "#%02x%02x%02x", Int((c[0] * 255).rounded()), Int((c[1] * 255).rounded()), Int((c[2] * 255).rounded()))
    }

    static func current() -> [String: Any] {
        let config = fetch()
        let style = Int(getUInt(config, "iconAppearanceTheme")), tint = Int(getUInt(config, "iconTintColorName"))
        return ["style": styles.indices.contains(style) ? styles[style] : "Unknown\(style)",
                "tint": tints.indices.contains(tint) ? tints[tint] : "Unknown\(tint)",
                "custom": storedCustomTint().map(customHex) ?? hex(customColor(config))]
    }

    /// What macOS stored in its defaults after a save. The keys are absent for the default style and for no tint.
    static func storedStyle() -> String {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue("AppleIconAppearanceTheme" as CFString, kCFPreferencesAnyApplication) as? String ?? "RegularLight"
    }

    static func storedTint() -> String {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue("AppleIconAppearanceTintColor" as CFString, kCFPreferencesAnyApplication) as? String ?? "None"
    }

    static func storedCustomTint() -> String? {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return CFPreferencesCopyAppValue("AppleIconAppearanceCustomTintColor" as CFString, kCFPreferencesAnyApplication) as? String
    }

    static func set(_ value: [String: Any]) {
        guard let styleName = value["style"] as? String, let style = styles.firstIndex(of: styleName) else { fail("unknown icon style") }
        let tintName = value["tint"] as? String
        let tint = tintName.flatMap { tints.firstIndex(of: $0) }
        let config = fetch()
        let before = (getUInt(config, "iconAppearanceTheme"), getUInt(config, "iconTintColorName"), customColor(config))
        setUInt(config, "setIconAppearanceTheme:", UInt32(style))
        if let tint { setUInt(config, "setIconTintColorName:", UInt32(tint)) }
        if let hexString = value["custom"] as? String, let color = parse(hexString) { setCustomColor(config, color) }
        save(config)
        usleep(300_000)
        let after = current()
        let stored = storedStyle()
        let tintOK = tintName == nil || storedTint() == tintName
        let customOK = value["custom"] as? String == nil || storedCustomTint() != nil
        guard after["style"] as? String == styleName, stored == styleName, tintOK, customOK else {
            let revert = fetch()
            setUInt(revert, "setIconAppearanceTheme:", before.0)
            setUInt(revert, "setIconTintColorName:", before.1)
            setCustomColor(revert, before.2)
            save(revert)
            fail("icon style read back \(after["style"] ?? "?") / defaults \(stored), tint \(storedTint()), custom \(storedCustomTint() ?? "none"); expected \(styleName) \(tintName ?? ""); reverted")
        }
        succeed(after)
    }

    /// "r g b a" floats, as SkyLight stores them, to #rrggbb.
    static func customHex(_ stored: String) -> Any {
        let parts = stored.split(separator: " ").compactMap { Double($0) }
        guard parts.count >= 3 else { return NSNull() }
        return String(format: "#%02x%02x%02x", Int((parts[0] * 255).rounded()), Int((parts[1] * 255).rounded()), Int((parts[2] * 255).rounded()))
    }

    static func parse(_ hex: String) -> CGColor? {
        guard hex.count == 7, hex.hasPrefix("#"), let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Entry point

let args = CommandLine.arguments.dropFirst()
switch (args.first, args.dropFirst().first) {
case ("check", _):
    succeed(["appearance": AppearanceTweak.resolves, "accent": AccentTweak.resolves, "iconStyle": IconTweak.resolves])
case ("get", "appearance"?):
    guard AppearanceTweak.resolves else { fail("appearance calls are missing") }
    succeed(AppearanceTweak.current())
case ("get", "accent"?):
    guard AccentTweak.resolves else { fail("accent calls are missing") }
    succeed(AccentTweak.readBack())
case ("get", "iconStyle"?):
    guard IconTweak.resolves else { fail("icon style calls are missing or changed") }
    succeed(IconTweak.current())
case ("set", let id?):
    guard let raw = args.dropFirst(2).first, let data = raw.data(using: .utf8),
          let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { fail("set needs a JSON value") }
    switch id {
    case "appearance":
        guard AppearanceTweak.resolves, let object = value as? [String: Any] else { fail("appearance calls are missing or the value is invalid") }
        AppearanceTweak.set(object)
    case "accent":
        guard AccentTweak.resolves, let number = value as? NSNumber else { fail("accent calls are missing or the value is invalid") }
        AccentTweak.apply(number.intValue)
    case "iconStyle":
        guard IconTweak.resolves, let object = value as? [String: Any] else { fail("icon style calls are missing or the value is invalid") }
        IconTweak.set(object)
    default:
        fail("unknown tweak \(id)")
    }
default:
    fail("usage: scene-tweak check | get <id> | set <id> <json>")
}
