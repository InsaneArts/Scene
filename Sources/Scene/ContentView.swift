import SceneEngine
import SceneThemes
import SwiftUI
import UniformTypeIdentifiers

/// What the detail column shows.
enum Page: Hashable {
    case theme(Theme.ID)
    case apps, history
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Apps or History. Nil shows the selected theme.
    @State private var page: Page?
    @State private var applying: Theme?
    @State private var importing = false
    @State private var columns = NavigationSplitViewVisibility.all
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(selection: selection, applying: $applying)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            Group {
                switch selection.wrappedValue {
                case .apps: AppsView()
                case .history: HistoryView()
                default:
                    if let theme = model.selectedTheme { ThemePage(theme: theme, applying: $applying) }
                    else { ContentUnavailableView("No Themes", systemImage: "paintpalette", description: Text("Import a theme to begin.")) }
                }
            }
            .safeAreaInset(edge: .top) { if let run = model.unfinished.first { InterruptedBanner(run: run) } }
            .toolbar {
                // Without a window title, the buttons would sit next to the sidebar.
                if #available(macOS 26, *) { ToolbarSpacer(.flexible) }
                ToolbarItemGroup {
                    Button { ThemeSwitcher.shared.show() } label: { Label("Switch Theme", systemImage: "rectangle.on.rectangle.angled") }
                        .help("Show every theme over the screen" + model.switcherShortcut.menuSuffix)
                    Menu {
                        NewThemeButton()
                        Divider()
                        Button("Import File or Folder…") { importing = true }
                        Button("Install from GitHub…") { model.installingFromGitHub = true }
                    } label: { Label("Add Theme", systemImage: "square.and.arrow.down") }
                        .help("Import a .scenetheme file, a theme folder, or an Omarchy theme folder, or install a theme from GitHub")
                    Button { Task { await model.undo() } } label: { Label("Undo Theme", systemImage: "arrow.uturn.backward") }
                        .disabled(model.history.isEmpty || model.isWorking)
                        .help("Go back to the previous theme")
                    SettingsLink { Label("Settings", systemImage: "gearshape") }
                        .help("Shortcuts and other settings")
                }
            }
        }
        .sheet(item: $applying) { theme in ApplySheet(theme: theme) }
        .sheet(isPresented: Binding(get: { model.installingFromGitHub }, set: { model.installingFromGitHub = $0 })) { GitHubInstallSheet() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, UTType(filenameExtension: "scenetheme") ?? .zip, .zip]) { result in
            if case .success(let url) = result { Task { await model.importTheme(from: url) } }
        }
        .overlay { if model.isWorking, applying == nil { WorkingHUD(message: model.progress) } }
        .alert("Scene", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert ?? "") }
        .task {
            await model.reload()
            await Snapshot.run(model: model, applying: $applying, page: $page, openSettings: { openSettings() })
        }
        .onOpenURL { url in Task { await model.importTheme(from: url) } }
        // An imported theme opens on its page, even from Apps or History.
        .onChange(of: model.selectedThemeID) { page = nil }
    }

    /// The sidebar selection: a theme, Apps, or History.
    private var selection: Binding<Page?> {
        Binding(get: { page ?? model.selectedThemeID.map(Page.theme) },
                set: { new in
                    if case .theme(let id)? = new { page = nil; model.selectedThemeID = id } else if let new { page = new }
                })
    }
}

/// A spinner over the window while Scene applies, undoes, or restores outside the Apply sheet.
struct WorkingHUD: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.08).ignoresSafeArea()
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(message.isEmpty ? "Working…" : message).font(.callout)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glass(in: Capsule())
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    let selection: Binding<Page?>
    @Binding var applying: Theme?

    var body: some View {
        @Bindable var model = model
        // Apps that need setup, or that changed outside Scene.
        let attention = model.detections.filter { $0.value.installed && ($0.value.setup != .ready || model.changedOutside[$0.key] != nil) }.count
        let matching = model.themes.filter { ThemeSearch.matches($0, model.searchText) }
        let favorites = matching.filter { model.favoriteThemes.contains($0.id) }
        List(selection: selection) {
            Section {
                Label("Apps", systemImage: "square.grid.2x2").badge(attention).tag(Page.apps)
                Label("History", systemImage: "clock.arrow.circlepath").tag(Page.history)
            }
            if !favorites.isEmpty {
                Section("Favorites") {
                    ForEach(favorites) { theme in ThemeRow(theme: theme).tag(Page.theme(theme.id)) }
                }
            }
            Section("Themes") {
                ForEach(matching.filter { !model.favoriteThemes.contains($0.id) }) { theme in
                    ThemeRow(theme: theme).tag(Page.theme(theme.id))
                }
                if matching.isEmpty { Text("No themes match “\(model.searchText)”").foregroundStyle(.secondary) }
                if !model.problems.isEmpty { ProblemsRow(problems: model.problems) }
            }
        }
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search themes")
        // Double-click or ↩ on a theme opens its plan.
        .contextMenu(forSelectionType: Page.self) { pages in
            if case .theme(let id)? = pages.first, let theme = model.themes.first(where: { $0.id == id }) {
                ThemeActions(theme: theme, applying: $applying)
            }
        } primaryAction: { pages in
            if case .theme(let id)? = pages.first { applying = model.themes.first { $0.id == id } }
        }
    }
}

struct ThemeRow: View {
    @Environment(AppModel.self) private var model
    let theme: Theme

    var body: some View {
        let variant = model.variant(for: theme)
        HStack(spacing: 10) {
            WallpaperView(variant: variant, url: model.wallpaper(for: variant)?.url, pixels: 240)
                .frame(width: 52, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 5) {
                Text(theme.manifest.name).lineLimit(1)
                PaletteDots(colors: variant.hues, size: 7)
            }
            Spacer(minLength: 0)
            if theme.id == model.currentThemeID {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    .help("The current theme").accessibilityLabel("Current theme")
            }
        }
        .padding(.vertical, 3)
    }
}

struct ThemeActions: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let theme: Theme
    @Binding var applying: Theme?

    var body: some View {
        Button("Apply…") { applying = theme }
        Button("Open in Theme Maker") { model.startDraft(from: theme); openWindow(id: "maker") }
        Button(model.favoriteThemes.contains(theme.id) ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite(theme) }
        Button("Export…") { export() }
        if let source = model.themeSources[theme.id], let url = URL(string: source) {
            Divider()
            Button("Update from GitHub") { Task { await model.updateFromGitHub(theme) } }
            Link("Open on GitHub", destination: url)
        }
        if !theme.isBundled {
            Divider()
            Button("Remove", role: .destructive) { Task { await model.remove(theme) } }
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(theme.manifest.name).scenetheme"
        panel.allowedContentTypes = [UTType(filenameExtension: "scenetheme") ?? .zip]
        if panel.runModal() == .OK, let url = panel.url { model.export(theme, to: url) }
    }
}

struct ProblemsRow: View {
    let problems: [ThemeLibrary.Problem]
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Label("\(problems.count) could not be loaded", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(problems) { problem in
                    Text(problem.folder).font(.callout.weight(.semibold))
                    Text(problem.errors.prefix(3).joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 360, alignment: .leading)
        }
    }
}

// MARK: - Theme page

/// A theme on its own wallpaper, in its own light or dark look.
struct ThemePage: View {
    @Environment(AppModel.self) private var model
    let theme: Theme
    @Binding var applying: Theme?

    var body: some View {
        let variant = model.variant(for: theme)
        let wallpaper = model.wallpaper(for: variant)
        GeometryReader { viewport in
            ScrollView {
                VStack(spacing: 22) {
                    // At most 60% of the window's height, so the name and Apply stay in view.
                    DesktopPreview(variant: variant, wallpaper: wallpaper?.url)
                        .frame(maxHeight: viewport.size.height * 0.6)
                        .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
                    if variant.wallpapers.count > 1 { BackgroundPicker(variant: variant) }
                    header(variant)
                    Divider()
                    ThemeCredits(theme: theme, variant: variant, wallpaper: wallpaper)
                }
                .padding(.horizontal, 36)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 1040)
                .frame(maxWidth: .infinity)
            }
        }
        .background { AmbientBackground(variant: variant, url: wallpaper?.url) }
        .environment(\.colorScheme, variant.colorScheme)
    }

    func header(_ variant: ResolvedVariant) -> some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(theme.manifest.name).font(.system(size: 32, weight: .bold))
                    let favorite = model.favoriteThemes.contains(theme.id)
                    Button { model.toggleFavorite(theme) } label: {
                        Image(systemName: favorite ? "star.fill" : "star").font(.title2)
                            .foregroundStyle(favorite ? variant.interface.accent.color : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(favorite ? "Remove from Favorites" : "Add to Favorites")
                    .accessibilityLabel(favorite ? "Remove from Favorites" : "Add to Favorites")
                    if theme.id == model.currentThemeID { Pill(text: "Current", color: variant.interface.accent.color) }
                }
                if let summary = theme.manifest.summary { Text(summary).font(.title3).foregroundStyle(.secondary) }
                PaletteDots(colors: variant.hues, size: 14).padding(.top, 6)
            }
            Spacer(minLength: 12)
            if theme.availableAppearances.count > 1 {
                Picker("Look", selection: Binding(get: { variant.appearance }, set: { model.previewAppearance[theme.id] = $0 })) {
                    Label("Dark", systemImage: "moon.fill").tag(Appearance.dark)
                    Label("Light", systemImage: "sun.max.fill").tag(Appearance.light)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.large).fixedSize()
            } else {
                Label(variant.appearance == .dark ? "Dark only" : "Light only", systemImage: variant.appearance == .dark ? "moon.fill" : "sun.max.fill")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Apply…") { applying = theme }
                .buttonStyle(CapsuleButtonStyle(fill: variant.interface.accent.color, label: variant.onAccent))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// A variant's wallpapers. The picked one is what Apply, the switcher, and Next Background start from.
struct BackgroundPicker: View {
    @Environment(AppModel.self) private var model
    let variant: ResolvedVariant

    var body: some View {
        let picked = model.wallpaper(for: variant)
        HStack(spacing: 12) {
            ForEach(Array(variant.wallpapers.enumerated()), id: \.element) { index, wallpaper in
                let isPicked = wallpaper == picked
                Button { model.choose(wallpaper, for: variant) } label: {
                    WallpaperView(variant: variant, url: wallpaper.url, pixels: 480)
                        .frame(width: 112, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .padding(5)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isPicked ? variant.interface.accent.color : .clear, lineWidth: 2.5))
                }
                .buttonStyle(.plain)
                .help(wallpaper.name)
                .accessibilityLabel("Background \(index + 1) of \(variant.wallpapers.count)")
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
        .animation(.snappy(duration: 0.2), value: picked)
    }
}

/// Who made the theme and its wallpaper, and what it changes in macOS.
struct ThemeCredits: View {
    @Environment(AppModel.self) private var model
    let theme: Theme
    let variant: ResolvedVariant
    let wallpaper: Wallpaper?

    var body: some View {
        let m = theme.manifest
        let asset = m.assets?.first { $0.file == "wallpapers/\(wallpaper?.name ?? "")" }
        VStack(alignment: .leading, spacing: 8) {
            Label("By \(m.authors.map(\.name).joined(separator: ", ")) · Version \(m.version)" + (theme.isBundled ? "" : " · Installed"),
                  systemImage: "person.2")
            if let source = model.themeSources[theme.id], let url = URL(string: source) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("From \(url.host() ?? "")\(url.path())", systemImage: "arrow.down.circle")
                    Link("Open", destination: url)
                    Button("Update") { Task { await model.updateFromGitHub(theme) } }.buttonStyle(.link).disabled(model.isWorking)
                }
            }
            if let accent = variant.system.accent {
                Label("macOS: \(accent.name.capitalized) accent" + (variant.system.iconStyle.map { ", \($0.rawValue) icons" } ?? "") + " (experimental)",
                      systemImage: "macwindow")
            }
            if let asset {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Wallpaper: \(asset.attribution ?? asset.file)", systemImage: "photo").lineLimit(2)
                    if let source = asset.source, let url = URL(string: source) { Link("Source", destination: url) }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InterruptedBanner: View {
    @Environment(AppModel.self) private var model
    let run: JournalRun

    var body: some View {
        let apps = Set(run.steps.filter { $0.state == "applied" }.map(\.integration))
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("Scene stopped while applying \(run.themeName).").font(.headline)
                Text("\(apps.count) app\(apps.count == 1 ? "" : "s") changed before it stopped.").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Keep As Is") { Task { await model.dismissUnfinished(run) } }
            Button("Restore These Apps") { Task { await model.restoreOriginal(only: apps); await model.dismissUnfinished(run) } }
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .glass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}

// MARK: - Install from GitHub

/// Installs a theme from a GitHub repository: an Omarchy theme or a Scene theme.
struct GitHubInstallSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install from GitHub").font(.title2.weight(.semibold))
            Text("Paste the address of an Omarchy theme or a Scene theme. Scene reads only its colors and images, and never runs code from it.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://github.com/owner/theme", text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(install)
                .disabled(working)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Link("Browse Omarchy's community themes", destination: URL(string: "https://omarchy.org/themes/")!)
                    .font(.callout)
                Spacer()
                if working { ProgressView().controlSize(.small).padding(.trailing, 6) }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Install") { install() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || GitHubRepository(text) == nil)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    func install() {
        guard !working, GitHubRepository(text) != nil else { return }
        working = true
        error = nil
        Task {
            error = await model.installFromGitHub(text)
            working = false
            if error == nil { dismiss() }
        }
    }
}

/// Opens the Theme Maker, starting from the theme on screen.
struct NewThemeButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Theme…") {
            if let theme = model.selectedTheme ?? model.themes.first { model.startDraft(from: theme) }
            openWindow(id: "maker")
        }
    }
}
