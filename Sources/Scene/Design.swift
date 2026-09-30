import AppKit
import SceneIntegrations
import SceneSwitcher
import SceneThemes
import SwiftUI

// Shared parts of Scene's look. A theme page takes its colors and its light or dark look from the theme itself.

extension ResolvedVariant {
    /// Red to cyan from the terminal palette: the colors that tell themes apart.
    var hues: [RGBA] { Array(terminal.ansi[1...6]) }

    var colorScheme: ColorScheme { appearance == .dark ? .dark : .light }

    /// Text on the accent color: the theme's background when it reads well, otherwise black or white.
    var onAccent: Color {
        let accent = interface.accent
        if accent.contrast(with: interface.background) >= 3 { return interface.background.color }
        return accent.luminance > 0.3 ? .black : .white
    }
}

extension View {
    /// Liquid Glass on macOS 26, a material on earlier versions.
    @ViewBuilder
    func glass(in shape: some Shape) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// A wallpaper, blurred and dimmed, behind a page. It fades when the wallpaper changes.
struct AmbientBackground: View {
    let variant: ResolvedVariant
    let url: URL?
    /// The look the dimming serves. Nil uses the variant's own.
    var scheme: ColorScheme?

    var body: some View {
        let dark = (scheme ?? variant.colorScheme) == .dark
        ZStack {
            WallpaperView(variant: variant, url: url, pixels: 96)
                .id(url)
                .transition(.opacity)
        }
        .blur(radius: 40, opaque: true)
        .overlay(dark ? Color.black.opacity(0.5) : Color.white.opacity(0.55))
        .animation(.easeInOut(duration: 0.45), value: url)
        .ignoresSafeArea()
    }
}

/// A row of color dots.
struct PaletteDots: View {
    let colors: [RGBA]
    var size: CGFloat = 10

    var body: some View {
        HStack(spacing: size * 0.4) {
            ForEach(colors.indices, id: \.self) { index in
                Circle().fill(colors[index].color)
                    .overlay(Circle().strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A short status in a tinted capsule.
struct Pill: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// One key of a shortcut.
struct Keycap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.primary.opacity(0.14), lineWidth: 0.5))
    }
}

extension HotKeySpec {
    /// The modifiers in Apple's order, then the key: one keycap each.
    var keys: [String] {
        [control ? "⌃" : nil, option ? "⌥" : nil, shift ? "⇧" : nil, command ? "⌘" : nil, keyLabel].compactMap { $0 }
    }
}

/// A capsule button with a solid fill. Scene's primary buttons use the theme's accent color.
struct CapsuleButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(label)
            .padding(.horizontal, 18)
            .frame(minHeight: 32)
            .background(fill, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A titled group of rows on a rounded card, like a section of a grouped form.
struct CardSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(spacing: 0) { content }
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// A scrolling page with a large title.
struct PageScroll<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 28, weight: .bold))
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

/// An app's own icon, or a System Settings–style tile for macOS settings, Neovim, and apps that are not installed.
struct AppIcon: View {
    let id: String
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = Self.icon(id) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                let (symbol, top, bottom) = Self.tile(id)
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                    .overlay(Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white))
                    // App icons leave the same margin around their shape.
                    .padding(size * 0.09)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let bundleIDs: [String: [String]] = VSCodeFamilyIntegration.all.reduce(into: [
        "ghostty": [GhosttyIntegration.bundleID], "iterm2": [ITermIntegration.bundleID], "kitty": [KittyIntegration.bundleID],
        "terminal": [TerminalAppIntegration.bundleID], "zed": ZedIntegration.bundleIDs, "xcode": [XcodeIntegration.bundleID],
        "alacritty": [AlacrittyIntegration.bundleID], "warp": [WarpIntegration.bundleID],
    ]) { $0[$1.id] = $1.bundleIDs }

    private static var icons: [String: NSImage?] = [:]

    private static func icon(_ id: String) -> NSImage? {
        if let known = icons[id] { return known }
        let app = bundleIDs[id]?.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
        let icon = app.map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[id] = icon
        return icon
    }

    private static func tile(_ id: String) -> (String, Color, Color) {
        switch id {
        case "wallpaper": ("photo.fill", Color(red: 0.3, green: 0.8, blue: 1), Color(red: 0.1, green: 0.45, blue: 0.95))
        case "appearance": ("circle.lefthalf.filled", Color(white: 0.45), Color(white: 0.18))
        case "accent": ("paintpalette.fill", Color(red: 1, green: 0.6, blue: 0.3), Color(red: 0.9, green: 0.25, blue: 0.5))
        case "iconStyle": ("square.grid.2x2.fill", Color(red: 0.5, green: 0.5, blue: 1), Color(red: 0.3, green: 0.25, blue: 0.85))
        case "neovim": ("chevron.left.forwardslash.chevron.right", Color(red: 0.45, green: 0.78, blue: 0.3), Color(red: 0.1, green: 0.5, blue: 0.3))
        case "ghostty", "iterm2", "kitty", "terminal", "alacritty", "warp": ("terminal.fill", Color(white: 0.45), Color(white: 0.2))
        case "helix": ("chevron.left.forwardslash.chevron.right", Color(red: 0.6, green: 0.45, blue: 0.95), Color(red: 0.35, green: 0.2, blue: 0.7))
        case "btop": ("gauge.with.dots.needle.67percent", Color(red: 0.95, green: 0.5, blue: 0.35), Color(red: 0.75, green: 0.25, blue: 0.2))
        case "borders": ("square.dashed", Color(red: 0.4, green: 0.8, blue: 0.95), Color(red: 0.15, green: 0.5, blue: 0.8))
        case "tmux": ("rectangle.split.2x1.fill", Color(red: 0.3, green: 0.75, blue: 0.4), Color(red: 0.1, green: 0.45, blue: 0.2))
        case "bat": ("doc.text.fill", Color(red: 0.55, green: 0.45, blue: 0.9), Color(red: 0.3, green: 0.2, blue: 0.65))
        default: ("curlybraces", Color(red: 0.3, green: 0.6, blue: 1), Color(red: 0.1, green: 0.35, blue: 0.85))
        }
    }
}
