# Status

Last updated: 2026-09-30. Version 0.1.0, build 4 (`version.env`).

## Verified

- 174 tests pass through the Scene scheme (`./Scripts/test.sh`). The app builds with warnings as errors.
- The apps added after the MVP: kitty, Alacritty, Warp, Terminal, Zed, Xcode, Helix, tmux, bat and delta, btop, and JankyBorders. Apply and restore against fixture home folders give back every user file byte for byte. Where an app is installed on the test Mac, its own parser read Scene's output in a throwaway folder: kitty 0.44 (`kitty +runpy`), tmux 3.6b (a private server, which accepts every option even without `-q`), bat 0.26.1 and delta 0.19.2 (bat's cache and an included git config), and `plutil` for the Xcode themes. Python's `tomllib` read the Alacritty, Helix, and Warp TOML.
- Install from GitHub: two community themes downloaded and installed into a throwaway library, `bjarneo/omarchy-aura-theme` (colors.toml) and `guilhermetk/omarchy-all-hallows-eve-theme` (only alacritty.toml). The importer reads 107 of the 108 colors.toml files of Omarchy's community themes. It refuses the other one, which has an invalid color (`#4A8B8Bi`).
- Theme Maker, redesigned around sliders: the Swift palette builder gives the same hex values as `build_palette` in `Scripts/themekit.py` (three looks checked); a sweep of the slider ranges gives no palette-check errors; a palette from Amber's wallpapers reads well in both looks and is the same on every run; one slider move with the preview takes 0.52 ms in a Debug build and 0.23 ms in Release. The new window renders in snapshot mode, started from Amber.
- Theme Maker: drafts, checks, the folder they build, and the command line are covered by tests. A bundled theme opened as a draft comes back with the same colors (Amber, Catppuccin, and Gruvbox, within 1 in a channel for mixed shades). The command line ran with the app binary: a draft with an error exited 1 and named the error, then built after the fix. The Theme Maker window renders in snapshot mode, started from Amber.
- Theme Maker's macOS look: the preview shows the accent as the highlighted item of an open File menu, and the icon style in a Dock of real app icons. The Dark icons that `IconStyles` builds were compared with the real Dark icons of the same eight apps on the test Mac, which uses Dark icons, and they match closely. Snapshot `15-icon-styles` shows all four styles; it was checked by eye in a dark look (Abyss) and a light look (Acme). Clear and Tinted were not compared with the real ones, because that needs a change to the Mac's icon style. Loading the eight icons takes 0.23 s once in a Debug build.
- Licenses are optional. The Theme Maker, the draft check, and the command line ask for none, and the app shows none. Credits (attribution and source) are optional too, and the README lists them.
- The skill `skills/create-scene-theme`, run once by hand as an agent would: Ice Core, with a dark and a light look, and six public-domain NASA images found through NASA's image API and prepared with `sips`. Two candidates were left out for spacecraft hardware and lettering in the frame. The first draft passed the check with no warnings and built. It was not installed.
- In snapshot mode: the sidebar's search and Favorites, the star on the theme page, the Install from GitHub sheet, the switcher searching, the menu bar panel's search, the new apps on the Apps page and in the Apply sheet, and the Light and Dark setting.
- 75 bundled themes (21 from Omarchy's palettes, 54 of Scene's own), 84 looks (dark or light), and 3 backgrounds per look: 252 images. 48 come from Omarchy and 24 from r/unixporn; 99 were generated with `gpt-image-2.5-sunburst` and 81 drawn with `Scripts/make-wallpaper.py`. Four themes are art-first: their palettes come from their paintings through `Scripts/palette-from-image.py`, and their second and third wallpapers take the first as a style reference. Every new palette passes `Scripts/check-palette.py` with no warnings, and all 71 themes load in the tests.
- Snapshot renders of new themes (Amber, Primary in both looks, the switcher at 71 themes), and the 168 new backgrounds reviewed on contact sheets. Three generated images were made again: one showed a US flag, one a device like a well-known handheld console, one a small made-up logo.
- On macOS 26.6.2 (25G83), the live test applied a theme to the real Mac and restored it byte for byte. The private-call check passed 7 of 7. See [DEVELOPMENT.md](DEVELOPMENT.md).
- Builds 1 to 3 were signed with Developer ID and notarized. Build 3's zip was in `dist/`, which is not in git.
- Build 4 was built by Xcode and signed with Developer ID (hardened runtime, secure timestamps, universal, SDK 26.5). It passed every release check except notarization, which was not run.
- The redesigned UI (branch `ui-redesign`), checked in snapshot mode in the light and the dark look, with several themes: the main window (sidebar, theme page, background picker, Apps, History), the Apply sheet, the switcher carousel, the menu bar panel, and the three Settings tabs.
- The product film (`Marketing/film/`), a 30-second cut: the 4K master has 1800 frames at 60 fps, and each frame matched a sharp 1080p render within 0.42 of 255 in mean luma, so none is broken. Its window, menu bar panel, switcher, and DesktopPreview were compared with snapshot-mode renders of the real views. Its soundtrack measures -16 LUFS with a true peak of -3.2 dBTP, and the clicks on the menu bar item, the panel, and the backgrounds, and ↩, sound within 2 ms of their cues.
- Sparkle 2.10.0 for updates: the app builds with warnings as errors, 120 tests pass, the packaged app embeds Sparkle with its helpers signed, its Info.plist carries the feed and the public key, and the key matches the new Keychain key (account `Scene`). Settings → General → Updates renders in snapshot mode.

## Not verified

- Pressing the global shortcuts on the real desktop: the switcher (⌃⇧⌘Space), and Next Background (⌃⌥⌘Space) changing the real wallpaper, followed by Undo.
- Recording a shortcut in Settings, and clicking Stop Managing (it also turns the app's switch off on the Apps page).
- The redesigned UI on macOS 14 and 15. Liquid Glass falls back to a material there, and without the macOS 26 toolbar spacer the toolbar buttons may sit next to the sidebar.
- In the redesigned UI: applying from the Apply sheet and its results page, the menu bar panel in the real menu bar, the switcher's backdrop on a second screen, and the status HUD. Snapshot mode never applies, and it renders the menu bar panel and the carousel in plain windows.
- iTerm2 on a real Mac. It is not installed on the test Mac.
- Notarizing an Xcode-built release. From the agent session, the preflight could not read the `camus-notary` profile.
- The film's soundtrack, by ear. `Marketing/film/score.py` synthesizes it, and its levels were set by measured loudness and band levels only.
- Updates end to end: Check for Updates… in a running app, and an update from a published release. The feed exists only after the first release is published.
- The new apps on the real Mac. No theme was applied to the real setup. The reloads (SIGUSR1 for kitty and Helix, SIGUSR2 for btop, `source-file` for tmux, colors sent to borders) are tested with fake processes only.
- Warp, Alacritty, and Helix are not installed on the test Mac. Warp's order (theme files, a 1-second pause, then the setting) comes from reading Warp's source, not from running it.
- Xcode: whether a running Xcode keeps Scene's theme settings when it quits. Scene asks for a restart.
- Terminal: a running Terminal can write its own profiles back when you edit a profile in its settings. Scene then reports the change outside Scene.
- Following macOS Light/Dark on a real switch, and the switcher's search on the real screen.
- In the running app: dragging the Theme Maker's sliders, Shuffle, From Wallpaper, Undo, setting a color by hand, Save to Scene, Export Folder…, and dropping images on the wallpaper slots. `--install` with the real library (a test covers it with a fake library).
- The skill in a real agent session started by someone who asks for a theme.

## Open decisions for the user

- **Image rights.** 54 of the Omarchy themes' 72 backgrounds have an unknown license. 16 more are Unsplash (12) and Pexels (4) photos, and both sites' terms ban wallpaper apps. They need clearing, or replacing, before the app is distributed. Scene's own themes use none of them.
- **Trademarks** (reported by the theme research on USPTO TSDR, not checked again here): LUMON is registered to Fifth Season, LLC, which produces Severance (reg. 8096416), and the Lumon theme shows the Lumon logo. VANTABLACK is registered to Surrey NanoSystems (reg. 4783953). OMARCHY is registered to 37signals (reg. 8250209); it is used only as a tag and in the credits. DRACULA is registered for color-scheme software (reg. 6306339), which matters if that palette is ever ported. None of the 50 new theme names has had a trademark search yet; the research suggests USPTO and EUIPO, classes 9 and 42, before the app ships.
- **Generated backgrounds** have no copyright holder in the US, so anyone can reuse them. OpenAI's terms assign whatever rights it has in the output to the account holder and ban passing output off as human-made, so the credits say "Generated for Scene with GPT Image".
- **Film font.** All text in the film uses SF Pro and SF Mono, and Apple licenses these fonts for mock-ups of user interfaces for its platforms. Check that license before the film is published, or change the font in `Marketing/film/film.css`.
- **License.** The repository has no LICENSE file.
- **Visibility.** InsaneArts/Scene became public on Sep 30, 2026, with `main` at 4c2f31e. Its history holds the backgrounds and the Lumon logo named under Image rights. The work since then is not pushed yet.
- **Size.** The app is 271 MB (Debug build), mostly images: 146 MB for the Omarchy themes' backgrounds and about 115 MB for Scene's 54 themes, stored as HEIC. Re-encoding the older backgrounds to HEIC would cut most of the 146 MB, but it changes the files.
- **Weaker backgrounds:**
  - gruvbox light `sunlit-room` and flexoki `cracked-paper` come from a wallpaper collection an r/unixporn poster linked, not from the wallpaper in their post. `sunlit-room` is also a photo of a living room.
  - catppuccin light `mountain-peak` is 32:9, so "fill" crops its sides.
  - everforest `misty-pines` and flexoki `ink-wave` are 1920×1080 and look soft on Retina screens.

## Not built

- Distribution: Homebrew. No GitHub release is published yet, so Sparkle has no feed to read.
- Tests for the app target. All tests are in SceneKit.
- The other art-style themes in the skill's `ART.md` (Leaf Node, Faint Signal, Bubble Sort, and more). Generation stopped when the OpenAI account ran out of credits.
- The highlight-color integration. macOS derives the highlight from the accent by default.
- More apps from the research: lazygit, Sublime Text, WezTerm, Obsidian, and Starship. A browsable theme store; themes install from a GitHub address.
