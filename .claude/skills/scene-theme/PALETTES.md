# Palettes

## What each key paints

`Scripts/make-bundled-themes.py` (`variant()`) maps the keys to Scene's roles. The code colors follow from the hues, so pick them with the editor in mind.

| Key | Paints |
|---|---|
| `background` | Terminal and editor background, ANSI black |
| `dark_background` | Sidebars and title bars |
| `lighter_background` | The current line, overlays |
| `selection` | Selected text |
| `muted` | Borders, ANSI bright black |
| `dark_foreground` | Comments (italic), line numbers, punctuation |
| `foreground` | Text, ANSI white |
| `bright_foreground` | The cursor, ANSI bright white |
| `accent` | The signature color: focus, links, the Apply button, the macOS accent when `accent_color` is `auto` |
| `red` | Errors, tags, removed lines |
| `orange` | Numbers and constants |
| `yellow` | Types, warnings, changed lines |
| `green` | Strings, added lines |
| `cyan` | Built-ins, properties, parameters |
| `blue` | Functions |
| `magenta`, `bright_magenta` | Keywords (`bright_magenta`) |
| `bright_blue` | Operators |

## Build it in OKLCH

Write colors as `from_oklch(lightness, chroma, hue)` from `Scripts/themekit.py`, which clips them into sRGB, and read them back with `check-palette.py --table`. Lightness is what makes a palette calm: hues at the same lightness read as a set, and one hue brighter than the rest shouts.

1. Start from the concept's two colors: the ground (`background`) and the signature (`accent`).
2. Dark look: `background` at L 0.16 to 0.26 with chroma up to 0.04, tinted toward the concept's hue. Then `dark_background` about 0.03 darker, `lighter_background` 0.04 lighter, `selection` 0.08 to 0.14 lighter with some accent in it, `muted` near 0.40, `dark_foreground` 0.55 to 0.62, `foreground` 0.84 to 0.90, `bright_foreground` 0.92 to 0.96.
3. Hues at L 0.70 to 0.84 and chroma 0.08 to 0.18, within about 0.06 lightness of each other and at least 30° of hue apart. Orange sits between red and yellow. Brights are 0.04 to 0.08 lighter.
4. Light look: the same hue angles, `background` at L 0.95 to 0.98 (paper, a little warm or cool), `foreground` 0.25 to 0.35, hues at L 0.45 to 0.58 with a little more chroma. Yellow and cyan go darkest, because they fade first on white.
5. `accent` is usually one of the hues, pushed a little in chroma. It must hold 3:1 on the background.

A monochrome concept (a green phosphor tube, an amber terminal) keeps one hue on purpose: step the lightness of the six hues instead, and pass `--mono` to the checker. Keep red readable as the error color even then.

## The macOS look

In `dark.toml` or `light.toml`: `accent_color` is `auto` (the nearest macOS preset to `accent`) or a preset name: multicolor, graphite, red, orange, yellow, green, blue, purple, pink. For a dark look, `icon_style` is `dark` for most themes, or `tinted` with `icon_tint = "accent"` for a theme that is about one color. A light look always gets the default icons.

## Names

A theme's name is one or two plain words that evoke the look: a material, a place, a technique, a time of day, an era of computing (Phosphor, Blueprint, Greenbar, Safelight). The name belongs to nobody: a product, a company, a film, a series, a game, a band, a character, and a living person are all off the table, and so are their logos and look-alikes in the wallpapers. Plain words that are also well-known software count as products: Chrome, Signal, Darkroom, Regolith, and Mission Control (a macOS feature) were all renamed for that reason. When unsure, pick the generic word for the thing (Handheld, not the console's brand) or the physical thing itself (Safelight, not the room).

## Porting a scheme

A well-loved scheme (Dracula, Solarized) keeps its canonical hex values, taken from the file its project publishes, and its credits: `author`, `author_url`, `homepage`, and `license` in `theme.toml` match upstream. Keep the upstream name only when its license allows it, and add `nvim` when the scheme has a Neovim port people install.
