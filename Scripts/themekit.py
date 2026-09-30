"""Palette files and color math shared by the theme scripts.

A palette file has one `key = "value"` per line, like Omarchy's colors.toml. Python 3.9 has no TOML parser,
and these files need none: every value is a string.
"""
import math
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
THEMES = os.path.join(REPO, "Themes")
SCENE_PALETTES = os.path.join(HERE, "scene-palettes")
SOURCES = os.path.join(THEMES, "WALLPAPER_SOURCES.json")

HUES = ("red", "orange", "yellow", "green", "cyan", "blue", "magenta")


def read(path):
    """Every `key = "value"` line of a file. Hex colors come back in lower case."""
    values = {}
    for line in open(path):
        m = re.match(r'^\s*([a-z0-9_]+)\s*=\s*"([^"]*)"', line)
        if m:
            values[m.group(1)] = m.group(2).lower() if m.group(2).startswith("#") else m.group(2)
    return values


def mix(top, bottom, amount):
    t = [int(top[i:i + 2], 16) for i in (1, 3, 5)]
    b = [int(bottom[i:i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{round(x * amount + y * (1 - amount)):02x}" for x, y in zip(t, b))


def complete(p):
    """Fills the keys a palette leaves out, the way Omarchy's templates do."""
    p.setdefault("orange", mix(p["red"], p["yellow"], 0.5))
    p.setdefault("bright_foreground", p["foreground"])
    p.setdefault("dark_foreground", mix(p["foreground"], p["background"], 0.5))
    p.setdefault("muted", mix(p["foreground"], p["background"], 0.3))
    p.setdefault("dark_background", mix("#000000", p["background"], 0.2))
    p.setdefault("lighter_background", mix(p["foreground"], p["background"], 0.08))
    p.setdefault("selection", mix(p.get("accent", p["blue"]), p["background"], 0.3))
    p.setdefault("accent", p["blue"])
    for color in ("red", "yellow", "green", "cyan", "blue", "magenta"):
        p.setdefault(f"bright_{color}", p[color])
    return p


def palette(path):
    return complete(read(path))


def spdx(note):
    """Maps a wallpaper's free-text license note to an SPDX-style id. An unknown license stays NOASSERTION."""
    lowered = note.lower()
    for prefix, value in (("public domain", "LicenseRef-PublicDomain"), ("unsplash", "LicenseRef-Unsplash"),
                          ("pexels", "LicenseRef-Pexels"), ("scene original", "LicenseRef-Scene"), ("cc0", "CC0-1.0"),
                          ("cc by 4.0", "CC-BY-4.0"), ("mit", "MIT")):
        if lowered.startswith(prefix):
            return value
    return "NOASSERTION"


# Their own terms ban wallpaper apps: Pexels ("Don't redistribute ... on other stock photo or wallpaper platforms"),
# Unsplash ("You cannot replicate the core user experience of Unsplash (unofficial clients, wallpaper applications, etc.)"),
# and Pixabay. Older bundled wallpapers from them are an open question in docs/STATUS.md.
BANNED_SOURCES = ("unsplash", "pexels", "pixabay")


# MARK: - Color math

def rgb(hex_color):
    return tuple(int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))


def luminance(hex_color):
    """WCAG relative luminance."""
    def linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in rgb(hex_color))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    """WCAG contrast ratio, 1 to 21."""
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def oklab(hex_color):
    """OKLab (L, a, b). Distances in OKLab follow perceived color difference."""
    def linear(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (linear(c) for c in rgb(hex_color))
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l, m, s = (math.copysign(abs(x) ** (1 / 3), x) for x in (l, m, s))
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)


def distance(a, b):
    """Perceived difference between two colors (OKLab Euclidean). About 0.02 is just noticeable."""
    return math.dist(oklab(a), oklab(b))


def chroma(hex_color):
    _, a, b = oklab(hex_color)
    return math.hypot(a, b)


def oklch(hex_color):
    """(lightness 0 to 1, chroma, hue in degrees). Balanced palettes keep their hues at similar lightness and chroma."""
    l, a, b = oklab(hex_color)
    return l, math.hypot(a, b), math.degrees(math.atan2(b, a)) % 360


def from_oklch(l, c, h):
    """The sRGB hex for an OKLCH color, with chroma reduced until it fits in sRGB."""
    def to_rgb(chroma):
        a, b = chroma * math.cos(math.radians(h)), chroma * math.sin(math.radians(h))
        l_ = (l + 0.3963377774 * a + 0.2158037573 * b) ** 3
        m_ = (l - 0.1055613458 * a - 0.0638541728 * b) ** 3
        s_ = (l - 0.0894841775 * a - 1.2914855480 * b) ** 3
        linear = (4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
                  -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
                  -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)
        return [12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055 for v in (max(0.0, x) for x in linear)], linear
    while True:
        srgb, linear = to_rgb(c)
        if all(-1e-4 <= v <= 1.0001 for v in linear) or c <= 0:
            return "#" + "".join(f"{round(min(1, max(0, v)) * 255):02x}" for v in srgb)
        c -= 0.002


# MARK: - Images

def image_stats(image):
    """The mean lightness (OKLab L, 0 to 1) and the dominant colors, as [(hex, share)], of a PIL image."""
    from PIL import Image
    small = image.convert("RGB").resize((160, 100), Image.LANCZOS)
    quantized = small.quantize(colors=6, method=Image.Quantize.MEDIANCUT)
    colors = quantized.getpalette()
    counts = sorted(quantized.getcolors(), reverse=True)
    total = sum(n for n, _ in counts)
    dominant = [("#%02x%02x%02x" % tuple(colors[i * 3:i * 3 + 3]), n / total) for n, i in counts]
    pixels = list(small.getdata())
    step = max(1, len(pixels) // 4000)
    lightness = sum(oklab("#%02x%02x%02x" % px)[0] for px in pixels[::step]) / len(pixels[::step])
    return lightness, dominant


def palette_fit(dominant, p):
    """How far, on average, an image's dominant colors sit from the nearest palette color. Lower fits better."""
    roles = ["background", "dark_background", "lighter_background", "foreground", "accent", "muted", "selection", *HUES]
    swatches = [p[r] for r in roles if r in p]
    return sum(share * min(distance(c, s) for s in swatches) for c, share in dominant)


# MARK: - Arrays (numpy is imported on use, so the theme generator needs only the standard library)

def to_oklab_array(rgb01):
    """sRGB values in 0...1, shape (..., 3), to OKLab, shape (..., 3)."""
    import numpy as np
    c = np.where(rgb01 <= 0.04045, rgb01 / 12.92, ((rgb01 + 0.055) / 1.055) ** 2.4)
    r, g, b = np.moveaxis(c, -1, 0)
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], -1)


def from_oklab_array(lab):
    """OKLab, shape (..., 3), to sRGB in 0...1, clipped."""
    import numpy as np
    L, a, b = np.moveaxis(lab, -1, 0)
    l = (L + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b) ** 3
    linear = np.clip(np.stack([4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                               -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                               -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s], -1), 0, 1)
    return np.where(linear <= 0.0031308, linear * 12.92, 1.055 * linear ** (1 / 2.4) - 0.055)


# MARK: - Building palettes

# Where each terminal hue sits on the OKLCH hue circle by default.
ANGLES = dict(red=27, orange=55, yellow=92, green=145, cyan=195, blue=255, magenta=325)


def build_palette(look, ground, accent, fg=None, hues=None, level=None, chroma=None):
    """A complete palette, in the Omarchy format, from a few OKLCH choices.

    ground and accent are (lightness, chroma, hue); fg is (hue, chroma) for the text. hues maps a role to its
    (hue, chroma); roles left out sit at ANGLES with `chroma`. `level` is the hues' lightness. Every other role
    follows from these, the way .claude/skills/scene-theme/PALETTES.md describes.
    """
    L, C, H = ground
    c = from_oklch
    dark = look == "dark"
    level = level if level is not None else (0.77 if dark else 0.52)
    chroma = chroma if chroma is not None else (0.12 if dark else 0.14)
    fg_h, fg_c = fg or (H, min(0.03, C + 0.01) if dark else min(0.04, C + 0.015))
    if dark:
        p = {"mode": "dark", "background": c(L, C, H), "dark_background": c(L - 0.035, C * 0.9, H),
             "darker_background": c(L - 0.06, C * 0.8, H), "lighter_background": c(L + 0.045, C * 1.15 + 0.004, H),
             "selection": c(L + 0.12, max(C, 0.03) + 0.03, accent[2]), "muted": c(L + 0.2, C * 1.3 + 0.008, H),
             "dark_foreground": c(0.6, C * 1.3 + 0.012, H), "foreground": c(0.88, fg_c, fg_h),
             "bright_foreground": c(0.95, fg_c * 0.8, fg_h)}
        # Yellow and green read darker than they measure; red and blue lighter.
        offset = {"yellow": 0.06, "green": 0.03, "cyan": 0.03, "red": -0.03, "blue": -0.03, "magenta": -0.02, "orange": 0.02}
        bright = 0.06
    else:
        p = {"mode": "light", "background": c(L, C, H), "dark_background": c(L - 0.03, C * 1.1 + 0.003, H),
             "darker_background": c(L - 0.06, C * 1.2 + 0.004, H), "lighter_background": c(L - 0.045, C * 1.2 + 0.004, H),
             "selection": c(L - 0.11, max(C, 0.025) + 0.03, accent[2]), "muted": c(L - 0.2, C * 1.2 + 0.008, H),
             "dark_foreground": c(0.55, C + 0.015, H), "foreground": c(0.3, fg_c, fg_h), "bright_foreground": c(0.22, fg_c, fg_h)}
        offset = {"yellow": 0.04, "green": 0.0, "cyan": -0.01, "red": 0.02, "blue": 0.0, "magenta": 0.03, "orange": 0.03}
        bright = 0.05
    p["accent"] = c(*accent)
    for role, angle in ANGLES.items():
        h, role_chroma = (hues or {}).get(role, (angle, chroma))
        p[role] = c(level + offset[role], role_chroma, h)
        if role != "orange":
            p[f"bright_{role}"] = c(min(0.97, level + offset[role] + bright), role_chroma + 0.01, h)
    return p


PALETTE_KEYS = ["mode", "background", "dark_background", "darker_background", "lighter_background", "selection", "muted",
                "dark_foreground", "foreground", "bright_foreground", "accent", "red", "orange", "yellow", "green", "cyan",
                "blue", "magenta", "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta",
                "accent_color", "icon_style", "icon_tint"]


def write_palette(path, p):
    """Writes a palette file: one `key = "value"` line per key, in the usual order."""
    with open(path, "w") as f:
        for key in PALETTE_KEYS + sorted(set(p) - set(PALETTE_KEYS)):
            if key in p:
                f.write(f'{key} = "{p[key]}"\n')
