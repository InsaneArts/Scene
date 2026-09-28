import AppKit
import SceneThemes
import SwiftUI

/// Development aid: with SCENE_SNAPSHOT=<folder>, the app renders its own windows to PNG files and quits.
/// It draws in-process, so it needs no screen-recording permission. It never applies anything.
@MainActor
enum Snapshot {
    static var folder: URL? { ProcessInfo.processInfo.environment["SCENE_SNAPSHOT"].map { URL(fileURLWithPath: $0) } }

    static func capture(_ name: String) {
        guard let folder else { return }
        for (index, window) in NSApp.windows.enumerated() where window.isVisible && window.contentView != nil {
            let views = [window.contentView!] + (window.attachedSheet?.contentView.map { [$0] } ?? [])
            for (i, view) in views.enumerated() {
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let suffix = i == 0 ? "" : "-sheet"
                try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(name)-\(index)\(suffix).png"))
            }
        }
    }

    static func run(model: AppModel, applying: Binding<Theme?>, sidebar: Binding<SidebarItem>, openSettings: () -> Void) async {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(2))
        capture("1-themes")
        if let light = model.themes.first(where: { $0.availableAppearances.count == 2 }) {
            model.selectedThemeID = light.id
            model.previewAppearance[light.id] = .light
            try? await Task.sleep(for: .seconds(1.5))
            capture("2-light-variant")
            applying.wrappedValue = light
            try? await Task.sleep(for: .seconds(4))
            capture("3-apply-plan")
            applying.wrappedValue = nil
        }
        sidebar.wrappedValue = .apps
        try? await Task.sleep(for: .seconds(1.5))
        capture("4-apps")
        sidebar.wrappedValue = .history
        try? await Task.sleep(for: .seconds(1))
        capture("5-history")
        // The theme page in a window of its own: the main window's split views capture blank.
        // SCENE_SNAPSHOT_THEME=<theme id> chooses the theme for this page and the carousel.
        let chosen = model.themes.first { $0.id == ProcessInfo.processInfo.environment["SCENE_SNAPSHOT_THEME"] }
            ?? model.themes.first { $0.variants.values.contains { $0.wallpapers.count > 1 } }
        if let theme = chosen, let variant = theme.variants[model.appearance(for: theme)] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 1000), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: ThemeDetailView(theme: theme, applying: .constant(nil)).environment(model))
            window.orderFront(nil)
            try? await Task.sleep(for: .seconds(2))
            capture("8-theme-page")
            // Pick the second wallpaper, then put your own picks back.
            let saved = model.backgroundChoices
            if variant.wallpapers.count > 1 { model.choose(variant.wallpapers[1], for: variant) }
            try? await Task.sleep(for: .seconds(1.5))
            capture("9-theme-page-picked")
            model.backgroundChoices = saved
            window.orderOut(nil)
        }
        // The switcher's carousel in a plain window, in dark mode. The real switcher takes keyboard focus.
        let state = CarouselState(themes: model.themes, currentID: model.currentThemeID, systemIsDark: true, wallpaper: { model.wallpaper(for: $0)?.url })
        if let index = model.themes.firstIndex(where: { $0.id == chosen?.id }) { state.selection.select(index) }
        let carousel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        carousel.contentView = NSHostingView(rootView: ThemeCarouselView(state: state, onApply: {}, onClose: {}))
        carousel.orderFront(nil)
        try? await Task.sleep(for: .seconds(2))
        capture("11-carousel")
        carousel.orderOut(nil)
        // The Settings window, one tab at a time.
        openSettings()
        for tab in [SettingsTab.general, .shortcuts, .apps, .experimental] {
            model.settingsTab = tab
            try? await Task.sleep(for: .seconds(1.2))
            capture("10-settings-\(tab)")
        }
        model.settingsTab = .general
        // SCENE_SNAPSHOT_SWITCHER=0 skips the switcher. It takes keyboard focus over every screen, and ↩ in it applies a theme.
        if ProcessInfo.processInfo.environment["SCENE_SNAPSHOT_SWITCHER"] != "0" {
            await switcher()
        }
        NSApp.terminate(nil)
    }

    static func switcher() async {
        ThemeSwitcher.shared.show()
        try? await Task.sleep(for: .seconds(1.5))
        capture("6-switcher")
        if let panel = ThemeSwitcher.shared.panels.first(where: \.isKeyWindow) {
            // Move right twice, as a person would with the arrow key.
            for _ in 0..<2 {
                if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
                                                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124) {
                    panel.keyDown(with: event)
                }
            }
            try? await Task.sleep(for: .seconds(1))
            capture("7-switcher-moved")
        }
        ThemeSwitcher.shared.hide()
    }
}
