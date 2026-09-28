import AppKit
import Observation
import SceneEngine
import SceneSwitcher
import SceneThemes
import SwiftUI

/// State of one carousel session.
@MainActor @Observable
final class CarouselState {
    let themes: [Theme]
    var selection: CarouselSelection
    var previewed: [Theme.ID: Appearance] = [:]
    let currentID: String?
    let systemIsDark: Bool
    /// The picked wallpaper of a variant.
    let wallpaper: (ResolvedVariant) -> URL?

    init(themes: [Theme], currentID: String?, systemIsDark: Bool, wallpaper: @escaping (ResolvedVariant) -> URL?) {
        self.themes = themes
        self.currentID = currentID
        self.systemIsDark = systemIsDark
        self.wallpaper = wallpaper
        selection = CarouselSelection(count: themes.count, index: themes.firstIndex { $0.id == currentID } ?? 0)
    }

    var selected: Theme { themes[selection.index] }

    func appearance(_ theme: Theme) -> Appearance {
        if let chosen = previewed[theme.id] { return chosen }
        let system: Appearance = systemIsDark ? .dark : .light
        return theme.variants[system] != nil ? system : (theme.availableAppearances.first ?? .dark)
    }

    func toggleVariant() {
        let theme = selected
        guard theme.availableAppearances.count == 2 else { return }
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
        let state = CarouselState(themes: model.themes, currentID: model.currentThemeID, systemIsDark: model.systemIsDark,
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

    /// Keys: ← → (or h l) move, ↑ ↓ or Tab switch Light/Dark, 1–9 jump, ↩ apply, Esc close.
    func handle(_ event: NSEvent) -> Bool {
        guard let state else { return false }
        let characters = event.charactersIgnoringModifiers ?? ""
        switch event.keyCode {
        case 123: state.selection.move(-1)
        case 124: state.selection.move(1)
        case 125, 126, 48: state.toggleVariant()
        case 36, 76: applySelected()
        case 53: hide()
        case 115: state.selection.select(0)
        case 119: state.selection.select(state.themes.count - 1)
        default:
            switch characters {
            case "h": state.selection.move(-1)
            case "l": state.selection.move(1)
            case "j", "k": state.toggleVariant()
            case "q": hide()
            default:
                guard let number = Int(characters) else { return false }
                state.selection.jump(toNumber: number)
            }
        }
        return true
    }

    func applySelected() {
        guard let state, let model else { return }
        let theme = state.selected
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
                VStack(spacing: 36) {
                    Spacer(minLength: 0)
                    carousel(cardWidth: width).frame(height: width * 10 / 16 + 40)
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

    var info: some View {
        let theme = state.selected
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
            hint(["↩"], "Apply")
            hint(["esc"], "Close")
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
        let theme = state.selected
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
