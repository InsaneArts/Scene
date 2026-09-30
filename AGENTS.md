# AGENTS.md

Scene is a native macOS app that gives the desktop, terminals, and code editors one theme in one step, like Omarchy does on Linux. It shows every change first and can put the original setup back. The repository is InsaneArts/Scene (private).

## Read first

- [docs/STATUS.md](docs/STATUS.md): what works, what is not verified yet, and the decisions that belong to the user.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how the code is written. Read the section for the area you change.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): build, tests, checking UI, bundled themes, release.
- [docs/research-and-architecture.md](docs/research-and-architecture.md): the research and plan from before the MVP. Where it disagrees with the code, the code and ARCHITECTURE.md are right.

## Making a change

1. Put logic in `Packages/SceneKit` and cover it with Swift Testing tests. The app target has no tests.
2. Build with warnings as errors, and run `./Scripts/test.sh`. Both must pass.
3. Check UI changes in snapshot mode (DEVELOPMENT.md → Checking UI) and look at the images.
4. Update ARCHITECTURE.md when the design moves, STATUS.md when the state changes, and README.md for changes a user sees.
5. Commit and push only when the user asks. So far, work has gone straight to `main`.

## Rules

- Ask before changing the user's live setup: the live tests (`SCENE_LIVE=1`), `Scripts/verify-tweaks.sh`, applying a theme, or anything that writes their config files, wallpaper, or macOS settings.
- Ask before running `Scripts/release.sh`. It sends the app to Apple for notarization.
- The user may be at the Mac. Run snapshot mode in the background with `SCENE_SNAPSHOT_SWITCHER=0`, because the real switcher takes keyboard focus and ↩ applies a theme.

## Conventions not visible in the code

- **Toolchain.** `xcode-select` points at an Xcode 27.1 beta. Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for every `swift` and `xcodebuild` call. The scripts do this already.
- **Xcode project.** It lists files one by one. Add a new file in `Sources/Scene` or `Sources/SceneTweak` to `Scene.xcodeproj`, or it is not compiled. Files in `Packages/SceneKit` need nothing.
- **Every system change goes through the Engine** as an `Operation`. Calling `SystemServices` from the app would break Undo and the three-way Restore.
- **Themes are data.** Parse colors into `RGBA` and write the numbers. Never copy a string from a theme into a config file, and never run code from a theme.
- **Private macOS calls** live only in the `scene-tweak` helper and run only on builds in `TweakCatalog.testedBuilds`. Add a macOS build there only after `Scripts/verify-tweaks.sh` passes on it.
- **Modules.** Dependencies go one way (see ARCHITECTURE.md). Anything used across modules must be `public`. SceneIntegrations declares `typealias Operation = SceneEngine.Operation`, because Foundation has an `Operation` too.
- **Swift.** Swift 6 language mode everywhere except `scene-tweak`, which uses Swift 5 mode because it works with raw C function pointers.
- **Bundled themes are generated.** Edit `Scripts/make-bundled-themes.py`, `Scripts/scene-palettes/`, or `Themes/WALLPAPER_SOURCES.json` (through `Scripts/add-wallpaper.py`), then run the script. Don't edit `Themes/*/theme.json` by hand, and leave `Scripts/omarchy-palettes/` as Omarchy ships it. The `scene-theme` skill (`.claude/skills/scene-theme/`) makes new themes.
- **Global shortcuts** use Carbon `RegisterEventHotKey`, with id 1 for the switcher and id 2 for Next Background. A shortcut needs ⌘ or ⌃, because macOS 15 and later refuse Option-only ones.
- **Wallpapers.** Each copy gets its own file name, because Scene verifies a display's wallpaper by its path.
- **Updates.** Sparkle's feed URL and public key are in `Config/Scene-Info.plist`. The private key lives only in the release Mac's Keychain, account `Scene`; never commit it. Publishing a GitHub release is the user's step (DEVELOPMENT.md → Release).

## Commands

| Task | Command |
|---|---|
| Tests | `./Scripts/test.sh` |
| Debug build | see DEVELOPMENT.md → Build and run |
| App bundle | `./Scripts/package_app.sh` → `build/Scene.app` |
| Bundled themes | `python3 Scripts/make-bundled-themes.py` |
| Release (ask first) | `./Scripts/release.sh` |
