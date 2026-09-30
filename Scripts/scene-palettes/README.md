# Scene palettes

Scene's own themes, one folder each. `Scripts/make-bundled-themes.py` turns every folder into `Themes/<folder>/theme.json`.

```
<folder>/theme.toml   name, summary, tags, and credits
<folder>/dark.toml    the dark look, if the theme has one
<folder>/light.toml   the light look, if the theme has one
```

Every value is a quoted string, one `key = "value"` per line.

`theme.toml`:

| Key | Needed | Meaning |
|---|---|---|
| `name` | yes | The name people see, one or two words |
| `summary` | yes | One line: what it looks like, not what it is |
| `tags` | no | Comma-separated, for example `dark, green, retro` |
| `author`, `author_url` | no | Credits. The default author is Scene |
| `license` | no | SPDX id of the palette. The default is `MIT` |
| `homepage` | no | For a theme ported from another project |
| `nvim` | no | A Neovim colorscheme to use when the person has it installed |

`dark.toml` and `light.toml` use the keys of Omarchy's `colors.toml`: `background`, `foreground`, `accent`, `red`, `green`, `yellow`, `blue`, `magenta`, and `cyan` are needed. `orange`, `selection`, `muted`, `dark_background`, `lighter_background`, `dark_foreground`, `bright_foreground`, and `bright_<color>` are filled in when missing. Three more keys set the macOS look: `accent_color` (`auto`, or a preset such as `green`), `icon_style` (`dark`, `default`, `clear`, or `tinted`), and `icon_tint` (`accent`, a preset, or `#hex`). The light look always uses the default icon style.

Check a palette with `python3 Scripts/check-palette.py --table <folder>/dark.toml`.
