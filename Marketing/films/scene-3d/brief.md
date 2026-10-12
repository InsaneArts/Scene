# Brief: Scene in 3D

**Idea (the user's words):** "Test if you can generate nice motion design, with Three.js and real 3D scenes. Do it." Time box: about one hour of work.

**One sentence:** A Mac where nothing matches gets one theme in one step, then shows how many themes there are, and ends on Scene.

## Facts the film may state
- Scene gives the desktop, terminals, and code editors one theme in one step.
- Tagline: "One theme for your whole Mac." (from the README and the landing page)
- The name: Scene.

No other copy. No numbers on screen.

## Assets (all real, copied into `assets/`)
| File | What | Source |
|---|---|---|
| `icon.png` | Scene's app icon, 824 px | `build/film/assets/icon.png` (from `Assets/Scene.icon`) |
| `screens/chaos.jpg` | A Mac wallpaper where nothing matches | the product film's prep |
| `screens/<theme>.jpg` | DesktopPreview renders of Neon Noir, Cyberdeck, Amber, Aurora (dark) | Scene's snapshot renders |
| `cards/*.jpg` | 60 thumbnails, every look of Scene's own themes | Scene's snapshot renders |
| `data.json` | The four themes' interface and terminal colors | `Themes/*/theme.json` via the film prep |
| `grain.png` | Film grain | the product film |

Only Scene's own themes appear: their wallpapers were made for Scene. Omarchy themes and Aetheria are left out, because their image licenses are unknown.

## Deliverables
- `out/scene-3d-wide.mp4`: 1920 × 1080, 60 fps, 28.8 s, with a synthesized score.
- Vertical is skipped in this time box.

## Engine
The bundled Canvas renderer, with Three.js (bundled into `src/vendor/three.js`) drawing each frame on a WebGL canvas that `draw` copies onto the film canvas: real 3D, and the skill's seekable stills, sound, and export stay as they are. Headless Chrome renders WebGL on the GPU (ANGLE Metal, Apple M4 Max).

## Rules
Every frame is a pure function of time. Seeded randomness only. No camera cuts: one continuous camera.
