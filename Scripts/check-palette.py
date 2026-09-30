#!/usr/bin/env python3
"""Checks that a palette reads well in a terminal and an editor.

    python3 Scripts/check-palette.py Scripts/scene-palettes/phosphor/dark.toml [more files]

Errors (exit 1) are palettes people cannot read. Warnings are weak spots worth a second look.
Thresholds come from WCAG contrast and were calibrated on the bundled Omarchy palettes.
Pass --mono for a theme that uses one hue on purpose, and --table to see each role's OKLCH and contrast.
"""
import itertools
import sys

from themekit import HUES, chroma, contrast, distance, luminance, oklch, palette

TABLE_ROLES = ["background", "dark_background", "lighter_background", "selection", "muted", "dark_foreground", "foreground",
               "bright_foreground", "accent", *HUES]


def check(path, mono=False):
    p = palette(path)
    bg = p["background"]
    light = luminance(bg) > 0.4
    errors, warnings = [], []

    def need(role, other, minimum, good):
        ratio = contrast(p[role], p[other])
        if ratio < minimum:
            errors.append(f"{role} {p[role]} on {other}: {ratio:.2f}, needs {minimum}")
        elif ratio < good:
            warnings.append(f"{role} {p[role]} on {other}: {ratio:.2f}, {good} reads better")
        return ratio

    need("foreground", "background", 4.5, 7)
    need("dark_foreground", "background", 2.2, 3)       # comments and line numbers
    need("accent", "background", 2.5, 3)
    need("foreground", "selection", 3.5, 4.5)           # selected text
    # Light themes print yellow and cyan darker than a dark theme needs.
    for hue in ("red", "green", "yellow", "blue", "magenta", "cyan"):
        need(hue, "background", 2 if light else 3, 3 if light else 4.5)
    if contrast(p["selection"], bg) < 1.15:
        warnings.append(f"selection {p['selection']} is hard to see on the background")
    if contrast(p["muted"], bg) < 1.3:
        warnings.append(f"muted {p['muted']} (borders, bright black) is hard to see")

    hues = {h: p[h] for h in HUES}
    if not mono:
        for (a, ca), (b, cb) in itertools.combinations(hues.items(), 2):
            if distance(ca, cb) < 0.06 and (a, b) != ("red", "orange") and (a, b) != ("orange", "yellow"):
                warnings.append(f"{a} {ca} and {b} {cb} look alike ({distance(ca, cb):.3f})")
        grays = [h for h, c in hues.items() if chroma(c) < 0.03]
        if grays:
            warnings.append(f"no color in {', '.join(grays)}: pass --mono if that is the idea")
    look = "light" if light else "dark"
    if p.get("mode") and p["mode"] != look:
        errors.append(f"mode says {p['mode']}, but the background is {look}")
    return look, errors, warnings


def table(path):
    """Each role's hex, OKLCH, and contrast on the background."""
    p = palette(path)
    for role in TABLE_ROLES:
        l, c, h = oklch(p[role])
        print(f"     {role:18} {p[role]}  L {l:.2f}  C {c:.3f}  h {h:5.1f}  {contrast(p[role], p['background']):5.2f}:1")


def main(args):
    mono = "--mono" in args
    failed = False
    for path in (a for a in args if not a.startswith("--")):
        look, errors, warnings = check(path, mono)
        status = "FAIL" if errors else "ok"
        print(f"{status:4} {path} ({look}): {len(errors)} errors, {len(warnings)} warnings")
        if "--table" in args:
            table(path)
        for e in errors:
            print(f"     error   {e}")
        for w in warnings:
            print(f"     warning {w}")
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
