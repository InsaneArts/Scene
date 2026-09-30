# The draft

`draft.json` sits next to the `images/` folder. Scene reads it with `--check-theme` and `--build-theme`. A relative `file` is relative to the draft.

```json
{
  "name": "Night Kiln",
  "summary": "Embers glowing in a dark workshop.",
  "author": "Ada Lovelace",
  "tags": ["dark", "orange", "warm"],
  "dark": {
    "colors": {
      "background": "#14100c", "dark_background": "#0e0b08", "lighter_background": "#1f1813",
      "foreground": "#f0d9bd", "dark_foreground": "#9c8570", "bright_foreground": "#fff0dc",
      "muted": "#4a3a2c", "selection": "#3d2a17", "accent": "#ff9f43",
      "red": "#ef7b6a", "orange": "#f59b5b", "yellow": "#e8c15c", "green": "#a8c96e",
      "cyan": "#5fcfc2", "blue": "#6cb1e6", "magenta": "#dd8bbd",
      "bright_red": "#ff8f7e", "bright_yellow": "#f9d36e", "bright_green": "#bbdc80",
      "bright_cyan": "#72e2d5", "bright_blue": "#80c4f9", "bright_magenta": "#f09ed0"
    },
    "accentColor": "orange",
    "iconStyle": "tinted",
    "iconTint": "accent",
    "wallpapers": [
      { "file": "images/dark-1.jpg", "attribution": "NASA", "source": "https://images.nasa.gov/details/..." },
      { "file": "images/dark-2.jpg", "attribution": "Generated with <tool>" },
      { "file": "images/dark-3.jpg" }
    ]
  },
  "light": { "colors": { }, "wallpapers": [ ] }
}
```

- `name`: at most 64 characters. `name` and `author` make the theme's id, so building again with the same two replaces the installed theme.
- `dark`, `light`: either or both. Leave a look out entirely rather than empty.
- `version` is optional (default `1.0.0`).

## Colors: what each key paints

All values are `#rrggbb`. The nine **required** keys are marked; Scene mixes the others from them when they are missing, but a theme that sets all twenty-two looks deliberate.

| Key | Paints |
|---|---|
| `background` (required) | Terminal and editor background, ANSI black |
| `foreground` (required) | Text, ANSI white |
| `accent` (required) | The signature color: focus rings, links, the active tab, tmux's current window, borders of the focused window, and the macOS accent when `accentColor` is `auto` |
| `selection` | Selected text |
| `dark_background` | Sidebars, title bars, status bars |
| `lighter_background` | Popups, the current line |
| `muted` | Borders, ANSI bright black |
| `dark_foreground` | Comments (italic), line numbers, punctuation |
| `bright_foreground` | The cursor, ANSI bright white |
| `red` (required) | Errors, tags, removed lines |
| `orange` | Numbers and constants |
| `yellow` (required) | Types, warnings, changed lines |
| `green` (required) | Strings, added lines |
| `cyan` (required) | Built-ins, properties, parameters |
| `blue` (required) | Functions |
| `magenta` (required) | ANSI magenta; `bright_magenta` paints keywords |
| `bright_*` (red, yellow, green, cyan, blue, magenta) | The bright ANSI colors. `bright_blue` also paints operators |

## macOS look

| Field | Values | Default |
|---|---|---|
| `accentColor` | `auto` (the macOS preset nearest `accent`), or `multicolor`, `graphite`, `red`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink` | `auto` |
| `iconStyle` | `default`, `dark`, `clear`, `tinted` | `default` |
| `iconTint` | With `tinted` only: `accent`, a preset name, or `#rrggbb` | none |

A dark look usually takes `dark` icons, or `tinted` with `iconTint: "accent"` when the theme is about one color. A light look takes `default`.

## Wallpapers

Exactly three per look, in order; the first is the default. Each has `file`. The credits are optional: `attribution` says who made the image, and `source` is the page it came from. The README lists them. [WALLPAPERS.md](WALLPAPERS.md) says what to put in `attribution` for each route.

## What the checker reports

Errors block the build. The palette errors are contrast ratios on the background (WCAG):

| Pair | Error below | Warning below |
|---|---|---|
| Text on Background | 4.5 | 7 |
| Dim text on Background | 2.2 | 3 |
| Accent on Background | 2.5 | 3 |
| Text on Selection | 3.5 | 4.5 |
| Each hue on Background, dark look | 3 | 4.5 |
| Each hue on Background, light look | 2 | 3 |

It also errors when a dark look has a light background (or the other way round), and warns when two hues look alike or a hue has no color.
