import Foundation
import SceneThemes
import SceneFoundation

/// Renders Emacs themes (`scene-dark-theme.el`, `scene-light-theme.el`) and a fixed loader for Doom Emacs.
/// Every value in a theme is a formatted `RGBA` or a fixed face attribute. Theme names appear only in comments.
public enum EmacsRenderer {
    public static let names: [Appearance: String] = [.dark: "scene-dark", .light: "scene-light"]
    public static let loaderName = "scene.el"

    /// `slot` names the theme and its file. It can differ from the variant's look: a theme with one look fills both slots.
    public static func themeFile(_ v: ResolvedVariant, slot: Appearance) -> String {
        let ui = v.interface, t = v.terminal, s = v.syntax, bg = ui.background
        let name = names[slot]!
        func q(_ c: RGBA) -> String { "\"\(c.hex)\"" }
        func tint(_ c: RGBA, _ amount: Double) -> RGBA { c.mixed(over: bg, amount: amount) }
        func face(_ name: String, fg: RGBA? = nil, bg b: RGBA? = nil, bold: Bool = false, italic: Bool = false,
                  underline: RGBA? = nil, wave: Bool = false, box: RGBA? = nil, inherit: String? = nil) -> String {
            var parts: [String] = []
            if let fg { parts.append(":foreground \(q(fg))") }
            if let b { parts.append(":background \(q(b))") }
            if bold { parts.append(":weight bold") }
            if italic { parts.append(":slant italic") }
            if let underline { parts.append(wave ? ":underline (:color \(q(underline)) :style wave)" : ":underline \(q(underline))") }
            if let box { parts.append(":box (:line-width 1 :color \(q(box)))") }
            if let inherit { parts.append(":inherit \(inherit)") }
            return "   '(\(name) ((t (\(parts.joined(separator: " "))))))"
        }
        func syn(_ name: String, _ st: SyntaxStyle) -> String {
            face(name, fg: st.color, bold: st.bold, italic: st.italic, underline: st.underline ? st.color : nil)
        }
        let faces: [String] = [
            face("default", fg: ui.foreground, bg: bg), face("cursor", bg: ui.cursor), face("region", bg: ui.selection),
            face("secondary-selection", bg: tint(ui.selection, 0.6)), face("highlight", bg: ui.currentLine),
            face("hl-line", bg: ui.currentLine), face("fringe", fg: ui.muted, bg: bg), face("shadow", fg: ui.muted),
            face("escape-glyph", fg: s.escape.color), face("minibuffer-prompt", fg: ui.accent, bold: true),
            face("link", fg: ui.accent, underline: ui.accent), face("link-visited", fg: s.keyword.color, underline: s.keyword.color),
            face("button", fg: ui.accent, underline: ui.accent), face("match", fg: ui.foreground, bg: ui.search),
            face("isearch", fg: bg, bg: ui.accent, bold: true), face("lazy-highlight", fg: ui.foreground, bg: ui.search),
            face("isearch-fail", fg: bg, bg: ui.error), face("show-paren-match", fg: ui.accent, bg: tint(ui.selection, 0.8), bold: true),
            face("show-paren-mismatch", fg: bg, bg: ui.error), face("trailing-whitespace", bg: ui.error),
            face("line-number", fg: tint(ui.muted, 0.7), bg: bg), face("line-number-current-line", fg: ui.accent, bg: ui.currentLine, bold: true),
            face("vertical-border", fg: ui.border), face("window-divider", fg: ui.border), face("window-divider-first-pixel", fg: ui.border),
            face("window-divider-last-pixel", fg: ui.border), face("border", bg: ui.border), face("internal-border", bg: bg),
            face("mode-line", fg: ui.foreground, bg: ui.surface, box: ui.surface),
            face("mode-line-inactive", fg: ui.muted, bg: ui.surface, box: ui.surface),
            face("mode-line-emphasis", fg: ui.accent, bold: true), face("mode-line-highlight", fg: ui.accent),
            face("header-line", fg: ui.foreground, bg: ui.surface), face("tab-bar", fg: ui.muted, bg: ui.surface),
            face("tab-bar-tab", fg: ui.foreground, bg: bg, bold: true), face("tab-bar-tab-inactive", fg: ui.muted, bg: ui.surface),
            face("tooltip", fg: ui.foreground, bg: ui.overlay), face("menu", fg: ui.foreground, bg: ui.overlay),
            face("tool-bar", fg: ui.foreground, bg: ui.surface), face("scroll-bar", fg: ui.border, bg: bg),
            face("error", fg: ui.error, bold: true), face("warning", fg: ui.warning, bold: true), face("success", fg: ui.success, bold: true),
            face("completions-common-part", fg: ui.accent, bold: true), face("completions-first-difference", fg: ui.foreground, bold: true),
            // Font lock.
            syn("font-lock-comment-face", s.comment), syn("font-lock-comment-delimiter-face", s.comment),
            syn("font-lock-doc-face", s.comment), syn("font-lock-string-face", s.string),
            syn("font-lock-keyword-face", s.keyword), syn("font-lock-builtin-face", s.builtin),
            syn("font-lock-function-name-face", s.function), syn("font-lock-function-call-face", s.function),
            syn("font-lock-variable-name-face", s.variable), syn("font-lock-variable-use-face", s.variable),
            syn("font-lock-type-face", s.type), syn("font-lock-constant-face", s.constant),
            syn("font-lock-number-face", s.number), syn("font-lock-operator-face", s.operator),
            syn("font-lock-property-name-face", s.property), syn("font-lock-property-use-face", s.property),
            syn("font-lock-punctuation-face", s.punctuation), syn("font-lock-bracket-face", s.punctuation),
            syn("font-lock-delimiter-face", s.punctuation), syn("font-lock-escape-face", s.escape),
            syn("font-lock-regexp-face", s.escape), syn("font-lock-regexp-grouping-backslash", s.escape),
            syn("font-lock-regexp-grouping-construct", s.escape), syn("font-lock-preprocessor-face", s.attribute),
            syn("font-lock-negation-char-face", s.operator), syn("font-lock-warning-face", SyntaxStyle(color: ui.warning)),
            // Diffs, Magit, diff-hl.
            face("diff-added", fg: s.added.color, bg: tint(s.added.color, 0.2)), face("diff-removed", fg: s.removed.color, bg: tint(s.removed.color, 0.2)),
            face("diff-changed", fg: s.changed.color, bg: tint(s.changed.color, 0.15)),
            face("diff-refine-added", bg: tint(s.added.color, 0.35)), face("diff-refine-removed", bg: tint(s.removed.color, 0.35)),
            face("diff-header", fg: ui.muted, bg: ui.surface), face("diff-file-header", fg: ui.foreground, bg: ui.surface, bold: true),
            face("diff-hunk-header", fg: ui.accent, bg: ui.surface),
            face("diff-hl-insert", fg: s.added.color, bg: s.added.color), face("diff-hl-delete", fg: s.removed.color, bg: s.removed.color),
            face("diff-hl-change", fg: s.changed.color, bg: s.changed.color),
            face("magit-section-heading", fg: ui.accent, bold: true), face("magit-section-highlight", bg: ui.currentLine),
            face("magit-branch-local", fg: s.function.color), face("magit-branch-remote", fg: s.string.color),
            face("magit-diff-added", fg: s.added.color, bg: tint(s.added.color, 0.15)),
            face("magit-diff-added-highlight", fg: s.added.color, bg: tint(s.added.color, 0.25)),
            face("magit-diff-removed", fg: s.removed.color, bg: tint(s.removed.color, 0.15)),
            face("magit-diff-removed-highlight", fg: s.removed.color, bg: tint(s.removed.color, 0.25)),
            face("magit-diff-hunk-heading", fg: ui.foreground, bg: ui.surface),
            face("magit-diff-hunk-heading-highlight", fg: ui.foreground, bg: ui.overlay),
            // Diagnostics (Flycheck, Flymake).
            face("flycheck-error", underline: ui.error, wave: true), face("flycheck-warning", underline: ui.warning, wave: true),
            face("flycheck-info", underline: ui.info, wave: true),
            face("flymake-error", underline: ui.error, wave: true), face("flymake-warning", underline: ui.warning, wave: true),
            face("flymake-note", underline: ui.info, wave: true),
            // Completion and search UIs: Vertico, Corfu, Company, Ivy, Consult, Orderless.
            face("vertico-current", bg: ui.selection, bold: true), face("corfu-default", fg: ui.foreground, bg: ui.overlay),
            face("corfu-current", fg: ui.foreground, bg: ui.selection), face("corfu-border", bg: ui.border),
            face("company-tooltip", fg: ui.foreground, bg: ui.overlay), face("company-tooltip-selection", bg: ui.selection),
            face("company-tooltip-common", fg: ui.accent, bold: true), face("company-scrollbar-bg", bg: ui.surface),
            face("company-scrollbar-fg", bg: ui.border), face("ivy-current-match", bg: ui.selection, bold: true),
            face("orderless-match-face-0", fg: ui.accent, bold: true), face("orderless-match-face-1", fg: s.function.color, bold: true),
            face("orderless-match-face-2", fg: s.string.color, bold: true), face("orderless-match-face-3", fg: s.type.color, bold: true),
            // Org and Markdown.
            face("org-level-1", fg: ui.accent, bold: true), face("org-level-2", fg: s.function.color, bold: true),
            face("org-level-3", fg: s.string.color, bold: true), face("org-level-4", fg: s.type.color),
            face("org-level-5", fg: s.keyword.color), face("org-level-6", fg: s.constant.color),
            face("org-level-7", fg: s.property.color), face("org-level-8", fg: s.attribute.color),
            face("org-todo", fg: ui.warning, bold: true), face("org-done", fg: ui.success, bold: true),
            face("org-link", fg: ui.accent, underline: ui.accent), face("org-code", fg: s.string.color), face("org-verbatim", fg: s.string.color),
            face("org-block", bg: ui.surface), face("org-block-begin-line", fg: ui.muted, bg: ui.surface), face("org-block-end-line", fg: ui.muted, bg: ui.surface),
            face("markdown-header-face", fg: ui.accent, bold: true), face("markdown-code-face", fg: s.string.color),
            face("markdown-inline-code-face", fg: s.string.color), face("markdown-link-face", fg: ui.accent),
            face("markdown-url-face", fg: ui.muted),
            // Doom and Treemacs.
            face("doom-modeline-bar", bg: ui.accent), face("doom-modeline-buffer-file", fg: ui.foreground, bold: true),
            face("doom-modeline-project-dir", fg: ui.accent, bold: true), face("doom-modeline-info", fg: ui.success),
            face("doom-modeline-warning", fg: ui.warning), face("doom-modeline-urgent", fg: ui.error),
            face("treemacs-root-face", fg: ui.accent, bold: true), face("treemacs-directory-face", fg: s.function.color),
            face("treemacs-file-face", fg: ui.foreground), face("treemacs-git-modified-face", fg: s.changed.color),
            face("treemacs-git-added-face", fg: s.added.color), face("treemacs-git-untracked-face", fg: ui.muted),
            face("dired-directory", fg: s.function.color), face("dired-header", fg: ui.accent, bold: true),
            face("dired-symlink", fg: s.constant.color), face("dired-marked", fg: ui.warning, bold: true),
            // Terminals inside Emacs.
        ] + ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"].enumerated().flatMap { i, color in
            [face("ansi-color-\(color)", fg: t.ansi[i], bg: t.ansi[i]), face("ansi-color-bright-\(color)", fg: t.ansi[i + 8], bg: t.ansi[i + 8]),
             face("term-color-\(color)", fg: t.ansi[i], bg: t.ansi[i])]
        }
        let header = "Managed by Scene: \(ThemeLoader.sanitized(v.themeName)) \(ThemeLoader.sanitized(v.themeVersion)) (\(v.appearance.rawValue)). Scene overwrites this file."
        // The first line stays fixed: Emacs reads file-local variables from a `-*- … -*-` pair on it, so theme text there
        // could set some. The second line is only a comment.
        return """
        ;;; \(name)-theme.el --- Generated by Scene.  -*- lexical-binding: t; -*-
        ;; \(header)

        (deftheme \(name) "\(v.appearance.rawValue.capitalized) theme generated by Scene.")

        (custom-theme-set-faces
         '\(name)
        \(faces.joined(separator: "\n"))
         )

        (custom-theme-set-variables
         '\(name)
         '(ansi-color-names-vector [\(q(t.ansi[0])) \(q(t.ansi[1])) \(q(t.ansi[2])) \(q(t.ansi[3])) \(q(t.ansi[4])) \(q(t.ansi[5])) \(q(t.ansi[6])) \(q(t.ansi[7]))]))

        (provide-theme '\(name))

        ;;; \(name)-theme.el ends here

        """
    }

    /// The fixed loader. `folder` is Scene's own path, never theme data. `forced` is `light`, `dark`, or nil to follow macOS.
    public static func loader(folder: String, forced: Appearance?) throws -> String {
        guard !folder.contains("\""), !folder.contains("\\"), !folder.contains("\n") else { throw SceneError.invalid("unsupported theme folder") }
        return """
        ;;; scene.el --- Managed by Scene. Scene overwrites this file.  -*- lexical-binding: t; -*-
        ;; Loads scene-dark or scene-light. To detach, use Restore in Scene.

        (add-to-list 'custom-theme-load-path "\(folder)")

        (defvar scene-theme-forced \(forced.map { "'\($0.rawValue)" } ?? "nil")
          "`light' or `dark' when Scene pins one look, nil to follow macOS.")

        (defun scene-theme-name (&optional appearance)
          "The Scene theme for APPEARANCE (`light' or `dark'), or for the current look."
          (let ((look (or appearance
                          scene-theme-forced
                          (if (string-match-p "Dark" (or (ignore-errors (shell-command-to-string "defaults read -g AppleInterfaceStyle")) ""))
                              'dark
                            'light))))
            (if (eq look 'dark) 'scene-dark 'scene-light)))

        (defun scene-theme-apply (&optional appearance)
          "Load Scene's theme for APPEARANCE, or for the current look."
          (interactive)
          (let ((theme (scene-theme-name appearance)))
            (mapc #'disable-theme (remove theme custom-enabled-themes))
            (disable-theme theme)
            (load-theme theme t)))

        (when (and (null scene-theme-forced) (boundp 'ns-system-appearance-change-functions))
          (add-hook 'ns-system-appearance-change-functions #'scene-theme-apply))

        ;; Hooks of the user's own that load a theme at startup run first; Scene's runs last (depth 90).
        (add-hook 'doom-init-ui-hook #'scene-theme-apply 90)

        (provide 'scene)
        ;;; scene.el ends here

        """
    }

    /// Lisp for a running Emacs: load the loader, then apply. Safe to run again after the files change.
    public static func reloadExpression(folder: String) -> String {
        "(progn (load \"\(folder)/\(loaderName)\" nil t) (scene-theme-apply))"
    }

    /// Lisp for a running Emacs after a restore: drop Scene's themes and bring back Doom's own.
    public static let restoreExpression =
        "(progn (mapc #'disable-theme '(scene-dark scene-light)) (when (and (boundp 'doom-theme) doom-theme) (load-theme doom-theme t)))"
}
