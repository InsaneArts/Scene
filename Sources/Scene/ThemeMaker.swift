import AppKit
import SceneThemes
import SwiftUI
import UniformTypeIdentifiers

/// The Theme Maker: a large live preview of the look on its wallpaper, and a few sliders beside it for the background,
/// the text's contrast, the accent, and the code colors. Every move rebuilds the whole palette by the rules Scene's own
/// themes were made with, and keeps it readable. Colors can also come from the wallpaper, from Shuffle, or be set by hand
/// on the palette strip. Save adds the theme to Scene; Export writes its folder, ready for GitHub.
struct ThemeMakerView: View {
    @Environment(AppModel.self) private var model
    @State private var editing = Appearance.dark
    /// The wallpaper in the preview, by slot.
    @State private var shown = 0
    @State private var issues: [ThemeDraft.Issue] = []
    @State private var history: [Snapshot] = []
    @State private var extracting = false
    /// Vivid colors of the last wallpaper colors came from, offered as accents.
    @State private var accents: [OKLCH] = []
    @State private var working = false
    @State private var status: Status?
    @State private var showingIssues = false

    struct Snapshot {
        var draft: ThemeDraft
        var edits: [Appearance: PaletteEdit]
    }

    enum Status: Equatable {
        case saved(String), exported(URL), failed(String)
    }

    var body: some View {
        if let draft = model.draft {
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    stage(draft)
                    Divider()
                    ScrollView { controls(draft).padding(20) }
                        .frame(width: 330)
                }
                Divider()
                footer
            }
            .task(id: draft) { await check(draft) }
            .onAppear { if draft.look(editing) == nil { editing = draft.dark == nil ? .light : .dark } }
        } else {
            ContentUnavailableView {
                Label("No Theme Open", systemImage: "paintpalette")
            } description: {
                Text("Start from a theme, change what you like, then save it or share it.")
            } actions: {
                if let theme = model.selectedTheme ?? model.themes.first {
                    Button("Start from \(theme.manifest.name)") { model.startDraft(from: theme) }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Theme name", text: field(\.name)).font(.title2.weight(.bold)).textFieldStyle(.plain)
                TextField("One line about how it looks", text: field(\.summary)).textFieldStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker("Look", selection: $editing) {
                Label("Dark", systemImage: "moon.fill").tag(Appearance.dark)
                Label("Light", systemImage: "sun.max.fill").tag(Appearance.light)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .onChange(of: editing) { shown = 0; accents = [] }
            Button(action: undo) { Label("Undo", systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z").disabled(history.isEmpty).help("Undo the last change (⌘Z)")
            Button(action: shuffle) { Label("Shuffle", systemImage: "shuffle") }
                .disabled(model.draft?.look(editing) == nil).help("A new background and accent")
            Button(action: fromWallpaper) {
                Label("From Wallpaper", systemImage: extracting ? "hourglass" : "wand.and.stars")
            }
            .disabled(extracting || (model.draft?.look(editing)?.wallpapers.isEmpty ?? true))
            .help("Colors from the wallpaper in the preview")
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    // MARK: Preview

    private func stage(_ draft: ThemeDraft) -> some View {
        let look = draft.look(editing)
        let variant = look == nil ? nil : try? draft.preview(only: editing).variants[editing]
        let wallpapers = look?.wallpapers ?? []
        let wallpaper = wallpapers.isEmpty ? nil : URL(fileURLWithPath: wallpapers[min(shown, wallpapers.count - 1)].file)
        return VStack(spacing: 16) {
            if let look, let variant {
                DesktopPreview(variant: variant, wallpaper: wallpaper, showsSystem: true)
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .shadow(color: .black.opacity(0.35), radius: 26, y: 14)
                    .frame(maxWidth: .infinity)
                PaletteStrip(colors: look.colors, pinned: Set(model.draftEdits[editing]?.pinned.keys.map { $0 } ?? []),
                             onBegin: record, set: { key, hex in model.editLook(editing) { $0.pin(key, hex) } })
                WallpaperStrip(look: lookBinding, variant: variant, shown: $shown, onChange: record)
            } else {
                Spacer()
                Image(systemName: editing == .dark ? "moon.stars" : "sun.max").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("This theme has no \(editing == .dark ? "dark" : "light") look yet.").font(.title3)
                Button("Add a \(editing == .dark ? "Dark" : "Light") Look") { record(); model.setLook(editing, on: true) }
                    .controlSize(.large)
                Spacer()
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { if let variant { AmbientBackground(variant: variant, url: wallpaper) } }
        .environment(\.colorScheme, editing == .dark ? .dark : .light)
    }

    // MARK: Sliders

    private func controls(_ draft: ThemeDraft) -> some View {
        let recipe = model.draftEdits[editing]?.recipe ?? .starting(editing)
        let range = PaletteRecipe.ranges(editing)
        let colors = draft.look(editing)?.colors ?? [:]
        let ratio = RGBA(hex: colors["foreground"] ?? "").flatMap { fg in RGBA(hex: colors["background"] ?? "").map { fg.contrast(with: $0) } }
        return VStack(alignment: .leading, spacing: 24) {
            if draft.look(editing) != nil {
                group("Background") {
                    ColorSlider(title: "Hue", value: slider(\.ground.h), range: 0...360, onBegin: record) { OKLCH(0.62, 0.1, $0).rgba.color }
                    ColorSlider(title: "Tint", value: slider(\.ground.c), range: range.groundChroma, onBegin: record) {
                        OKLCH(0.55, $0 * 2, recipe.ground.h).rgba.color
                    }
                    ColorSlider(title: "Lightness", value: slider(\.ground.l), range: range.groundLightness, onBegin: record) {
                        OKLCH($0, recipe.ground.c, recipe.ground.h).rgba.color
                    }
                }
                group("Text") {
                    ColorSlider(title: "Contrast", value: slider(\.text), range: range.text, onBegin: record,
                                readout: ratio.map { String(format: "%.1f : 1", $0) }) { OKLCH($0, 0.02, recipe.ground.h).rgba.color }
                }
                group("Accent") {
                    ColorSlider(title: "Hue", value: slider(\.accent.h), range: 0...360, onBegin: record) {
                        OKLCH(recipe.accent.l, recipe.accent.c, $0).rgba.color
                    }
                    ColorSlider(title: "Vividness", value: slider(\.accent.c), range: range.accentChroma, onBegin: record) {
                        OKLCH(recipe.accent.l, $0, recipe.accent.h).rgba.color
                    }
                    ColorSlider(title: "Lightness", value: slider(\.accent.l), range: range.accentLightness, onBegin: record) {
                        OKLCH($0, recipe.accent.c, recipe.accent.h).rgba.color
                    }
                    if !accents.isEmpty {
                        HStack(spacing: 8) {
                            Text("From the wallpaper").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(accents.enumerated()), id: \.offset) { _, color in
                                Button { record(); model.editLook(editing) { $0.slide { $0.accent = color } } } label: {
                                    Circle().fill(color.rgba.color).frame(width: 18, height: 18)
                                        .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                                }
                                .buttonStyle(.plain).help("Use this color as the accent")
                            }
                        }
                    }
                }
                group("Code colors") {
                    ColorSlider(title: "Vividness", value: slider(\.chroma), range: range.chroma, onBegin: record) {
                        OKLCH(recipe.level, $0, 255 + recipe.shift).rgba.color
                    }
                    ColorSlider(title: "Brightness", value: slider(\.level), range: range.level, onBegin: record) {
                        OKLCH($0, recipe.chroma, 145 + recipe.shift).rgba.color
                    }
                    ColorSlider(title: "Hue shift", value: slider(\.shift), range: range.shift, onBegin: record) {
                        OKLCH(recipe.level, recipe.chroma, 27 + $0).rgba.color
                    }
                }
                group("macOS") { macOSLook }
            }
            group("Details") {
                TextField("Author", text: field(\.author))
                if draft.dark != nil && draft.light != nil {
                    Button("Remove the \(editing == .dark ? "Dark" : "Light") Look", role: .destructive) {
                        record()
                        model.setLook(editing, on: false)
                        editing = editing == .dark ? .light : .dark
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
    }

    private var macOSLook: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Accent color", selection: lookField(\.accentColor)) {
                Text("Nearest to the accent").tag("auto")
                ForEach(Self.presets, id: \.self) { Text($0.capitalized).tag($0) }
            }
            Picker("Icons", selection: lookField(\.iconStyle)) {
                ForEach(IconStyle.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0.rawValue) }
            }
            if model.draft?.look(editing)?.iconStyle == IconStyle.tinted.rawValue {
                Picker("Tint", selection: tint) {
                    Text("Accent").tag("accent")
                    ForEach(Self.presets.filter { $0 != "multicolor" }, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            Text("The preview shows them in the open File menu and the Dock. On your Mac they need Scene's experimental setting.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    static let presets = ["multicolor", "graphite", "red", "orange", "yellow", "green", "blue", "purple", "pink"]

    // MARK: Footer

    private var footer: some View {
        let errors = issues.filter(\.isError), warnings = issues.filter { !$0.isError }
        return HStack(spacing: 12) {
            Button { showingIssues = true } label: {
                if errors.isEmpty {
                    Label(warnings.isEmpty ? "Ready to save and share" : "Ready · \(warnings.count) to look at", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(errors.count) to finish", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingIssues) { issueList(errors + warnings).padding(16).frame(width: 420) }
            statusLine
            Spacer()
            Menu("Start From") {
                ForEach(model.orderedThemes) { theme in
                    Button(theme.manifest.name) { record(); model.startDraft(from: theme); status = nil; accents = [] }
                }
            }
            .fixedSize()
            if working { ProgressView().controlSize(.small) }
            Button("Export Folder…", action: export).disabled(working || !errors.isEmpty)
            Button("Save to Scene", action: save).keyboardShortcut(.defaultAction).disabled(working || !errors.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func issueList(_ list: [ThemeDraft.Issue]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if list.isEmpty { Text("Nothing to fix.").foregroundStyle(.secondary) }
            ForEach(list, id: \.self) { issue in
                Label(issue.message, systemImage: issue.isError ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(issue.isError ? Color.red : Color.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .saved(let name)?:
            Text("Saved \(name) to your themes.").foregroundStyle(.secondary)
        case .exported(let folder)?:
            HStack(spacing: 6) {
                Text("Exported \(folder.lastPathComponent). Put it on GitHub to share it.").foregroundStyle(.secondary)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.buttonStyle(.link)
            }
        case .failed(let reason)?:
            Text(reason).foregroundStyle(.red).lineLimit(2)
        case nil:
            EmptyView()
        }
    }

    // MARK: Bindings

    private func field(_ path: WritableKeyPath<ThemeDraft, String>) -> Binding<String> {
        Binding(get: { model.draft?[keyPath: path] ?? "" }, set: { model.draft?[keyPath: path] = $0 })
    }

    private var lookBinding: Binding<ThemeDraft.Look> {
        Binding(get: { model.draft?.look(editing) ?? ThemeDraft.Look(colors: [:]) },
                set: { model.draft?.setLook($0, for: editing) })
    }

    private func lookField(_ path: WritableKeyPath<ThemeDraft.Look, String>) -> Binding<String> {
        Binding(get: { model.draft?.look(editing)?[keyPath: path] ?? "" }, set: { value in
            record()
            lookBinding.wrappedValue[keyPath: path] = value
        })
    }

    private var tint: Binding<String> {
        Binding(get: { model.draft?.look(editing)?.iconTint ?? "accent" }, set: { lookBinding.wrappedValue.iconTint = $0 })
    }

    /// A recipe value the sliders move. Moving one rebuilds the look's palette.
    private func slider(_ path: WritableKeyPath<PaletteRecipe, Double>) -> Binding<Double> {
        Binding(get: { model.draftEdits[editing]?.recipe[keyPath: path] ?? 0 },
                set: { value in model.editLook(editing) { $0.slide { $0[keyPath: path] = value } } })
    }

    // MARK: Actions

    private func record() {
        guard let draft = model.draft else { return }
        history.append(Snapshot(draft: draft, edits: model.draftEdits))
        if history.count > 80 { history.removeFirst() }
    }

    private func undo() {
        guard let last = history.popLast() else { return }
        model.draft = last.draft
        model.draftEdits = last.edits
    }

    /// A new background and accent, kept calm: a slightly tinted ground and a vivid accent.
    private func shuffle() {
        record()
        let dark = editing == .dark
        model.editLook(editing) { edit in
            var recipe = edit.recipe
            recipe.ground = OKLCH(dark ? .random(in: 0.15...0.24) : .random(in: 0.95...0.985), .random(in: 0.005...0.04), .random(in: 0..<360))
            recipe.accent = OKLCH(recipe.accent.l, .random(in: 0.11...0.19), .random(in: 0..<360))
            recipe.shift = .random(in: -12...12)
            recipe.hues = [:]
            edit.replace(with: recipe)
        }
        accents = []
    }

    private func fromWallpaper() {
        guard let wallpapers = model.draft?.look(editing)?.wallpapers, !wallpapers.isEmpty else { return }
        let url = URL(fileURLWithPath: wallpapers[min(shown, wallpapers.count - 1)].file)
        let appearance = editing
        extracting = true
        Task {
            let result = await Task.detached { PaletteExtraction.palette(from: [url], appearance: appearance) }.value
            extracting = false
            guard let result else { status = .failed("Scene could not read colors from this wallpaper."); return }
            record()
            model.editLook(appearance) { $0.replace(with: result.recipe) }
            accents = result.accents
        }
    }

    private func check(_ draft: ThemeDraft) async {
        // Checking reads every wallpaper, so it waits until the sliders rest and runs off the main thread.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let found = await Task.detached { draft.check() }.value
        guard !Task.isCancelled else { return }
        issues = found
    }

    private func save() {
        working = true
        Task {
            let name = model.draft?.name ?? ""
            if let reason = await model.saveDraft() { status = .failed(reason) } else { status = .saved(name) }
            working = false
        }
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Scene makes a folder for the theme here."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do { status = .exported(try model.exportDraft(to: parent)) } catch { status = .failed("\(error)") }
    }
}

// MARK: - Slider

/// A slider whose track shows what it changes: the colors along its range.
private struct ColorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onBegin: () -> Void = {}
    var readout: String?
    /// The color at a value on the track.
    let color: (Double) -> Color
    @State private var dragging = false

    var body: some View {
        let span = range.upperBound - range.lowerBound
        let fraction = min(max((value - range.lowerBound) / span, 0), 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                if let readout { Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            GeometryReader { geo in
                let knob: CGFloat = 20
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: (0...16).map { color(range.lowerBound + span * Double($0) / 16) },
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .frame(height: 10)
                    Circle().fill(color(value))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .frame(width: knob, height: knob)
                        .offset(x: fraction * (geo.size.width - knob))
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !dragging { dragging = true; onBegin() }
                        let position = min(max((drag.location.x - knob / 2) / max(geo.size.width - knob, 1), 0), 1)
                        value = range.lowerBound + span * position
                    }
                    .onEnded { _ in dragging = false })
            }
            .frame(height: 20)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(readout ?? "\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            onBegin()
            let step = span / 20
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }
}

// MARK: - Palette strip

/// The look's colors in a row. Click one to set it by hand; the pin marks colors the sliders no longer move.
private struct PaletteStrip: View {
    let colors: [String: String]
    let pinned: Set<String>
    let onBegin: () -> Void
    let set: (String, String?) -> Void
    @State private var editing: String?

    static let keys = ["background", "dark_background", "lighter_background", "selection", "muted", "dark_foreground", "foreground",
                       "accent", "red", "orange", "yellow", "green", "cyan", "blue", "magenta"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.keys, id: \.self) { key in
                let color = RGBA(hex: colors[key] ?? "")?.color ?? .clear
                Button { onBegin(); editing = key } label: {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color)
                        .frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                        .overlay(alignment: .topTrailing) {
                            if pinned.contains(key) {
                                Image(systemName: "pin.fill").font(.system(size: 8)).padding(3)
                                    .foregroundStyle(.white).shadow(radius: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("\(ThemeDraft.labels[key] ?? key) \(colors[key] ?? "")")
                .popover(isPresented: Binding(get: { editing == key }, set: { if !$0 { editing = nil } })) {
                    editor(key).padding(14).frame(width: 240)
                }
            }
        }
    }

    private func editor(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ThemeDraft.labels[key] ?? key).font(.headline)
            HStack {
                ColorPicker("Color", selection: Binding(get: { RGBA(hex: colors[key] ?? "")?.color ?? .gray },
                                                         set: { if let rgba = RGBA(color: $0) { set(key, rgba.hex) } }),
                            supportsOpacity: false)
                    .labelsHidden()
                Text(colors[key] ?? "").font(.body.monospaced()).textSelection(.enabled)
            }
            if pinned.contains(key) {
                Button("Let the Sliders Set It") { set(key, nil) }
            } else {
                Text("A color set by hand stays when the sliders move.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Wallpapers

/// A look's three wallpapers. Click one to see it in the preview; drop or choose an image to add or replace one.
private struct WallpaperStrip: View {
    @Binding var look: ThemeDraft.Look
    let variant: ResolvedVariant
    @Binding var shown: Int
    let onChange: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<ThemeDraft.wallpapersPerLook, id: \.self) { index in slot(index) }
        }
    }

    private func slot(_ index: Int) -> some View {
        let wallpaper = look.wallpapers.indices.contains(index) ? look.wallpapers[index] : nil
        let selected = wallpaper != nil && index == min(shown, look.wallpapers.count - 1)
        return VStack(spacing: 5) {
            Button { if wallpaper == nil { choose(index) } else { shown = index } } label: {
                ZStack {
                    if let wallpaper {
                        WallpaperView(variant: variant, url: URL(fileURLWithPath: wallpaper.file), pixels: 360)
                    } else {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.background.opacity(0.4))
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                            .foregroundStyle(.secondary)
                        Label("Add wallpaper", systemImage: "plus").font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? variant.interface.accent.color : .clear, lineWidth: 2.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(wallpaper == nil ? "Choose an image, or drop one here" : "Show it in the preview")
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                set(url, at: index)
                return true
            }
            .contextMenu {
                if wallpaper != nil {
                    Button("Replace…") { choose(index) }
                    Button("Remove", role: .destructive) { onChange(); look.wallpapers.remove(at: index); shown = 0 }
                }
            }
            Text(index == 0 ? "Default" : "Wallpaper \(index + 1)").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func choose(_ index: Int) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.message = "Choose a wallpaper, at least 1024 pixels wide."
        if panel.runModal() == .OK, let url = panel.url { set(url, at: index) }
    }

    /// A new image starts with empty credits: the old credits belonged to the old image.
    private func set(_ url: URL, at index: Int) {
        onChange()
        if look.wallpapers.indices.contains(index) {
            look.wallpapers[index] = ThemeDraft.Wallpaper(file: url.path)
            shown = index
        } else {
            look.wallpapers.append(ThemeDraft.Wallpaper(file: url.path))
            shown = look.wallpapers.count - 1
        }
    }
}

extension RGBA {
    /// The sRGB value of a color from a color picker.
    init?(color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> UInt8 { UInt8((max(0, min(1, value)) * 255).rounded()) }
        self.init(r: byte(c.redComponent), g: byte(c.greenComponent), b: byte(c.blueComponent))
    }
}
