import Foundation
import SceneThemes
import SceneFoundation

/// Renders a VS Code color theme (workbench colors, TextMate token rules, semantic tokens)
/// and the theme-only extension that carries it.
public enum VSCodeRenderer {
    public static let extensionName = "scene-themes"
    public static let publisher = "scene"
    public static var extensionID: String { "\(publisher).\(extensionName)" }
    public static let labels: [Appearance: String] = [.dark: "Scene Dark", .light: "Scene Light"]

    // MARK: Theme JSON

    public static func theme(_ v: ResolvedVariant, label: String? = nil) throws -> Data {
        var colors = workbenchColors(v)
        var tokenRules = tokenColors(v)
        var semantic = semanticTokenColors(v)
        if let data = v.overrides["vscode"], let override = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (key, value) in override["colors"] as? [String: String] ?? [:] { colors[key] = value }
            tokenRules += override["tokenColors"] as? [[String: Any]] ?? []
            for (key, value) in override["semanticTokenColors"] as? [String: Any] ?? [:] { semantic[key] = value }
        }
        let json: [String: Any] = [
            "$schema": "vscode://schemas/color-theme",
            "name": label ?? labels[v.appearance]!,
            "type": v.appearance.rawValue,
            "semanticHighlighting": true,
            "colors": colors,
            "tokenColors": tokenRules,
            "semanticTokenColors": semantic,
        ]
        return try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
    }

    static func workbenchColors(_ v: ResolvedVariant) -> [String: String] {
        let ui = v.interface, t = v.terminal, s = v.syntax
        let bg = ui.background
        func a(_ c: RGBA, _ alpha: Double) -> String { c.with(alpha: alpha).hexWithAlpha }
        var c: [String: String] = [
            "foreground": ui.foreground.hex, "descriptionForeground": ui.muted.hex, "errorForeground": ui.error.hex,
            "focusBorder": a(ui.accent, 0.6), "selection.background": ui.selection.hex, "widget.shadow": "#00000040",
            "textLink.foreground": ui.accent.hex, "textLink.activeForeground": ui.accent.hex, "progressBar.background": ui.accent.hex,
            "editor.background": bg.hex, "editor.foreground": ui.foreground.hex,
            "editorLineNumber.foreground": ui.muted.mixed(over: bg, amount: 0.7).hex, "editorLineNumber.activeForeground": ui.foreground.hex,
            "editorCursor.foreground": ui.cursor.hex, "editor.selectionBackground": ui.selection.hex,
            "editor.inactiveSelectionBackground": ui.selection.mixed(over: bg, amount: 0.6).hex,
            "editor.lineHighlightBackground": ui.currentLine.hex, "editor.lineHighlightBorder": ui.currentLine.hex,
            "editor.findMatchBackground": ui.search.hex, "editor.findMatchHighlightBackground": a(ui.search, 0.5),
            "editor.wordHighlightBackground": a(ui.selection, 0.5), "editor.wordHighlightStrongBackground": a(ui.selection, 0.7),
            "editorIndentGuide.background1": ui.border.hex, "editorIndentGuide.activeBackground1": ui.muted.hex,
            "editorWhitespace.foreground": ui.border.hex, "editorRuler.foreground": ui.border.hex,
            "editorBracketMatch.background": a(ui.selection, 0.5), "editorBracketMatch.border": ui.accent.hex,
            "editorWidget.background": ui.overlay.hex, "editorWidget.border": ui.border.hex,
            "editorSuggestWidget.background": ui.overlay.hex, "editorSuggestWidget.border": ui.border.hex,
            "editorSuggestWidget.selectedBackground": ui.selection.hex, "editorSuggestWidget.highlightForeground": ui.accent.hex,
            "editorHoverWidget.background": ui.overlay.hex, "editorHoverWidget.border": ui.border.hex,
            "editorGroupHeader.tabsBackground": ui.surface.hex, "editorGroup.border": ui.border.hex,
            "tab.activeBackground": bg.hex, "tab.inactiveBackground": ui.surface.hex, "tab.activeForeground": ui.foreground.hex,
            "tab.inactiveForeground": ui.muted.hex, "tab.border": ui.border.hex, "tab.activeBorderTop": ui.accent.hex,
            "sideBar.background": ui.surface.hex, "sideBar.foreground": ui.foreground.hex, "sideBar.border": ui.border.hex,
            "sideBarTitle.foreground": ui.muted.hex, "sideBarSectionHeader.background": ui.surface.hex,
            "activityBar.background": ui.surface.hex, "activityBar.foreground": ui.foreground.hex,
            "activityBar.inactiveForeground": ui.muted.hex, "activityBar.border": ui.border.hex,
            "activityBarBadge.background": ui.accent.hex, "activityBarBadge.foreground": bg.hex,
            "titleBar.activeBackground": ui.surface.hex, "titleBar.activeForeground": ui.foreground.hex,
            "titleBar.inactiveBackground": ui.surface.hex, "titleBar.inactiveForeground": ui.muted.hex, "titleBar.border": ui.border.hex,
            "statusBar.background": ui.surface.hex, "statusBar.foreground": ui.muted.hex, "statusBar.border": ui.border.hex,
            "statusBar.debuggingBackground": ui.warning.hex, "statusBar.debuggingForeground": bg.hex,
            "statusBarItem.remoteBackground": ui.accent.hex, "statusBarItem.remoteForeground": bg.hex,
            "panel.background": ui.surface.hex, "panel.border": ui.border.hex, "panelTitle.activeForeground": ui.foreground.hex,
            "panelTitle.activeBorder": ui.accent.hex, "panelTitle.inactiveForeground": ui.muted.hex,
            "input.background": ui.overlay.hex, "input.border": ui.border.hex, "input.foreground": ui.foreground.hex,
            "input.placeholderForeground": ui.muted.hex, "dropdown.background": ui.overlay.hex, "dropdown.border": ui.border.hex,
            "dropdown.foreground": ui.foreground.hex, "button.background": ui.accent.hex, "button.foreground": bg.hex,
            "button.hoverBackground": ui.accent.mixed(over: ui.foreground, amount: 0.85).hex,
            "badge.background": ui.accent.hex, "badge.foreground": bg.hex,
            "list.activeSelectionBackground": ui.selection.hex, "list.activeSelectionForeground": ui.foreground.hex,
            "list.inactiveSelectionBackground": ui.selection.mixed(over: bg, amount: 0.6).hex, "list.hoverBackground": ui.currentLine.hex,
            "list.highlightForeground": ui.accent.hex, "list.focusOutline": a(ui.accent, 0.6),
            "quickInput.background": ui.overlay.hex, "quickInputList.focusBackground": ui.selection.hex,
            "menu.background": ui.overlay.hex, "menu.foreground": ui.foreground.hex, "menu.selectionBackground": ui.selection.hex,
            "menu.border": ui.border.hex, "notifications.background": ui.overlay.hex, "notifications.border": ui.border.hex,
            "scrollbarSlider.background": a(ui.muted, 0.2), "scrollbarSlider.hoverBackground": a(ui.muted, 0.33),
            "scrollbarSlider.activeBackground": a(ui.muted, 0.45),
            "editorError.foreground": ui.error.hex, "editorWarning.foreground": ui.warning.hex, "editorInfo.foreground": ui.info.hex,
            "gitDecoration.addedResourceForeground": s.added.color.hex, "gitDecoration.modifiedResourceForeground": s.changed.color.hex,
            "gitDecoration.deletedResourceForeground": s.removed.color.hex, "gitDecoration.untrackedResourceForeground": ui.success.hex,
            "gitDecoration.ignoredResourceForeground": ui.muted.hex,
            "editorGutter.addedBackground": s.added.color.hex, "editorGutter.modifiedBackground": s.changed.color.hex,
            "editorGutter.deletedBackground": s.removed.color.hex,
            "diffEditor.insertedTextBackground": a(s.added.color, 0.15), "diffEditor.removedTextBackground": a(s.removed.color, 0.15),
            "breadcrumb.foreground": ui.muted.hex, "breadcrumb.focusForeground": ui.foreground.hex,
            "peekView.border": ui.accent.hex, "peekViewEditor.background": ui.surface.hex, "peekViewResult.background": ui.surface.hex,
            "editorOverviewRuler.border": ui.border.hex,
            "terminal.background": t.background.hex, "terminal.foreground": t.foreground.hex,
            "terminalCursor.foreground": t.cursor.hex, "terminal.selectionBackground": t.selectionBackground.hex,
        ]
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        for (i, name) in names.enumerated() {
            c["terminal.ansi\(name)"] = t.ansi[i].hex
            c["terminal.ansiBright\(name)"] = t.ansi[i + 8].hex
        }
        return c
    }

    static func tokenColors(_ v: ResolvedVariant) -> [[String: Any]] {
        let s = v.syntax
        func rule(_ name: String, _ scopes: [String], _ style: SyntaxStyle, bold: Bool = false) -> [String: Any] {
            var settings: [String: Any] = ["foreground": style.color.hex]
            let words = [(style.bold || bold) ? "bold" : nil, style.italic ? "italic" : nil, style.underline ? "underline" : nil].compactMap { $0 }
            if !words.isEmpty { settings["fontStyle"] = words.joined(separator: " ") }
            return ["name": name, "scope": scopes, "settings": settings]
        }
        return [
            rule("Variable", ["variable", "variable.other.readwrite"], s.variable),
            rule("Punctuation", ["punctuation", "meta.brace"], s.punctuation),
            rule("Operator", ["keyword.operator"], s.operator),
            rule("Keyword", ["keyword", "keyword.control", "storage.type", "storage.modifier"], s.keyword),
            rule("String", ["string", "string.quoted"], s.string),
            rule("Escape", ["constant.character.escape", "string.regexp"], s.escape),
            rule("Number", ["constant.numeric"], s.number),
            rule("Constant", ["constant.language", "variable.other.constant", "variable.other.enummember", "support.constant"], s.constant),
            rule("Function", ["entity.name.function", "support.function", "meta.function-call.generic"], s.function),
            rule("Type", ["entity.name.type", "entity.name.class", "support.type", "support.class", "entity.other.inherited-class"], s.type),
            rule("Builtin", ["support.function.builtin", "variable.language", "support.variable"], s.builtin),
            rule("Parameter", ["variable.parameter"], s.parameter),
            rule("Property", ["variable.other.property", "variable.other.object.property", "support.type.property-name", "meta.object-literal.key"], s.property),
            rule("Tag", ["entity.name.tag"], s.tag),
            rule("Attribute", ["entity.other.attribute-name", "meta.attribute", "storage.type.annotation"], s.attribute),
            rule("Comment", ["comment", "punctuation.definition.comment"], s.comment),
            rule("Inserted", ["markup.inserted"], s.added),
            rule("Deleted", ["markup.deleted"], s.removed),
            rule("Changed", ["markup.changed"], s.changed),
            rule("Heading", ["markup.heading", "entity.name.section"], s.keyword, bold: true),
            ["name": "Bold", "scope": ["markup.bold"], "settings": ["fontStyle": "bold"]],
            ["name": "Italic", "scope": ["markup.italic"], "settings": ["fontStyle": "italic"]],
            rule("Link", ["markup.underline.link"], SyntaxStyle(color: v.interface.accent, underline: true)),
        ]
    }

    static func semanticTokenColors(_ v: ResolvedVariant) -> [String: Any] {
        let s = v.syntax
        return [
            "function": s.function.color.hex, "method": s.function.color.hex, "type": s.type.color.hex, "class": s.type.color.hex,
            "interface": s.type.color.hex, "enum": s.type.color.hex, "struct": s.type.color.hex, "typeParameter": s.type.color.hex,
            "namespace": s.type.color.hex, "parameter": s.parameter.color.hex, "variable": s.variable.color.hex,
            "property": s.property.color.hex, "enumMember": s.constant.color.hex, "keyword": s.keyword.color.hex,
            "string": s.string.color.hex, "number": s.number.color.hex, "macro": s.attribute.color.hex,
            "variable.readonly": s.constant.color.hex, "*.defaultLibrary": s.builtin.color.hex,
            "comment": ["foreground": s.comment.color.hex, "italic": s.comment.italic],
        ]
    }

    // MARK: Extension

    /// Files of the theme-only extension, as VSIX paths. Both labels are always contributed, so a
    /// setting that names either one keeps resolving when the next theme has only one variant.
    public static func extensionFiles(variants: [Appearance: ResolvedVariant]) throws -> (files: [(path: String, data: Data)], version: String) {
        guard let fallback = variants[.dark] ?? variants[.light] else { throw SceneError.invalid("no variant to render") }
        var themeFiles: [(String, Data)] = []
        for slot in Appearance.allCases {
            let data = try theme(variants[slot] ?? fallback, label: labels[slot]!)
            themeFiles.append(("extension/themes/scene-\(slot.rawValue).json", data))
        }
        // The version derives from the content: VS Code caches loaded themes until the extension version changes.
        let digest = FileOps.sha256(themeFiles.map(\.1).reduce(Data(), +))
        let version = "1.0.\(UInt32(digest.prefix(8), radix: 16) ?? 0)"
        let package: [String: Any] = [
            "name": extensionName, "displayName": "Scene Themes", "publisher": publisher, "version": version,
            "description": "Themes applied by Scene. Scene manages this extension; do not edit it.",
            "engines": ["vscode": "^1.70.0"], "categories": ["Themes"],
            "contributes": ["themes": Appearance.allCases.map { slot in
                ["label": labels[slot]!, "uiTheme": (variants[slot] ?? fallback).appearance == .dark ? "vs-dark" : "vs",
                 "path": "./themes/scene-\(slot.rawValue).json"]
            }],
        ]
        let manifest = """
        <?xml version="1.0" encoding="utf-8"?>
        <PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
          <Metadata><Identity Language="en-US" Id="\(extensionName)" Version="\(version)" Publisher="\(publisher)"/><DisplayName>Scene Themes</DisplayName><Description xml:space="preserve">Themes applied by Scene</Description><Categories>Themes</Categories></Metadata>
          <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation><Dependencies/>
          <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
        </PackageManifest>
        """
        let contentTypes = """
        <?xml version="1.0" encoding="utf-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>
        """
        let files: [(path: String, data: Data)] = [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("extension.vsixmanifest", Data(manifest.utf8)),
            ("extension/package.json", try JSONSerialization.data(withJSONObject: package, options: [.prettyPrinted, .sortedKeys])),
        ] + themeFiles.map { (path: $0.0, data: $0.1) }
        return (files, version)
    }

}
