import ImageIO
import SceneThemes
import SwiftUI
import UniformTypeIdentifiers

/// Scene keeps running after its window closes, so the theme switcher shortcut keeps working.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            ThemeSwitcher.shared.model?.registerShortcuts()
            ThemeSwitcher.shared.model?.startFollowingAppearance()
            Updater.shared.start()
        }
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
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 800)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.canCheckForUpdates)
            }
            CommandGroup(after: .newItem) {
                Button("Install Theme from GitHub…") { model.installingFromGitHub = true }
                Divider()
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
        .menuBarExtraStyle(.window)
    }
}
