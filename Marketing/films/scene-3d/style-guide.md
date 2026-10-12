# Style guide

**Direction:** a dark studio. The only light comes from the screen, the theme, and the accent of the theme on screen. Premium and calm, like a product film: one idea per shot, slow eased moves, nothing spins for its own sake.

## Palette
- Void: `#040507` with a faint cool fog. The frame is never pure black at the edges because of the fog.
- Light: from the hero theme in view. Neon Noir `#0dd7c6`, Cyberdeck `#f252d8`, Amber `#ffa839`, Aurora `#5aea98`. Between themes, colors cross-fade in linear light.
- Before the first theme, the panes clash: a hot pink, a sour yellow, a royal blue. That clash is the problem.

## Objects and their motion
| Object | Material | Motion rule |
|---|---|---|
| Display | dark anodized aluminum, clearcoat, a thin glass front; the screen is emissive | barely moves; its float is a slow sine of 6 mm |
| App panes (terminal, editor, desktop slab) | thin glass slabs with an emissive face in theme colors | orbit the display on slow ellipses; settle into place with a critically damped spring after each theme |
| Theme orb | glass sphere with the theme's 16 terminal colors as bands, glowing | rises once, then turns slowly; each theme change pulses it (scale 1 → 1.12 → 1) |
| Wave | a thin ring of light in the accent, expanding from the orb | 0.6 s from the orb to past the camera, ease-out |
| Theme cards | thumbnails on thin glass tiles, on a tilted ring | the ring turns at a constant speed; cards fade in by distance |
| Icon tile | the app icon on a rounded glass tile | arrives with a spring, then holds |

## Camera
One continuous camera. Focal length 38° vertical FOV. Moves ease in and out (cubic), never linear; a move starts on a downbeat. No shake, no cuts, no whip pans.

## Light and finish
RoomEnvironment reflections at low intensity, a key light from the screen, and an accent light that takes the theme's color. Bloom on emissive parts only (threshold high). Film grain at 5%, a soft vignette.

## Type
SF Pro (system-ui). "Scene" at 600 weight, the tagline at 400, white at 92%, under the icon on the end card. Type fades in with an 8 px rise; it never animates letter by letter.

## Banned defaults
Centered text on a gradient. Rainbow gradients (except the "nothing matches" screen, which is the problem). Lens flares. Camera shake. Spinning cubes. Particle explosions. Letter-by-letter type. Any copy beyond the name and the tagline.
