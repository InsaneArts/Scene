import Foundation
import SceneThemes
import SceneFoundation

/// Renders Xcode `.xccolortheme` files: XML property lists with colors as "r g b a" strings.
/// Fonts and line spacing come from the theme the user has now, so Scene changes colors only.
public enum XcodeRenderer {
    public static let fileNames: [Appearance: String] = [.dark: "Scene (Dark).xccolortheme", .light: "Scene (Light).xccolortheme"]

    /// - Parameter base: the user's current theme. Only its font keys, line spacing, and version are kept.
    public static func theme(_ v: ResolvedVariant, base: [String: Any]?) throws -> Data {
        var theme = fonts(from: base)
        let ui = v.interface, s = v.syntax, bg = ui.background
        let colors: [String: RGBA] = [
            "DVTSourceTextBackground": bg, "DVTSourceTextCurrentLineHighlightColor": ui.currentLine,
            "DVTSourceTextInsertionPointColor": ui.cursor, "DVTSourceTextInvisiblesColor": ui.border,
            "DVTSourceTextSelectionColor": ui.selection, "DVTSourceTextBlockDimBackgroundColor": ui.muted,
            "DVTConsoleTextBackgroundColor": bg, "DVTConsoleTextInsertionPointColor": ui.cursor, "DVTConsoleTextSelectionColor": ui.selection,
            "DVTConsoleDebuggerInputTextColor": ui.foreground, "DVTConsoleDebuggerOutputTextColor": ui.foreground,
            "DVTConsoleDebuggerPromptTextColor": ui.accent,
            // Xcode spells these keys "Exectuable".
            "DVTConsoleExectuableInputTextColor": ui.foreground, "DVTConsoleExectuableOutputTextColor": ui.foreground,
            "DVTDebuggerInstructionPointerColor": ui.info.mixed(over: bg, amount: 0.35),
            "DVTMarkupTextBackgroundColor": ui.overlay, "DVTMarkupTextBorderColor": ui.border,
            "DVTMarkupTextEmphasisColor": ui.foreground, "DVTMarkupTextInlineCodeColor": ui.foreground.with(alpha: 0.7),
            "DVTMarkupTextLinkColor": ui.accent, "DVTMarkupTextNormalColor": ui.foreground,
            "DVTMarkupTextOtherHeadingColor": ui.foreground.with(alpha: 0.5), "DVTMarkupTextPrimaryHeadingColor": ui.foreground,
            "DVTMarkupTextSecondaryHeadingColor": ui.foreground, "DVTMarkupTextStrongColor": ui.foreground,
            "DVTScrollbarMarkerAnalyzerColor": ui.info, "DVTScrollbarMarkerBreakpointColor": ui.accent,
            "DVTScrollbarMarkerDiffColor": ui.muted, "DVTScrollbarMarkerDiffConflictColor": ui.error,
            "DVTScrollbarMarkerErrorColor": ui.error, "DVTScrollbarMarkerRuntimeIssueColor": s.keyword.color,
            "DVTScrollbarMarkerWarningColor": ui.warning,
        ]
        for (key, color) in colors { theme[key] = string(color) }
        let docKeyword = s.comment.color.mixed(over: ui.foreground, amount: 0.6)
        var syntax: [String: RGBA] = [
            "xcode.syntax.plain": ui.foreground, "xcode.syntax.attribute": s.attribute.color, "xcode.syntax.character": s.string.color,
            "xcode.syntax.comment": s.comment.color, "xcode.syntax.comment.doc": s.comment.color, "xcode.syntax.comment.doc.keyword": docKeyword,
            "xcode.syntax.declaration.other": s.function.color, "xcode.syntax.declaration.type": s.type.color,
            "xcode.syntax.identifier.class": s.type.color, "xcode.syntax.identifier.class.system": s.builtin.color,
            "xcode.syntax.identifier.constant": s.constant.color, "xcode.syntax.identifier.constant.system": s.builtin.color,
            "xcode.syntax.identifier.function": s.function.color, "xcode.syntax.identifier.function.system": s.builtin.color,
            "xcode.syntax.identifier.macro": s.attribute.color, "xcode.syntax.identifier.macro.system": s.attribute.color,
            "xcode.syntax.identifier.type": s.type.color, "xcode.syntax.identifier.type.system": s.builtin.color,
            "xcode.syntax.identifier.variable": s.property.color, "xcode.syntax.identifier.variable.system": s.builtin.color,
            "xcode.syntax.keyword": s.keyword.color, "xcode.syntax.mark": docKeyword, "xcode.syntax.markup.code": s.string.color,
            "xcode.syntax.number": s.number.color, "xcode.syntax.preprocessor": s.attribute.color, "xcode.syntax.string": s.string.color,
            "xcode.syntax.url": ui.accent, "xcode.syntax.regex": s.escape.color, "xcode.syntax.regex.capturename": s.constant.color,
            "xcode.syntax.regex.charname": s.escape.color, "xcode.syntax.regex.number": s.number.color, "xcode.syntax.regex.other": s.escape.color,
        ]
        // Keys a newer Xcode added that Scene does not know get the nearest role.
        for key in (base?["DVTSourceTextSyntaxColors"] as? [String: Any] ?? [:]).keys where syntax[key] == nil && key.hasPrefix("xcode.syntax.") {
            syntax[key] = key.contains("comment") ? s.comment.color : key.contains("string") ? s.string.color : ui.foreground
        }
        theme["DVTSourceTextSyntaxColors"] = syntax.mapValues(string)
        return try PropertyListSerialization.data(fromPropertyList: theme, format: .xml, options: 0)
    }

    /// Font keys, line spacing, and version from the base theme, or Xcode's defaults.
    static func fonts(from base: [String: Any]?) -> [String: Any] {
        var out: [String: Any] = ["DVTFontAndColorVersion": 1, "DVTLineSpacing": 1.1]
        var syntaxFonts = defaultSyntaxFonts
        for (key, font) in defaultFonts { out[key] = font }
        if let base {
            for (key, value) in base where key.hasSuffix("Font") {
                if let font = value as? String { out[key] = font }
            }
            if let spacing = base["DVTLineSpacing"] as? Double { out["DVTLineSpacing"] = spacing }
            for (key, value) in base["DVTSourceTextSyntaxFonts"] as? [String: Any] ?? [:] {
                if let font = value as? String { syntaxFonts[key] = font }
            }
        }
        out["DVTSourceTextSyntaxFonts"] = syntaxFonts
        return out
    }

    /// "r g b a" with each channel from 0 to 1.
    static func string(_ c: RGBA) -> String {
        [c.red, c.green, c.blue, c.alpha].map { String(format: "%.6g", $0) }.joined(separator: " ")
    }

    static let defaultFonts: [String: String] = [
        "DVTConsoleDebuggerInputTextFont": "SFMono-Bold - 12.0", "DVTConsoleDebuggerOutputTextFont": "SFMono-Medium - 12.0",
        "DVTConsoleDebuggerPromptTextFont": "SFMono-Bold - 12.0", "DVTConsoleExectuableInputTextFont": "SFMono-Medium - 12.0",
        "DVTConsoleExectuableOutputTextFont": "SFMono-Bold - 12.0", "DVTMarkupTextCodeFont": "SFMono-Regular - 10.0",
        "DVTMarkupTextEmphasisFont": ".AppleSystemUIFontItalic - 10.0", "DVTMarkupTextLinkFont": ".AppleSystemUIFont - 10.0",
        "DVTMarkupTextNormalFont": ".AppleSystemUIFont - 10.0", "DVTMarkupTextOtherHeadingFont": ".AppleSystemUIFont - 14.0",
        "DVTMarkupTextPrimaryHeadingFont": ".AppleSystemUIFont - 24.0", "DVTMarkupTextSecondaryHeadingFont": ".AppleSystemUIFont - 18.0",
        "DVTMarkupTextStrongFont": ".AppleSystemUIFontBold - 10.0",
    ]

    static let defaultSyntaxFonts: [String: String] = {
        let keys = ["plain", "attribute", "character", "comment", "comment.doc", "declaration.other", "declaration.type",
                    "identifier.class", "identifier.class.system", "identifier.constant", "identifier.constant.system",
                    "identifier.function", "identifier.function.system", "identifier.macro", "identifier.macro.system",
                    "identifier.type", "identifier.type.system", "identifier.variable", "identifier.variable.system",
                    "markup.code", "number", "preprocessor", "string", "url",
                    "regex", "regex.capturename", "regex.charname", "regex.number", "regex.other"]
        var fonts = Dictionary(uniqueKeysWithValues: keys.map { ("xcode.syntax.\($0)", "SFMono-Medium - 12.0") })
        fonts["xcode.syntax.keyword"] = "SFMono-Bold - 12.0"
        fonts["xcode.syntax.mark"] = "SFMono-Bold - 12.0"
        fonts["xcode.syntax.comment.doc.keyword"] = "SFMono-Bold - 12.0"
        return fonts
    }()
}
