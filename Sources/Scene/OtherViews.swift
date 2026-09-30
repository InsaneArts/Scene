import SceneEngine
import SceneSwitcher
import SceneThemes
import SwiftUI

// MARK: - Apps

/// What Scene found on this Mac, which apps a theme changes, and a way to give one back.
/// The Apply sheet's switches change the same setting.
struct AppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let integrations = model.engine.integrations
        let installed = integrations.filter { model.detections[$0.id]?.installed ?? false }
        let missing = integrations.filter { !(model.detections[$0.id]?.installed ?? false) }
        PageScroll(title: "Apps", subtitle: "What Scene found on this Mac. A theme changes only the apps that are on.") {
            ForEach([IntegrationKind.system, .terminal, .editor, .tool, .experimental], id: \.self) { kind in
                let items = installed.filter { $0.kind == kind }
                if !items.isEmpty {
                    CardSection(title: title(kind)) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, integration in
                            if index > 0 { Divider().padding(.leading, 58) }
                            AppRow(integration: integration)
                        }
                    }
                }
            }
            CardSection(title: "Other apps") {
                VStack(alignment: .leading, spacing: 12) {
                    if !missing.isEmpty {
                        HStack(spacing: 14) {
                            Text("Not installed").foregroundStyle(.secondary)
                            ForEach(missing, id: \.id) { integration in
                                Label { Text(integration.displayName) } icon: { AppIcon(id: integration.id, size: 18) }
                            }
                        }
                        .opacity(0.8)
                        Divider()
                    }
                    Text("Slack, Discord, Safari, Chrome, and Raycast cannot be themed by other apps. Set their appearance to follow the system, and they switch with Light/Dark.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toolbar { Button { Task { await model.refreshSystemState() } } label: { Label("Check Again", systemImage: "arrow.clockwise") } }
        .task { if model.detections.isEmpty { await model.refreshSystemState() } }
    }

    func title(_ kind: IntegrationKind) -> String {
        switch kind {
        case .system: "Desktop"
        case .terminal: "Terminals"
        case .editor: "Editors"
        case .tool: "Command-line tools"
        case .experimental: "macOS look · experimental"
        }
    }
}

struct AppRow: View {
    @Environment(AppModel.self) private var model
    let integration: any Integration

    var body: some View {
        let id = integration.id
        let detection = model.detections[id]
        HStack(alignment: .top, spacing: 12) {
            AppIcon(id: id, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(integration.displayName).font(.body.weight(.medium))
                    if let version = detection?.version { Text(version).font(.caption).foregroundStyle(.tertiary) }
                }
                if let detail = detection?.detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }
                ForEach(warnings(detection), id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
                ForEach(detection?.conflicts ?? [], id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            if model.ledger.contains(where: { $0.integration == id }) {
                Menu {
                    Button("Stop Managing") {
                        model.disabledIntegrations.insert(id)
                        Task { await model.restoreOriginal(only: [id]) }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Stop Managing restores this app's original setup and leaves it out of future themes")
            }
            Toggle("Change \(integration.displayName) with themes", isOn: Binding(get: { !model.disabledIntegrations.contains(id) }, set: { on in
                if on { model.disabledIntegrations.remove(id) } else { model.disabledIntegrations.insert(id) }
            }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    func warnings(_ detection: Detection?) -> [String] {
        var warnings: [String] = []
        if case .blocked(let reason)? = detection?.setup { warnings.append(reason) }
        if case .needsOneTimeSetup(let step)? = detection?.setup { warnings.append(step) }
        if model.changedOutside[integration.id] != nil {
            warnings.append("Changed outside Scene since the last theme. Scene leaves it alone until you apply again.")
        }
        return warnings
    }
}

// MARK: - History and restore

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmRestore = false

    var body: some View {
        PageScroll(title: "History", subtitle: "Undo goes back one theme. Restore puts back everything Scene changed and keeps the changes you made yourself.") {
            if let current = model.history.last {
                currentCard(current)
            } else {
                CardSection {
                    ContentUnavailableView("No Theme Applied Yet", systemImage: "clock",
                                           description: Text("Themes you apply show up here, with a way back."))
                        .padding(.vertical, 20)
                }
            }
            if model.history.count > 1 {
                CardSection(title: "Earlier") {
                    ForEach(Array(model.history.dropLast().reversed().enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().padding(.leading, 90) }
                        HStack(spacing: 12) {
                            HistoryThumbnail(entry: entry).frame(width: 64, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.themeName).font(.body.weight(.medium))
                                Text(details(entry)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(entry.date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
            }
            if let results = model.lastRestore, !results.isEmpty {
                CardSection(title: "Last restore") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(results) { item in
                            Label("\(item.integration): \(item.result)",
                                  systemImage: item.keptUserChange ? "person.crop.circle.badge.checkmark" : "arrow.uturn.backward.circle")
                        }
                    }
                    .font(.caption)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !model.ledger.isEmpty { ManagedItems(ledger: model.ledger) }
        }
        .confirmationDialog("Restore your original setup?", isPresented: $confirmRestore) {
            Button("Restore Original Setup", role: .destructive) { Task { await model.restoreOriginal() } }
        } message: {
            Text("Scene restores \(model.ledger.count) items it changed, in \(Set(model.ledger.map(\.integration)).count) apps. Your own later changes stay.")
        }
    }

    func currentCard(_ entry: HistoryEntry) -> some View {
        CardSection {
            HStack(spacing: 18) {
                HistoryThumbnail(entry: entry).frame(width: 184, height: 115)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Current theme").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(entry.themeName).font(.title2.weight(.semibold))
                    Text(entry.date, format: .dateTime.month().day().hour().minute()).font(.callout).foregroundStyle(.secondary)
                        + Text(" · " + details(entry)).font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button("Undo Last Theme") { Task { await model.undo() } }
                        Button("Restore Original Setup…") { confirmRestore = true }.disabled(model.ledger.isEmpty)
                    }
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }

    func details(_ entry: HistoryEntry) -> String {
        "\(entry.integrations.count) apps · " + (entry.mode == .system ? "Matches macOS" : entry.mode.rawValue.capitalized)
    }
}

/// The wallpaper a history entry showed, or a placeholder when its theme is gone.
struct HistoryThumbnail: View {
    @Environment(AppModel.self) private var model
    let entry: HistoryEntry

    var body: some View {
        if let theme = model.themes.first(where: { $0.id == entry.themeID }) {
            let variant = ApplyRequest(theme: theme, mode: entry.mode, systemIsDark: model.systemIsDark).current
            WallpaperView(variant: variant, url: variant.wallpaper(named: entry.wallpaper)?.url, pixels: 480)
        } else {
            Rectangle().fill(.quaternary).overlay(Image(systemName: "paintpalette").foregroundStyle(.secondary))
        }
    }
}

/// Every file and setting Scene manages, by app. Restore puts each one back.
struct ManagedItems: View {
    let ledger: [LedgerEntry]
    @State private var expanded = false

    var body: some View {
        let apps = Dictionary(grouping: ledger, by: \.integration).sorted { $0.key < $1.key }
        CardSection {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(apps, id: \.key) { app, entries in
                        HStack(alignment: .top, spacing: 10) {
                            AppIcon(id: app, size: 20)
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(entries, id: \.resource) { Text($0.operation.summary) }
                            }
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("What Scene manages now").font(.body.weight(.medium))
                    + Text("  \(ledger.count) items").foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }
}

// MARK: - Settings

enum SettingsTab: Hashable { case general, shortcuts, experimental }

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        // The window takes each tab's size, so each tab fits its content without scrolling.
        TabView(selection: $model.settingsTab) {
            GeneralSettings().frame(width: 540, height: 440).tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            ShortcutSettings().frame(width: 540, height: 440).tabItem { Label("Shortcuts", systemImage: "keyboard") }.tag(SettingsTab.shortcuts)
            ExperimentalSettings().frame(width: 540, height: 330).tabItem { Label("Experimental", systemImage: "flask") }.tag(SettingsTab.experimental)
        }
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        @Bindable var updater = Updater.shared
        Form {
            Section {
                Toggle("Open Scene at login", isOn: Binding(get: { _ = model.loginItemVersion; return model.openAtLogin }, set: { model.openAtLogin = $0 }))
                Toggle("Show Scene in the menu bar", isOn: $model.showMenuBarExtra)
            } footer: {
                Text("The shortcuts work while Scene runs. Scene keeps running after you close its window. Choose which apps a theme changes on the Apps page of the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                LabeledContent {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } label: {
                    Text("Scene \(Updater.version)")
                    Text(updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))." } ?? "Not checked yet.")
                }
                Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
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
                HStack { Text("Switch theme"); Spacer(); ShortcutRecorder(shortcut: \.switcherShortcut, standard: .omarchyDefault) }
                HStack { Text("Next background"); Spacer(); ShortcutRecorder(shortcut: \.nextBackgroundShortcut, standard: .nextBackgroundDefault) }
                if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Anywhere on your Mac")
            } footer: {
                Text("Click a shortcut, then press the new keys. A shortcut needs ⌘ or ⌃. Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("In the theme switcher") {
                keys("Choose a theme", ["←", "→"], or: ["H", "L"])
                keys("Jump to a theme", ["1"], through: ["9"])
                keys("Light or Dark", ["↑", "↓"], or: ["⇥"])
                keys("Apply", ["↩"])
                keys("Close", ["esc"])
            }
        }
        .formStyle(.grouped)
    }

    func keys(_ action: String, _ keys: [String], or alternative: [String] = [], through last: [String] = []) -> some View {
        LabeledContent(action) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { Keycap(key: $0) }
                if !alternative.isEmpty { Text("or").foregroundStyle(.secondary).padding(.horizontal, 3) }
                if !last.isEmpty { Text("to").foregroundStyle(.secondary).padding(.horizontal, 3) }
                ForEach(alternative + last, id: \.self) { Keycap(key: $0) }
            }
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
            } footer: {
                Text("These calls are what System Settings uses. They run in a separate helper, are checked before each use, and are read back after. Any macOS update can turn them off until Scene is updated.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Status") {
                ForEach(["appearance", "accent", "iconStyle"], id: \.self) { id in
                    LabeledContent {
                        switch model.tweaks.availability(id) {
                        case .available: Label("Available", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .disabled(let reason): Text(reason).foregroundStyle(.secondary)
                        }
                    } label: {
                        Label { Text(label(id)) } icon: { AppIcon(id: id, size: 20) }
                    }
                }
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
            Button { recording ? stop() : start() } label: {
                HStack(spacing: 3) {
                    if recording { Text("Type a shortcut…").foregroundStyle(.secondary) }
                    else if let current { ForEach(current.keys, id: \.self) { Keycap(key: $0) } }
                    else { Text("Off").foregroundStyle(.secondary) }
                }
                .padding(3)
                .frame(minWidth: 96, minHeight: 28)
                .background(.primary.opacity(recording ? 0.1 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(recording ? Color.accentColor : .clear, lineWidth: 1.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recording ? "Press the new keys. Esc cancels." : "Click, then press the new keys")
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

/// The menu bar panel: the current theme, every theme to apply in one click, and the usual commands.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            current
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(model.themes) { theme in tile(theme) }
                }
                .padding(4)
            }
            .frame(height: 262)
            Divider()
            VStack(spacing: 0) {
                row("Switch Theme…", model.switcherShortcut) { ThemeSwitcher.shared.show() }
                row("Next Background", model.nextBackgroundShortcut) { Task { await model.nextBackground() } }
                    .disabled(model.history.isEmpty)
                row("Undo Last Theme", nil) { Task { await model.undo() } }
                    .disabled(model.history.isEmpty)
            }
            Divider()
            VStack(spacing: 0) {
                row("Open Scene", nil) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                row("Settings…", nil) {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                row("Quit Scene", nil) { NSApp.terminate(nil) }
            }
        }
        .padding(12)
        .frame(width: 340)
    }

    @ViewBuilder
    var current: some View {
        ZStack(alignment: .bottomLeading) {
            if let entry = model.history.last { HistoryThumbnail(entry: entry) } else { Rectangle().fill(.quaternary) }
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.history.isEmpty ? "No theme yet" : "Current theme").font(.caption).opacity(0.8)
                    Text(model.history.last?.themeName ?? "Pick one below").font(.title3.weight(.semibold))
                }
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small).environment(\.colorScheme, .dark) }
            }
            .foregroundStyle(.white)
            .padding(12)
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    func tile(_ theme: Theme) -> some View {
        let variant = model.variant(for: theme)
        let isCurrent = theme.id == model.currentThemeID
        return Button { Task { await model.quickApply(theme) } } label: {
            VStack(spacing: 5) {
                WallpaperView(variant: variant, url: model.wallpaper(for: variant)?.url, pixels: 240)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                    .padding(3)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2))
                Text(theme.manifest.name).font(.caption).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorking)
        .help("Apply \(theme.manifest.name)")
    }

    func row(_ title: String, _ shortcut: HotKeySpec?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut.display).foregroundStyle(.secondary) }
            }
        }
        .buttonStyle(MenuRowStyle())
    }
}

/// A menu item look: the row lights up under the pointer.
struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Row(configuration: configuration) }

    struct Row: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let lit = hovering && isEnabled
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(lit ? Color.white : .primary)
                .background(lit ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
