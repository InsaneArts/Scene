# Palettes

## Build it by lightness

Think in OKLCH (lightness 0 to 1, chroma, hue angle), then write the hex values. Lightness is what makes a palette calm: hues at the same lightness read as a set, and one hue brighter than the rest shouts. `--check-theme` reports every contrast ratio that falls short, so adjust and run it again.

1. Start from the idea's two colors: the ground (`background`) and the signature (`accent`).
2. **Dark look.** `background` at L 0.16 to 0.26 with a little chroma (up to 0.04), tinted toward the idea's hue. `dark_background` about 0.03 darker, `lighter_background` 0.04 lighter, `selection` 0.08 to 0.14 lighter with some accent in it, `muted` near 0.40, `dark_foreground` 0.55 to 0.62, `foreground` 0.84 to 0.90, `bright_foreground` 0.92 to 0.96.
3. **Hues** (red, orange, yellow, green, cyan, blue, magenta) at L 0.70 to 0.84 and chroma 0.08 to 0.18, within about 0.06 lightness of each other, and at least 30° of hue apart. Orange sits between red and yellow. The `bright_` hues are 0.04 to 0.08 lighter.
4. **Light look.** The same hue angles. `background` at L 0.95 to 0.98 (paper, a little warm or cool), `foreground` 0.25 to 0.35, hues at L 0.45 to 0.58 with a little more chroma. Yellow and cyan go darkest, because they fade first on white.
5. `accent` is usually one of the hues, pushed a little in chroma. It holds 3:1 on the background.

A one-hue idea (a green phosphor tube, an amber terminal) steps the lightness of the six hues instead of their angle. Keep `red` readable as the error color even then. The checker warns about look-alike hues; that warning is expected for such a theme.

## Porting a scheme

A well-known scheme (Dracula, Solarized, Gruvbox) keeps its published hex values: take them from the file its project publishes, not from memory. Credit it: the upstream author in `author` only if they made this port, otherwise in `summary` ("A port of …").

## Names

One or two plain words that evoke the look: a material, a place, a technique, a time of day, an era of computing (Phosphor, Blueprint, Greenbar, Safelight). The name belongs to nobody. Leave out products, companies, films, series, games, bands, characters, and living people, and their logos and look-alikes in the wallpapers. Plain words that are also well-known software count as products (Chrome, Signal, Darkroom). When unsure, use the generic word for the thing (Handheld, not the console's brand).
