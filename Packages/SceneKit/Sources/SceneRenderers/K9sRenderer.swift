import SceneThemes

/// A k9s skin file. Every color is a quoted hex value formatted from parsed colors. Backgrounds that sit on the
/// terminal use `default`, so they follow the terminal's own background.
public enum K9sRenderer {
    public static func skin(_ v: ResolvedVariant) -> String {
        let ui = v.interface, ansi = v.terminal.ansi
        func q(_ color: RGBA) -> String { "\"\(color.hex)\"" }
        let (fg, bg, accent, muted) = (q(ui.foreground), q(ui.background), q(ui.accent), q(ui.muted))
        let (success, warning, error) = (q(ui.success), q(ui.warning), q(ui.error))
        let (selection, line, border) = (q(ui.selection), q(ui.currentLine), q(ui.border))
        let blue = q(ansi[4])
        return """
        # Scene theme for k9s. Scene rewrites this file on every apply.
        k9s:
          body:
            fgColor: \(fg)
            bgColor: default
            logoColor: \(accent)
          prompt:
            fgColor: \(fg)
            bgColor: \(bg)
            suggestColor: \(warning)
          info:
            fgColor: \(accent)
            sectionColor: \(fg)
          dialog:
            fgColor: \(fg)
            bgColor: default
            buttonFgColor: \(fg)
            buttonBgColor: \(blue)
            buttonFocusFgColor: \(bg)
            buttonFocusBgColor: \(accent)
            labelFgColor: \(muted)
            fieldFgColor: \(fg)
          frame:
            border:
              fgColor: \(border)
              focusColor: \(accent)
            menu:
              fgColor: \(fg)
              keyColor: \(success)
              numKeyColor: \(success)
            crumbs:
              fgColor: \(bg)
              bgColor: \(accent)
              activeColor: \(success)
            status:
              newColor: \(accent)
              modifyColor: \(blue)
              addColor: \(success)
              errorColor: \(error)
              highlightColor: \(warning)
              killColor: \(muted)
              completedColor: \(muted)
            title:
              fgColor: \(fg)
              bgColor: default
              highlightColor: \(accent)
              counterColor: \(success)
              filterColor: \(success)
          views:
            charts:
              bgColor: default
              defaultDialColors:
                - \(accent)
                - \(success)
              defaultChartColors:
                - \(accent)
                - \(success)
            table:
              fgColor: \(fg)
              bgColor: default
              cursorFgColor: \(fg)
              cursorBgColor: \(line)
              markColor: \(warning)
              header:
                fgColor: \(fg)
                bgColor: default
                sorterColor: \(accent)
            xray:
              fgColor: \(fg)
              bgColor: default
              cursorColor: \(line)
              graphicColor: \(accent)
              showIcons: false
            yaml:
              keyColor: \(accent)
              colonColor: \(blue)
              valueColor: \(fg)
            logs:
              fgColor: \(fg)
              bgColor: default
              indicator:
                fgColor: \(fg)
                bgColor: \(selection)
            help:
              fgColor: \(fg)
              bgColor: default
              indicator:
                fgColor: \(success)
                bgColor: \(selection)

        """
    }
}
