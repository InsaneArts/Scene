# Review 1: scene-3d-wide

Critic: a fresh subagent that saw only brief.md, style-guide.md, the contact sheets, and frames decoded from `out/scene-3d-wide.mp4`.

## Checklist

- **Fail: phone readability.** The tagline fails (defect 3). "Scene" reads at about 11 px cap height.
- **Fail: safe area.** Panes cross it at `t007.20` (top), `t008.80` (left, about 100 px) and `t016.80` (both sides). Cards leave the frame at `t021.00` and `t023.40`. All type stays inside.
- **Pass: real assets.** The frames show `chaos.jpg`, the four renders, the 60 cards (all Scene's own themes) and `icon.png`. The icon's dark areas are crushed: the bottom wave is (2,7,24) in the film and (26,28,38) in the asset.
- **Fail: type and color.** The tagline peaks near 75% white, but the spec is 92%. The orb is near-white in all four themes. Its halo is olive (60,73,48) under the magenta Cyberdeck theme (`t010.80`).
- **Fail: transitions.** Defect 1 fails this item. Four more problems:
  - Bloom hides "Scene" in the menu bar (`t007.65`).
  - The cards smear into gray blocks (`t020.40`).
  - The orb glow flickers over the front pane at 22.23–22.43 s.
  - The glow on the side panes cuts off within two frames at 12.68 s and 15.08 s.
- **Pass, picture only: beat grid.** Onsets land exactly on frames 432, 576, 720 and 864. The 19.2 s move, "Scene" and the tagline land within 1 frame. The 24.0 s change is eased. Sound: not checked. The mp4 already has an AAC track.
- **Fail: hook.** See defect 2.
- **Fail: poster frame.** `t027.00` would work, but the last frame is black (defect 3).
- **Pass: banned defaults.** The closest call is a bloom glint that floats over the code in each theme (`t012.80`). Also, the renders show "104" and "9:41", and the brief says no numbers on screen.

## Scores

Hook 1, readability 3, continuity 2, motion 3, sound sync not checked, brand fidelity 3.

## Three largest defects

1. **7.7–8.82 s: the first theme does not reach the panes.** In `t008.00`, the top pane keeps a hot-pink band and the left pane keeps a yellow band. A royal-blue sliver stays beside the display. The bands stay at full brightness until 8.78 s. Then they disappear in two frames, off the beat grid (`t008.80` shows the change). In `t007.65`, the wipes on these panes move inward, against the ring. Fix the pane faces: start the wipe at the edge nearest the orb, and finish it at 7.8 s with the wave. Turn the blue pane to face the camera, or remove it.

   **Fixed, see `wide/t007.35.png` to `wide/t008.80.png`.** The wipe only reached 1.5 in pane units, and a pane's far corner is 1.98 away, so a band of the old look stayed until the hard switch at since = 1.6 s. Now each pane computes its reach to the far corner, starts at the edge nearest the orb, and finishes by 7.81 s. The blue pane is the one behind the display; it now switches with the others, so it stays.
2. **0.0–2.0 s: no hook.** In `t000.80` and `t001.00`, the film fades up from black. Mean brightness is 1.7% at 1.0 s and 4.9% at 2.0 s. The display is 26% of the frame width, and its screen is about 10% bright. On a phone this is a black frame. The clash first reads in `t003.60`. Fix the camera and the display: open with the display at 45% of the frame width or more, at full brightness by 0.4 s.

   **Fixed, see `wide/t000.40.png`, `wide/t001.00.png`, `wide/t002.00.png`.** The camera opens at z 2.95, beside the display, and drifts back. The fade from black is 0.4 s, and the screen is at full gain from the first frame. Mean brightness is now 16.7% at 0.4 s, 18.5% at 1.0 s and 17.8% at 2.0 s. The display is about 46% of the frame width at 0.4 s.
3. **25.8–28.8 s: the end card.** In `t027.00`, the tagline cap height is 26 px, which is about 5 px at 360 px wide. From about 28.3 s everything fades, and the last frame is black. Fix the end card: make the tagline cap height 44 px or more, at 92% white. Keep full opacity until the last frame, and fade only the sound.

   **Fixed, see `wide/t027.00.png`, `wide/t028.78.png`.** The tagline is 64 px with a 45 px cap height, and the name is 128 px. Both are 92% white. The icon is smaller (0.52) and higher (y 0.36) to make room. Nothing fades at the end, and the score's level fade from 27.6 s is the only fade.

## Not fixed in this round

The time box allowed one critic round. These findings remain: panes and cards cross the safe area (7.2, 8.8, 16.8, 21.0, 23.4 s), the orb reads near-white, bloom over the menu bar at 7.65 s, cards smear at 20.4 s, and the orb glow flickers at 22.23–22.43 s.

## Sound (checked by the author after the review)

Deep pulses measured at 7.215, 9.615, 12.010 and 14.415 s: on the grid within one frame. The ring bells were only 0 to 3 dB above the pad in their own band, so their bus went from 0.05 to 0.12.
