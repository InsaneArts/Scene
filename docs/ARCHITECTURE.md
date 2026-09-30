# Architecture

Scene is a macOS app (SwiftUI and AppKit) with its core in a local Swift package. This document describes the code as it is. [research-and-architecture.md](research-and-architecture.md) is the research and plan from before the MVP; where the two disagree, this document is right.

## Targets

| Target | Kind | Path | Notes |
|---|---|---|---|
| Scene | app | `Sources/Scene` | SwiftUI, Swift 6, warnings are errors |
| scene-tweak | command-line tool | `Sources/SceneTweak` | Private macOS calls. Swift 5 mode. Copied to `Scene.app/Contents/Helpers` |
| SceneKit | local package | `Packages/SceneKit` | The core, with no UI |

## SceneKit modules

Dependencies go one way:

```
SceneFoundation ← SceneThemes ← SceneRenderers ─┐
                              ← SceneEngine ────┴─ SceneIntegrations
SceneSwitcher        (no dependencies)
SceneTestSupport     (used by tests only)
```

| Module | What it holds | Main types |
|---|---|---|
| SceneFoundation | ZIP read and write, comment-preserving JSONC edits, one-key edits in TOML-style files, atomic file writes, marked blocks in text files, running processes, shared errors and versions | `ZipArchive`, `JSONCDocument`, `JSONValue`, `KeyValueDocument`, `FileOps`, `Anchor`, `Processes`, `CLIResult`, `SceneError`, `SemanticVersion` |
| SceneThemes | The theme format: manifest, validation, resolved colors, library, Omarchy import, install from GitHub, search, drafts and their checks, palettes from a few choices or from a picture, and the theme command line | `ThemeManifest`, `ThemeLoader`, `Theme`, `ResolvedVariant`, `Wallpaper`, `RGBA`, `ThemeLibrary`, `OmarchyImporter`, `GitHubRepository`, `ThemeSearch`, `ThemeDraft`, `PaletteCheck`, `OKLCH`, `PaletteRecipe`, `PaletteEdit`, `PaletteExtraction`, `ThemeTool` |
| SceneRenderers | Pure functions from a resolved variant to each app's files | `GhosttyRenderer`, `ITermRenderer`, `KittyRenderer`, `AlacrittyRenderer`, `WarpRenderer`, `TerminalAppRenderer`, `BordersRenderer`, `VSCodeRenderer`, `NeovimRenderer`, `ZedRenderer`, `XcodeRenderer`, `HelixRenderer`, `TmuxRenderer`, `BatRenderer`, `BtopRenderer` |
| SceneEngine | Requests, plans, operations, apply, journal, ledger, history, undo, restore, system services, the experimental tier | `Engine`, `Integration`, `Operation`, `ApplyRequest`, `EngineStore`, `SystemServices`, `LiveSystemServices`, `TweakRunner`, `TweakCatalog` |
| SceneIntegrations | One integration per app or system setting | `WallpaperIntegration`, `AppearanceIntegration`, `AccentColorIntegration`, `IconStyleIntegration`, `BordersIntegration`, `GhosttyIntegration`, `ITermIntegration`, `KittyIntegration`, `AlacrittyIntegration`, `WarpIntegration`, `TerminalAppIntegration`, `VSCodeFamilyIntegration`, `NeovimIntegration`, `ZedIntegration`, `XcodeIntegration`, `HelixIntegration`, `TmuxIntegration`, `BatIntegration`, `BtopIntegration` |
| SceneSwitcher | Carousel selection rules, typing in the switcher, and the shortcut value type | `CarouselSelection`, `SwitcherSearch`, `HotKeySpec` |
| SceneTestSupport | Fixture home folders, fake system services, repository paths | `FixtureHome`, `FakeServices`, `Fixtures`, `Repo` |

## Theme format

A theme is a folder, or a `.scenetheme` ZIP of that folder:

```
theme.json
wallpapers/<name>.jpg|jpeg|png|heic
apps/<name>.json      optional curated overrides for VS Code and Neovim
README.md             optional
```

Anything else is rejected. `ThemeLoader.Limits`: 64 entries, 40 MB in total, 20 MB per image, 1 MB per JSON file, an image long side of 1024 to 8192 px. The image type comes from the file header, not the extension, and must be JPEG, PNG, or HEIC.

`theme.json` (format 1):

- `format`, `id` (`creator/slug`), `version` (semantic version), `name`, `summary`, `authors`, `license` (SPDX), `homepage`, `tags`, `requires`.
- `variants`: `dark`, `light`, or both. Each variant has:
  - `palette`: 15 interface roles. `background`, `foreground`, and `accent` are required. The others are derived when missing.
  - `terminal`: 16 ANSI colors (the 8 normal ones are required; bright ones fall back to normal ones), plus background, foreground, cursor, and selection. A value is `#RRGGBB`, `#RRGGBBAA`, or `@role`.
  - `syntax`: 19 roles. Each is a color, or `{color, bold, italic, underline}`. Missing roles follow fixed fallback chains.
  - `wallpapers`: a list of `{file, fit}`. The first one is the default. `fit` is fill, fit, stretch, or center.
  - `system`: `accentColor` (`auto` or a preset), `iconStyle` (default, dark, clear, tinted), `iconTint`, `highlightColor`.
- `apps`: per-app overrides (`vscode`, `neovim`: `dark` and `light` files in `apps/`, checked by `OverrideValidator`), and `preferInstalled` to use a port the user already has.
- `assets`: the license, attribution, and source of each image.

`ThemeLoader.load` validates in four layers: container (files, sizes, symlinks), schema (strict decoding, identity), meaning (colors parse, references resolve, images check), and overrides. The result is a `Theme` with one `ResolvedVariant` per appearance: typed `RGBA` colors, `[Wallpaper]`, the system look, and validated overrides. `ResolvedVariant.wallpaper(named:)` falls back to the first wallpaper; `wallpaper(after:)` wraps around.

**Themes are data.** Every color is parsed into `RGBA`, and Scene writes the numbers itself, so no string from a theme reaches a config file. The one exception is the theme id, which the loader restricts to `[a-z0-9._-]` and `/`; Warp's theme files are named after it. Neovim gets a fixed Lua shim that reads a JSON data file. Importing runs no code from a theme. The Omarchy importer reads only `colors.toml` (or, when a theme has none, the colors in `alacritty.toml`) and `backgrounds/`. It reads Omarchy 4's named keys and the older `color0` to `color15`, mapped as Omarchy maps them.

**Bundled themes** in `Themes/` are generated by `Scripts/make-bundled-themes.py` from `Scripts/omarchy-palettes/*.toml` (Omarchy's themes), `Scripts/scene-palettes/<folder>/` (Scene's own), and `Themes/WALLPAPER_SOURCES.json`. That file holds each image's provenance, and its `order` field sets each look's wallpaper list. A Scene theme's credits and license come from its `theme.toml`; an Omarchy theme's are Omarchy's.

**`ThemeLibrary`** loads bundled themes from `Scene.app/Contents/Resources/Themes` and installed ones from `~/Library/Application Support/Scene/Themes`. An installed theme with the same id replaces the bundled one. The library also imports (`.scenetheme`, folder, or Omarchy folder), exports, and removes themes.

**Install from GitHub.** `GitHubRepository` reads `https://github.com/owner/repo` (or `owner/repo`) and downloads `archive/HEAD.zip`, at most 150 MB. `ThemeLibrary.installRepository` reads only `theme.json`, `README.md`, `colors.toml`, `wallpapers/`, `backgrounds/`, and `apps/*.json` below the archive's top folder: `ZipArchive.read(_:limits:include:)` validates and counts only those entries. A `theme.json` makes a Scene theme. A `colors.toml` makes an Omarchy theme through the Omarchy importer, named as Omarchy names it (`omarchy-aura-theme` becomes `aura`). Config files and code in the repository are never read. The app remembers each theme's repository (`themeSources`) for Update.

**Drafts.** `ThemeDraft` is a theme being made: name, summary, author, and for each look Omarchy's color keys, the macOS look (accent, icon style, tint), and three wallpapers with optional credits (attribution and source). Licenses are optional: the theme's defaults to MIT, and a wallpaper with credits but no license gets `NOASSERTION` in `assets`. The Theme Maker edits one, and an agent writes one as JSON. Its colors go through `OmarchyImporter.variant`, the mapping Scene's own themes use, so a bundled theme opened as a draft comes back with the same colors (shades Scene mixes itself may differ by 1 in a channel). `check()` lists errors and warnings: missing fields, the palette check (`PaletteCheck`, a port of `Scripts/check-palette.py` with the same thresholds), three wallpapers per look, and each image's type and size. `write(to:)` builds the theme in a scratch folder and loads it with `ThemeLoader`. Then it replaces only `theme.json`, `README.md`, and `wallpapers/<look>-<n>.<ext>` in the target, so the folder can be a git repository with its own files. The README has a picture (the first JPEG or PNG; GitHub shows HEIC only in Safari), install steps, and every credit. The id is `<author>/<name>` in ASCII, so saving the same theme again replaces it.

**Palettes from a few choices.** `PaletteRecipe` holds what a look's palette follows from, in OKLCH: the background (lightness, tint, hue), the text's lightness, the accent, and the seven hues' lightness, vividness, and a shift around the color circle (each hue may also keep its own angle, from a picture). `colors()` builds the palette in Omarchy's keys with the rules of `build_palette` in `Scripts/themekit.py`, which made Scene's own themes; a test checks that both give the same hex values. Then, unless asked not to, it lifts any color below the palette check's error thresholds in lightness, away from what it sits on, so no slider position makes code unreadable (a test sweeps the slider ranges). `PaletteExtraction` is a port of `Scripts/palette-from-image.py`: k-means in OKLab on about 4,000 pixels of a 120 px copy, with a fixed seed, then the background from the picture's darkest (or lightest) third, the accent from a vivid color that stands apart, and each hue from the picture when it has one near its usual angle. It also returns the picture's other vivid colors as accent choices. `PaletteEdit` is a look in the Theme Maker: the recipe, colors set by hand (which win), and, for a look opened from a theme, that theme's exact colors until the first slider moves. `ThemeDraft.preview` resolves a draft in memory, without files, and keeps the macOS look when its values are valid, so the preview can draw it; one slider move, with the preview, takes about 0.5 ms in a Debug build.

**Command line.** `SceneApp.init` runs `ThemeTool` before any window opens: `Scene --check-theme <draft.json>` checks a draft, and `Scene --build-theme <draft.json> <folder> [--install]` also builds it. Each problem is a line that starts with `error` or `warning`; the exit status is 0, 1 for errors, or 2 for a wrong command. `--install` imports the folder and posts the distributed notification `com.insanearts.scene.library-changed`, so a running Scene reloads its themes. The Info.plist key `SceneThemeCommands` (1) tells tools that this Scene has the commands; an older Scene would open its window instead. The skill `skills/create-scene-theme` uses them.

**Icon styles.** The Theme Maker's Dock shows real app icons in the look's icon style. macOS renders the Dark, Clear, and Tinted styles with a private framework, and `NSWorkspace` gives icons only in the Mac's current style. So the Dock takes each app's Default icon from the app's asset catalog, and `IconStyles` works out the other styles from it. It finds the plate's color from a ring inside the icon, and turns the plate dark gray. A glyph lighter than a colored plate takes the plate's color, as Mail's envelope does in macOS. The glyph also comes back as a gray mask, which the view colors for Clear and Tinted. Apps whose icon is only an `.icns` file (Messages, Maps, FaceTime) are left out, because ImageIO would read it, and Scene limits ImageIO to PNG, JPEG, and HEIC.

**Folder import** copies the theme's own files into a scratch folder and validates the copy, so a git repository's `.git` and `LICENSE` stay behind.

**Search.** `ThemeSearch.matches` wants every word of the query to start a word of the theme's name, tags, authors, or looks (`light`, `dark`), ignoring case and accents. `ThemeSearch.ordered` puts favorites first. The sidebar, the switcher, and the menu bar panel use both.

## Engine

The flow is detect, plan, apply, verify, and later undo or restore.

- **`Integration`**: `id`, `displayName`, `kind` (system, experimental, terminal, editor), `detect`, `plan`, `reload`, `verify`. An integration changes nothing itself. `plan` returns operations and the engine runs them. `reload` only asks a running app to re-read its config.
- **`Operation`** is a closed set: `writeManagedFile`, `ensureAnchor` (a marked block in a user's file), `setJSONValue` (a comment-preserving edit), `setConfigValue` (one key in a TOML-style file, as raw TOML text), `setPreference`, `setPreferenceEntry` (one entry of a dictionary preference, such as one Terminal profile), `setWallpaper`, `setAppearance`, `installEditorExtension`, `setTweak`, and `pause`. Each has a `resource` key. `pause` waits between two changes, so an app that watches files loads the first before it reads the second; it changes nothing, and the engine records nothing for it.
- **`SystemServices`** also finds running processes (by bundle id or executable name) and sends signals, so `reload` in tests signals nothing real.
- **`ApplyRequest`**: the theme, the mode (system, light, dark), `effectiveAppearance`, `forcedAppearance`, and `wallpaperName` (the picked background). `nativeVariants` gives apps that switch on their own both variants.
- **Apply.** `Engine.apply` runs integrations in parallel, and each integration's operations in order. The first time a resource is touched, the ledger records its original state, and files are backed up. Each step is journaled as pending, then applied or failed. When an operation fails, that integration's finished operations are reverted and its new ledger entries are dropped. The other integrations continue. Then the integration reloads and verifies. The outcome is applied, applied with a restart needed, applied but partly overridden, needs action, skipped, or failed.
- **History.** Each apply adds a `HistoryEntry`: theme id and version, mode, the integrations that succeeded, the date, the wallpaper file name, and the look it showed. `undo` drops the last entry and applies the previous one with its wallpaper. When there is no previous entry, it restores the original setup. An apply with `replacingLastHistory` replaces the newest entry instead; following macOS Light/Dark uses it, so Undo skips the look changes.
- **Restore** uses a three-way rule per ledger entry, newest first. If the resource still has Scene's value, it goes back to the original. If it already has the original, nothing happens. If the user changed it since, the user's change stays. Apps reload afterwards. `changesOutsideScene` reports resources that no longer have Scene's value.
- **Storage** (`EngineStore`) is in `~/Library/Application Support/Scene`: `Ledger.json`, `History.json`, `Journal/<run>.json`, and `Backups/`. A journal file that is left over means Scene stopped in the middle of an apply, and the app offers to restore those apps. The same folder holds `Wallpapers/` (copies), `VSCode/` (built extensions), `Neovim/theme.json`, and `Themes/` (installed themes).

## Integrations

| id | Changes | How |
|---|---|---|
| `wallpaper` | Every display's wallpaper | Copies the picked image to `Wallpapers/<theme>-<file>` and sets it per display. Each image gets its own path, because Scene verifies a wallpaper by its path |
| `appearance` | Light/Dark | The private SkyLight call when the experimental tier allows it, otherwise System Events (needs the Automation permission). Only when the request forces an appearance |
| `accent` | Accent color | Helper call. `auto` maps `palette.accent` to the nearest macOS preset |
| `iconStyle` | Icon & widget style | Helper call |
| `ghostty` | Ghostty | Writes a theme file per variant in `ghostty/themes` and a `scene.conf` next to the config, then adds one marked `config-file = ?"…/scene.conf"` block at the end of the config, because includes load last. Reloads with SIGUSR2 on 1.2 or later. Verifies with `ghostty +show-config` and reports the user's color lines that override the theme |
| `iterm2` | iTerm2 | A Dynamic Profile in `DynamicProfiles/scene.json` whose parent is the user's default profile |
| `vscode`, `cursor`, `vscodium`, `windsurf` | The VS Code family | Builds a VSIX with Scene Dark and Scene Light (the version comes from a content hash), installs it with the app's own CLI, and sets `workbench.colorTheme`. When `window.autoDetectColorScheme` is on, it sets the `preferred*ColorTheme` keys instead |
| `neovim` | Neovim | Adds `plugin/scene.lua` (a fixed shim that reads and watches the JSON data file) and `colors/scene.lua`. It never edits `init.lua`. The data file is `Application Support/Scene/Neovim/theme.json` |
| `kitty` | kitty | Writes `scene-theme.conf` and adds one marked `include scene-theme.conf` block at the end of `kitty.conf`. When the user has `light-`, `dark-`, or `no-preference-theme.auto.conf` (these override every other color), Scene writes its colors into the ones that exist. Reloads with SIGUSR1 on 0.24 and later; on macOS, older kitty quits on SIGUSR1 |
| `alacritty` | Alacritty 0.13 or later | Writes `alacritty/scene.toml` and adds it last to the user's import list: `general.import` (0.14 and later), or `import` when the file still has the old key (which then wins over `general.import`). A new key goes into `[general]`, or next to `general.…` dotted keys. Color keys in `alacritty.toml` win over imports, so Scene reports them as overrides. Alacritty reloads by itself, but it watches only the imports that existed when it started, so the first apply asks for one restart |
| `warp` | Warp | Needs `~/.warp/settings.toml`, which Warp makes when it moves its old settings; Scene never creates it. Writes one YAML per theme and look in `~/.warp/themes/scene/`, then sets `theme`, `system_theme`, and, for a theme with both looks, `selected_system_themes` in `[appearance.themes]` (absolute paths). Warp repaints only when that setting changes, so each theme gets its own file and name. While Warp runs, a 1-second `pause` sits between the files and the setting: Warp loads theme files through a 500 ms debounce, and a setting that names a theme it has not loaded falls back to Dark |
| `terminal` | Terminal | Adds a “Scene” profile to `Window Settings` (a copy of the default profile with the theme's colors as `NSColor` archives) and makes it the default and startup profile. Terminal reads profiles when it starts, so a running Terminal needs a restart |
| `zed` | Zed | Writes a theme family (`zed/themes/scene.json`, “Scene Dark” and “Scene Light”) and sets `theme` in `settings.json` to `{mode, light, dark}`. Zed reloads both files by itself |
| `xcode` | Xcode | Writes `Scene (Light).xccolortheme` and `Scene (Dark).xccolortheme` in `UserData/FontAndColorThemes` with the fonts and line spacing of the user's current themes, and sets `XCFontAndColorCurrentTheme` and `XCFontAndColorCurrentDarkTheme`. A running Xcode needs a restart |
| `helix` | Helix | Writes `helix/themes/scene.toml` and sets `theme` in `config.toml`, or `light` and `dark` under `[theme]` when the file uses that table. Reloads with SIGUSR1 |
| `tmux` | tmux | Writes `tmux/scene.conf` (`set -gq` style options) and adds one marked `source-file -q` block to `~/.tmux.conf` or the XDG file. Loads it into a running server. After a restore, unsets Scene's options on the server and loads the user's config again |
| `bat` | bat and delta | Writes `scene-dark` and `scene-light` `.tmTheme` files (the same token rules as the VS Code theme), adds a marked block to bat's `config` (`--theme=auto:system` with both themes on bat 0.25 and later), and runs `bat cache --build`, also after a restore. With delta installed, writes `git/scene-delta.gitconfig` (syntax theme and diff colors) and includes it from the global git config. delta reads bat's cache at its default place |
| `btop` | btop | Writes `btop/themes/scene.theme` and sets `color_theme` in `btop.conf`. Reloads with SIGUSR2 on 1.3.1 and later |
| `borders` | JankyBorders | Adds one marked `borders active_color=… inactive_color=…` line at the end of `~/.config/borders/bordersrc` (or `~/.bordersrc`), which borders runs when it starts without arguments. While borders runs, sends it the file's last colors. It never calls `borders` otherwise, because `borders` with arguments starts a new instance when none runs |

## Experimental tier

- Private calls run only in the `scene-tweak` helper, a separate process, so a crash cannot take the app down. Commands: `check`, `get <id>`, and `set <id> <json>`, with JSON in and out. The ids are `appearance`, `accent`, and `iconStyle`.
- The calls: SkyLight `SLSSetAppearanceThemeNotifying` and `SLSSetAppearanceThemeSwitchesAutomatically` (Light/Dark and Auto), AppKit `NSColorSetUserAccentColor` (accent), and `SLSIconAppearanceConfiguration` (icon style and tint; a custom tint is stored in `AppleIconAppearanceCustomTintColor`). The helper reads each value back after setting it and reverts it on a mismatch.
- `TweakRunner` allows a call only when Settings has the tier on and the macOS build is in `TweakCatalog.testedBuilds` (now 25G83 for all three), unless "Allow on macOS versions Scene has not tested" is on. `Scripts/verify-tweaks.sh` tests a new macOS build.

## App (Sources/Scene)

| File | What it holds |
|---|---|
| `SceneApp.swift` | The `@main` app: the main window, the Theme Maker window, the theme command line (see Command line), menu commands (Check for Updates…, New Theme…, Install Theme from GitHub…, Switch Theme…, Next Background, Undo Last Theme ⌥⌘Z), the Settings scene, and the menu bar panel (a `.window` style menu bar extra). `AppDelegate` keeps Scene running when its window closes, and at launch registers the shortcuts, starts watching Light/Dark and the library, and starts the updater |
| `ThemeMaker.swift` | The Theme Maker window. On the left, a large live `DesktopPreview` of the look on its wallpaper, with the wallpaper's blurred light behind it, the palette strip (click a color to set it by hand), and the look's three wallpaper slots (choose, drop). The preview has an open File menu, whose highlighted item shows the macOS accent, and a Dock in the chosen icon style. On the right, sliders whose tracks show their colors: background hue, tint, and lightness; text contrast with its ratio; accent hue, vividness, and lightness; code colors' vividness, brightness, and hue shift; then the macOS look and the details. The header has the name, Dark and Light, Undo (⌘Z), Shuffle, and From Wallpaper; the footer has the checklist, Start From, Export Folder…, and Save to Scene |
| `AppModel.swift` | `@Observable` state and actions: themes, detections, history, ledger, settings, background picks, plan, apply, quick apply, undo, restore, Next Background, shortcut registration, and `Locations` (bundled themes, helper) |
| `ContentView.swift` | The main window: a sidebar with a search field, Apps, History, Favorites, and every theme (wallpaper thumbnail and palette), the theme page with its star, the background picker, and Apply, import, the Install from GitHub sheet, and a toolbar with the switcher, Add Theme, undo, and Settings |
| `ApplySheet.swift` | The plan: a wallpaper header, the appearance mode, each app with its icon, a switch, and its changes, and the results |
| `OtherViews.swift` | The Apps page (a switch per app in Desktop, Terminals, Editors, Command-line tools, and macOS look, and Stop Managing), the History page, Settings (General with Light and Dark and Updates, Shortcuts, Experimental), `ShortcutRecorder`, and the menu bar panel with its search field and favorites first |
| `Updater.swift` | Sparkle, wrapped so nothing else imports it: it starts at launch (not in snapshot mode), runs Check for Updates, and mirrors whether Sparkle can check, when it last checked, and the automatic-check setting |
| `ThemeSwitcher.swift` | The full-screen carousel: an `NSPanel` per screen (non-activating, `.screenSaver` level), key handling, and the status HUD. Every screen shows the selected theme's wallpaper, blurred. Favorites come first. Typing searches: each letter narrows the cards and selects the first match, ⌫ deletes, and Esc clears the search before it closes. Digits still jump to a card |
| `HotKey.swift` | Global shortcuts through Carbon `RegisterEventHotKey`, which needs no permission. Id 1 is the switcher, id 2 is Next Background |
| `Previews.swift` | Desktop, terminal, and code previews in a theme's colors, and the thumbnail cache (one entry per image and size). With `showsSystem`, the desktop preview adds an open menu in the macOS accent and a Dock of real app icons in the icon style (see Icon styles) |
| `Design.swift` | Shared parts of the look: the blurred wallpaper backdrop, palette dots, keycaps, pills, cards, the capsule button, app icons, and a Liquid Glass helper |
| `Snapshot.swift` | `SCENE_SNAPSHOT` mode, which renders the windows to PNG files through the window server, without screen recording |

**Look.** A theme's page shows the theme in its own light or dark look (`colorScheme`) on its own wallpaper, blurred (`AmbientBackground`), and its Apply button takes the theme's accent color. The switcher, always dark, shows the selected theme's wallpaper, blurred, on every screen. The Apply sheet has the wallpaper as its header and the accent color on its Apply button. The sidebar, the sheet's list, Apps, History, and Settings follow macOS. `AppIcon` shows an app's own icon, found by bundle id, or a System Settings–style tile for macOS settings, Neovim, and apps that are not installed. `View.glass(in:)` uses Liquid Glass on macOS 26 and a material before.

Settings and state live in `UserDefaults` (`com.insanearts.scene`):

| Key | Meaning |
|---|---|
| `experimentalEnabled` | Private calls are on (default: on) |
| `allowUntested` | Private calls may run on untested macOS builds |
| `showMenuBarExtra` | Show the menu bar icon |
| `favoriteThemes` | Starred theme ids. They come first in every list |
| `themeSources` | The GitHub repository of each theme installed from one, by theme id |
| `followSystemAppearance` | Switch the current theme's look when macOS switches Light/Dark (default: off) |
| `themeAuthor` | The author name the Theme Maker fills in. Default: the account's full name |
| `disabledIntegrations` | Apps a theme leaves alone. Set on the Apps page, in the Apply sheet, and by Stop Managing |
| `backgroundChoices` | The picked wallpaper file per `"<theme id>#<appearance>"` |
| `switcherShortcut`, `nextBackgroundShortcut` | `HotKeySpec` as JSON. No value means the default, empty data means off |

**Updates.** Sparkle 2 (a Swift package of the app target) checks `SUFeedURL` in `Config/Scene-Info.plist`: the `appcast.xml` attached to the latest release of InsaneArts/Scene, so the feed works only while the repository is public. Sparkle installs an update only when its EdDSA signature matches `SUPublicEDKey` in the same file. The private key is in the release Mac's login Keychain, account `Scene`. Sparkle checks once a day by default (`SUEnableAutomaticChecks`, `SUScheduledCheckInterval`), keeps its own `SU…` keys in `UserDefaults`, and shows its own windows. Settings → General → Updates shows the version, Check for Updates…, and the automatic-check switch.

**Following Light/Dark.** With `followSystemAppearance` on, `AppModel` watches `NSApp.effectiveAppearance`. One second after macOS switches, and once Scene is idle, it applies the current theme again with the mode “system” when `HistoryEntry.needsOtherLook` says so: the theme has both looks, and the newest entry shows the other one. The apply replaces the newest history entry. A theme with one look never switches macOS back, and nothing runs in snapshot mode.

**Next Background** takes the current theme (the last history entry), moves the pick for the current look to the next wallpaper, and applies only the `wallpaper` integration through the engine, so Undo and Restore still work.
