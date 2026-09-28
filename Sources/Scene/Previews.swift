import ImageIO
import SceneThemes
import SwiftUI

extension RGBA {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

// MARK: - Wallpaper thumbnails

/// Downsampled wallpaper images, decoded off the main thread through ImageIO thumbnails.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()
    private let cache = NSCache<NSURL, NSImage>()

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL, maxPixels: Int = 1600) async -> NSImage? {
        if let hit = cached(url) { return hit }
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixels, kCGImageSourceShouldCacheImmediately: true]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let image else { return nil }
        let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        cache.setObject(result, forKey: url as NSURL)
        return result
    }
}

struct WallpaperView: View {
    let variant: ResolvedVariant
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [variant.interface.surface.color, variant.interface.background.color, variant.interface.accent.color.opacity(0.35)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = Thumbnails.shared.cached(url) { image = hit; return }
            let loaded = await Thumbnails.shared.load(url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

// MARK: - Terminal

/// Sample shell output colored with the real ANSI palette. Colors are exact.
struct TerminalPreview: View {
    let variant: ResolvedVariant
    var fontSize: CGFloat = 11

    private typealias Run = (String, Int?)   // text, ANSI index (nil = foreground)

    private var lines: [[Run]] {
        [
            [("➜ ", 2), ("scene ", 6), ("git:(", 4), ("main", 1), (") ", 4), ("ls", nil)],
            [("Sources  ", 4), ("Tests  ", 4), ("Themes  ", 4), ("Package.swift  ", nil), ("build.sh", 2)],
            [("➜ ", 2), ("scene ", 6), ("git status --short", nil)],
            [(" M ", 3), ("Sources/Engine.swift", nil)],
            [("?? ", 1), ("Themes/tidewater/", nil)],
            [("➜ ", 2), ("scene ", 6), ("swift test", nil)],
            [("✔ ", 2), ("Test run with 104 tests passed", nil)],
            [("  0 ", 8), ("1 ", 9), ("2 ", 10), ("3 ", 11), ("4 ", 12), ("5 ", 13), ("6 ", 14), ("7", 15)],
        ]
    }

    var body: some View {
        let t = variant.terminal
        VStack(alignment: .leading, spacing: 2) {
            ForEach(lines.indices, id: \.self) { index in
                lines[index].reduce(Text("")) { partial, run in
                    partial + Text(run.0).foregroundColor(run.1.map { t.ansi[$0].color } ?? t.foreground.color)
                }
                .lineLimit(1)
            }
            HStack(spacing: 0) {
                Text("➜ ").foregroundColor(t.ansi[2].color)
                Rectangle().fill(t.cursor.color).frame(width: fontSize * 0.6, height: fontSize * 1.15)
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
        .padding(fontSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.background.color)
        .clipped()
    }
}

// MARK: - Code

/// A code sample highlighted with the theme's syntax roles. Colors are exact; token boundaries
/// come from a small tokenizer, so they can differ from an editor's grammar.
struct CodePreview: View {
    let variant: ResolvedVariant
    var fontSize: CGFloat = 11

    static let sample = """
    import SceneCore

    /// Applies a theme and reports each app.
    struct Applier {
        let engine: Engine
        var retries = 3

        func run(_ theme: Theme) async -> Bool {
            let report = await engine.apply(theme)
            print("Applied \\(report.count) apps")
            return retries > 0 && report.ok
        }
    }
    """

    var body: some View {
        let ui = variant.interface
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(Self.sample.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { index, _ in
                    Text("\(index + 1)").foregroundColor(index == 8 ? ui.foreground.color : ui.muted.color.opacity(0.7))
                }
            }
            .padding(.horizontal, fontSize * 0.8)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(Self.sample.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { index, line in
                    Highlighter.text(String(line), variant.syntax, fallback: ui.foreground)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == 8 ? ui.currentLine.color : .clear)
                }
            }
        }
        .font(.system(size: fontSize, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, fontSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ui.background.color)
        .clipped()
    }
}

enum Highlighter {
    static let keywords: Set<String> = ["import", "struct", "let", "var", "func", "async", "await", "return", "if", "else", "for", "in"]
    static let types: Set<String> = ["SceneCore", "Applier", "Engine", "Theme", "Bool", "Int", "String"]
    static let builtins: Set<String> = ["print", "true", "false", "self"]

    static func text(_ line: String, _ s: SyntaxColors, fallback: RGBA) -> Text {
        func styled(_ piece: String, _ style: SyntaxStyle) -> Text {
            var text = Text(piece).foregroundColor(style.color.color)
            if style.italic { text = text.italic() }
            if style.bold { text = text.bold() }
            return text
        }
        if let range = line.range(of: "//") { return styled(String(line[..<range.lowerBound]), SyntaxStyle(color: fallback)) + styled(String(line[range.lowerBound...]), s.comment) }
        var result = Text("")
        var index = line.startIndex
        var previousWord = ""
        while index < line.endIndex {
            let c = line[index]
            if c == "\"" {
                var end = line.index(after: index)
                while end < line.endIndex, line[end] != "\"" { end = line.index(after: end) }
                if end < line.endIndex { end = line.index(after: end) }
                result = result + styled(String(line[index..<end]), s.string)
                index = end
            } else if c.isLetter || c == "_" {
                var end = index
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" { end = line.index(after: end) }
                let word = String(line[index..<end])
                let next = end < line.endIndex ? line[end] : " "
                let style: SyntaxStyle
                if keywords.contains(word) { style = s.keyword }
                else if types.contains(word) { style = s.type }
                else if builtins.contains(word) { style = word == "print" ? s.function : s.builtin }
                else if next == "(" || previousWord == "func" { style = s.function }
                else if previousWord == "." { style = s.property }
                else if next == ":" && previousWord == "(" { style = s.parameter }
                else { style = s.variable }
                result = result + styled(word, style)
                previousWord = word
                index = end
            } else if c.isNumber {
                var end = index
                while end < line.endIndex, line[end].isNumber { end = line.index(after: end) }
                result = result + styled(String(line[index..<end]), s.number)
                index = end
            } else {
                let isOperator = "=><&|!+-*/".contains(c)
                result = result + styled(String(c), isOperator ? s.operator : s.punctuation)
                if c != " " { previousWord = String(c) }
                index = line.index(after: index)
            }
        }
        return result
    }
}

// MARK: - Desktop

/// Wallpaper with a mock menu bar, a terminal window, and an editor window in the theme's colors.
/// The wallpaper and colors are exact; window layouts are approximate.
struct DesktopPreview: View {
    let variant: ResolvedVariant
    let wallpaper: URL?
    var compact = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let font = max(5, w / (compact ? 70 : 62))
            ZStack(alignment: .topLeading) {
                WallpaperView(variant: variant, url: wallpaper)
                // Menu bar.
                HStack(spacing: w * 0.02) {
                    Image(systemName: "apple.logo")
                    Text("Scene").fontWeight(.semibold)
                    Text("File"); Text("Edit"); Text("View")
                    Spacer()
                    Circle().fill(variant.interface.accent.color).frame(width: font * 0.9, height: font * 0.9)
                    Image(systemName: variant.appearance == .dark ? "moon.fill" : "sun.max.fill")
                }
                .font(.system(size: font))
                .foregroundStyle(variant.appearance == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.85))
                .padding(.horizontal, w * 0.02)
                .frame(height: h * 0.055)
                .background(.ultraThinMaterial.opacity(0.9))
                // Windows.
                window(title: "zsh", w: w * 0.5, h: h * 0.52) { TerminalPreview(variant: variant, fontSize: font) }
                    .offset(x: w * 0.05, y: h * 0.14)
                window(title: "Applier.swift", w: w * 0.52, h: h * 0.6) { CodePreview(variant: variant, fontSize: font) }
                    .offset(x: w * 0.43, y: h * 0.3)
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
    }

    func window<Content: View>(title: String, w: CGFloat, h: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let ui = variant.interface
        return VStack(spacing: 0) {
            HStack(spacing: w * 0.012) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
                Spacer()
                Text(title).font(.system(size: w * 0.028)).foregroundColor(ui.muted.color)
                Spacer()
            }
            .frame(height: h * 0.075)
            .padding(.horizontal, w * 0.025)
            .background(ui.surface.color)
            // A fixed, top-aligned frame: content that is taller than the window is cut at the bottom.
            content()
                .frame(width: w, height: h * 0.925, alignment: .topLeading)
                .clipped()
        }
        .frame(width: w, height: h, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: w * 0.025, style: .continuous).strokeBorder(ui.border.color.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: w * 0.03, y: h * 0.02)
    }
}

// MARK: - Palette strip

struct PaletteStrip: View {
    let variant: ResolvedVariant
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(variant.terminal.ansi.prefix(8).enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 3).fill(color.color).frame(height: 10)
            }
        }
    }
}
