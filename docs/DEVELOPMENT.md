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
| SceneFoundationTests | ZIP, JSONC edits |
| SceneThemesTests | Colors, validation, bundled themes (all 21 load, 3 wallpapers per look), library, import, export |
| SceneRenderersTests | Output for each app |
| SceneEngineTests | The experimental tier with fake helpers |
| SceneIntegrationsTests | Apply, verify, rollback, undo, restore, and backgrounds against fixture home folders |
| SceneSwitcherTests | Carousel selection and shortcut rules |
| SceneLiveTests | The real Mac. Opt-in, and not in the scheme |

`./Scripts/test.sh` runs everything except SceneLiveTests through the Scene scheme. `swift test --package-path Packages/SceneKit` runs the same tests with Swift Package Manager (with `DEVELOPER_DIR` set).

These change the real Mac, so run them only when the user agrees:

- `SCENE_LIVE=1 swift test --package-path Packages/SceneKit --filter SceneLiveTests` applies Catppuccin to the real wallpaper, Ghostty, Neovim, and VS Code family apps, then restores them. With `SCENE_LIVE_TWEAKS=1` it also changes the accent color and icon style. It needs one Xcode build first, so the helper exists.
- `./Scripts/verify-tweaks.sh` changes Light/Dark, the accent color, and the icon style for a few seconds each, then puts every original value back. Run it on each new macOS build before adding the build to `TweakCatalog.testedBuilds`.

## Checking UI

`screencapture` needs the Screen Recording permission, which the terminal doesn't have. Snapshot mode needs none: the app renders its own windows to PNG files and quits. It never applies anything.

```sh
open -W -n -g -a "$PWD/.build/Xcode/Build/Products/Debug/Scene.app" \
  --env SCENE_SNAPSHOT=/tmp/scene-snap --env SCENE_SNAPSHOT_SWITCHER=0 \
  --args -ApplePersistenceIgnoreState YES
```

- `open -n -g` starts a new copy in the background, so it doesn't take focus from the user.
- `SCENE_SNAPSHOT_SWITCHER=0` skips the real switcher. The switcher takes keyboard focus over every screen, and ↩ in it applies a theme to the real Mac. Always set it when the user may be at the Mac.
- `SCENE_SNAPSHOT_THEME=<theme id>` picks the theme for the theme page and the carousel.
- `-ApplePersistenceIgnoreState YES` makes the main window open even when it was closed last time.
- The snapshot copy shares the user's settings. To render a default value, pass it in the argument domain instead of writing it, for example `-switcherShortcut "<hex of the JSON>"`.

Files are named `<step>-<window index>.png`. The main window's split views render blank, and some buttons render as blank capsules. That's why the theme page, the carousel (`11-carousel`), and Settings (`10-settings-<tab>`) also render in windows of their own. The images in `.github/assets` come from these renders.

## Bundled themes

`Themes/<folder>/theme.json` is generated. Don't edit it by hand. Change the inputs and run the script:

- `Scripts/make-bundled-themes.py`: theme names, summaries, and how Omarchy's colors map to Scene's roles.
- `Scripts/omarchy-palettes/*.toml`: the palettes, from Omarchy v4.0.4 (MIT).
- `Themes/WALLPAPER_SOURCES.json`: one entry per image, with its theme, variant, `order`, file, source, author, license, sha256, and size.

```sh
python3 Scripts/make-bundled-themes.py
```

A theme must stay under the 40 MB package limit. The bundled-theme test loads all 21 themes through the validator and requires 3 wallpapers per look.

## Release

Bump `BUILD_NUMBER` in `version.env` first. `./Scripts/release.sh` makes a distributable build. It follows the same steps as FindSFSymbols and Jolt: a universal (arm64 and x86_64) build, Developer ID signing (Techzy LLC, 539293JFA3) with hardened runtime and a secure timestamp, notarization with the `camus-notary` keychain profile, stapling, a Gatekeeper check, and `dist/Scene-<version>.zip`. It publishes nothing.

Notarization sends the app to Apple, so ask the user before running it. On Sep 28 the preflight failed from an agent session with "No Keychain password item found for profile: camus-notary", although builds 1 to 3 were notarized with that profile earlier that day. If that happens, the user runs `./Scripts/release.sh` in their own terminal.

## Layout

```
Scene.xcodeproj           the app target Scene and the helper target scene-tweak
Sources/Scene             SwiftUI app
Sources/SceneTweak        scene-tweak helper for experimental private calls (Swift 5 mode)
Packages/SceneKit         the core as a local package, no UI
  SceneFoundation         ZIP, JSONC, safe file writes, processes
  SceneThemes             theme model, validation, library, Omarchy import
  SceneRenderers          theme files for Ghostty, iTerm2, VS Code, and Neovim
  SceneEngine             plan, apply, journal, ledger, restore, system services
  SceneIntegrations       one integration per app or system setting
  SceneSwitcher           carousel selection and shortcut rules
  SceneTestSupport        fixtures and fakes for the tests
Config/                   Info.plist keys, entitlements, Version.xcconfig (reads version.env)
Assets/Scene.icon         app icon (Icon Composer format)
Themes/                   bundled themes (generated)
Scripts/                  test, package, release, theme generation, private-call check
.github/assets/           README images
docs/                     this file, ARCHITECTURE.md, STATUS.md, the original research
```

## Verified on macOS 26.6.2 (25G83)

- The live test (`SCENE_LIVE=1 SCENE_LIVE_TWEAKS=1`) applied Catppuccin to the real wallpaper, Ghostty, Neovim, VS Code, Cursor, accent color, and icon style, then restored it. Apply took 0.5–1.3 s. Every watched config file was byte-identical after restore.
- `./Scripts/verify-tweaks.sh` passed 7 of 7 private-call checks (Light/Dark, Auto, accent, three icon styles including a custom tint) and restored every original value.
