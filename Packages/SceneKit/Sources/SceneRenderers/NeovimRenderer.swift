import Foundation
import SceneThemes
import SceneFoundation

/// Neovim support has two parts:
/// - fixed Lua code (the shim) that Scene writes once and never builds from theme data, and
/// - a JSON data file with highlight groups, which the shim reads and watches.
/// Theme values therefore never become Lua code.
public enum NeovimRenderer {

    public static func dataFile(variants: [Appearance: ResolvedVariant]) throws -> Data {
        var out: [String: Any] = ["format": 1]
        var rendered: [String: Any] = [:]
        var prefer: [String: String] = [:]
        for (appearance, v) in variants {
            var groups = highlightGroups(v)
            if let data = v.overrides["neovim"],
               let override = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let extra = override["groups"] as? [String: Any] {
                for (name, spec) in extra { groups[name] = spec }
            }
            rendered[appearance.rawValue] = ["groups": groups, "terminal": v.terminal.ansi.map(\.hex)]
            if let scheme = v.preferInstalled["neovim"]?.colorscheme { prefer[appearance.rawValue] = scheme }
            out["theme"] = ThemeLoader.sanitized(v.themeName)
        }
        out["variants"] = rendered
        if !prefer.isEmpty { out["prefer"] = prefer }
        return try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
    }

    /// Highlight groups for the editor UI, legacy syntax groups, Tree-sitter captures, diagnostics,
    /// diffs, and a few common plugins. Neovim has no alpha, so blends are precomputed.
    static func highlightGroups(_ v: ResolvedVariant) -> [String: Any] {
        let ui = v.interface, s = v.syntax, bg = ui.background
        func hl(fg: RGBA? = nil, bg b: RGBA? = nil, sp: RGBA? = nil, bold: Bool = false, italic: Bool = false,
                underline: Bool = false, undercurl: Bool = false) -> [String: Any] {
            var spec: [String: Any] = [:]
            if let fg { spec["fg"] = fg.hex }
            if let b { spec["bg"] = b.hex }
            if let sp { spec["sp"] = sp.hex }
            if bold { spec["bold"] = true }
            if italic { spec["italic"] = true }
            if underline { spec["underline"] = true }
            if undercurl { spec["undercurl"] = true }
            return spec
        }
        func syn(_ style: SyntaxStyle) -> [String: Any] {
            hl(fg: style.color, bold: style.bold, italic: style.italic, underline: style.underline)
        }
        func tint(_ c: RGBA, _ amount: Double) -> RGBA { c.mixed(over: bg, amount: amount) }
        func link(_ target: String) -> [String: Any] { ["link": target] }

        var g: [String: Any] = [
            "Normal": hl(fg: ui.foreground, bg: bg), "NormalNC": hl(fg: ui.foreground, bg: bg),
            "NormalFloat": hl(fg: ui.foreground, bg: ui.overlay), "FloatBorder": hl(fg: ui.border, bg: ui.overlay),
            "FloatTitle": hl(fg: ui.accent, bg: ui.overlay, bold: true),
            "ColorColumn": hl(bg: ui.surface), "CursorLine": hl(bg: ui.currentLine), "CursorColumn": hl(bg: ui.currentLine),
            "CursorLineNr": hl(fg: ui.accent, bold: true), "LineNr": hl(fg: tint(ui.muted, 0.7)),
            "SignColumn": hl(bg: bg), "FoldColumn": hl(fg: ui.muted), "Folded": hl(fg: ui.muted, bg: ui.surface),
            "Cursor": hl(fg: bg, bg: ui.cursor), "lCursor": link("Cursor"), "TermCursor": link("Cursor"),
            "Visual": hl(bg: ui.selection), "VisualNOS": link("Visual"),
            "Search": hl(fg: ui.foreground, bg: ui.search), "IncSearch": hl(fg: bg, bg: ui.accent), "CurSearch": link("IncSearch"),
            "Substitute": hl(fg: bg, bg: ui.error), "MatchParen": hl(fg: ui.accent, bg: tint(ui.selection, 0.8), bold: true),
            "Pmenu": hl(fg: ui.foreground, bg: ui.overlay), "PmenuSel": hl(fg: ui.foreground, bg: ui.selection, bold: true),
            "PmenuSbar": hl(bg: ui.surface), "PmenuThumb": hl(bg: ui.border),
            "StatusLine": hl(fg: ui.foreground, bg: ui.surface), "StatusLineNC": hl(fg: ui.muted, bg: ui.surface),
            "TabLine": hl(fg: ui.muted, bg: ui.surface), "TabLineSel": hl(fg: ui.foreground, bg: bg, bold: true), "TabLineFill": hl(bg: ui.surface),
            "WinSeparator": hl(fg: ui.border), "VertSplit": link("WinSeparator"), "WinBar": hl(fg: ui.foreground), "WinBarNC": hl(fg: ui.muted),
            "NonText": hl(fg: ui.border), "Whitespace": hl(fg: ui.border), "SpecialKey": hl(fg: ui.border), "EndOfBuffer": hl(fg: bg),
            "Directory": hl(fg: s.function.color), "Title": hl(fg: ui.accent, bold: true), "Question": hl(fg: ui.success),
            "MoreMsg": hl(fg: ui.success), "ModeMsg": hl(fg: ui.foreground, bold: true), "ErrorMsg": hl(fg: ui.error), "WarningMsg": hl(fg: ui.warning),
            "WildMenu": hl(bg: ui.selection), "QuickFixLine": hl(bg: ui.selection), "Conceal": hl(fg: ui.muted),
            "SpellBad": hl(sp: ui.error, undercurl: true), "SpellCap": hl(sp: ui.warning, undercurl: true),
            "SpellRare": hl(sp: ui.info, undercurl: true), "SpellLocal": hl(sp: ui.info, undercurl: true),
            "DiffAdd": hl(bg: tint(s.added.color, 0.2)), "DiffChange": hl(bg: tint(s.changed.color, 0.15)),
            "DiffDelete": hl(fg: s.removed.color, bg: tint(s.removed.color, 0.2)), "DiffText": hl(bg: tint(s.changed.color, 0.35)),
            "Added": hl(fg: s.added.color), "Changed": hl(fg: s.changed.color), "Removed": hl(fg: s.removed.color),
            "diffAdded": link("Added"), "diffRemoved": link("Removed"), "diffChanged": link("Changed"),
            // Legacy syntax groups.
            "Comment": syn(s.comment), "Constant": syn(s.constant), "String": syn(s.string), "Character": syn(s.string),
            "Number": syn(s.number), "Boolean": syn(s.constant), "Float": syn(s.number), "Identifier": syn(s.variable),
            "Function": syn(s.function), "Statement": syn(s.keyword), "Conditional": syn(s.keyword), "Repeat": syn(s.keyword),
            "Label": syn(s.keyword), "Operator": syn(s.operator), "Keyword": syn(s.keyword), "Exception": syn(s.keyword),
            "PreProc": syn(s.attribute), "Include": syn(s.keyword), "Define": syn(s.keyword), "Macro": syn(s.attribute),
            "PreCondit": syn(s.attribute), "Type": syn(s.type), "StorageClass": syn(s.keyword), "Structure": syn(s.type),
            "Typedef": syn(s.type), "Special": syn(s.escape), "SpecialChar": syn(s.escape), "Tag": syn(s.tag),
            "Delimiter": syn(s.punctuation), "SpecialComment": syn(s.comment), "Debug": hl(fg: ui.warning),
            "Underlined": hl(fg: ui.accent, underline: true), "Error": hl(fg: ui.error), "Todo": hl(fg: bg, bg: ui.warning, bold: true),
            // Tree-sitter captures.
            "@comment": link("Comment"), "@comment.documentation": link("Comment"), "@comment.error": hl(fg: ui.error, bold: true),
            "@comment.warning": hl(fg: ui.warning, bold: true), "@comment.todo": link("Todo"), "@comment.note": hl(fg: ui.info, bold: true),
            "@keyword": syn(s.keyword), "@keyword.function": syn(s.keyword), "@keyword.return": syn(s.keyword),
            "@keyword.operator": syn(s.keyword), "@keyword.import": syn(s.keyword), "@operator": syn(s.operator),
            "@punctuation.delimiter": syn(s.punctuation), "@punctuation.bracket": syn(s.punctuation), "@punctuation.special": syn(s.escape),
            "@string": syn(s.string), "@string.escape": syn(s.escape), "@string.regexp": syn(s.escape), "@string.special": syn(s.escape),
            "@character": syn(s.string), "@number": syn(s.number), "@number.float": syn(s.number), "@boolean": syn(s.constant),
            "@constant": syn(s.constant), "@constant.builtin": syn(s.builtin), "@constant.macro": syn(s.attribute),
            "@function": syn(s.function), "@function.call": syn(s.function), "@function.method": syn(s.function),
            "@function.method.call": syn(s.function), "@function.builtin": syn(s.builtin), "@function.macro": syn(s.attribute),
            "@constructor": syn(s.type), "@type": syn(s.type), "@type.definition": syn(s.type), "@type.builtin": syn(s.builtin),
            "@module": syn(s.type), "@label": syn(s.keyword), "@variable": syn(s.variable), "@variable.builtin": syn(s.builtin),
            "@variable.parameter": syn(s.parameter), "@variable.member": syn(s.property), "@property": syn(s.property),
            "@attribute": syn(s.attribute), "@tag": syn(s.tag), "@tag.attribute": syn(s.attribute), "@tag.delimiter": syn(s.punctuation),
            "@markup.heading": hl(fg: ui.accent, bold: true), "@markup.strong": hl(bold: true), "@markup.italic": hl(italic: true),
            "@markup.link": hl(fg: ui.accent, underline: true), "@markup.link.url": hl(fg: ui.accent, underline: true),
            "@markup.raw": syn(s.string), "@markup.list": syn(s.punctuation), "@markup.quote": syn(s.comment),
            "@diff.plus": link("Added"), "@diff.minus": link("Removed"), "@diff.delta": link("Changed"),
            // Diagnostics.
            "DiagnosticError": hl(fg: ui.error), "DiagnosticWarn": hl(fg: ui.warning), "DiagnosticInfo": hl(fg: ui.info),
            "DiagnosticHint": hl(fg: ui.accent), "DiagnosticOk": hl(fg: ui.success),
            "DiagnosticUnderlineError": hl(sp: ui.error, undercurl: true), "DiagnosticUnderlineWarn": hl(sp: ui.warning, undercurl: true),
            "DiagnosticUnderlineInfo": hl(sp: ui.info, undercurl: true), "DiagnosticUnderlineHint": hl(sp: ui.accent, undercurl: true),
            "DiagnosticVirtualTextError": hl(fg: ui.error, bg: tint(ui.error, 0.1)), "DiagnosticVirtualTextWarn": hl(fg: ui.warning, bg: tint(ui.warning, 0.1)),
            "DiagnosticVirtualTextInfo": hl(fg: ui.info, bg: tint(ui.info, 0.1)), "DiagnosticVirtualTextHint": hl(fg: ui.accent, bg: tint(ui.accent, 0.1)),
            // Common plugins.
            "GitSignsAdd": link("Added"), "GitSignsChange": link("Changed"), "GitSignsDelete": link("Removed"),
            "TelescopeNormal": link("NormalFloat"), "TelescopeBorder": link("FloatBorder"),
            "TelescopeSelection": hl(bg: ui.selection), "TelescopeMatching": hl(fg: ui.accent, bold: true),
        ]
        g["LspReferenceText"] = hl(bg: tint(ui.selection, 0.6))
        g["LspReferenceRead"] = hl(bg: tint(ui.selection, 0.6))
        g["LspReferenceWrite"] = hl(bg: tint(ui.selection, 0.8))
        return g
    }

    /// The fixed shim. `dataPath` is Scene's own support path, never theme data.
    public static func shim(dataPath: String) throws -> String {
        guard !dataPath.contains("]==]"), !dataPath.contains("\n") else { throw SceneError.invalid("unsupported data path") }
        return """
        -- Managed by Scene (plugin/scene.lua). Scene overwrites this file.
        -- It applies the theme that Scene selected and reloads it when Scene changes it.
        -- To detach, use Restore in Scene, or delete this file and colors/scene.lua.
        local data_path = [==[\(dataPath)]==]
        local uv = vim.uv or vim.loop
        local state = { previous = nil, applied = false, busy = false }

        local function read()
          local file = io.open(data_path, "r")
          if not file then return nil end
          local text = file:read("*a")
          file:close()
          local ok, data = pcall(vim.json.decode, text)
          if ok and type(data) == "table" then return data end
          return nil
        end

        local function restore_previous()
          if not state.applied then return end
          state.applied = false
          if vim.g.colors_name == "scene" then
            vim.cmd("highlight clear")
            if state.previous and state.previous ~= "scene" then pcall(vim.cmd.colorscheme, state.previous) end
          end
        end

        local function apply()
          if state.busy then return end
          state.busy = true
          local ok, err = pcall(function()
            local data = read()
            if not data or type(data.variants) ~= "table" then restore_previous() return end
            if not state.applied and vim.g.colors_name ~= "scene" then state.previous = vim.g.colors_name end
            local mode = vim.o.background
            if data.variants[mode] == nil then
              mode = data.variants.dark and "dark" or "light"
              if vim.o.background ~= mode then vim.o.background = mode end
            end
            local variant = data.variants[mode]
            local prefer = type(data.prefer) == "table" and data.prefer[mode] or nil
            if prefer and pcall(vim.cmd.colorscheme, prefer) then state.applied = true return end
            vim.cmd("highlight clear")
            if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
            vim.g.colors_name = "scene"
            for name, spec in pairs(variant.groups or {}) do vim.api.nvim_set_hl(0, name, spec) end
            for index, color in ipairs(variant.terminal or {}) do vim.g["terminal_color_" .. (index - 1)] = color end
            state.applied = true
          end)
          state.busy = false
          if not ok then vim.notify("Scene: " .. tostring(err), vim.log.levels.WARN) end
        end

        _G.SceneApplyTheme = apply

        local function watch()
          local dir = vim.fs.dirname(data_path)
          if vim.fn.isdirectory(dir) == 0 then return end
          local handle = uv.new_fs_event()
          if not handle then return end
          handle:start(dir, {}, vim.schedule_wrap(function() apply() end))
        end

        apply()
        watch()

        """
    }

    /// `colors/scene.lua`, so `:colorscheme scene` and background changes re-apply the Scene theme.
    public static let colorsFile = """
    -- Managed by Scene. Scene overwrites this file.
    if _G.SceneApplyTheme then _G.SceneApplyTheme() end

    """
}
