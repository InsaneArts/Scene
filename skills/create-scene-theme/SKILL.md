---
name: create-scene-theme
description: Designs a complete theme for Scene, the Mac app that themes the desktop, terminals, and code editors in one step, then builds and installs it with Scene. A theme is a readable palette for a dark look, a light look, or both, three wallpapers per look, and the macOS accent and icon style. Use when someone asks to make, design, remix, or port a Scene theme, or one theme for their Mac's wallpaper, terminal, and editor together.
---

# Create a Scene theme

A Scene theme is a palette and three wallpapers per look that **belong** together: the wallpapers carry the palette's colors and the theme's mood, and text stays readable on top of them. You write a small **draft** (JSON), and Scene builds the theme folder from it, checks it with the same rules as its Theme Maker, and installs it. Each step ends on its check. The theme is done when step 5 passes.

## 0. Find Scene

```sh
APP=/Applications/Scene.app
[ -d "$APP" ] || APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.insanearts.scene'" | head -1)"
defaults read "$APP/Contents/Info.plist" SceneThemeCommands
SCENE="$APP/Contents/MacOS/Scene"
```

Check: `defaults read` prints `1`. Anything else means Scene is missing or too old to have the theme commands, and an old Scene would open its window instead of answering: stop, and point the person to github.com/InsaneArts/Scene/releases.

## 1. Brief

Ask only what the conversation has not answered yet, in one message:

- **Idea**: a mood, place, material, time of day, era of computing, picture, or color scheme to port.
- **Looks**: dark, light, or both.
- **Wallpapers**: the person's own images, images you find that anyone may share, or images you generate (only if you have an image tool).
- **Name**: offer two or three (rules in [PALETTES.md](PALETTES.md)), and the **author** name.

Check: you can say the idea in one line, and you know the looks, the wallpaper route, the name, and the author.

## 2. Palette

Design each look in Omarchy's color keys. [DRAFT.md](DRAFT.md) lists what each key paints; [PALETTES.md](PALETTES.md) says how to build a palette that reads well.

Check: each look has the nine required keys and all twenty-two keys, and no two hues sit within 30° of each other unless the idea is one hue on purpose.

## 3. Wallpapers

Get three wallpapers per look that carry the palette: [WALLPAPERS.md](WALLPAPERS.md) has what belongs, where to find or make them, and how to prepare the files with `sips`.

Check: three files per look in an `images/` folder, each a JPEG, PNG, or HEIC with a long side of 1024 to 8192 px (3840 × 2160 or more is best) and under 20 MB. For each found image, you know who made it and its page, for the credits.

## 4. Draft

Write `draft.json` next to `images/` ([DRAFT.md](DRAFT.md) has the format and an example). Then:

```sh
"$SCENE" --check-theme draft.json
```

Check: no line starts with `error`. Fix what each error names and run the check again. Read the warnings too: fix every one about text that is hard to read, and keep the rest only when the idea needs them.

## 5. Build and install

```sh
"$SCENE" --build-theme draft.json <name-in-kebab-case> --install
```

Check: it prints `ok Built` and `ok Installed`. Tell the person the theme is in Scene's sidebar, how to apply it (select it, then Apply), and that Scene's Theme Maker opens it for changes by hand (right-click the theme → Open in Theme Maker).

## 6. Share, only when the person asks

The built folder is a complete GitHub repository already: theme.json, wallpapers/, and a README.md with a picture, install steps, and every credit. Publishing is public, so ask before you create or push a repository.

```sh
cd <folder> && git init && git add . && git commit -m "<Name> theme for Scene"
gh repo create <folder> --public --source . --push
```

Check: the repository page shows the README. Anyone installs the theme in Scene with Add Theme → Install from GitHub and the repository's address.
