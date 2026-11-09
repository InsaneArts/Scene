# Wallpapers

## What belongs

- **Colors**: the dominant colors come from the palette. `add-wallpaper.py` reports the palette fit: drawn and recolored art scores about 0.01, a generated image with the palette in its prompt 0.01 to 0.04, a matched photo 0.04 to 0.09, and above 0.10 the image is a guest in the theme.
- **Light**: a dark look gets a dark image (lightness up to about 0.55); a light look gets a light one.
- **Composition**: a calm middle, because windows sit there. Detail goes to the edges or a low horizon, and the top strip stays quiet for the menu bar.
- **Clean**: no text, letters, logos, watermarks, signatures, UI, brands, flags, emblems, or faces of real people. A generic object that looks like a famous product (a handheld console, a branded computer) is a brand too.
- **Size**: 3840 × 2160 or larger. The loader takes a long side of 1024 to 8192 px and 20 MB per image. `add-wallpaper.py` stores HEIC (about 1 MB at 4K) unless `--format png` keeps flat or pixel art crisp.
- **Three that differ**: for example a scene, an abstract, and a pattern. A theme with three versions of one picture is one wallpaper.

## Generated

`Scripts/generate-wallpaper.py` calls OpenAI's image API with the model set in the script (`gpt-image-2.5-sunburst`, first on LMArena's text-to-image and Art boards in September 2026; check the board again before a big batch). It needs `OPENAI_API_KEY` in the environment: ask the person for it, and keep it out of every file. At high quality a 3840 × 2160 image costs about $0.10 and takes about 40 seconds; four run well in parallel.

1. Write the subject: one picture, concrete, with light and framing ("a 1970s terminal glowing in a dark room, seen from the side, its green screen lighting the desk"). The script adds the composition rules, so the subject says only what the picture shows. Name what must stay out when the subject invites it: "no flags, no emblems" for a control room, "only the screen, no device" for a gadget.
2. Review the full prompt with `--dry-run`, then generate: `python3 Scripts/generate-wallpaper.py OUT.png --subject "..." --palette <palette>`. The largest sizes are 3840x2160 (16:9) and 3632x2272 (16:10).
3. Open it, then open a brightened full-size crop of any walls, screens, and devices: small flags, insignia, made-up logos, and product look-alikes hide there. Make it again when anything from "Clean" shows.
4. The palette in the prompt usually lands the colors (fit 0.01 to 0.04). Recolor only a loose fit (above about 0.08): `recolor-wallpaper.py --mode blend --strength 0.4`, and say so in `--notes`.
5. Add it with the printed prompt:

```sh
python3 Scripts/add-wallpaper.py <folder> dark 1 OUT.png --name <slug> --source generated --author Scene \
  --license "Scene original (generated with gpt-image-2.5-sunburst)" --attribution "Generated for Scene with GPT Image" \
  --prompt "<the prompt the script printed>"
```

A generated image has no copyright holder in the US, so anyone may reuse it; nobody else holds rights to it either. The attribution says it was generated, because the provider's terms ban passing it off as human-made. ChatGPT's app makes smaller images (about 1.6 MP) and cannot be scripted: use the API. Midjourney's terms ban automated use.

## Art-first

A theme built on an art style starts from its picture, and its palette comes from the art (step 2 in SKILL.md). [ART.md](ART.md) lists styles and concepts that work.

1. Generate wallpaper 1 with `--look dark` (or `light`) instead of `--palette`, so the style keeps its own colors. Describe the technique, not only a painter: medium, brushwork, composition, light ("oil on canvas with thick impasto and short directional strokes, a swirling cobalt sky, chrome-yellow stars").
2. Derive the palette from it with `palette-from-image.py`.
3. Generate wallpapers 2 and 3 with `--reference <wallpaper 1>`: the edits endpoint copies the style, and the prompt asks for a new composition. Give each a different subject and framing (a wide scene, a close-up, an object), or the set repeats itself.
4. Check the fit as usual; art-first images score about 0.01 to 0.03 against their own palette.

## Found

A found image may ship only when its license allows redistribution inside a paid app. Check the license on the image's own page, and record that page in `--page-url`.

| Source | License | Credit (`--attribution`) |
|---|---|---|
| NASA, JPL, NOAA, USGS | `public domain` (US government work) | "NASA" (or the agency; JPL asks "Courtesy NASA/JPL-Caltech") |
| Museum open access: the Met, Art Institute of Chicago, Cleveland, Smithsonian (CC0 items), National Gallery of Art, Rijksmuseum | `CC0` or `public domain` | Artist, title, date, museum |
| Wikimedia Commons, files marked CC0 or public domain | as marked on the file page | Author, as on the file page |
| ESA/Hubble, ESA/Webb | `CC BY 4.0` | The credit line exactly as published, and "recolored" when changed |

Keep out images with identifiable people, logos, insignia, or a credit naming someone other than the agency or museum. Unsplash, Pexels, and Pixabay ban wallpaper apps in their terms, and `add-wallpaper.py` refuses them. NASA's search needs no key: `https://images-api.nasa.gov/search?q=<words>&media_type=image`, then `https://images-api.nasa.gov/asset/<nasa_id>` lists the `~orig.jpg`. Commons: the `api.php` query with `prop=imageinfo&iiprop=url|size|extmetadata` returns each file's `LicenseShortName` and `Artist`.

## Recolored

Recoloring pulls a found image, or a generated one that drifted, into the palette. The result is derived from the original, so record the original's source and license.

```sh
python3 Scripts/recolor-wallpaper.py IN Scripts/scene-palettes/<folder>/<look>.toml OUT --mode blend --strength 0.85
python3 Scripts/recolor-wallpaper.py IN <palette> OUT --mode gradient --ramp dark_background,muted,accent,bright_foreground
```

`blend` keeps the image's light and shade and moves its colors toward the palette: good for photos and paintings. `gradient` maps brightness onto a ramp of palette roles, like a duotone print: strong for space, microscope, and satellite images. Put `recolored with Scripts/recolor-wallpaper.py <options>` in `--notes`.

## Drawn with code

`Scripts/make-wallpaper.py STYLE <palette> OUT --seed N` draws in the palette's exact colors, and nobody else holds rights to the result. The same style, palette, seed, size, and colors always give the same image, so the command is the provenance.

`aura`, `flow`, `stars`, and `dither` paint with the theme's family: the accent and the palette hues nearest it, so a red theme stays red. `--colors` names the roles instead, in order, for example `--colors yellow,red,magenta,blue` for a rainbow sunrise or `--colors bright_foreground,accent,green,muted` for four shades of one green.

| Style | Picture | Looks | Format |
|---|---|---|---|
| `aura` | Light spilling in from beyond one edge; pale washes of color on a light look | both | heic |
| `topo` | Contour lines of an imaginary terrain | both | heic |
| `ridges` | Stacked signal lines that rise in the middle, like a pulsar plot | dark | heic |
| `maze` | The Commodore 64 one-line maze, mostly dim, with a glow passing over it | dark | png |
| `dither` | A sunrise in ordered dithering with chunky pixels | both | png |
| `grid` | A striped sun over a glowing perspective grid | dark | heic |
| `stars` | A nebula in two family colors over a star field | dark | heic |
| `flow` | Thousands of strokes following a smooth current | both | heic |
| `scope` | An oscilloscope graticule with a glowing trace and scanlines | dark | heic |
| `greenbar` | Tractor-feed printer paper with pale bands and sprocket holes | light | png |
| `bauhaus` | Circles, halves, and bars at the edges, a quiet middle | both | png |
| `blueprint` | A drafting grid with circles, an arc, and a dimension line | both | heic |
| `mosaic` | A sunset in the block graphics of a teletext page | dark | png |
| `rasterbars` | Demoscene copper bars, lit like metal tubes, frozen mid-wave | dark | heic |
| `stripes` | 1970s supergraphics: bands along the bottom that sweep up the right side | light | png |

Try several seeds and keep the best. Record it like this:

```sh
python3 Scripts/add-wallpaper.py <folder> dark 2 OUT.jpg --name <slug> --source procedural --author Scene \
  --license "Scene original (drawn by Scripts/make-wallpaper.py)" --attribution "Drawn for Scene with code" \
  --notes "python3 Scripts/make-wallpaper.py topo Scripts/scene-palettes/<folder>/dark.toml OUT --seed 7"
```

## Licenses

The `--license` text starts with the license name, and `make-bundled-themes.py` turns that prefix into the SPDX id in `theme.json`:

| Starts with | SPDX id |
|---|---|
| `Scene original` | `LicenseRef-Scene` |
| `public domain` | `LicenseRef-PublicDomain` |
| `CC0` | `CC0-1.0` |
| `CC BY 4.0` | `CC-BY-4.0` (put the required credit in `--attribution`) |
| anything else | `NOASSERTION`: `add-wallpaper.py` refuses it |
