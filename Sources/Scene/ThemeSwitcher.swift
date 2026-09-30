import AppKit
import Observation
import SceneEngine
import SceneSwitcher
import SceneThemes
import SwiftUI

/// State of one carousel session.
@MainActor @Observable
final class CarouselState {
    /// Every theme, favorites first. `themes` holds the ones that match the search.
    let allThemes: [Theme]
    private(set) var themes: [Theme]
    var selection: CarouselSelection
    /// What you typed. Each change selects the first match. Clearing it keeps the selected theme.
    var query = "" {
        didSet { if query != oldValue { refilter() } }
    }
    /// The theme shown before the search found nothing, so the backdrop stays.
    private(set) var lastShown: Theme
    var previewed: [Theme.ID: Appearance] = [:]
    let currentID: String?
    let systemIsDark: Bool
    /// The picked wallpaper of a variant.
    let wallpaper: (ResolvedVariant) -> URL?

    init(themes: [Theme], currentID: String?, systemIsDark: Bool, wallpaper: @escaping (ResolvedVariant) -> URL?) {
        allThemes = themes
        self.themes = themes
        self.currentID = currentID
        self.systemIsDark = systemIsDark
        self.wallpaper = wallpaper
        let index = themes.firstIndex { $0.id == currentID } ?? 0
        selection = CarouselSelection(count: themes.count, index: index)
        lastShown = themes[index]
    }

    var selected: Theme? { themes.indices.contains(selection.index) ? themes[selection.index] : nil }
    var backdrop: Theme { selected ?? lastShown }

    private func refilter() {
        if let selected { lastShown = selected }
        themes = allThemes.filter { ThemeSearch.matches($0, query) }
        selection = CarouselSelection(count: themes.count, index: query.isEmpty ? themes.firstIndex { $0.id == lastShown.id } ?? 0 : 0)
    }

    func appearance(_ theme: Theme) -> Appearance {
        if let chosen = previewed[theme.id] { return chosen }
        let system: Appearance = systemIsDark ? .dark : .light
        return theme.variants[system] != nil ? system : (theme.availableAppearances.first ?? .dark)
    }

    func toggleVariant() {
        guard let theme = selected, theme.availableAppearances.count == 2 else { return }
        previewed[theme.id] = appearance(theme) == .dark ? .light : .dark
    }

    /// What you see is what you get: a variant other than the system's switches macOS to it.
    func mode(for theme: Theme) -> AppearanceMode {
        guard theme.availableAppearances.count == 2 else { return .system }
        let system: Appearance = systemIsDark ? .dark : .light
        let shown = appearance(theme)
        return shown == system ? .system : (shown == .dark ? .dark : .light)
    }
}

/// The keyboard-driven theme carousel that appears over every screen, like Omarchy's theme menu.
@MainActor
final class ThemeSwitcher {
    static let shared = ThemeSwitcher()
    var model: AppModel?
    private(set) var panels: [SwitcherPanel] = []
    private var state: CarouselState?
    private var activeScreen: NSScreen?
    private var resignObserver: NSObjectProtocol?
    private var hud: NSPanel?
    private var hudTask: Task<Void, Never>?

    var isVisible: Bool { !panels.isEmpty }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard !isVisible, let model else { return }
        Task { @MainActor in
            if model.themes.isEmpty { await model.reload() }
            guard !model.themes.isEmpty, !isVisible else { return }
            present(model)
        }
    }

    private func present(_ model: AppModel) {
        let state = CarouselState(themes: model.orderedThemes, currentID: model.currentThemeID, systemIsDark: model.systemIsDark,
                                  wallpaper: { model.wallpaper(for: $0)?.url })
        self.state = state
        let mouse = NSEvent.mouseLocation
        let active = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        activeScreen = active
        for screen in NSScreen.screens {
            let panel = SwitcherPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.onKey = { [weak self] event in self?.handle(event) ?? false }
            if screen == active {
                panel.contentView = NSHostingView(rootView: ThemeCarouselView(state: state, onApply: { [weak self] in self?.applySelected() },
                                                                                onClose: { [weak self] in self?.hide() }))
            } else {
                panel.contentView = NSHostingView(rootView: SwitcherBackdrop(state: state, onClose: { [weak self] in self?.hide() }))
            }
            panel.setFrame(screen.frame, display: false)
            panel.orderFrontRegardless()
            if screen == active { panel.makeKey() }
            panels.append(panel)
        }
        // Switching to another app with ⌘Tab closes the carousel.
        if let key = panels.first(where: \.isKeyWindow) {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: key, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.panels.contains(where: \.isKeyWindow) else { return }
                    self.hide()
                }
            }
        }
    }

    func hide() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        state = nil
    }

    /// Keys: ← → move, ↑ ↓ or Tab switch Light/Dark, 1–9 jump, typing searches, ⌫ deletes, ↩ applies.
    /// Esc clears the search, then closes.
    func handle(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        let characters = event.characters ?? ""
        switch event.keyCode {
        case 123: state.selection.move(-1)
        case 124: state.selection.move(1)
        case 125, 126, 48: state.toggleVariant()
        case 36, 76: applySelected()
        case 53: if state.query.isEmpty { hide() } else { state.query = "" }
        case 51: if !state.query.isEmpty { state.query.removeLast() }
        case 115: state.selection.select(0)
        case 119: state.selection.select(state.themes.count - 1)
        default:
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
            if let text = SwitcherSearch.text(for: characters) {
                state.query += text
            } else if let number = Int(characters) {
                state.selection.jump(toNumber: number)
            } else {
                return false
            }
        }
        return true
    }

    func applySelected() {
        guard let state, let model, let theme = state.selected else { NSSound.beep(); return }
        let mode = state.mode(for: theme)
        let screen = activeScreen
        hide()
        showHUD(title: "Applying \(theme.manifest.name)…", detail: nil, symbol: nil, on: screen, until: nil)
        Task { @MainActor in
            await model.quickApply(theme, mode: mode)
            let results = model.lastReport?.results ?? []
            let applied = results.filter(\.outcome.isSuccess).count
            let attention = results.filter { if case .failed = $0.outcome { true } else if case .needsAction = $0.outcome { true } else { false } }
            let detail = attention.isEmpty
                ? "\(applied) app\(applied == 1 ? "" : "s") changed. Undo with ⌥⌘Z in Scene."
                : "\(applied) changed · \(attention.map(\.name).joined(separator: ", ")) need\(attention.count == 1 ? "s" : "") attention"
            showHUD(title: theme.manifest.name, detail: detail,
                    symbol: attention.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill", on: screen, until: 2.8)
        }
    }

    // MARK: Status panel

    private func showHUD(title: String, detail: String?, symbol: String?, on screen: NSScreen?, until seconds: Double?) {
        hudTask?.cancel()
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let view = NSHostingView(rootView: HUDView(title: title, detail: detail, symbol: symbol))
        let size = view.fittingSize
        let panel = hud ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = view
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + 120, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        hud = panel
        if let seconds {
            hudTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.hud?.orderOut(nil)
            }
        }
    }
}

/// A borderless panel that can take keyboard focus without activating Scene, like Spotlight.
final class SwitcherPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

// MARK: - Views

struct ThemeCarouselView: View {
    let state: CarouselState
    let onApply: () -> Void
    let onClose: () -> Void
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { screen in
            let width = min(screen.size.width * 0.44, 760)
            ZStack {
                SwitcherBackdrop(state: state, onClose: onClose)
                VStack(spacing: 28) {
                    Spacer(minLength: 0)
                    // The search keeps its place when empty, so the cards stay put when you start typing.
                    search.opacity(state.query.isEmpty ? 0 : 1)
                    carousel(cardWidth: width).frame(height: width * 10 / 16 + 40)
                        .overlay { if state.themes.isEmpty { noMatch } }
                    info
                    Spacer(minLength: 0)
                    hints.padding(.bottom, 44)
                }
                .scaleEffect(appeared ? 1 : 0.97)
                .opacity(appeared ? 1 : 0)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { appeared = true } }
    }

    func carousel(cardWidth width: CGFloat) -> some View {
        GeometryReader { geo in
            let height = width * 10 / 16
            let step = width * 0.7 + 24
            ZStack {
                ForEach(Array(state.themes.enumerated()), id: \.element.id) { index, theme in
                    let distance = index - state.selection.index
                    let variant = theme.variants[state.appearance(theme)] ?? theme.variants.values.first!
                    card(theme: theme, variant: variant, selected: distance == 0)
                        .frame(width: width, height: height)
                        // Side cards turn toward the middle, like pages of a book.
                        .rotation3DEffect(.degrees(distance == 0 || reduceMotion ? 0 : distance < 0 ? 24 : -24), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .scaleEffect(distance == 0 ? 1 : 0.8)
                        .opacity(distance == 0 ? 1 : max(0, 0.7 - Double(abs(distance) - 1) * 0.35))
                        .offset(x: CGFloat(distance) * step)
                        .zIndex(-Double(abs(distance)))
                        .onTapGesture { distance == 0 ? onApply() : state.selection.select(index) }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.spring(response: 0.38, dampingFraction: 0.86), value: state.selection.index)
            .animation(.easeInOut(duration: 0.25), value: state.previewed)
        }
    }

    func card(theme: Theme, variant: ResolvedVariant, selected: Bool) -> some View {
        DesktopPreview(variant: variant, wallpaper: state.wallpaper(variant))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(selected ? 0.35 : 0.12), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if theme.id == state.currentID {
                    Label("Current", systemImage: "checkmark").font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .glass(in: Capsule())
                        .padding(14)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.55 : 0.3), radius: selected ? 44 : 16, y: selected ? 26 : 10)
    }

    /// What you typed, over the cards.
    var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            Text(state.query).font(.title3.weight(.medium))
            Text("\(state.themes.count) of \(state.allThemes.count)").font(.callout).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .glass(in: Capsule())
    }

    var noMatch: some View {
        VStack(spacing: 8) {
            Text("No themes match “\(state.query)”").font(.title2.weight(.semibold))
            Text("⌫ deletes a letter. Esc clears the search.").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var info: some View {
        if let theme = state.selected { info(theme) }
    }

    func info(_ theme: Theme) -> some View {
        let appearance = state.appearance(theme)
        let variant = theme.variants[appearance] ?? theme.variants.values.first!
        return VStack(spacing: 12) {
            Text(theme.manifest.name).font(.system(size: 42, weight: .bold))
            if let summary = theme.manifest.summary { Text(summary).font(.title3).foregroundStyle(.secondary) }
            HStack(spacing: 18) {
                PaletteDots(colors: variant.hues, size: 13)
                HStack(spacing: 2) {
                    ForEach(theme.availableAppearances.reversed(), id: \.self) { look in
                        Label(look == .dark ? "Dark" : "Light", systemImage: look == .dark ? "moon.fill" : "sun.max.fill")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(look == appearance ? Color.white.opacity(0.2) : .clear, in: Capsule())
                            .foregroundStyle(look == appearance ? .primary : .secondary)
                    }
                }
                .padding(3)
                .glass(in: Capsule())
            }
            .padding(.top, 4)
            PageDots(count: state.themes.count, index: state.selection.index).padding(.top, 10)
        }
        .animation(.easeInOut(duration: 0.18), value: state.selection.index)
    }

    var hints: some View {
        HStack(spacing: 24) {
            hint(["←", "→"], "Choose")
            if state.themes.contains(where: { $0.availableAppearances.count == 2 }) { hint(["↑", "↓"], "Light / Dark") }
            Text("Type to search").padding(.leading, 2)
            hint(["↩"], "Apply")
            hint(["esc"], state.query.isEmpty ? "Close" : "Clear")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18).padding(.vertical, 10)
        .glass(in: Capsule())
    }

    func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { Keycap(key: $0) }
            Text(label).padding(.leading, 2)
        }
    }
}

/// Where the carousel is: one dot per theme. Too many themes for dots show "7 of 40".
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        if count <= 30 {
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(i == index ? Color.white : Color.white.opacity(0.3))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
        } else {
            Text("\(index + 1) of \(count)").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// The selected theme's wallpaper, blurred, over a whole screen. It follows the selection. A click closes the switcher.
struct SwitcherBackdrop: View {
    let state: CarouselState
    let onClose: () -> Void

    var body: some View {
        let theme = state.backdrop
        let variant = theme.variants[state.appearance(theme)] ?? theme.variants.values.first!
        AmbientBackground(variant: variant, url: state.wallpaper(variant), scheme: .dark)
            .contentShape(Rectangle())
            .onTapGesture(perform: onClose)
    }
}

struct HUDView: View {
    let title: String
    let detail: String?
    let symbol: String?

    var body: some View {
        HStack(spacing: 12) {
            if let symbol { Image(systemName: symbol).font(.title2).foregroundStyle(symbol.hasPrefix("checkmark") ? .green : .orange) }
            else { ProgressView().controlSize(.small) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .glass(in: Capsule())
        .environment(\.colorScheme, .dark)
        .padding(20)
    }
}
