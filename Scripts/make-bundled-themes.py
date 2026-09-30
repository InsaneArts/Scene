#!/usr/bin/env python3
"""Generates Themes/<folder>/theme.json for the bundled themes.

Palettes come from Omarchy v4.0.4 (MIT), vendored in Scripts/omarchy-palettes/. Two variants that Omarchy
does not ship come from their upstream projects: Rosé Pine Main (rose-pine/palette) and Gruvbox light
(sainnhe/gruvbox-material, light, medium). The role mapping follows Omarchy's own templates
(ghostty.conf.tpl, vscode-theme.json.tpl). Wallpapers and their provenance come from Themes/WALLPAPER_SOURCES.json.

Scene's own themes live in Scripts/scene-palettes/<folder>/: theme.toml (name, summary, tags, credits) and dark.toml,
light.toml, or both (the palette, in the Omarchy format, and the macOS look). See Scripts/scene-palettes/README.md.
"""
import json
import os

from themekit import SCENE_PALETTES, complete, mix, read, spdx

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "Themes")
PALETTES = os.path.join(HERE, "omarchy-palettes")
OMARCHY_THEMES = "https://github.com/omacom/omarchy/tree/v4.0.4/themes"
OMARCHY_AUTHORS = [{"name": "Omarchy contributors", "url": "https://github.com/omacom/omarchy"}]


def omarchy(name):
    """An Omarchy colors.toml, with the keys a palette leaves out filled in."""
    return complete(read(os.path.join(PALETTES, f"{name}.toml")))


def variant(p, system):
    """Maps an Omarchy-style palette to Scene roles."""
    return {
        "palette": {
            "background": p["background"], "surface": p["dark_background"], "overlay": p["lighter_background"],
            "border": p["muted"], "foreground": p["foreground"], "muted": p["dark_foreground"],
            "accent": p["accent"], "selection": p["selection"], "cursor": p["bright_foreground"],
            "currentLine": mix(p["lighter_background"], p["background"], 0.5),
            "search": mix(p["yellow"], p["background"], 0.3),
            "error": p["red"], "warning": p["yellow"], "success": p["green"], "info": p["blue"],
        },
        "terminal": {
            "background": "@background", "foreground": "@foreground", "cursor": "@cursor", "cursorText": "@background",
            "selectionBackground": "@selection", "selectionForeground": p["bright_foreground"],
            "ansi": {
                "black": p["background"], "red": p["red"], "green": p["green"], "yellow": p["yellow"],
                "blue": p["blue"], "magenta": p["magenta"], "cyan": p["cyan"], "white": p["foreground"],
                "brightBlack": p["muted"], "brightRed": p["bright_red"], "brightGreen": p["bright_green"],
                "brightYellow": p["bright_yellow"], "brightBlue": p["bright_blue"], "brightMagenta": p["bright_magenta"],
                "brightCyan": p["bright_cyan"], "brightWhite": p["bright_foreground"],
            },
        },
        "syntax": {
            "comment": {"color": p["dark_foreground"], "italic": True},
            "keyword": p["bright_magenta"], "operator": p["bright_blue"], "punctuation": p["dark_foreground"],
            "string": p["green"], "escape": p["bright_magenta"], "number": p["orange"], "constant": p["orange"],
            "function": p["blue"], "type": p["yellow"], "builtin": p["cyan"], "variable": p["foreground"],
            "parameter": {"color": p["cyan"], "italic": True}, "property": p["cyan"], "tag": p["red"],
            "attribute": {"color": p["cyan"], "italic": True},
            "added": p["green"], "removed": p["red"], "changed": p["yellow"],
        },
        "system": system,
    }


def dark(accent="auto", icons="dark", tint=None):
    s = {"accentColor": accent, "iconStyle": icons}
    if tint:
        s["iconTint"] = tint
    return s


def light(accent="auto"):
    return {"accentColor": accent, "iconStyle": "default"}


# rose-pine/palette "main", mapped the same way Omarchy maps Dawn. Highlight med/high are Rosé Pine's own values.
ROSE_PINE_MAIN = complete(dict(accent="#9ccfd8", selection="#403d52", muted="#524f67", background="#191724", dark_background="#1f1d2e",
                               lighter_background="#26233a", foreground="#e0def4", dark_foreground="#6e6a86", bright_foreground="#e0def4",
                               red="#eb6f92", yellow="#f6c177", orange="#ebbcba", green="#31748f", cyan="#ebbcba", blue="#9ccfd8",
                               magenta="#c4a7e7"))
# sainnhe/gruvbox-material, light background, "medium" contrast.
GRUVBOX_LIGHT = complete(dict(accent="#45707a", selection="#dadec0", muted="#ddccab", background="#fbf1c7", dark_background="#f2e5bc",
                              lighter_background="#f4e8be", foreground="#654735", dark_foreground="#928374", bright_foreground="#4f3829",
                              red="#c14a4a", yellow="#b47109", orange="#c35e0a", green="#6c782e", cyan="#4c7a5d", blue="#45707a",
                              magenta="#945e80"))


def theme(folder, name, summary, variants, homepage=None, tags=(), nvim=None):
    return dict(folder=folder, name=name, summary=summary, variants=variants, homepage=homepage or f"{OMARCHY_THEMES}/{folder}",
                tags=list(tags) + ["omarchy"], nvim=nvim or {}, authors=OMARCHY_AUTHORS, license="MIT")


def scene_themes():
    """Scene's own themes, one folder each in Scripts/scene-palettes."""
    themes = []
    for folder in sorted(os.listdir(SCENE_PALETTES)) if os.path.isdir(SCENE_PALETTES) else []:
        path = os.path.join(SCENE_PALETTES, folder)
        if not os.path.isdir(path):
            continue
        about = read(os.path.join(path, "theme.toml"))
        variants = {}
        for look in ("dark", "light"):
            if os.path.exists(os.path.join(path, f"{look}.toml")):
                p = complete(read(os.path.join(path, f"{look}.toml")))
                system = (dark(p.get("accent_color", "auto"), p.get("icon_style", "dark"), p.get("icon_tint")) if look == "dark"
                          else light(p.get("accent_color", "auto")))
                variants[look] = variant(p, system)
        author = {"name": about.get("author", "Scene")}
        if about.get("author_url"):
            author["url"] = about["author_url"]
        themes.append(dict(folder=folder, name=about["name"], summary=about["summary"], variants=variants,
                           homepage=about.get("homepage"), tags=[t.strip() for t in about.get("tags", "").split(",") if t.strip()],
                           nvim={"any": about["nvim"]} if about.get("nvim") else {}, authors=[author],
                           license=about.get("license", "MIT")))
    return themes


THEMES = [
    theme("tokyo-night", "Tokyo Night", "Neon city blues after dark. Omarchy's default theme.",
          {"dark": variant(omarchy("tokyo-night"), dark(icons="tinted", tint="accent"))},
          homepage="https://github.com/folke/tokyonight.nvim", tags=["dark", "blue"], nvim={"dark": "tokyonight-night"}),
    theme("catppuccin", "Catppuccin", "Soothing pastels: Mocha after dark, Latte by day.",
          {"dark": variant(omarchy("catppuccin"), dark()), "light": variant(omarchy("catppuccin-latte"), light())},
          homepage="https://catppuccin.com", tags=["pastel"]),
    theme("rose-pine", "Rosé Pine", "All natural pine, faux fur, and a bit of soho vibes.",
          {"dark": variant(ROSE_PINE_MAIN, dark()), "light": variant(omarchy("rose-pine"), light())},
          homepage="https://rosepinetheme.com", tags=["muted"]),
    theme("gruvbox", "Gruvbox", "Retro groove colors, softened by Gruvbox Material.",
          {"dark": variant(omarchy("gruvbox"), dark()), "light": variant(GRUVBOX_LIGHT, light())},
          homepage="https://github.com/sainnhe/gruvbox-material", tags=["warm", "retro"]),
    theme("ethereal", "Ethereal", "Nebula violets with a warm peach glow.",
          {"dark": variant(omarchy("ethereal"), dark())}, tags=["dark", "purple"]),
    theme("everforest", "Everforest", "Soft greens and warm sand, easy on the eyes.",
          {"dark": variant(omarchy("everforest"), dark(accent="green"))}, homepage="https://github.com/sainnhe/everforest",
          tags=["dark", "green"], nvim={"dark": "everforest"}),
    theme("flexoki", "Flexoki", "Paper and ink colors for prose and code.",
          {"light": variant(omarchy("flexoki-light"), light())}, homepage="https://stephango.com/flexoki",
          tags=["light", "ink"], nvim={"light": "flexoki-light"}),
    theme("hackerman", "Hackerman", "Neon green on midnight, straight off a synthwave grid.",
          {"dark": variant(omarchy("hackerman"), dark())}, tags=["dark", "green", "neon"], nvim={"dark": "hackerman"}),
    theme("kanagawa", "Kanagawa", "Ink and wave blues from Hokusai's Great Wave.",
          {"dark": variant(omarchy("kanagawa"), dark(accent="blue"))}, homepage="https://github.com/rebelot/kanagawa.nvim",
          tags=["dark", "blue"], nvim={"dark": "kanagawa"}),
    theme("last-horizon", "Last Horizon", "Near-black with soft rose and bone white.",
          {"dark": variant(omarchy("last-horizon"), dark(accent="graphite"))}, tags=["dark", "minimal"]),
    theme("lumon", "Lumon", "Cold office blues from Severance.",
          {"dark": variant(omarchy("lumon"), dark())}, tags=["dark", "blue"], nvim={"dark": "lumon"}),
    theme("lupine", "Lupine", "Bright and clean, with cherry blossoms and cobalt.",
          {"light": variant(omarchy("lupine"), light())}, tags=["light", "blue"]),
    theme("matte-black", "Matte Black", "Flat black with a single amber accent.",
          {"dark": variant(omarchy("matte-black"), dark())}, tags=["dark", "minimal"], nvim={"dark": "matteblack"}),
    theme("miasma", "Miasma", "Smoky grays and moss in low light.",
          {"dark": variant(omarchy("miasma"), dark())}, tags=["dark", "earthy"]),
    theme("nord", "Nord", "Arctic blues and frosted grays.",
          {"dark": variant(omarchy("nord"), dark())}, homepage="https://www.nordtheme.com", tags=["dark", "blue"],
          nvim={"dark": "nordfox"}),
    theme("osaka-jade", "Osaka Jade", "Jade greens over a city at night.",
          {"dark": variant(omarchy("osaka-jade"), dark())}, tags=["dark", "green"], nvim={"dark": "bamboo"}),
    theme("retro-82", "Retro 82", "Deep navy and sunset orange, like a vinyl sleeve.",
          {"dark": variant(omarchy("retro-82"), dark())}, tags=["dark", "retro"], nvim={"dark": "retro-82"}),
    theme("ristretto", "Ristretto", "Espresso browns with a warm crema accent.",
          {"dark": variant(omarchy("ristretto"), dark(accent="orange"))}, tags=["dark", "warm"]),
    theme("solitude", "Solitude", "Quiet grays in ink and paper.",
          {"dark": variant(omarchy("solitude"), dark(accent="graphite"))}, tags=["dark", "minimal"], nvim={"dark": "ashen"}),
    theme("vantablack", "Vantablack", "Pure black, pure white, nothing else.",
          {"dark": variant(omarchy("vantablack"), dark())}, tags=["dark", "minimal"]),
    theme("white", "White", "Pure white with black type.",
          {"light": variant(omarchy("white"), light())}, tags=["light", "minimal"]),
] + scene_themes()


def main():
    sources_path = os.path.join(ROOT, "WALLPAPER_SOURCES.json")
    sources = json.load(open(sources_path)) if os.path.exists(sources_path) else []
    for t in THEMES:
        folder = os.path.join(ROOT, t["folder"])
        os.makedirs(folder, exist_ok=True)
        assets = []
        for name, spec in t["variants"].items():
            # A variant's wallpapers in their "order". The first one is the default.
            matches = sorted((s for s in sources if s["theme"] == t["folder"] and s["variant"] == name), key=lambda s: s.get("order", 0))
            wallpapers = []
            for match in matches:
                # Paths in WALLPAPER_SOURCES.json are relative to Themes/.
                relative = match["file"].removeprefix(t["folder"] + "/")
                if not os.path.exists(os.path.join(folder, relative)):
                    continue
                wallpapers.append({"file": relative, "fit": "fill"})
                author = match.get("author") or "unknown author"
                via = {"omarchy": "Omarchy", "unixporn": "r/unixporn"}.get(match["source"])
                attribution = match.get("attribution") or (f"{author}, via {via}" if via else author)
                asset = {"file": relative, "license": spdx(match.get("license", "")), "attribution": attribution}
                if match.get("pageURL") or match.get("imageURL"):
                    asset["source"] = match.get("pageURL") or match.get("imageURL")
                assets.append(asset)
            if wallpapers:
                spec["wallpapers"] = wallpapers
        manifest = {
            "$schema": "https://schema.scene.example/theme/1.json", "format": 1, "id": f"scene/{t['folder']}", "version": "1.0.0",
            "name": t["name"], "summary": t["summary"], "authors": t["authors"], "license": t["license"],
            "homepage": t["homepage"], "tags": t["tags"], "requires": {"scene": ">=1.0"}, "variants": t["variants"],
        }
        if not t["homepage"]:
            del manifest["homepage"]
        if t["nvim"]:
            manifest["apps"] = {"neovim": {"preferInstalled": {"colorscheme": next(iter(t["nvim"].values()))}}}
        if assets:
            manifest["assets"] = assets
        with open(os.path.join(folder, "theme.json"), "w") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print(f"{t['folder']:13} {', '.join(t['variants']):12} wallpapers: {len(assets)}")
    print(f"{len(THEMES)} themes")


if __name__ == "__main__":
    main()
