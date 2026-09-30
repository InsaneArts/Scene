import ImageIO
import SceneEngine
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
            ThemeSwitcher.shared.model?.startWatchingLibrary()
            Updater.shared.start()
        }
    }
}

@main
struct SceneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        // `Scene --check-theme` and `Scene --build-theme` run the theme command line and quit before any window opens.
        if let status = ThemeTool.run(CommandLine.arguments, install: Self.install, print: { print($0) }) { exit(status) }
        // Limit ImageIO to the formats themes may contain, for the lifetime of the process.
        if #available(macOS 14.2, *) {
            CGImageSourceSetAllowableTypes([UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier] as CFArray)
        }
        let model = AppModel()
        ThemeSwitcher.shared.model = model
        _model = State(initialValue: model)
    }

    /// Adds a theme folder built on the command line to the library, and tells a running Scene to show it.
    static func install(_ folder: URL) throws {
        let library = ThemeLibrary(bundledFolder: Locations.bundledThemes,
                                   installedFolder: SceneEnvironment.live().appSupport.appendingPathComponent("Themes"))
        try library.importPackage(at: folder)
        DistributedNotificationCenter.default().postNotificationName(AppModel.libraryChanged, object: nil, userInfo: nil, deliverImmediately: true)
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
                // Commands sit outside the window's views, so the model is passed in.
                NewThemeButton().environment(model)
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

        Window("Theme Maker", id: "maker") {
            ThemeMakerView().environment(model)
                .frame(minWidth: 1100, minHeight: 740)
        }
        .defaultSize(width: 1320, height: 880)

        Settings {
            SettingsView().environment(model)
        }

        MenuBarExtra("Scene", systemImage: "paintpalette", isInserted: $model.showMenuBarExtra) {
            MenuBarView().environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
