import ImageIO
import SceneThemes
import SwiftUI
import UniformTypeIdentifiers

/// Scene keeps running after its window closes, so the theme switcher shortcut keeps working.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { ThemeSwitcher.shared.model?.registerShortcuts() }
    }
}

@main
struct SceneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        // Limit ImageIO to the formats themes may contain, for the lifetime of the process.
        if #available(macOS 14.2, *) {
            CGImageSourceSetAllowableTypes([UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier] as CFArray)
        }
        let model = AppModel()
        ThemeSwitcher.shared.model = model
        _model = State(initialValue: model)
    }

    var body: some Scene {
        @Bindable var model = model
        Window("Scene", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Switch Theme…" + model.switcherShortcut.menuSuffix) { ThemeSwitcher.shared.show() }
                Button("Next Background" + model.nextBackgroundShortcut.menuSuffix) { Task { await model.nextBackground() } }
                    .disabled(model.history.isEmpty)
                Button("Undo Last Theme") { Task { await model.undo() } }
                    .keyboardShortcut("z", modifiers: [.command, .option])
                    .disabled(model.history.isEmpty)
            }
        }

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra("Scene", systemImage: "paintpalette", isInserted: $model.showMenuBarExtra) {
            MenuBarView().environment(model)
        }
    }
}
