import AppKit
import SceneThemes
import SwiftUI

/// Development aid: with SCENE_SNAPSHOT=<folder>, the app renders its own windows to PNG files and quits.
/// It draws in-process, so it needs no screen-recording permission. It never applies anything.
@MainActor
enum Snapshot {
    static var folder: URL? { ProcessInfo.processInfo.environment["SCENE_SNAPSHOT"].map { URL(fileURLWithPath: $0) } }

    /// Renders each visible window, with its sheet, through the window server. A process may capture its
    /// own windows without the Screen Recording permission. The call is deprecated, so it is looked up at run time.
    static func capture(_ name: String) {
        guard let folder, let createImage else { return }
        let windows = NSApp.windows.filter { $0.isVisible && $0.sheetParent == nil && $0.frame.width > 100 && $0.frame.height > 100 }
        for (index, window) in windows.enumerated() {
            var ids = ((window.attachedSheet.map { [$0] } ?? []) + [window]).map { UnsafeRawPointer(bitPattern: UInt($0.windowNumber)) }
            guard let array = CFArrayCreate(nil, &ids, ids.count, nil),
                  let image = createImage(.null, array, 1 << 0 | 1 << 3)?.takeRetainedValue() else { continue }   // ignore framing, best resolution
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent("\(name)-\(index).png"))
        }
    }

    private typealias CreateImage = @convention(c) (CGRect, CFArray, UInt32) -> Unmanaged<CGImage>?
    private static let createImage: CreateImage? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImageFromArray")
        .map { unsafeBitCast($0, to: CreateImage.self) }

    static func run(model: AppModel, applying: Binding<Theme?>, page: Binding<Page?>, openSettings: () -> Void) async {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let environment = ProcessInfo.processInfo.environment
        // SCENE_SNAPSHOT_APPEARANCE=light or dark renders Scene in that look, whatever macOS uses.
        if let look = environment["SCENE_SNAPSHOT_APPEARANCE"] { NSApp.appearance = NSAppearance(named: look == "light" ? .aqua : .darkAqua) }
        // SCENE_SNAPSHOT_THEME=<theme id> chooses the theme for the theme page, the Apply sheet, and the carousel.
        let chosen = model.themes.first { $0.id == environment["SCENE_SNAPSHOT_THEME"] }
            ?? model.themes.first { $0.variants.values.contains { $0.wallpapers.count > 1 } }
        if let chosen { model.selectedThemeID = chosen.id }
        try? await Task.sleep(for: .seconds(2.5))
        capture("1-theme")
        if let theme = chosen {
            if theme.availableAppearances.count == 2 {
                model.previewAppearance[theme.id] = model.appearance(for: theme) == .dark ? .light : .dark
                try? await Task.sleep(for: .seconds(1.5))
                capture("2-other-look")
                model.previewAppearance[theme.id] = nil
            }
            // Pick the second wallpaper, then put your own picks back.
            let variant = model.variant(for: theme)
            let saved = model.backgroundChoices
            if variant.wallpapers.count > 1 { model.choose(variant.wallpapers[1], for: variant) }
            try? await Task.sleep(for: .seconds(1.5))
            capture("3-background-picked")
            model.backgroundChoices = saved
            applying.wrappedValue = theme
            try? await Task.sleep(for: .seconds(4))
            capture("4-apply-plan")
            applying.wrappedValue = nil
            try? await Task.sleep(for: .seconds(1))
        }
        page.wrappedValue = .apps
        try? await Task.sleep(for: .seconds(1.5))
        capture("5-apps")
        page.wrappedValue = .history
        try? await Task.sleep(for: .seconds(1.5))
        capture("6-history")
        page.wrappedValue = nil
        // The switcher's carousel in a plain window, in dark mode. The real switcher takes keyboard focus.
        let state = CarouselState(themes: model.themes, currentID: model.currentThemeID, systemIsDark: true, wallpaper: { model.wallpaper(for: $0)?.url })
        if let index = model.themes.firstIndex(where: { $0.id == chosen?.id }) { state.selection.select(index) }
        await show(ThemeCarouselView(state: state, onApply: {}, onClose: {}), size: NSSize(width: 1600, height: 900), style: [.borderless], name: "7-carousel")
        await show(MenuBarView().environment(model), size: NSSize(width: 364, height: 590), style: [.titled], name: "8-menu-bar")
        // The Settings window, one tab at a time.
        openSettings()
        for tab in [SettingsTab.general, .shortcuts, .experimental] {
            model.settingsTab = tab
            try? await Task.sleep(for: .seconds(1.2))
            capture("9-settings-\(tab)")
        }
        model.settingsTab = .general
        // SCENE_SNAPSHOT_SWITCHER=0 skips the switcher. It takes keyboard focus over every screen, and ↩ in it applies a theme.
        if environment["SCENE_SNAPSHOT_SWITCHER"] != "0" {
            await switcher()
        }
        NSApp.terminate(nil)
    }

    /// Shows a view in a window of its own for one capture.
    static func show(_ view: some View, size: NSSize, style: NSWindow.StyleMask, name: String) async {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: view)
        window.orderFront(nil)
        try? await Task.sleep(for: .seconds(2))
        capture(name)
        window.orderOut(nil)
    }

    static func switcher() async {
        ThemeSwitcher.shared.show()
        try? await Task.sleep(for: .seconds(1.5))
        capture("10-switcher")
        if let panel = ThemeSwitcher.shared.panels.first(where: \.isKeyWindow) {
            // Move right twice, as a person would with the arrow key.
            for _ in 0..<2 {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124) {
                    panel.keyDown(with: event)
                }
            }
            try? await Task.sleep(for: .seconds(1))
            capture("11-switcher-moved")
        }
        ThemeSwitcher.shared.hide()
    }
}
