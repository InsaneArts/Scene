---
name: scene-theme
description: Designs and adds a Scene theme end to end, a readable palette plus three wallpapers per look that belong to it, then builds, tests, and renders it. Use when asked to create, design, port, or batch-produce themes, or to make, find, generate, or replace a theme's wallpapers.
---

# Scene theme

A theme is a palette and three wallpapers per look (dark, light, or both) that **belong** together: the wallpapers carry the palette's colors and the theme's mood, and code stays readable on top of them. Work on a branch. Each step ends on its check, and a theme is done when every check passes.

## 1. Concept

- **Name**: one or two plain words that evoke the look and belong to nobody (Names in [PALETTES.md](PALETTES.md)). The folder is the name in kebab-case, new in `Themes/` and `Scripts/scene-palettes/`.
- **Summary**: one concrete line about what it looks like, in the house style: "Green phosphor glowing on a dark tube."
- **Looks**: dark, light, or both. **Tags**: look, main color, mood.
- Write `Scripts/scene-palettes/<folder>/theme.toml` (format: `Scripts/scene-palettes/README.md`).

Check: the name is safe and the folder is new.

## 2. Palette

A look's palette is designed or derived:

- **Designed**, when the concept is a color idea (a phosphor tube, an amber terminal): write `dark.toml` or `light.toml` in OKLCH, following [PALETTES.md](PALETTES.md).
- **Derived**, when the concept is a picture (a painting style, a scene): make wallpaper 1 first, with no palette (Art-first in [WALLPAPERS.md](WALLPAPERS.md)), then `python3 Scripts/palette-from-image.py <wallpaper 1> --look <look> --out Scripts/scene-palettes/<folder>/<look>.toml` and open the swatch sheet it saves. `--accent-hue` picks another of the accents it lists.

Then:

```sh
python3 Scripts/check-palette.py --table Scripts/scene-palettes/<folder>/*.toml
```

Check: 0 errors, and each warning fixed or intended.

## 3. Wallpapers

Three per look, in order: 1 is the default and the strongest. For each, pick a source in [WALLPAPERS.md](WALLPAPERS.md) (generated, found, recolored, or drawn with code) so the three differ in subject.

1. Make or fetch the image into the scratchpad.
2. Open it and judge it against "What belongs" in WALLPAPERS.md. Redo it when it fails; three strong images beat three quick ones.
3. Add it. The script checks size, look, and palette fit, writes `Themes/<folder>/wallpapers/`, and records provenance in `Themes/WALLPAPER_SOURCES.json`:

```sh
python3 Scripts/add-wallpaper.py <folder> <dark|light> <1-3> <image> --name <slug> \
  --source <source> --author <author> --license "<license>" [--attribution ...] [--page-url ...] [--prompt ...] [--notes ...] [--format png]
```

Check: no errors from `add-wallpaper.py`, palette fit at most 0.10 unless the picture earns more, and three wallpapers per look.

## 4. Build and look

1. `python3 Scripts/make-bundled-themes.py`
2. Set the count in `bundlesEveryTheme` in `Packages/SceneKit/Tests/SceneThemesTests/ThemeTests.swift`, then `./Scripts/test.sh`.
3. Build Debug and render the theme in snapshot mode (`docs/DEVELOPMENT.md`, Checking UI) with `SCENE_SNAPSHOT_THEME=scene/<folder>` and `SCENE_SNAPSHOT_SWITCHER=0`. Open `1-theme`, `2-other-look`, and `7-carousel`.

Check: the tests pass, and in the renders the code in the mock windows reads clearly while the wallpaper stays behind it.

## 5. Record

Update the theme and wallpaper counts in `README.md` and `docs/STATUS.md`.

## Batches

For many themes, plan the whole lineup first: name, looks, concept, and a source for each wallpaper, so neighbours differ in hue and subject. Write and check every palette, then make the wallpapers in parallel batches (generated four at a time, drawn all at once), review them on contact sheets, redo the weak ones, and add them in one sequential pass, because `add-wallpaper.py` rewrites `WALLPAPER_SOURCES.json`. Then do steps 4 and 5 once. Every wallpaper ships inside Scene: at about 1 MB per HEIC image, 50 themes add about 100 MB.
