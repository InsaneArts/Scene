# Status

Last updated: 2026-09-28. Version 0.1.0, build 4 (`version.env`).

## Verified

- 120 tests pass through the Scene scheme (`./Scripts/test.sh`).
- 21 bundled themes, 24 looks (dark or light), and 3 backgrounds per look: 72 images, 48 from Omarchy and 24 from r/unixporn.
- On macOS 26.6.2 (25G83), the live test applied a theme to the real Mac and restored it byte for byte. The private-call check passed 7 of 7. See [DEVELOPMENT.md](DEVELOPMENT.md).
- Builds 1 to 3 were signed with Developer ID and notarized. Build 3's zip was in `dist/`, which is not in git.
- Build 4 was built by Xcode and signed with Developer ID (hardened runtime, secure timestamps, universal, SDK 26.5). It passed every release check except notarization, which was not run.
- UI checked in snapshot mode: the switcher carousel, the theme page with the background picker, the Apply sheet, and all four Settings tabs.

## Not verified

- Pressing the global shortcuts on the real desktop: the switcher (⌃⇧⌘Space), and Next Background (⌃⌥⌘Space) changing the real wallpaper, followed by Undo.
- Recording a shortcut in Settings, and clicking Stop Managing (it now also turns the app off in Settings → Apps).
- The theme gallery in the main window. Snapshot mode renders it blank.
- iTerm2 on a real Mac. It is not installed on the test Mac.
- Notarizing an Xcode-built release. From the agent session, the preflight could not read the `camus-notary` profile.

## Open decisions for the user

- **Image rights.** 54 of the 72 backgrounds have an unknown license, and the Lumon theme shows the Lumon logo from Severance. They need clearing, or replacing, before the app is distributed.
- **License.** The repository has no LICENSE file.
- **Visibility.** InsaneArts/Scene is private.
- **Size.** The app is 151 MB, mostly images. Re-encoding the largest PNGs to HEIC would make it much smaller, but it changes the files.
- **Weaker backgrounds:**
  - gruvbox light `sunlit-room` and flexoki `cracked-paper` come from a wallpaper collection an r/unixporn poster linked, not from the wallpaper in their post. `sunlit-room` is also a photo of a living room.
  - catppuccin light `mountain-peak` is 32:9, so "fill" crops its sides.
  - everforest `misty-pines` and flexoki `ink-wave` are 1920×1080 and look soft on Retina screens.

## Not built

- Distribution: Sparkle updates, GitHub releases, and Homebrew.
- Tests for the app target. All tests are in SceneKit.
- The highlight-color integration. macOS derives the highlight from the accent by default.
- The rest of the research plan: more apps (kitty, for example) and a community theme store.
