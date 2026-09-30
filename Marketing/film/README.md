# Scene film

A 30-second product film for Scene: 3840 × 2160 at 60 fps, cut to music at 96 BPM (twelve bars). The film is an HTML page that headless Chrome draws frame by frame. ffmpeg encodes the frames.

A Mac where nothing matches opens Scene's menu bar panel and picks Neon Noir, and one wave changes every app. Scene's window opens: ↓ runs down the sidebar, two more backgrounds, then the light look. Its preview flies into the switcher, which runs to Vaporwave, and ↩ applies it. The camera pulls back onto a wall of every theme, and the wall becomes the app icon.

## Make it

You need Google Chrome, Node, ffmpeg 8 with libx265 (the `aac_at` encoder needs a macOS build), and Python 3 with Pillow, numpy, scipy, and soundfile.

```sh
cd Marketing/film
npm install
python3 prepare.py        # theme colors, wallpapers as JPEG, the icon, and grain, into build/film/
node render.mjs thumbs    # each look's DesktopPreview, for the window, the switcher, and the wall
python3 score.py          # the soundtrack
node render.mjs film      # the 4K master, about 30 minutes on a 14-core Apple silicon Mac
node render.mjs deliver   # the copies with sound
node render.mjs readme    # the README's pictures, into .github/assets/
```

Run `prepare.py` and `thumbs` again after a theme changes. The README's pictures are frames of the film; their times are in `README` in `render.mjs`.

## Outputs

Everything goes to `build/film/`, which git ignores.

| File | Contents |
|---|---|
| `scene-film-4k.mp4` | HEVC 10-bit with AAC, for YouTube, Apple devices, and the web |
| `scene-film-1080p.mp4` | H.264 with AAC, for social posts |
| `scene-film-4k-prores.mov` | ProRes 422 HQ with 24-bit PCM, for editing |
| `scene-film-master.mov` | The same picture without sound |
| `score.wav` | The soundtrack alone: 48 kHz, 24-bit, -16 LUFS |

## Review

- `node render.mjs stills 2.1,4.9,13.5` writes those frames as PNG to `build/film/stills/`.
- `node render.mjs film --scale 1 --shutter 1 --out preview.mov` makes a 1080p preview without motion blur in about two minutes.
- `film.html?t=13.5` opened in Chrome shows one frame.

## How it works

- `film.js` computes every frame from the time alone, through `window.render(t)`. Nothing animates by itself, so a frame renders the same way every time.
- The timeline is at the top of `film.js`. Its cues sit on the music's grid, where a beat is 0.625 s. `score.py` copies these cue times, so change both files together.
- `window.BLUR` lists the fast moves. Each of their frames averages 32 moments across half a frame, like a 180° film shutter. The other frames take one moment.
- The film shows only Scene's own themes. `prepare.py` stops if a wallpaper is not a Scene original, so the film carries no third-party image.
- `score.py` synthesizes every sound, with no samples or licensed music. It sets each track's level by measured loudness (ITU-R BS.1770), relative to the pad.
- The window, the menu bar panel, the switcher, and DesktopPreview copy the app's SwiftUI views (`ContentView.swift`, `OtherViews.swift`, `ThemeSwitcher.swift`, `Previews.swift`). Snapshot mode (docs/DEVELOPMENT.md) renders the real ones to compare against.
- The Mac before Scene is `TH.chaos` in `film.js`. `prepare.py` draws its wallpaper.
- "75 themes." and the switcher's "54 of 75" count the themes in `Themes/`.
- All text in the film uses SF Pro and SF Mono from the system. Apple licenses these fonts for mock-ups of user interfaces for its platforms. Check that license before you publish, or change the font variables at the top of `film.css`.
- `archive/v1/` holds the sources of the first, 20-second cut, which opened on the shortcut's keys.
