# Developing Scene

## Build and run

Scene runs on macOS 14 or later. Building needs Xcode 26 or later, because an app linked before SDK 26 does not get the macOS 26 design.

```sh
open Scene.xcodeproj          # Scene scheme: ⌘R runs the app, ⌘U runs the SceneKit tests
./Scripts/test.sh             # the same 120 tests from the command line
./Scripts/package_app.sh      # builds build/Scene.app (release, host architecture, ad-hoc signed)
open build/Scene.app
```

For a quick build without packaging:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Scene.xcodeproj -scheme Scene \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/Xcode -clonedSourcePackagesDirPath .build/SourcePackages -quiet
```

The app lands in `.build/Xcode/Build/Products/Debug/Scene.app`.

## Toolchain

`xcode-select` on the development Mac points at an Xcode 27.1 beta in `~/Downloads`. Don't build with it: it can link against an older SDK, and its tools write a `default.profraw` file into the current folder. Use the release Xcode by setting `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The scripts in `Scripts/` already set it. `*.profraw` is in `.gitignore`.

## Xcode project

`Scene.xcodeproj` is a plain project. It was generated once with XcodeGen, and the spec was not kept, like Jolt. Edit it in Xcode.

- The project lists its files one by one. A new file in `Sources/Scene` or `Sources/SceneTweak` must be added to the project, or it is not compiled.
- Files in `Packages/SceneKit` need nothing: Swift Package Manager finds them.
- `Themes/` is a folder reference, so new themes are copied into the app as they are. `package_app.sh` then deletes every file in the bundle's `Themes/` that a theme package may not contain.
- The app target and the helper target treat warnings as errors.
- Debug builds sign with Apple Development for team 539293JFA3. Release builds are unsigned from Xcode, and `package_app.sh` signs them.

## Tests

| Target | Covers |
|---|---|
| SceneFoundationTests | ZIP, JSONC edits, TOML-style key edits |
| SceneThemesTests | Colors, validation, bundled themes (all load, 3 wallpapers per look), library, import, export, install from GitHub, search, icon styles |
| SceneRenderersTests | Output for each app. Where the app is installed, its own parser reads the output in a throwaway folder: Ghostty, VS Code, Neovim, kitty (`kitty +runpy`), tmux (a private server, `-L`), bat and delta. A Python with `tomllib` checks the Alacritty and Helix TOML |
| SceneEngineTests | The experimental tier with fake helpers |
| SceneIntegrationsTests | Apply, verify, rollback, undo, restore, and backgrounds against fixture home folders |
| SceneSwitcherTests | Carousel selection and shortcut rules |
| SceneLiveTests | The real Mac. Opt-in, and not in the scheme |

The theme command line runs from a Debug build without a window: `.build/Xcode/Build/Products/Debug/Scene.app/Contents/MacOS/Scene --check-theme draft.json` (see ARCHITECTURE.md → Command line). Leave out `--install` unless the user agrees, because it adds the theme to their Scene library.

`./Scripts/test.sh` runs everything except SceneLiveTests through the Scene scheme. Two more tests are opt-in and change nothing on the Mac: `SCENE_NETWORK=1` downloads a real theme repository into a throwaway library (`SCENE_NETWORK_REPO=owner/repo` picks it, default `bjarneo/omarchy-aura-theme`), and `SCENE_OMARCHY_CORPUS=<folder>` imports every `colors.toml` in a folder. `swift test --package-path Packages/SceneKit` runs the same tests with Swift Package Manager (with `DEVELOPER_DIR` set).

These change the real Mac, so run them only when the user agrees:

- `SCENE_LIVE=1 swift test --package-path Packages/SceneKit --filter SceneLiveTests` applies Catppuccin to the real wallpaper, Ghostty, Neovim, and VS Code family apps, then restores them. With `SCENE_LIVE_TWEAKS=1` it also changes the accent color and icon style. It needs one Xcode build first, so the helper exists.
- `./Scripts/verify-tweaks.sh` changes Light/Dark, the accent color, and the icon style for a few seconds each, then puts every original value back. Run it on each new macOS build before adding the build to `TweakCatalog.testedBuilds`.

## Checking UI

`screencapture` needs the Screen Recording permission, which the terminal doesn't have. Snapshot mode needs none: the app captures its own windows through the window server (`CGWindowListCreateImageFromArray`, which a process may use on its own windows without the permission), writes PNG files, and quits. It never applies anything.

```sh
open -W -n -g -a "$PWD/.build/Xcode/Build/Products/Debug/Scene.app" \
  --env SCENE_SNAPSHOT=/tmp/scene-snap --env SCENE_SNAPSHOT_SWITCHER=0 \
  --args -ApplePersistenceIgnoreState YES
```

- `open -n -g` starts a new copy in the background, so it doesn't take focus from the user.
- `SCENE_SNAPSHOT_SWITCHER=0` skips the real switcher. The switcher takes keyboard focus over every screen, and ↩ in it applies a theme to the real Mac. Always set it when the user may be at the Mac.
- `SCENE_SNAPSHOT_THEME=<theme id>` (for example `scene/tokyo-night`) picks the theme for the theme page, the Apply sheet, and the carousel.
- `SCENE_SNAPSHOT_APPEARANCE=light` or `dark` renders Scene in that look, whatever macOS uses.
- `-ApplePersistenceIgnoreState YES` makes the main window open even when it was closed last time.
- The snapshot copy shares the user's settings. To render a default value, pass it in the argument domain instead of writing it, for example `-switcherShortcut "<hex of the JSON>"`, or favorites with `-favoriteThemes '("scene/nord", "scene/tokyo-night")'`.
- The main window keeps the user's saved size. If macOS tiled it, it keeps the tile's size too.

Files are named `<step>-<window index>.png`: `1-theme`, `2-other-look` (the theme's other variant), `3-background-picked`, `4-apply-plan` (the window with its sheet, and the sheet alone as `4-apply-plan-0-sheet`), `5-apps`, `6-history`, `12-search` (the sidebar searching "night"), `13-github` (the Install from GitHub sheet), `7-carousel`, `7-carousel-search` (the carousel searching "ro"), `8-menu-bar`, `14-maker` (the Theme Maker, started from the chosen theme), `15-icon-styles` (the Theme Maker's Dock in all four icon styles, on the chosen theme's look), and `9-settings-<tab>`, then `10-switcher` and `11-switcher-moved` when the real switcher runs. The carousel and the menu bar panel render in windows of their own. Scene runs in the background, so windows show their inactive look: gray sidebar text and gray standard buttons. The PNG screenshots in `.github/assets` come from these renders. The JPEG images are frames of the product film, from `node Marketing/film/render.mjs readme`.

## Bundled themes

`Themes/<folder>/theme.json` is generated. Don't edit it by hand. Change the inputs and run the script:

- `Scripts/make-bundled-themes.py`: the Omarchy themes' names and summaries, and how a palette maps to Scene's roles.
- `Scripts/omarchy-palettes/*.toml`: Omarchy's palettes, from Omarchy v4.0.4 (MIT), unchanged.
- `Scripts/scene-palettes/<folder>/`: Scene's own themes, one folder each (`theme.toml`, `dark.toml`, `light.toml`). The format is in that folder's README.
- `Themes/WALLPAPER_SOURCES.json`: one entry per image, with its theme, variant, `order`, file, source, author, license, attribution, sha256, and size, plus the prompt or the command for a generated image.

```sh
python3 Scripts/make-bundled-themes.py
```

A theme must stay under the 40 MB package limit. The bundled-theme test loads every theme through the validator, checks the count in `bundlesEveryTheme`, and requires 3 wallpapers per look.

To make a theme, use the `scene-theme` skill (`.claude/skills/scene-theme/`). Its scripts also work on their own:

| Script | Does |
|---|---|
| `check-palette.py` | Checks contrast and hue spacing; `--table` shows each role's OKLCH |
| `make-wallpaper.py` | Draws a wallpaper from a palette with code (15 styles) |
| `generate-wallpaper.py` | Generates one with OpenAI's image API, in a palette's colors or in its own, optionally in the style of earlier wallpapers; needs `OPENAI_API_KEY` |
| `recolor-wallpaper.py` | Pulls an image into a palette |
| `palette-from-image.py` | Derives a palette from a picture, for a theme that starts from its art |
| `add-wallpaper.py` | Checks an image, writes it into `Themes/` (as HEIC through macOS's `sips`, or PNG), and records its provenance |

`themekit.py` holds what they share: reading palettes, and the color math.

## Release

Bump `BUILD_NUMBER` in `version.env` first, and write the release notes in `releases/<version>.md`: Sparkle shows them in its update window. `./Scripts/release.sh` makes a distributable build. It follows the same steps as FindSFSymbols and Jolt: a universal (arm64 and x86_64) build, Developer ID signing (Techzy LLC, 539293JFA3) with hardened runtime and a secure timestamp, Sparkle's helpers signed the same way, notarization with the `camus-notary` keychain profile, stapling, a Gatekeeper check, and `dist/Scene-<version>.zip`. Like WorldClock, it then checks that the Keychain's Sparkle key matches `SUPublicEDKey`, writes `dist/appcast.xml`, signs it, and verifies the feed's and the zip's signatures. It publishes nothing.

**Publishing** is the user's step, and it needs the repository to be public. The feed URL reads `appcast.xml` from the latest release, so both files go on the release:

```sh
gh release create v<version> dist/Scene-<version>.zip dist/appcast.xml --repo InsaneArts/Scene \
  --title "Scene <version>" --notes-file releases/<version>.md
```

**The Sparkle key.** The private key was created on Sep 30, 2026 with `generate_keys --account Scene` and lives only in the login Keychain. Without it, no later update can be signed, and people would have to download Scene again by hand. Back it up to a safe place with `.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account Scene -x <file>`, and import it on another Mac with `-f <file>`. The tools appear after the first build resolves the Sparkle package.

Notarization sends the app to Apple, so ask the user before running it. On Sep 28 the preflight failed from an agent session with "No Keychain password item found for profile: camus-notary", although builds 1 to 3 were notarized with that profile earlier that day. If that happens, the user runs `./Scripts/release.sh` in their own terminal.

## Layout

```
Scene.xcodeproj           the app target Scene and the helper target scene-tweak
Sources/Scene             SwiftUI app
Sources/SceneTweak        scene-tweak helper for experimental private calls (Swift 5 mode)
Packages/SceneKit         the core as a local package, no UI
  SceneFoundation         ZIP, JSONC and TOML-style edits, safe file writes, processes
  SceneThemes             theme model, validation, library, Omarchy import, GitHub install, drafts, the theme command line
  SceneRenderers          theme files for each app
  SceneEngine             plan, apply, journal, ledger, restore, system services
  SceneIntegrations       one integration per app or system setting
  SceneSwitcher           carousel selection and shortcut rules
  SceneTestSupport        fixtures and fakes for the tests
Config/                   Info.plist keys, entitlements, Version.xcconfig (reads version.env)
Assets/Scene.icon         app icon (Icon Composer format)
Themes/                   bundled themes (generated)
Scripts/                  test, package, release, theme generation, private-call check
releases/                 release notes, one Markdown file per version, for Sparkle's update window
skills/create-scene-theme the skill that lets an AI agent make a theme for a Scene user
.github/assets/           README images
Marketing/film/           the 30-second product film, rendered from HTML (see its README)
docs/                     this file, ARCHITECTURE.md, STATUS.md, the original research
```

## Verified on macOS 26.6.2 (25G83)

- The live test (`SCENE_LIVE=1 SCENE_LIVE_TWEAKS=1`) applied Catppuccin to the real wallpaper, Ghostty, Neovim, VS Code, Cursor, accent color, and icon style, then restored it. Apply took 0.5–1.3 s. Every watched config file was byte-identical after restore.
- `./Scripts/verify-tweaks.sh` passed 7 of 7 private-call checks (Light/Dark, Auto, accent, three icon styles including a custom tint) and restored every original value.
