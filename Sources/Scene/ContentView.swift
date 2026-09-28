import SceneEngine
import SceneThemes
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, Hashable, CaseIterable {
    case themes, apps, history

    var title: String {
        switch self {
        case .themes: "Themes"
        case .apps: "Apps"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .themes: "paintpalette"
        case .apps: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebar: SidebarItem = .themes
    @State private var applying: Theme?
    @State private var importing = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $sidebar) { item in
                Label(item.title, systemImage: item.symbol)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch sidebar {
            case .themes: ThemesView(applying: $applying)
            case .apps: AppsView()
            case .history: HistoryView()
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { importing = true } label: { Label("Import Theme", systemImage: "square.and.arrow.down") }
                    .help("Import a .scenetheme file, a theme folder, or an Omarchy theme folder")
                Button { Task { await model.undo() } } label: { Label("Undo Theme", systemImage: "arrow.uturn.backward") }
                    .disabled(model.history.isEmpty || model.isWorking)
                    .help("Go back to the previous theme")
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .help("Shortcuts, apps, and other settings")
            }
        }
        .sheet(item: $applying) { theme in ApplySheet(theme: theme) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder, UTType(filenameExtension: "scenetheme") ?? .zip, .zip]) { result in
            if case .success(let url) = result { Task { await model.importTheme(from: url) } }
        }
        .overlay { if model.isWorking { WorkingOverlay(message: model.progress) } }
        .alert("Scene", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("OK") { model.alert = nil }
        } message: { Text(model.alert ?? "") }
        .task {
            await model.reload()
            await Snapshot.run(model: model, applying: $applying, sidebar: $sidebar, openSettings: { openSettings() })
        }
        .onOpenURL { url in Task { await model.importTheme(from: url) } }
    }
}

struct WorkingOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.15).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(message.isEmpty ? "Working…" : message).font(.callout).foregroundStyle(.secondary)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Themes

struct ThemesView: View {
    @Environment(AppModel.self) private var model
    @Binding var applying: Theme?

    var body: some View {
        @Bindable var model = model
        HSplitView {
            ScrollView {
                if let run = model.unfinished.first { InterruptedBanner(run: run) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)], spacing: 22) {
                    ForEach(model.themes) { theme in
                        ThemeCard(theme: theme, isSelected: theme.id == model.selectedThemeID, isCurrent: theme.id == model.currentThemeID)
                            .onTapGesture { model.selectedThemeID = theme.id }
                            .onTapGesture(count: 2) { applying = theme }
                            .contextMenu { ThemeActions(theme: theme, applying: $applying) }
                    }
                }
                .padding(20)
                if !model.problems.isEmpty { ProblemsList(problems: model.problems).padding(.horizontal, 20) }
            }
            .frame(minWidth: 280)
            Group {
                if let theme = model.selectedTheme { ThemeDetailView(theme: theme, applying: $applying) }
                else { ContentUnavailableView("No Theme Selected", systemImage: "paintpalette") }
            }
            .frame(minWidth: 460, idealWidth: 560)
        }
        .navigationTitle("Themes")
    }
}

struct ThemeCard: View {
    @Environment(AppModel.self) private var model
    let theme: Theme
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        let appearance = model.appearance(for: theme)
        VStack(alignment: .leading, spacing: 8) {
            if let variant = theme.variants[appearance] {
                DesktopPreview(variant: variant, wallpaper: model.wallpaper(for: variant)?.url, compact: true)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(theme.manifest.name).font(.headline)
                if isCurrent { Text("Current").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 2).background(.tint.opacity(0.15), in: Capsule()) }
                Spacer()
                ForEach(theme.availableAppearances.reversed(), id: \.self) { a in
                    Image(systemName: a == .dark ? "moon.fill" : "sun.max.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let summary = theme.manifest.summary { Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
        .contentShape(Rectangle())
    }
}

struct ThemeActions: View {
    @Environment(AppModel.self) private var model
    let theme: Theme
    @Binding var applying: Theme?

    var body: some View {
        Button("Apply…") { applying = theme }
        Button("Export…") { export() }
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

struct ThemeDetailView: View {
    @Environment(AppModel.self) private var model
    let theme: Theme
    @Binding var applying: Theme?

    var body: some View {
        @Bindable var model = model
        let appearance = model.appearance(for: theme)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let variant = theme.variants[appearance] {
                    DesktopPreview(variant: variant, wallpaper: model.wallpaper(for: variant)?.url).shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                    if variant.wallpapers.count > 1 { BackgroundPicker(variant: variant) }
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(theme.manifest.name).font(.title.weight(.semibold))
                            if let summary = theme.manifest.summary { Text(summary).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if theme.availableAppearances.count > 1 {
                            Picker("Variant", selection: Binding(get: { appearance }, set: { model.previewAppearance[theme.id] = $0 })) {
                                Label("Light", systemImage: "sun.max").tag(Appearance.light)
                                Label("Dark", systemImage: "moon").tag(Appearance.dark)
                            }
                            .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                        }
                        Button { applying = theme } label: { Text("Apply…").frame(minWidth: 70) }
                            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    }
                    HStack(spacing: 12) {
                        TerminalPreview(variant: variant, fontSize: 11).frame(height: 190, alignment: .top).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        CodePreview(variant: variant, fontSize: 10.5).frame(height: 190, alignment: .top).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Text("Colors and the wallpaper are exact. App window layouts are approximate.").font(.caption).foregroundStyle(.secondary)
                    ThemeInfo(theme: theme, variant: variant, wallpaper: model.wallpaper(for: variant))
                }
            }
            .padding(22)
        }
    }
}

/// A variant's wallpapers. The picked one is what Apply, the switcher, and Next Background start from.
struct BackgroundPicker: View {
    @Environment(AppModel.self) private var model
    let variant: ResolvedVariant

    var body: some View {
        let picked = model.wallpaper(for: variant)
        HStack(spacing: 10) {
            ForEach(variant.wallpapers, id: \.self) { wallpaper in
                let isPicked = wallpaper == picked
                Button { model.choose(wallpaper, for: variant) } label: {
                    WallpaperView(variant: variant, url: wallpaper.url)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .frame(width: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(isPicked ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isPicked ? 2.5 : 1))
                }
                .buttonStyle(.plain)
                .help(wallpaper.name)
            }
        }
    }
}

struct ThemeInfo: View {
    let theme: Theme
    let variant: ResolvedVariant
    let wallpaper: Wallpaper?

    var body: some View {
        let m = theme.manifest
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow { Text("Palette").foregroundStyle(.secondary); PaletteStrip(variant: variant).frame(maxWidth: 220) }
            GridRow { Text("Authors").foregroundStyle(.secondary); Text(m.authors.map(\.name).joined(separator: ", ")) }
            GridRow { Text("License").foregroundStyle(.secondary); Text(m.license) }
            if let system = Optional(variant.system), let accent = system.accent {
                GridRow { Text("macOS").foregroundStyle(.secondary); Text("Accent \(accent.name)" + (system.iconStyle.map { ", \($0.rawValue) icons" } ?? "") + " (experimental)") }
            }
            ForEach((m.assets ?? []).filter { $0.file == "wallpapers/\(wallpaper?.name ?? "")" }, id: \.file) { asset in
                GridRow {
                    Text("Wallpaper").foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(asset.attribution ?? asset.file)
                        HStack {
                            Text("License: \(asset.license)")
                            if let source = asset.source, let url = URL(string: source) { Link("Source", destination: url) }
                        }.foregroundStyle(.secondary)
                    }
                }
            }
            GridRow { Text("Version").foregroundStyle(.secondary); Text("\(m.version)" + (theme.isBundled ? " · Bundled" : " · Installed")) }
        }
        .font(.callout)
    }
}

struct ProblemsList: View {
    let problems: [ThemeLibrary.Problem]
    var body: some View {
        GroupBox("Themes that could not be loaded") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(problems) { problem in
                    Text(problem.folder).font(.callout.weight(.semibold))
                    Text(problem.errors.prefix(3).joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct InterruptedBanner: View {
    @Environment(AppModel.self) private var model
    let run: JournalRun

    var body: some View {
        let applied = run.steps.filter { $0.state == "applied" }
        let apps = Set(applied.map(\.integration))
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow).font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text("Scene stopped while applying \(run.themeName).").font(.headline)
                Text("\(apps.count) app\(apps.count == 1 ? "" : "s") changed before it stopped.").foregroundStyle(.secondary)
                HStack {
                    Button("Restore These Apps") { Task { await model.restoreOriginal(only: apps); await model.dismissUnfinished(run) } }
                    Button("Keep As Is") { Task { await model.dismissUnfinished(run) } }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding([.horizontal, .top], 20)
    }
}
