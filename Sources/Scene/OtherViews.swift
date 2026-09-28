import SceneEngine
import SceneSwitcher
import SceneThemes
import SwiftUI

// MARK: - Apps

/// What Scene found on this Mac, and what it can do there.
struct AppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let integrations = model.engine.integrations
        List {
            Section {
                ForEach(integrations.filter { model.detections[$0.id]?.installed ?? false }, id: \.id) { integration in
                    let detection = model.detections[integration.id]!
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: Symbols.integration(integration.id)).frame(width: 22).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(integration.displayName).font(.body.weight(.medium))
                                if let version = detection.version { Text(version).font(.caption).foregroundStyle(.tertiary) }
                            }
                            if let detail = detection.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            if case .blocked(let reason) = detection.setup { Text(reason).font(.caption).foregroundStyle(.orange) }
                            if case .needsOneTimeSetup(let step) = detection.setup { Text(step).font(.caption).foregroundStyle(.orange) }
                            ForEach(detection.conflicts, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                            if model.changedOutside[integration.id] != nil {
                                Label("Changed outside Scene since the last theme. Scene leaves it alone until you apply again.", systemImage: "exclamationmark.triangle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if model.ledger.contains(where: { $0.integration == integration.id }) {
                            Button("Stop Managing") { Task { await model.restoreOriginal(only: [integration.id]) } }
                                .help("Restore this app's original setup and leave it out of future themes")
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("Detected on this Mac") }
            let missing = integrations.filter { !(model.detections[$0.id]?.installed ?? false) }
            if !missing.isEmpty {
                Section("Not installed") { Text(missing.map(\.displayName).joined(separator: ", ")).foregroundStyle(.secondary) }
            }
            Section("Follows Light/Dark only") {
                Text("Slack, Discord, Safari, and Chrome cannot be themed by other apps. Set their appearance to follow the system and they switch with macOS.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Apps")
        .toolbar { Button { Task { await model.refreshSystemState() } } label: { Label("Check Again", systemImage: "arrow.clockwise") } }
    }
}

// MARK: - History and restore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRestore = false

    var body: some View {
        List {
            Section {
                if model.history.isEmpty { Text("No theme applied yet.").foregroundStyle(.secondary) }
                ForEach(model.history.reversed()) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.themeName).font(.body.weight(.medium))
                            Text("\(entry.integrations.count) apps · \(entry.mode == .system ? "Matches macOS" : entry.mode.rawValue.capitalized)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entry.date, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: { Text("Applied themes") }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Restore puts back everything Scene changed: files, settings, the wallpaper, and macOS appearance. Anything you changed yourself after Scene stays as you left it.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Undo Last Theme") { Task { await model.undo() } }.disabled(model.history.isEmpty)
                        Button("Restore Original Setup…") { confirmRestore = true }.disabled(model.ledger.isEmpty)
                    }
                }
                .padding(.vertical, 4)
                if let results = model.lastRestore, !results.isEmpty {
                    ForEach(results) { item in
                        Label("\(item.integration): \(item.result)", systemImage: item.keptUserChange ? "person.crop.circle.badge.checkmark" : "arrow.uturn.backward.circle")
                            .font(.caption)
                    }
                }
            } header: { Text("Restore") }

            if !model.ledger.isEmpty {
                Section("What Scene manages now") {
                    ForEach(model.ledger, id: \.resource) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.operation.summary).font(.callout)
                            Text(entry.integration).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .confirmationDialog("Restore your original setup?", isPresented: $confirmRestore) {
            Button("Restore Original Setup", role: .destructive) { Task { await model.restoreOriginal() } }
        } message: {
            Text("Scene restores \(model.ledger.count) items it changed, in \(Set(model.ledger.map(\.integration)).count) apps. Your own later changes stay.")
        }
    }
}

// MARK: - Settings

enum SettingsTab: Hashable { case general, shortcuts, apps, experimental }

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // The window takes each tab's size, so each tab fits its content without scrolling.
        TabView(selection: $model.settingsTab) {
            GeneralSettings().frame(width: 560, height: 150).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            ShortcutSettings().frame(width: 560, height: 420).tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(SettingsTab.shortcuts)
            AppSettings().frame(width: 560, height: 680).tabItem { Label("Apps", systemImage: "square.grid.2x2") }.tag(SettingsTab.apps)
            ExperimentalSettings().frame(width: 560, height: 270).tabItem { Label("Experimental", systemImage: "flask") }.tag(SettingsTab.experimental)
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Open Scene at login", isOn: Binding(get: { _ = model.loginItemVersion; return model.openAtLogin }, set: { model.openAtLogin = $0 }))
                Toggle("Show Scene in the menu bar", isOn: $model.showMenuBarExtra)
            } footer: {
                Text("The shortcuts work while Scene runs. Scene keeps running after you close its window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct ShortcutSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                LabeledContent("Switch theme") { ShortcutRecorder(shortcut: \.switcherShortcut, standard: .omarchyDefault) }
                LabeledContent("Next background") { ShortcutRecorder(shortcut: \.nextBackgroundShortcut, standard: .nextBackgroundDefault) }
                if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Anywhere on your Mac")
            } footer: {
                Text("Click a shortcut, then press the new keys. A shortcut needs ⌘ or ⌃. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("In the theme switcher") {
                keys("Choose a theme", "← →", "h l")
                keys("Jump to a theme", "1 – 9")
                keys("Light or Dark", "↑ ↓", "Tab")
                keys("Apply", "↩")
                keys("Close", "Esc")
            }
        }
        .formStyle(.grouped)
    }

    func keys(_ action: String, _ keys: String, _ alternative: String? = nil) -> some View {
        LabeledContent(action) {
            (Text(keys).monospaced() + Text(alternative == nil ? "" : " or ") + Text(alternative ?? "").monospaced())
                .foregroundStyle(.secondary)
        }
    }
}

/// Which apps a theme changes. The Apply sheet's toggles change the same setting.
struct AppSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            ForEach([IntegrationKind.system, .experimental, .terminal, .editor], id: \.self) { kind in
                Section {
                    ForEach(model.engine.integrations.filter { $0.kind == kind }, id: \.id) { integration in
                        Toggle(isOn: Binding(get: { !model.disabledIntegrations.contains(integration.id) }, set: { on in
                            if on { model.disabledIntegrations.remove(integration.id) } else { model.disabledIntegrations.insert(integration.id) }
                        })) {
                            HStack {
                                Image(systemName: Symbols.integration(integration.id)).frame(width: 20).foregroundStyle(.secondary)
                                Text(integration.displayName)
                                if model.detections[integration.id]?.installed == false { Text("Not installed").font(.caption).foregroundStyle(.tertiary) }
                            }
                        }
                    }
                } header: {
                    Text(title(kind))
                } footer: {
                    if kind == .editor {
                        Text("Apply and the theme switcher change only the apps that are on here. Turning an app off in the Apply sheet turns it off here too.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { if model.detections.isEmpty { await model.refreshSystemState() } }
    }

    func title(_ kind: IntegrationKind) -> String {
        switch kind {
        case .system: "Desktop"
        case .experimental: "macOS look (experimental)"
        case .terminal: "Terminals"
        case .editor: "Editors"
        }
    }
}

struct ExperimentalSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("Change accent color, icon style, and Light/Dark with private macOS calls", isOn: $model.experimentalEnabled)
                Toggle("Allow on macOS versions Scene has not tested", isOn: $model.allowUntested)
                    .disabled(!model.experimentalEnabled)
                ForEach(["appearance", "accent", "iconStyle"], id: \.self) { id in
                    LabeledContent(label(id)) {
                        switch model.tweaks.availability(id) {
                        case .available: Text("On").foregroundStyle(.green)
                        case .disabled(let reason): Text(reason).foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            } footer: {
                Text("These calls are what System Settings uses. They run in a separate helper, are checked before each use, and are read back after. Any macOS update can turn them off until Scene is updated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    func label(_ id: String) -> String {
        switch id {
        case "appearance": "Light/Dark without a permission prompt"
        case "accent": "Accent color"
        default: "Icon & widget style"
        }
    }
}

/// Records a global shortcut. Scene's shortcuts are paused while recording, so pressing one of them is captured.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    let shortcut: ReferenceWritableKeyPath<AppModel, HotKeySpec?>
    /// What the reset button restores.
    let standard: HotKeySpec
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        let current = model[keyPath: shortcut]
        HStack(spacing: 6) {
            Button(recording ? "Type a shortcut…" : current?.display ?? "Off") { recording ? stop() : start() }
                .monospaced()
            Button { model[keyPath: shortcut] = standard } label: { Image(systemName: "arrow.counterclockwise") }
                .buttonStyle(.borderless).help("Use the default, \(standard.display)").disabled(current == standard)
            Button { model[keyPath: shortcut] = nil } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).help("Turn this shortcut off").disabled(current == nil)
        }
        .onDisappear { stop() }
    }

    func start() {
        recording = true
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }   // Esc cancels
            let flags = event.modifierFlags
            let spec = HotKeySpec(keyCode: UInt32(event.keyCode), command: flags.contains(.command), control: flags.contains(.control),
                                  option: flags.contains(.option), shift: flags.contains(.shift), keyLabel: Self.label(event))
            // Scene's other shortcut cannot share the keys.
            let others = [model.switcherShortcut, model.nextBackgroundShortcut].compactMap { $0 }.filter { $0 != model[keyPath: shortcut] }
            guard spec.isAllowed, !others.contains(spec) else { NSSound.beep(); return nil }
            model[keyPath: shortcut] = spec
            stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { recording = false; model.registerShortcuts() }
    }

    static func label(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: "Space"
        case 36: "↩"
        case 48: "⇥"
        case 51: "⌫"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        case 122: "F1"
        case 120: "F2"
        case 99: "F3"
        case 118: "F4"
        case 96: "F5"
        case 97: "F6"
        case 98: "F7"
        case 100: "F8"
        default: (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(model.themes) { theme in
            Button { Task { await model.quickApply(theme) } } label: {
                Text(theme.id == model.currentThemeID ? "✓ \(theme.manifest.name)" : theme.manifest.name)
            }
        }
        Divider()
        Button("Switch Theme…" + model.switcherShortcut.menuSuffix) { ThemeSwitcher.shared.show() }
        Button("Next Background" + model.nextBackgroundShortcut.menuSuffix) { Task { await model.nextBackground() } }.disabled(model.history.isEmpty)
        Button("Undo Last Theme") { Task { await model.undo() } }.disabled(model.history.isEmpty)
        Button("Open Scene") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        Divider()
        Button("Quit Scene") { NSApp.terminate(nil) }
    }
}
