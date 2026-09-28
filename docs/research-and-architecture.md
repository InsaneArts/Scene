# Scene: research, scope, and architecture

Research date: 2026-09-28. Test Mac: macOS 26.6.2 (25G83), Apple silicon. macOS 27 shipped on 2026-09-14 ([Comm](https://9to5mac.com/2026/09/22/macos-27-gives-you-more-control-over-liquid-glass/)). This document notes where 27 changes something. "Scene" is a working name taken from the project folder. The folder is empty apart from a stray `default.profraw`, so there is no existing structure to follow.

Every capability claim has one evidence label. The label is a link when a source exists.

| Label | Meaning |
|---|---|
| **Doc** | Vendor documentation, or metadata the vendor ships in the app (scripting dictionary, built-in help) |
| **Src** | Read in source code |
| **Local** | Checked on the test Mac with a read-only command or an isolated fixture. No live setting was changed. Appendix A lists the checks. |
| **Comm** | Community source: issue, forum post, blog, third-party project |
| **Inferred** | Reasoning only. An experiment in §10 must confirm it. |

Contents: 1 Verdict · 2 Omarchy · 3 Feasibility matrix · 4 Scope · 5 Theme format · 6 Architecture · 7 Apply and restore · 8 Theme store · 9 User experience · 10 Risks and experiments · 11 Roadmap · 12 Open questions · A Local checks

---

## 1. Verdict

**Feasible, with a narrower promise than "theme the whole Mac".**

Scene can reliably coordinate four groups:

- **Wallpaper**, through a public API. Limit: it changes only the current Space of each display.
- **Light/Dark mode**, through System Events scripting, after one macOS permission prompt.
- **Terminals**: Ghostty, iTerm2, kitty, Alacritty, WezTerm, and, with more friction, Terminal.app.
- **Code editors**: VS Code and its forks, Neovim, Vim, Zed, and Xcode up to version 26 (after a restart). Xcode 27 changed its theme format and comes later.

Scene cannot set custom colors in Slack, Discord, Safari, or Chrome through any supported route. These apps can only follow Light/Dark. Firefox is the one browser with an official path, through a companion extension.

Accent color, icon and widget style, Liquid Glass, and the menu bar background have no public API. Scene reaches them in an **experimental tier** through the same private calls that System Settings makes (§6.8). The tier works only on macOS builds that Scene has tested, and any macOS update can break it.

**Recommended promise:** "Scene gives your desktop, terminals, and code editors one theme in one step. It shows every change first, and it can put your original setup back."

| # | Decision | Recommendation | Main alternative | Practical tradeoff |
|---|---|---|---|---|
| D1 | Scope | Desktop and developer tools. Chat apps and browsers follow Light/Dark only. | "The whole Mac" | A smaller claim, but every claim holds |
| D2 | Distribution | Developer ID, notarized, not sandboxed. Sparkle updates and a Homebrew cask. | Mac App Store | No store discovery or Apple billing. In return Scene can edit dotfiles, signal apps, and run their CLIs, which the sandbox blocks (§6.7). |
| D3 | How Scene changes an app | Scene-owned files plus one marked include line in the user's config | Edit the user's config in place | Each app's include rules must be learned. Restore becomes simple, and user lines and comments stay untouched. |
| D4 | Integration code | Integrations return plans. One engine applies, records, verifies, and undoes. | Each integration applies and restores itself | More engine work first. Restore and crash recovery are written once. |
| D5 | Extensibility | Built-in integrations, some data-driven. No plugins at launch. | External plugin system | Niche apps wait for app updates. No third-party code runs. |
| D6 | Theme model | Own JSON format: semantic roles plus curated per-app overrides. base16 and others are imported. | base16/base24 as the native model | More spec work. Room for wallpaper, system settings, and curation. |
| D7 | Theme content | Data only. Only validated, typed values reach config files. | Allow hooks or scripts | Some effects are impossible. The store is safe to browse. |
| D8 | Light/Dark | Use each app's own light/dark switching. Scene forces the system appearance only when the user asks. | Scene switches every app on each appearance change | Apps without native switching need Scene running. |
| D9 | Store | Git registry, CI, signed static index, CDN | Custom backend with accounts | Creators need GitHub. No servers to run. |
| D10 | Main interface | Window app with an optional menu bar extra | Menu bar only | More interface to build. The plan and the results get room. |
| D11 | Settings without a public API | An experimental tier of private calls, run in a small helper process, on tested macOS builds only | Leave these settings out | The look reaches accent color, icon tint, and Liquid Glass. Each macOS release needs a test pass before the tier turns on. |

---

## 2. Omarchy: what to take

### 2.1 How Omarchy themes work

Read at tag v4.0.4 (2026-09-14). The repository moved from `basecamp/omarchy` to `omacom/omarchy`.

- **A theme is a folder.** Since [v3.3.0](https://github.com/omacom/omarchy/releases/tag/v3.3.0) (2026-01-07) its core is `colors.toml`. In v4 that file has `mode` and 25 keys: `accent`, `selection`, `muted`, four backgrounds, four foregrounds, eight hues, and six bright hues (Local: `themes/tokyo-night/colors.toml`). A theme also has `backgrounds/`, `preview.png`, `icons.theme`, and optional hand-written per-app files.
- **Templates generate per-app files.** 19 templates in `default/themed/` use `{{ key }}`, `{{ key_strip }}`, and `{{ key_rgb }}` ([Src](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-theme-set-templates)). A file shipped by the theme wins over a user template, which wins over a built-in template.
- **Applying** ([Src](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-theme-set)): take a lock, stage the theme, render templates, and replace `~/.local/state/omarchy/current/theme` with `rm` then `mv` (not atomic). Then push colors to the desktop shell over IPC, run 16 per-app reload commands in parallel, and run user hooks.
- **Each app includes a file from the current theme and gets a reload nudge:**

| App | Reads the theme through | Reload |
|---|---|---|
| kitty | `include` | SIGUSR1 |
| Ghostty | `config-file = ?"…"` | SIGUSR2 |
| Alacritty | `general.import` | `touch` on the main config |
| Neovim | A LazyVim spec, symlinked to the theme's `neovim.lua`, that names an upstream colorscheme plugin | A hot-reload plugin ([Src](https://github.com/omacom/omarchy-pkgs/tree/e2bc7586e2bebfa09365fc5e32059969f0714ddc/pkgbuilds/omarchy-nvim)) |
| VS Code, Cursor, VSCodium | Installs the Marketplace extension the theme names, or generates a local extension | Edits `workbench.colorTheme` |
| Chromium, Chrome, Brave, Edge | A root helper writes a managed `BrowserThemeColor` policy | `--refresh-platform-policy` ([Src](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-theme-set-browser)) |

- **VS Code caches themes.** Omarchy's development branch derives the generated extension's version from the theme content. Its comment: "VS Code caches loaded color themes in memory and only rebuilds a registry entry when the providing extension changes". It also sets an undocumented `_watch: true` on the theme ([Src](https://github.com/omacom/omarchy/blob/349ecc09a2184d73c9807e294a2a720ef0e94459/bin/omarchy-theme-set-vscode), Local).
- **Community themes** install from a git URL. Since v4.0.1 a cloned theme loses `*.lua` files, terminal configs, `vscode.json`, and symlinks, because they can run code ([Doc](https://github.com/omacom/omarchy/blob/v4.0.4/docs/theming.md), Local). A registry created on 2026-09-07 checks theme repositories in CI and pins each one to a validated commit ([Doc](https://github.com/omacom/omarchy-theme-registry)).
- **Theme data has already been an attack path.** [v4.0.0](https://github.com/omacom/omarchy/releases/tag/v4.0.0) closed "three code-execution paths a malicious theme could take through install (colors.toml values reaching GNU sed's `e` flag, an unescaped VS Code theme name, unvalidated keyboard RGB)" (Local: release notes). Omarchy's docs call their file filter "a statement about where a theme came from and not a sandbox".

### 2.2 Take and leave

| Take | Leave |
|---|---|
| One folder per theme: palette, backgrounds, optional per-app files | Desktop shell theming (bar, borders, notifications, lock screen). macOS has no API for these. |
| App-owned templates, with hand-tuned per-theme files that win | GTK, gsettings, and icon themes |
| An include line plus a reload nudge per app | A root-owned browser policy behind a sudoers rule |
| Pointing an editor at an upstream theme the user already has | Git repositories as the package format |
| A lock around theme switches; render first, then swap | A non-atomic swap; update and remove that leave the applied theme stale |
| Two trust levels, turned into one stricter rule: every theme is data | A denylist of dangerous files. Scene uses an allowlist. |

Omarchy does not show a plan, back up user files, or restore an original setup. `omarchy reinstall configs` copies defaults over the user's files without a backup ([Src](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-reinstall-configs)). These three gaps are where Scene earns trust.

Omarchy-style dotfiles for macOS already exist. [macarchy](https://github.com/jlargs64/macarchy/blob/main/docs/theme-system.md) reloads Ghostty with SIGUSR2 and kitty with SIGUSR1, uses an iTerm2 Dynamic Profile, and restarts `WallpaperAgent` for wallpapers. [omarchy-mac](https://github.com/mattvv/omarchy-mac/blob/main/bin/theme.py) sets Light/Dark through System Events (Comm). They use the same mechanisms this document recommends.

---

## 3. Feasibility matrix

**Columns.** *Themable*: what Scene can change. *Mechanism*: what Scene uses. *Takes effect*: live, after a reload, or after a restart. *Setup and permission*: one-time user steps and macOS prompts. *Restore*: how Scene undoes it. *Level*: Official (documented mechanism), Scripting (documented AppleScript or CLI), Private API (experimental tier, §6.8), Undocumented, Manual, Light/Dark only, or Unavailable.

Every mechanism below needs an app outside the sandbox, except the wallpaper (§6.7).

### 3.1 macOS

| Surface | Themable | Mechanism | Takes effect | Setup and permission | Restore | Level |
|---|---|---|---|---|---|---|
| Wallpaper | Image per display; fit or fill; fill color | `NSWorkspace.setDesktopImageURL(_:for:options:)` ([Doc](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:))) | Live, but only on the current Space of each display ([Comm](https://github.com/sindresorhus/macos-wallpaper/issues/23)). On Tahoe a programmatic set can turn off "Show on all Spaces" ([Comm](https://developer.apple.com/forums/thread/814926)). | None | Read the URL and options per display first (Local). The image must stay at its path, because the wallpaper store references it by URL (Local). | Official |
| Light/Dark | Light, Dark, or Auto | System Events `appearance preferences` → `dark mode` (Local: scripting dictionary). No public setter exists ([Doc](https://developer.apple.com/documentation/appkit/choosing-a-specific-appearance-for-your-macos-app)). Experimental alternative: `SLSSetAppearanceThemeNotifying`, the call System Settings makes, and `SLSSetAppearanceThemeSwitchesAutomatically` for Auto (Local, §6.8). | Live in all apps ([Src](https://github.com/sindresorhus/dark-mode/blob/main/Sources/DarkMode.swift)) | System Events: one Automation prompt and the entitlement `com.apple.security.automation.apple-events` ([Doc](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.automation.apple-events)). The private path needs no prompt (Inferred, E2). | Read `AppleInterfaceStyle` and the Auto state. System Events has no Auto property (Local), so only the private path can restore Auto. | Scripting; private alternative |
| Highlight color | Text selection color, any RGB | System Events `highlight color` (Local: scripting dictionary), or the experimental `NSColorSetUserHighlightColor` | Live (Inferred) | Same prompt, or none on the private path | Read `AppleHighlightColor` | Scripting |
| Accent color | 8 presets | Experimental: `NSColorSetUserAccentColor`, which System Settings calls (Local: exported by AppKit, imported by the Appearance pane). The older route, `AppleAccentColor` plus two distributed notifications, worked through macOS 12 ([Comm](https://alexwlchan.net/2022/changing-the-macos-accent-colour/)) but System Settings stopped posting the notification on 26 ([Comm](https://bugs.openjdk.org/browse/JDK-8367370)). A public route to test: the "Update Accent color" Settings intent through a user-installed Shortcut (Local, untested). | Live (Inferred) | None expected (§6.8) | Read `AppleAccentColor` | Private API |
| Icon and widget style, tint, default folder color | Default, Dark, Clear, or Tinted; a tint name or a custom color | Experimental: the Objective-C class `SLSIconAppearanceConfiguration`, with typed setters and `save` (Local: runtime listing). The tint also sets the default folder color ([Comm](https://eclecticlight.co/2025/09/18/customising-folders-in-tahoe/)). Logout-only fallback: the `AppleIconAppearanceTheme` key ([Src](https://github.com/nix-darwin/nix-darwin/blob/master/modules/system/defaults/NSGlobalDomain.nix)). | Live for apps with Icon Composer icons. Apps that ship only ICNS icons keep them ([Comm](https://github.com/stablyai/orca/issues/16495)). | None expected | Read the current configuration object | Private API |
| Liquid Glass (26.1+) | Clear or Tinted; a slider on 27 | Experimental: the Swift-only `NSGlassEffectView.Legibility.setSystemLegibility(_:completionHandler:)` (Local: exported by AppKit, imported by the pane). macOS 27 replaced the control with a slider ([Comm](https://9to5mac.com/2026/09/22/macos-27-gives-you-more-control-over-liquid-glass/)). | Live (Inferred) | None expected | Read `NSGlassDiffusionSetting` (Local) | Private API, most fragile |
| Menu bar background | Shown or hidden | Experimental: `SLSSetMenuBarUseBlurredAppearance` (Local: exported) | Live (Inferred) | None expected | Read `SLSMenuBarUseBlurredAppearance` (Local) | Private API |
| Pointer colors | Outline and fill | Private HIServices calls exist (Local) | n/a | n/a | n/a | Not planned: people set it for visibility, as an accessibility setting |
| Dock, login window, screen saver | n/a | No color surface, or no API at all | n/a | n/a | n/a | Unavailable |

### 3.2 Terminals

| App (version) | Themable | Mechanism | Takes effect | Setup and permission | Restore | Level |
|---|---|---|---|---|---|---|
| Ghostty 1.3.1 | 16 ANSI (up to 256), background, foreground, cursor, selection, split divider, search | Two theme files in `~/.config/ghostty/themes/`. A Scene file sets `theme = light:scene-light,dark:scene-dark`. One anchor: `config-file = ?scene.conf` ([Doc](https://ghostty.org/docs/config), Local). | After a reload. SIGUSR2 reloads on macOS from 1.2 ([Src](https://github.com/ghostty-org/ghostty/pull/7759)). Version 1.1 has no handler, so the signal would quit it (Inferred), and Scene checks the version first. Ghostty does not watch files ([Comm](https://github.com/ghostty-org/ghostty/discussions/3643)). Light/Dark switching is native. | None | Remove the anchor and the files | Official |
| iTerm2 3.7.3 | Full palette with light/dark pairs; link, tab, badge, underline colors | A Dynamic Profile JSON file. Its parent is the user's default profile, and it sets "Use Separate Colors for Light and Dark Mode" ([Doc](https://iterm2.com/documentation-dynamic-profiles.html), [Doc](https://iterm2.com/downloads/stable/iTerm2-3_5_0.changelog)). | Live for sessions on that profile; iTerm2 watches the folder | One time: make "Scene" the default profile. The Python API can do it, but needs "Enable Python API" and an Automation prompt ([Doc](https://iterm2.com/python-api-auth.html)). | Reset the default profile if it is Scene's, then delete the file | Official |
| kitty 0.49.1 (0.44.0 on test Mac) | Full palette, tab bar, borders, URL color | Anchor `include scene-theme.conf` at the end of kitty.conf, because position decides (Local). For native Light/Dark, the `*-theme.auto.conf` files (0.38+), which "override all other colors" ([Doc](https://sw.kovidgoyal.net/kitty/kittens/themes/)). | Live after SIGUSR1 ([Doc](https://sw.kovidgoyal.net/kitty/conf/)). New auto files need one kitty restart. | None | Remove the anchor; put back the user's auto files | Official |
| Alacritty 0.17 | Full palette, cursor, selection, search, hints | Scene file as the last `general.import` | Live; imports are watched from 0.14 ([Doc](https://alacritty.org/config-alacritty.html)). No Light/Dark support ([Comm](https://github.com/alacritty/alacritty/issues/5999)). | None. `[colors]` in the main file override imports, so Scene reports them. | Remove the anchor | Official |
| WezTerm 20240203 (nightly 2026-09-27) | Full palette, tab bar, title bar | A generated Lua module plus one line, `require('scene').apply_to_config(config)`. `wezterm.gui.get_appearance()` picks the variant ([Doc](https://wezterm.org/config/lua/wezterm.gui/get_appearance.html)). | Live; files loaded with `require` are watched ([Doc](https://wezterm.org/config/lua/wezterm/add_to_config_reload_watch_list.html)) | One time: the user adds the line. Scene never edits Lua. | Delete the module; the user removes the line | Official |
| Terminal.app 2.15 | 16 ANSI, background, text, bold, selection, cursor (Local: profile keys) | A generated `.terminal` profile per variant, imported once. AppleScript sets `default settings`, `startup settings`, and each tab's `current settings`. AppleScript exposes only 4 colors (Local), so the import is required. | Live through AppleScript. No native Light/Dark ([Comm](https://discussions.apple.com/thread/256198096)). | Automation prompt. Import opens a window ([Src](https://github.com/mathiasbynens/dotfiles/blob/main/.macos)), and a same-name import creates "Name 1" ([Comm](https://github.com/fcreme/TerminalStyles/pull/24)). Terminal rewrites its plist on quit. | Set the previous profiles back through AppleScript | Scripting |

Shell theme scripts (tinted-shell, formerly base16-shell) send color escape sequences at shell start. Those colors survive config reloads in Ghostty, Alacritty, and WezTerm ([Src](https://github.com/tinted-theming/tinted-shell)). Scene detects these scripts and warns instead of fighting them.

### 3.3 Editors

| App (version) | Themable | Mechanism | Takes effect | Setup and permission | Restore | Level |
|---|---|---|---|---|---|---|
| VS Code 1.136.2 (1.139 current); Cursor 3.21; VSCodium; Devin Desktop (formerly Windsurf) | Workbench colors, token colors, semantic tokens, integrated-terminal ANSI ([Doc](https://code.visualstudio.com/api/references/theme-color)) | A generated theme-only extension, installed with the CLI inside each app bundle (Local: a hand-built VSIX installs without `vsce`; a folder missing from `extensions.json` is ignored). Settings: `workbench.colorTheme`, or the `workbench.preferred{Dark,Light}ColorTheme` keys when `window.autoDetectColorScheme` is on ([Comm](https://github.com/microsoft/vscode/issues/91231)). | Settings apply live ([Src](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/themes/browser/workbenchThemeService.ts)). CLI installs appear without a restart ([Src](https://github.com/microsoft/vscode/blob/main/src/vs/platform/extensionManagement/node/extensionsWatcher.ts)). Changed theme content is live only with the undocumented `_watch: true`; otherwise reinstall with a new version (E6). | None. One install per VS Code profile. | Uninstall the extension; three-way rule on settings (§7.2) | Official, plus one undocumented flag |
| Neovim 0.11.5 (0.12.5 current) | All highlight groups, including Tree-sitter and LSP groups; `terminal_color_0..15` for new terminals ([Doc](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/terminal.txt)) | A Scene-owned `~/.config/nvim/plugin/scene.lua` (fixed code) reads a JSON data file and applies highlights. It watches the data folder. A documented alternative is `autocmd Signal SIGUSR1` plus `pkill -USR1 -x nvim` ([Doc](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/autocmd.txt)). | Live in every running instance (Local, also under lazy.nvim with `rtp.reset`) | None. `NVIM_APPNAME` or a custom `XDG_CONFIG_HOME` moves the folder, so Scene asks. | The shim switches running instances back to the colorscheme it replaced. Then Scene deletes both files. | Official |
| Vim 9.2, MacVim | Highlight groups | `~/.vim/colors/scene.vim` and `~/.vim/plugin/scene.vim` with a `SigUSR1` autocommand ([Doc](https://github.com/vim/vim/blob/master/runtime/doc/autocmd.txt)) | Live after SIGUSR1 | Detect `~/.vim` or `~/.config/vim` | Delete the files | Official |
| Zed 1.20.2 (1.21 current) | About 70 UI keys, a syntax map, 28 terminal keys, player colors ([Doc](https://zed.dev/docs/extensions/themes)) | Theme family JSON in `~/.config/zed/themes/`; settings `"theme": {"mode": "system", "light": …, "dark": …}` ([Doc](https://zed.dev/docs/themes)) | Live. Release builds watch the themes folder and the settings file ([Src](https://github.com/zed-industries/zed/blob/main/crates/zed/src/main.rs)). | None | Delete the file; three-way rule on settings | Official |
| Xcode 15–26 (26.6 on test Mac) | Editor (28 syntax keys), console, markup. Fonts are stored inside the theme (Local). | A generated `.xccolortheme` in `~/Library/Developer/Xcode/UserData/FontAndColorThemes/`. Keys `XCFontAndColorCurrentTheme` and `XCFontAndColorCurrentDarkTheme` (Local). | After an Xcode restart ([Comm](https://github.com/kylereddoch/catppuccin-xcode)) | None. Scene copies the user's fonts into the generated theme. | Three-way rule on the keys; delete the file | Undocumented format, stable keys |
| Xcode 27 | Themes generated from a base palette, OKLCh colors, fonts stored separately, per-workspace themes ([Doc](https://developer.apple.com/videos/play/wwdc2026/258/)) | A `.xcworkspacecolortheme` file, format known only from reverse engineering ([Comm](https://github.com/kylereddoch/catppuccin-xcode)). The selection is JSON in `DVTWorkspaceThemeSettings` with `light` and `dark` entries (Local, 27.1 beta). | After a restart | Possibly one manual pick in Settings → Appearance (E8) | Three-way rule on the key | Undocumented and new |

### 3.4 Chat apps and browsers

This section is about each app's own interface. Restyling web pages (Dark Reader and similar) is a different product. It breaks per site, and Scene does not do it.

| App (version) | Interface theming exists? | What Scene can do | Level |
|---|---|---|---|
| Slack 4.52 | Yes, by hand: built-in themes, custom color pickers, a share string, and "Import theme → Paste your legacy theme colors" ([Doc](https://slack.com/help/articles/205166337-Change-your-Slack-theme)) | Follow Light/Dark when Slack's Color Mode is System ([Doc](https://slack.com/help/articles/360019434914-Use-dark-mode-in-Slack)). Optional manual step: copy a generated legacy theme string for the user to paste. There is no API: `slack://` has no theme path, and Slack's API terms rule out the undocumented preferences method ([Doc](https://slack.com/terms-of-service/api)). | Light/Dark only, plus manual paste |
| Discord 0.0.413 | Yes, by hand: Light, Ash, Dark, Onyx, "Sync with computer"; Nitro custom themes ([Doc](https://discord.com/blog/bring-your-vibe-to-discord-with-new-themes-in-nitro)) | Follow Light/Dark through Sync. Client mods break Discord's terms: "using any unauthorized software designed to modify the services" ([Doc](https://discord.com/terms)). | Light/Dark only |
| Safari 27 | No. It follows the system. The tab bar can take its color from the page ([Doc](https://support.apple.com/guide/safari/ibrw1012/mac)). | Nothing for the interface. A Safari web extension can restyle page content only ([Doc](https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension)). | Light/Dark only |
| Chrome 153, Brave 154 | Yes: theme extensions and the Customize Chrome color picker | Follow Light/Dark. Extensions have no runtime theme API ([Doc](https://developer.chrome.com/docs/extensions/reference/api)). `BrowserThemeColor` applies live but only as a mandatory policy ([Src](https://github.com/chromium/chromium/blob/main/components/policy/resources/templates/policy_definitions/Miscellaneous/BrowserThemeColor.yaml)). On macOS, `defaults write` sets policies at the "recommended" level ([Doc](https://www.chromium.org/administrators/mac-quick-start/)), so the policy needs MDM or a configuration profile. | Light/Dark only |
| Firefox | Yes | A companion extension calls `browser.theme.update()` ([Doc](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/theme/update)). Scene sends colors through a per-user native messaging host ([Doc](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_manifests)). AMO must sign the extension, listed or unlisted ([Doc](https://extensionworkshop.com/documentation/publish/signing-and-distribution-overview/)). `theme.reset()` undoes it. | Official, later phase |

---

## 4. Scope

### 4.1 MVP

The MVP proves one thing: one click changes what a developer sees all day, and one click puts it back.

| Integration | Why it is in | Relative effort |
|---|---|---|
| Wallpaper | The largest visual change; public API | Low |
| Light/Dark | Also moves Slack, Discord, Safari, and Chrome when they are set to follow the system | Low |
| Ghostty | Include file plus native Light/Dark. Scene can check the effective config with `ghostty +show-config` (Local). | Low |
| iTerm2 | File-based and live after a one-time step. Covers users who do not use Ghostty. | Medium |
| VS Code family | One integration covers VS Code, Cursor, VSCodium, and Devin Desktop | Medium |
| Neovim | Live update in every running instance, verified (Local) | Medium (highlight mapping) |
| System look, experimental: accent and highlight color, icon and widget style | The strongest whole-Mac signal after the wallpaper. Icon style has a typed Objective-C interface (Local). On tested macOS builds only (§6.8). | Medium, plus a test pass per macOS release |

The MVP also has four bundled themes with light and dark variants, preview, the apply plan, per-app results, undo, restore, `.scenetheme` import and export, and restore that works with symlinked dotfiles.

### 4.2 Next, in order

Zed and kitty (both low effort and live), Xcode 15–26, Alacritty, WezTerm, Terminal.app, and Vim. Then CLI tools through descriptors (btop, bat, delta, lazygit, tmux, Starship) and SketchyBar and JankyBorders for Omarchy-style setups. Also: Liquid Glass and the menu bar background (experimental), the Slack "copy theme" step, importers, the theme editor, the menu bar extra with appearance following, and the store.

### 4.3 Later

Firefox companion extension. Xcode 27 themes.

### 4.4 Not supported

| Item | Reason |
|---|---|
| Custom colors in Slack, Discord, Safari, Chrome | No supported mechanism (§3.4) |
| Discord client mods; Slack local storage or private API | They break the vendors' terms and break on updates |
| Chrome managed policy | Needs MDM or a configuration profile, and Chrome then shows "Managed by your organization" |
| Dock, login window, screen saver | No color surface, or no API at all (§3.1) |
| Pointer colors | People set them for visibility, as an accessibility setting |
| Forcing one app into Light (`NSRequiresAquaSystemAppearance`) | Light only, needs an app relaunch, unverified on 26 ([Comm](https://github.com/zenangst/Gray/issues/136)) |
| Fonts inside themes | Font licensing and font-parser attack surface. Omarchy also keeps fonts separate. |
| Scripts or hooks inside themes | Code execution (§8.4) |

### 4.5 Assumptions to challenge

- **"Theme the whole Mac."** False. Claim only what §3 verifies.
- **"The preview is what you get."** True for colors and the wallpaper. False for app layouts, so the preview says so (§9.3).
- **"Applying is one transaction."** False. Independent apps fail independently, so Scene reports per app (§7).
- **"Scene keeps everything in sync."** Only until the user changes an app directly. Scene then detects the change and stops managing that app. It never fights the user.
- **"One palette maps well everywhere."** False for editors. Curated overrides exist for this reason (§5.5).
- **"The wallpaper changes everywhere."** False with several Spaces. The result says so, and the menu bar extra can re-apply on Space change (E1).
- **"Private API means impossible."** False outside the App Store: "Notarization of macOS software is not App Review" ([Doc](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). The real cost is a test pass on every macOS release (§6.8).

### 4.6 How Scene talks about support

Each app in the apply sheet has one status: **Live**, **On next launch**, **One-time setup**, **Experimental**, **Follows Light/Dark**, **Not supported**, or **Not installed** (hidden by default). Each non-live status has one plain sentence of reason and, where possible, one button. Examples:

- "Slack does not let other apps change its theme. Turn on Color Mode → System in Slack to follow Light and Dark." [Open Slack]
- "WezTerm needs one line in your config. Scene never edits WezTerm's Lua file." [Copy line] [Open file] [Check again]
- "Xcode reads the new theme after you restart it."
- "Accent color uses a private macOS call that Scene has tested on macOS 26.6. On other versions it stays off until Scene is updated."

---

## 5. Theme format

### 5.1 Decisions

| Decision | Recommendation | Main alternative | Tradeoff |
|---|---|---|---|
| Container | One zip file with the extension `.scenetheme`. The library stores it unpacked. A plain folder is also accepted for creators. | macOS package (folder bundle) | A zip travels over the web, AirDrop, and email as one file. A bundle must be zipped for transport anyway. |
| Manifest syntax | JSON (`theme.json`) with a published JSON Schema | TOML, as Omarchy uses | JSON decodes with Foundation and has schema tooling for editors and CI. TOML is easier to hand-edit but needs a third-party parser in Swift. |
| Color model | Per variant: 15 interface roles, 22 terminal colors, 19 syntax roles | base16/base24 as the native model | base16 has the largest ecosystem, but its 16 slots mix interface and syntax roles. It has no place for wallpaper, system settings, or curation. Scene imports base16 instead. |
| Per-app quality | A generated baseline from roles, plus optional curated override files per app | Generated only | Generated-only themes look coherent but flat in editors. Curated files cost the creator more work. |
| Executable content | None. Scene never runs or writes theme-supplied code. | Hooks or scripts (Omarchy themes could carry `exec` lines or Lua) | Some effects become impossible. The store stays safe. |

### 5.2 Package layout

```
tidewater.scenetheme            (zip)
├── theme.json                  required manifest
├── wallpapers/
│   ├── harbor-night.heic
│   └── harbor-day.heic
└── apps/                       optional curated overrides
    ├── vscode-dark.json
    └── vscode-light.json
```

Allowed file types: `.json`, `.heic`, `.jpg`, `.png`, and one optional `README.md`. Nothing else. Scene's store CI renders previews from the theme data, so packages carry no preview images.

### 5.3 Example manifest

This file is valid JSON (Local).

```json
{
  "$schema": "https://schema.scene.example/theme/1.json",
  "format": 1,
  "id": "ada/tidewater",
  "version": "1.2.0",
  "name": "Tidewater",
  "summary": "Deep harbor blues with a coral accent.",
  "authors": [{ "name": "Ada Example", "url": "https://example.com/ada" }],
  "license": "MIT",
  "homepage": "https://github.com/ada/tidewater",
  "tags": ["blue", "coral"],
  "requires": { "scene": ">=1.0" },

  "variants": {
    "dark": {
      "palette": {
        "background": "#0f1720", "surface": "#16212c", "overlay": "#1e2b38", "border": "#2a3a4a",
        "foreground": "#d6e2ec", "muted": "#7f93a6",
        "accent": "#ff7a66", "selection": "#264057", "cursor": "#ff7a66",
        "currentLine": "#131d27", "search": "#5a4a1f",
        "error": "#ef6b73", "warning": "#e8b86c", "success": "#7fc8a0", "info": "#6cb3e8"
      },
      "terminal": {
        "background": "@background", "foreground": "@foreground",
        "cursor": "@cursor", "cursorText": "@background",
        "selectionBackground": "@selection", "selectionForeground": "@foreground",
        "ansi": {
          "black": "#0b1118", "red": "#ef6b73", "green": "#7fc8a0", "yellow": "#e8b86c",
          "blue": "#6cb3e8", "magenta": "#c49bf0", "cyan": "#6fd3d0", "white": "#c3d0dc",
          "brightBlack": "#3b4b5c", "brightRed": "#ff8a92", "brightGreen": "#98dcb6",
          "brightYellow": "#f5cd8a", "brightBlue": "#8ac6f2", "brightMagenta": "#d6b4f7",
          "brightCyan": "#8fe3e0", "brightWhite": "#eef4f9"
        }
      },
      "syntax": {
        "comment": { "color": "#5f7488", "italic": true },
        "keyword": "#c49bf0", "operator": "#8fa7bb", "punctuation": "#7f93a6",
        "string": "#7fc8a0", "escape": "#6fd3d0", "number": "#e8b86c", "constant": "#ff9e7a",
        "function": "#6cb3e8", "type": "#6fd3d0", "builtin": "#ff9e7a",
        "variable": "@foreground", "parameter": "#e0c6a8", "property": "#9fc1dc",
        "tag": "#ef6b73", "attribute": "#e8b86c",
        "added": "#7fc8a0", "removed": "#ef6b73", "changed": "#e8b86c"
      },
      "wallpapers": [{ "file": "wallpapers/harbor-night.heic", "fit": "fill" }],
      "system": { "highlightColor": "@selection" }
    },
    "light": {
      "palette": {
        "background": "#f6f8fa", "surface": "#eceff3", "overlay": "#ffffff", "border": "#d3dae2",
        "foreground": "#1d2a36", "muted": "#5c6d7e",
        "accent": "#d9503c", "selection": "#cfe0ef", "cursor": "#d9503c",
        "currentLine": "#eef2f6", "search": "#f6e3b4",
        "error": "#c43d47", "warning": "#a86b12", "success": "#2f8a5b", "info": "#2f74b5"
      },
      "terminal": {
        "background": "@background", "foreground": "@foreground",
        "cursor": "@cursor", "cursorText": "@background",
        "selectionBackground": "@selection", "selectionForeground": "@foreground",
        "ansi": {
          "black": "#1d2a36", "red": "#c43d47", "green": "#2f8a5b", "yellow": "#a86b12",
          "blue": "#2f74b5", "magenta": "#8a4fc9", "cyan": "#1d8a86", "white": "#dfe5eb",
          "brightBlack": "#5c6d7e", "brightRed": "#d9505a", "brightGreen": "#3c9f6b",
          "brightYellow": "#bf7f1f", "brightBlue": "#3c86c9", "brightMagenta": "#9d63db",
          "brightCyan": "#27a19c", "brightWhite": "#f6f8fa"
        }
      },
      "syntax": {
        "comment": { "color": "#7a8a99", "italic": true },
        "keyword": "#8a4fc9", "operator": "#4c5d6e", "punctuation": "#5c6d7e",
        "string": "#2f8a5b", "escape": "#1d8a86", "number": "#a86b12", "constant": "#c2563a",
        "function": "#2f74b5", "type": "#1d8a86", "builtin": "#c2563a",
        "variable": "@foreground", "parameter": "#7a5a3a", "property": "#3b6a91",
        "tag": "#c43d47", "attribute": "#a86b12",
        "added": "#2f8a5b", "removed": "#c43d47", "changed": "#a86b12"
      },
      "wallpapers": [{ "file": "wallpapers/harbor-day.heic", "fit": "fill" }],
      "system": { "highlightColor": "@selection" }
    }
  },

  "apps": {
    "vscode": { "dark": "apps/vscode-dark.json", "light": "apps/vscode-light.json" },
    "neovim": { "preferInstalled": { "colorscheme": "tidewater" } }
  },

  "assets": [
    { "file": "wallpapers/harbor-night.heic", "license": "CC-BY-4.0",
      "attribution": "Photo by Ada Example", "source": "https://example.com/photos/42" },
    { "file": "wallpapers/harbor-day.heic", "license": "CC-BY-4.0",
      "attribution": "Photo by Ada Example", "source": "https://example.com/photos/43" }
  ]
}
```

Rules the example shows:

- `id` stays the same across versions. It is `<creator>/<slug>`, and the store reserves the creator part. Local themes use `local/<uuid>`.
- `format` is the schema version (an integer). `version` is the theme's own semantic version.
- `@role` refers to another role in the same variant. References resolve at load time. A cycle is an error.
- Colors are sRGB `#RRGGBB` or `#RRGGBBAA`. Scene parses every color into numbers at load time. No color reaches a config file as the original string.
- A theme needs at least one variant. A theme with only `dark` shows as dark-only.
- `system.highlightColor` sets the text highlight color. System Events accepts it as RGB (Local). The accent color is not in v1 (§3.1).
- `apps.<integration>.preferInstalled` means: if the user already has this app's upstream port, select it instead of generating one. Omarchy uses upstream Neovim and VS Code themes the same way. Scene only selects what is already installed. It never installs code.
- `wallpapers` lists a variant's wallpapers. The first one is the default. The user can pick another one, and Next Background moves through the list.
- `assets` gives the license and attribution of each image. The store rejects images without a license.

### 5.4 Role set

| Group | Roles | Used by |
|---|---|---|
| Interface (15) | `background`, `surface`, `overlay`, `border`, `foreground`, `muted`, `accent`, `selection`, `cursor`, `currentLine`, `search`, `error`, `warning`, `success`, `info` | Editor chrome, previews |
| Terminal (22) | 16 named ANSI colors, `background`, `foreground`, `cursor`, `cursorText`, `selectionBackground`, `selectionForeground` | Terminals; editors' integrated terminals; Neovim `terminal_color_0..15` |
| Syntax (19) | `comment`, `keyword`, `operator`, `punctuation`, `string`, `escape`, `number`, `constant`, `function`, `type`, `builtin`, `variable`, `parameter`, `property`, `tag`, `attribute`, `added`, `removed`, `changed` | VS Code token rules, Neovim groups, Zed syntax, Xcode syntax keys |
| System | `highlightColor`, `wallpapers` (each with `file`, `fit`) | macOS |

Syntax roles can set `bold`, `italic`, and `underline`. Missing optional roles fall back along fixed chains, for example `parameter → variable → foreground` and `builtin → constant`. The validator lists every fallback it used, so the creator sees what they did not define.

### 5.5 Where a shared palette is enough

- **Enough:** terminals, wallpaper, system appearance, window borders, status bars, and small CLI tools. A terminal has about 22 color slots, and the theme defines each one directly.
- **Not enough:** editors. VS Code has hundreds of workbench color IDs and scope-based token rules. Neovim has about 60 Tree-sitter captures plus LSP groups and plugin groups ([Doc](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/treesitter.txt)). Xcode 26 has 28 syntax keys and stores fonts in the theme (Local).

The evidence agrees. Stylix, which maps base16 to many apps, says "there will be several applications that don't fit" ([Doc](https://nix-community.github.io/stylix/styling.html)). Catppuccin reviews every port by hand ([Doc](https://github.com/catppuccin/catppuccin/blob/main/docs/port-creation.md)). Omarchy grew its palette from 8 to 24 colors and still ships hand-written editor files for most built-in themes ([Doc](https://github.com/omacom/omarchy/releases/tag/v4.0.0)).

So the model has two layers. The renderer always produces a complete baseline from roles, including derived blends (for example, selection at 25% over the background for apps that need opaque colors). An optional curated file such as `apps/vscode-dark.json` replaces generated values key by key. Override files have a strict schema per integration: color IDs and token rules only. They cannot have `include` keys, file references, or settings.

### 5.6 One theme in two integrations

**Ghostty** (terminal: the palette is enough). Scene writes Scene-owned files and never edits the user's color lines.

| Theme field | Ghostty key |
|---|---|
| `terminal.background` / `foreground` | `background` / `foreground` |
| `terminal.cursor` / `cursorText` | `cursor-color` / `cursor-text` |
| `terminal.selectionBackground` / `selectionForeground` | `selection-background` / `selection-foreground` |
| `terminal.ansi.black` … `brightWhite` | `palette = 0=…` … `palette = 15=…` |
| `palette.border` | `split-divider-color` |
| `palette.search` | `search-background` |

Generated files:

```
# ~/.config/ghostty/themes/scene-dark   (Scene-owned; scene-light has the same keys)
background = #0f1720
foreground = #d6e2ec
cursor-color = #ff7a66
cursor-text = #0f1720
selection-background = #264057
selection-foreground = #d6e2ec
palette = 0=#0b1118
palette = 1=#ef6b73
# … palette 2 to 15
split-divider-color = #2a3a4a
search-background = #5a4a1f

# ~/.config/ghostty/scene.conf   (Scene-owned)
theme = light:scene-light,dark:scene-dark
```

One anchor in the user's config, added once:

```
# >>> Scene: managed include. Remove this block to detach Scene. >>>
config-file = ?scene.conf
# <<< Scene <<<
```

Three checked facts shape this design (Local, Ghostty 1.3.1, isolated config):

1. A `config-file` include loads after the file that contains it, so its values win wherever the anchor sits.
2. Colors set explicitly in the user's config, such as `palette = 4=#3D52E2`, still win over colors from a `theme`. The test Mac's own Ghostty config has this pattern. Scene reads the effective result with `ghostty +show-config` and reports "2 colors in your Ghostty config override this theme". It does not edit those lines.
3. The `?` prefix makes a missing include harmless. If Scene is deleted without a restore, Ghostty still starts.

**VS Code** (editor: roles plus curation). Scene generates a theme-only extension, installs it with the bundled CLI, and sets settings.

| Theme field | VS Code target (excerpt of about 60 generated keys) |
|---|---|
| `palette.background` | `editor.background` |
| `palette.surface` | `sideBar.background`, `activityBar.background`, `panel.background`, `titleBar.activeBackground` |
| `palette.overlay` | `editorWidget.background`, `quickInput.background`, `menu.background` |
| `palette.accent` | `focusBorder`, `button.background`, `activityBarBadge.background`, `tab.activeBorderTop` |
| `palette.selection` | `editor.selectionBackground`, `list.activeSelectionBackground` |
| `palette.currentLine` | `editor.lineHighlightBackground` |
| `terminal.ansi.*` | `terminal.ansiBlack` … `terminal.ansiBrightWhite` |
| `syntax.keyword` | Token scopes `keyword`, `storage.type`, `storage.modifier`; semantic token `keyword` |
| `syntax.function` | Token scopes `entity.name.function`, `support.function`; semantic tokens `function`, `method` |
| `syntax.type` | Token scopes `entity.name.type`, `support.type`; semantic tokens `type`, `class`, `interface`, `enum` |
| `apps/vscode-dark.json` | Replaces any generated key it names |

Details:

- The extension has two stable themes, "Scene Dark" and "Scene Light". Stable names keep Settings Sync harmless: other Macs without Scene show VS Code's default theme and keep the setting ([Src](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/themes/browser/workbenchThemeService.ts)).
- The extension version derives from a hash of the theme content, because VS Code caches loaded themes (Src: Omarchy).
- Scene writes `workbench.colorTheme` when `window.autoDetectColorScheme` is off. When it is on, VS Code ignores that key, so Scene writes `workbench.preferredDarkColorTheme` and `workbench.preferredLightColorTheme` ([Comm](https://github.com/microsoft/vscode/issues/91231)).
- Settings edits keep comments. VS Code itself edits settings with minimal text edits ([Src](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/jsonEdit.ts)), and Scene's JSONC editor does the same.

### 5.7 Validation

Validation runs on every import and every store download, in four layers:

1. **Container.** Only allowed paths and types. No symlinks, no absolute paths, no `..`. At most 64 entries, 40 MB unpacked, 20 MB per image, and a compression-ratio limit against zip bombs ([Doc](https://www.usenix.org/conference/woot19/presentation/fifield)). File types are checked by content, not by extension. Scene uses its own small extractor, because Swift zip libraries have had path and symlink traversal bugs ([Doc](https://github.com/advisories/GHSA-c2cc-3569-6jh2)).
2. **Schema.** Strict decoding into Swift types. Unknown top-level keys produce a warning and are ignored. Strings have length limits. Control and bidirectional-override characters are removed from names.
3. **Meaning.** Every referenced file exists. References resolve without cycles. Images decode, with dimensions read before the full decode and a long side between 1024 and 8192 px. Contrast checks (foreground on background, ANSI colors on background) give warnings, not errors.
4. **Per-integration override schemas.** Color IDs and token rules only. For VS Code, `include` is rejected, because VS Code theme files use it to load other files ([Src](https://github.com/microsoft/vscode/blob/main/src/vs/workbench/services/themes/common/colorThemeData.ts)).

### 5.8 Schema migration

- `format` changes only for breaking changes. Added optional fields do not change it.
- The app has one pure migration function per step (`1 → 2`). The library keeps the original package and a migrated copy.
- A package with a newer `format` than the app knows shows "Needs a newer version of Scene" and cannot be applied.
- The store index lists `format` for each theme version, so older apps can hide versions they cannot read.

### 5.9 Import

Import creates a draft theme and marks what it had to guess. It never promises a full conversion.

| Source | What Scene takes | What Scene derives or marks |
|---|---|---|
| base16 or base24 scheme (YAML) | Interface and syntax roles through the base16 styling guide ([Doc](https://github.com/tinted-theming/home/blob/main/styling.md)); ANSI colors | base16 has no distinct bright colors; base24 adds them ([Doc](https://github.com/tinted-theming/base24/blob/main/styling.md)). Marked "not curated". |
| `.itermcolors`, Ghostty, kitty, Alacritty, WezTerm themes | Terminal colors | Interface roles from background, foreground, and selection. Syntax roles from ANSI hues, marked "derived". |
| VS Code color theme JSON | The file as a curated `vscode` override; roles from common color IDs and scopes | Terminal colors if the theme has no `terminal.ansi*` keys |
| Omarchy theme folder | `colors.toml` and backgrounds | Everything else. Config files and `neovim.lua` are ignored and never run. |

---

## 6. Architecture

### 6.1 Shape

One app process, plus one small helper executable that runs private calls (§6.8). Swift 6, SwiftUI for the interface, and AppKit where SwiftUI is weak (`NSWorkspace`, Apple Events, menu bar details). No XPC service, no daemon, and no server in the MVP.

```
Scene.app  (Developer ID, notarized, not sandboxed)
│
├── Interface (SwiftUI)
│     Library · Theme detail and preview · Apply sheet · Results · Customize · Store · Menu bar extra
│
├── SceneCore  (Swift package, no UI; a later CLI can reuse it)
│   ├── Model ........... Theme, Variant, Roles: resolved and typed
│   ├── Packages ........ unzip, validate, migrate. The only code that reads untrusted bytes.
│   ├── Library ......... installed themes, versions, favorites, history
│   ├── Renderers ....... pure functions: resolved variant → per-app file contents
│   ├── Integrations .... detect · plan · reload · verify (one per app, built in)
│   ├── Engine .......... plan → back up → apply → reload → verify → report; restore; journal; ledger
│   ├── System .......... atomic file writer, config editors (line-based, JSONC), CFPreferences,
│   │                     Apple Events, signals, CLI runner, NSWorkspace
│   ├── SystemTweaks .... experimental private calls: tested-build list, signature checks, read, write
│   └── StoreClient ..... signed index, downloads, checksums → Packages
│
├── Contents/Helpers/scene-tweak   runs one SystemTweaks call per launch; a crash stays in the helper
│
└── Storage: ~/Library/Application Support/Scene/
      Themes/   Backups/   Journal/   Ledger.json   StoreCache/
```

### 6.2 Responsibilities

| Component | Owns | Does not |
|---|---|---|
| Interface | State display, user intent, permission explanations | Touch files or other apps |
| Model | Typed theme data after validation | Parse raw bytes |
| Packages | All parsing of untrusted input, limits, migration | Write outside `Themes/` |
| Library | Installed themes and versions; offline availability | Use the network |
| Renderers | Deterministic output per integration, pinned by snapshot tests | Read the disk |
| Integrations | Knowledge of one app: paths, formats, versions, reload, verification | Write files; they return plans |
| Engine | Every change, its backup, its journal entry, and its undo | Know app formats |
| System | The mechanics of safe writes and calls to other apps | Make decisions |
| SystemTweaks | Private calls: which macOS builds each one passed on, symbol and signature checks, read and write | Run inside the app process; it runs in `scene-tweak` |
| StoreClient | Catalog fetch, signature and checksum checks | Apply themes |

### 6.3 The integration interface

An integration returns operations from a closed set. The engine knows how to back up, apply, verify, and undo each operation type. So restore, crash recovery, dry runs, and "show me what will change" are written once, not once per app. Apply and restore are deliberately missing from the protocol.

Mapping to the requested operations: `detect` covers detection, capability reporting, and current-state inspection. `plan` covers planning. The engine covers applying and restoring. `verify` covers verification.

The sketch below is complete and type-checks with Swift 6.4 (Local).

```swift
import Foundation

/// A built-in integration for one app or system surface.
/// Integrations describe changes. The engine performs, records, verifies, and undoes them.
protocol Integration: Sendable {
    var id: IntegrationID { get }            // "ghostty", "vscode", "wallpaper"
    var displayName: String { get }

    /// Read-only and fast. Installed? Version? Config files? Conflicts? Setup needed?
    func detect(_ env: Environment) async -> Detection

    /// Pure: no disk, process, or network access. Maps one resolved theme variant
    /// to operations on resources that this integration owns.
    func plan(_ variant: ResolvedVariant, _ detection: Detection) throws -> IntegrationPlan

    /// Best effort: make running instances load the new state (signal, AppleScript, CLI).
    func reload(_ detection: Detection) async -> ReloadResult

    /// Read back the effective state and compare it with the plan.
    func verify(_ plan: IntegrationPlan, _ env: Environment) async -> Verification
}

struct Detection: Sendable {
    var installed: Bool
    var version: String?
    var resources: [URL]                   // config files and folders this integration reads or writes
    var capabilities: Set<Capability>
    var support: SupportLevel
    var setup: SetupState
    var conflicts: [Conflict]              // other theme managers, keys that override ours, read-only files
}

enum Capability: Sendable { case terminalColors, syntax, interface, wallpaper, appearance, liveReload, nativeLightDark }
enum SupportLevel: Sendable { case official, undocumented, manualOnly, unsupported(reason: String) }
enum SetupState: Sendable { case ready, needsOneTimeSetup(instructions: String), blocked(reason: String) }

struct IntegrationPlan: Sendable {
    var operations: [Operation]
    var requirements: [Requirement]        // .automation(bundleID:), .restart(app:), .oneTimeSetup(_:)
    var conflicts: [Conflict]
}

/// The closed set of changes the engine knows how to back up, apply, verify, and undo.
enum Operation: Sendable {
    case writeManagedFile(URL, contents: Data)                          // Scene owns the whole file
    case ensureAnchor(in: URL, block: String, placement: Placement)     // one marked block in a user file
    case setJSONValue(in: URL, keyPath: [String], value: JSONValue?)    // comment-preserving JSONC edit
    case setPreference(domain: String, key: String, value: PlistValue?) // CFPreferences
    case setWallpaper(displayID: UInt32, image: URL)
    case setAppearance(Appearance)
    case installEditorExtension(cli: URL, package: URL, extensionID: String)
    case setSystemTweak(id: String, value: PlistValue)                 // experimental private call (§6.8)
}

enum ReloadResult: Sendable { case reloaded, notRunning, needsRestart, needsUserAction(String), failed(String) }
enum Verification: Sendable { case matches, overridden([Conflict]), mismatch(String) }

// Supporting types
struct IntegrationID: Hashable, Sendable { let rawValue: String }
struct Conflict: Sendable { var message: String; var file: URL?; var line: Int? }
enum Requirement: Sendable { case automation(bundleID: String), restart(app: String), oneTimeSetup(String) }
enum Placement: Sendable { case start, end }
enum Appearance: Sendable { case light, dark }
indirect enum JSONValue: Sendable { case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]) }
indirect enum PlistValue: Sendable { case string(String), int(Int), bool(Bool), data(Data), dictionary([String: PlistValue]) }
struct Environment: Sendable { var home: URL }          // paths, running apps, versions
struct ResolvedVariant: Sendable { }                     // typed roles after references resolve
```

### 6.4 Data-driven and custom integrations

A **descriptor integration** is a JSON descriptor shipped inside the app, plus a template. It fits apps where the whole job is "render a file, add one include line, and maybe send a signal":

```json
{
  "id": "kitty",
  "bundleIDs": ["net.kovidgoyal.kitty"],
  "config": { "dir": "~/.config/kitty", "file": "kitty.conf", "comment": "#" },
  "managedFile": { "name": "scene-theme.conf", "template": "kitty.conf.tmpl" },
  "anchor": { "line": "include scene-theme.conf", "placement": "end" },
  "reload": { "signal": "SIGUSR1", "process": "kitty" },
  "conflicts": [
    { "pattern": "^# BEGIN_KITTY_THEME", "message": "kitty's theme kitten is active. Scene's include comes after it and wins." },
    { "file": "dark-theme.auto.conf", "message": "kitty's automatic theme files override every include. Scene will manage them and keep yours for restore." }
  ]
}
```

Templates allow typed substitutions only (`{{ terminal.ansi.red | hex }}`). They have no logic and receive no strings from the theme. Candidates: kitty, Alacritty, btop, bat, lazygit, tmux, Starship, SketchyBar, and JankyBorders.

**Custom code** is needed for: wallpaper, appearance, Ghostty (version-gated reload, verification with `+show-config`), iTerm2, Terminal.app (archived `NSColor` data, AppleScript), the VS Code family (VSIX packaging, JSONC, per-fork paths), Neovim (shim), Zed (JSONC), Xcode (two formats, fonts), and later Firefox.

### 6.5 Plugins

No external plugin system at launch. Built-in integrations are enough:

- Plugins are code, and the store must stay data-only.
- A public plugin API freezes internal types before the right shape is known.
- Descriptor integrations give most of the reach at a fraction of the cost, and they ship inside signed app updates.

Revisit this when users ask for apps that descriptors cannot express. A local descriptor that the user writes, never distributed through the store, is the likely first step.

### 6.6 Light/Dark and background work

Most target apps switch themselves when both variants are installed: Ghostty (`theme = light:…,dark:…`), kitty auto theme files, iTerm2 separate colors, VS Code preferred themes, Zed `"mode": "system"`, and probably Xcode's separate dark theme key (E8). Neovim 0.11+ follows the terminal through OSC 11 and mode 2031, which Ghostty and kitty support ([Doc](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/news-0.11.txt), [Doc](https://contour-terminal.org/vt-extensions/color-palette-update-notifications/)). Scene's Neovim shim picks the variant from `background`. For all these apps, Scene writes both variants once and does not need to run.

Terminal.app, Alacritty, and the wallpaper (with several Spaces) need Scene running. The menu bar extra covers this. It is the same app process, started at login through `SMAppService.mainApp` ([Doc](https://developer.apple.com/documentation/servicemanagement/smappservice)) when the user turns it on. There is no separate agent.

If the system appearance is Auto, Scene keeps it. The experimental `SLSSetAppearanceThemeSwitchesAutomatically` can put Auto back after a forced change (§6.8). Where that call is off, Scene does not force Light or Dark and uses the variant that matches the current appearance. System Events cannot set Auto back (Local), so forcing an appearance through it would silently break the user's setting.

### 6.7 Distribution

| Decision | Recommendation | Main alternative | Tradeoff |
|---|---|---|---|
| Channel | Developer ID signing, hardened runtime, notarization ([Doc](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). Direct download with Sparkle (EdDSA-signed updates, [Doc](https://sparkle-project.org/documentation/)) and a Homebrew cask ([Doc](https://docs.brew.sh/Cask-Cookbook)). | Mac App Store | See the sandbox facts below. Setapp stays possible: it requires notarization and does not mention the sandbox ([Doc](https://docs.setapp.com/docs/preparing-your-application-for-setapp), Inferred). |
| Entitlements | `com.apple.security.automation.apple-events`, with `NSAppleEventsUsageDescription` | None | Needed for Light/Dark (unless the private path is on) and Terminal.app. Each target app triggers one macOS consent prompt. |
| Private API | Allowed in the Developer ID build (§6.8) | None | "Notarization of macOS software is not App Review." The notary service "scans your software for malicious content, checks for code-signing issues" ([Doc](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)). Whether Setapp's review accepts private calls is unknown. |
| Minimum macOS | 14 | 15 or 26 | 14 has the current wallpaper system. See open question 5. |

Sandbox facts that rule out the Mac App Store for this product:

- A sandboxed app "cannot access or modify the settings of another app or process" ([Doc](https://developer.apple.com/documentation/foundation/userdefaults)). Xcode, Terminal, and iTerm2 settings are out of reach.
- "The sandbox prevents you from sending a Unix signal to other processes, and there's no temporary exception entitlement to allow that" ([Doc](https://developer.apple.com/forums/thread/776609)). Ghostty, kitty, Neovim, and Vim reloads use signals.
- Unix sockets outside a shared app-group container are blocked ([Doc](https://developer.apple.com/forums/thread/788364)).
- Apple Events to System Events need a temporary exception that "will likely result in rejection" ([Doc](https://developer.apple.com/library/archive/qa/qa1888/_index.html)).
- Dotfiles are reachable only through folders the user picks, kept with security-scoped bookmarks ([Doc](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)).

A sandboxed build could set wallpapers and write picked folders, and nothing else useful.

### 6.8 Experimental tier: private macOS calls

Scene reaches settings without a public API through the calls that System Settings itself makes. Nothing below was called on the test Mac. The facts come from symbol tables, the Objective-C runtime, and the disassembly of the Appearance pane (macOS 26.6.2, Local).

| Setting | Call | What is known | Fragility |
|---|---|---|---|
| Icon and widget style, icon tint | Objective-C class `SLSIconAppearanceConfiguration` (SkyLight) | `+fetchCurrentIconAppearanceConfiguration`; `setIconAppearanceTheme:` and `setIconTintColorName:` take a `UInt32`; `setOtherIconTintColor:` takes a `CGColor`; `-save` writes. The runtime reports these types. | Lowest. Scene checks each method's type encoding before it calls. |
| Light/Dark and Auto | `SLSSetAppearanceThemeNotifying`, `SLSSetAppearanceThemeSwitchesAutomatically` (SkyLight) | System Settings passes two integers to the first, for example `(1, 0)`, and one boolean to the second (disassembly) | Low to medium. C functions; the meaning of each argument needs E2. |
| Accent and highlight color | `NSColorSetUserAccentColor`, `NSColorSetUserHighlightColor` (AppKit) | The accent call takes one 8-byte value and a flag set to 1. The highlight call takes two object pointers and a flag. | Medium. The type of the accent value needs E3. |
| Liquid Glass | Swift `NSGlassEffectView.Legibility.setSystemLegibility(_:completionHandler:)` (AppKit) | The cases `.standard(_:)` and `.increased(_:)` carry associated values | Highest. Scene must match a Swift enum layout, and macOS 27 already replaced the control. |
| Menu bar background | `SLSSetMenuBarUseBlurredAppearance` (SkyLight) | Exported | Medium. The argument needs a test. |

The Appearance pane has no private entitlement for appearance. Its private entitlements cover screen capture, default-app changes, accessibility storage, and power logging only (Local). So a third-party process can probably make the same calls (Inferred). DarkModeBuddy ships `SLSSetAppearanceThemeLegacy` with no entitlements at all ([Src](https://github.com/insidegui/DarkModeBuddy)).

Eight rules contain the risk:

1. **Tested builds only.** Each tweak has a list of macOS builds it passed on. On any other build it is off, and its row says "Not yet tested on macOS 27.1".
2. **Check before calling.** Scene resolves each symbol with `dlsym` or the Objective-C runtime and compares method type encodings with the expected ones. Any difference turns the tweak off.
3. **Helper process.** The call runs in `scene-tweak`, a small executable inside the app bundle, one call per launch. A crash there becomes a "Failed" row, not a crashed app. The helper needs no privileges, no launchd job, and no XPC.
4. **Read back.** After each call, Scene reads the value back from the defaults key (`AppleAccentColor`, `AppleIconAppearanceTheme`, `NSGlassDiffusionSetting`, and so on) or the getter. A mismatch starts the fallback.
5. **Fallback chain.** The private call first. Then the defaults key, with "Applies after you log out". Then a Settings intent through a Shortcut, where one exists (E3). Then a manual step.
6. **Same restore rules.** The original value comes from the getters and keys, and the three-way rule applies (§7.2).
7. **Kill switch.** App updates carry the tested-build list. Once the store exists, its signed index can also turn a tweak off for one build without an app update.
8. **A test pass per macOS release.** A suite runs every tweak in a macOS virtual machine on each beta and release. A build joins the list only after the suite passes.

The recurring cost is rule 8. After every major release, and sometimes after a minor one, the tier stays off until the suite passes on the new version.

---

## 7. Apply and restore lifecycle

### 7.1 Stages

```
Select ─► Preview ─► Plan ─► Confirm ─► Back up ─► Apply ─► Reload ─► Verify ─► Report
 (no changes)        (read-only)        (per app, in order, journaled)
```

1. **Select and preview.** Scene renders previews itself. Nothing on the system changes.
2. **Plan.** For each participating app, `detect` and then `plan`. The result lists operations, permissions, restarts, one-time steps, and conflicts. This is a dry run, and the apply sheet shows it.
3. **Confirm.** The user can switch apps off for this theme. Scene remembers the choice.
4. **Back up.** Before the first change to any resource, the engine records its original state (§7.2). The record stays until the user restores or forgets it.
5. **Apply.** One app at a time. For each operation: write a journal entry, apply, and record the result hash. File writes are atomic: a temporary file in the same folder, then a rename. A failure stops that app only. Other apps continue.
6. **Reload.** Best effort per app: a signal, an AppleScript action, or nothing.
7. **Verify.** Read back the effective state: file hashes, `ghostty +show-config`, `NSWorkspace.desktopImageURL(for:)`, `AppleInterfaceStyle`.
8. **Report.** One line per app, with one outcome:

| Outcome | Shown to the user as |
|---|---|
| Applied | Done and verified |
| Applied, restart needed | Done. The app reads it on next launch (Xcode). |
| Applied, partly overridden | Your own config overrides N colors. [Show] |
| Needs your action | One step only you can do. Scene shows it and checks again. |
| Skipped | Not installed, or switched off |
| Failed | Nothing changed for this app, or Scene rolled it back. The reason is shown. |

### 7.2 Ownership model

Every change belongs to one of three kinds. The kind decides backup and restore.

| Kind | Example | Backup | Restore |
|---|---|---|---|
| **Managed file.** Scene writes the whole file. | `~/.config/ghostty/scene.conf`, `~/.config/nvim/plugin/scene.lua`, the generated VS Code extension. Also kitty's `dark-theme.auto.conf` when the user already had one. | If a file existed at that path, a copy of its bytes. Always the hash of what Scene wrote. | If the file still has Scene's hash, put the original back, or delete the file if there was none. If the hash changed, keep the file and report it. |
| **Anchor.** One marked block in a user file. | `config-file = ?scene.conf` in Ghostty's config; `include scene-theme.conf` in kitty.conf | A full copy of the file before the first edit, plus the block text | Remove only the block. The rest of the file stays as it is now, including edits made after Scene. |
| **Setting.** One value that Scene sets. | `workbench.colorTheme`; `XCFontAndColorCurrentTheme`; the wallpaper per display; Light/Dark; accent color; icon style | The original value, or "absent" | Three-way rule below |

**Three-way rule.** Scene stores the original value O and the value it applied A. At restore it reads the current value C.

- If C equals A, Scene writes O back, or deletes the key if O was absent.
- If C differs from A, someone changed it after Scene. Scene keeps C and reports: "You changed this after Scene applied its theme. Scene kept your change."

The full-file backups are for disaster recovery only ("Reveal backup"). Restore never copies a whole file back, because that would discard the user's later edits.

Scene never re-applies a theme on its own. If the user changes an app's theme outside Scene, Scene marks the app "Changed outside Scene" and leaves it alone until the next explicit apply.

### 7.3 Hard cases

- **Symlinked configs** (dotfile repositories, GNU Stow). Scene resolves the link, edits the target in place, and keeps the link. If the target is read-only (for example under `/nix/store`), the app gets "Needs your action" with the exact line to add in the user's source.
- **Generated configs** (chezmoi, Home Manager). The tool would overwrite Scene's edits on its next run. Scene detects the tool and shows the line to add in the tool's source instead.
- **Includes and order.** Include rules differ per app. Ghostty includes win wherever they sit. kitty is positional, so the anchor goes at the end (Local). Alacritty's main file overrides its imports. kitty's auto theme files override every include. Each integration encodes its rule, and verification reports the keys that still override the theme.
- **Other theme managers.** kitty's theme kitten block, Ghostty `theme =` lines, Neovim appearance plugins, VS Code's own theme setting, and tinted-shell or tinty scripts. Scene detects them, does not edit or delete them, and tells the user what will win. The test Mac has three at once: a kitty kitten block with an auto theme file, a Ghostty light/dark pair with palette overrides, and a Neovim appearance bridge (Local).
- **Changes outside Scene.** Before every plan and at launch, Scene compares managed-file hashes, anchor presence, and setting values with the ledger.
- **Interrupted apply or crash.** The journal entry is flushed to disk before each operation. At launch, an unfinished journal produces: "Scene stopped while applying Tidewater. 3 of 5 apps changed. [Finish] [Undo these changes]". Every operation is idempotent, so both paths are safe to repeat.
- **Partial success.** Independent apps allow no atomic transaction. Rollback is per app and best effort. If an app fails verification, Scene undoes that app's operations and reports it. The other apps keep the new theme, and the user can still undo everything.

### 7.4 Undo and restore

| Action | What it does |
|---|---|
| **Undo** (back to the previous theme) | Applies the previous entry in the history. Managed files are regenerated from that theme, not copied from backups. If there is no previous theme, Undo is the same as "Restore original setup". |
| **Restore original setup** | For every resource Scene ever touched: restore managed files by the hash rule, remove anchors, and apply the three-way rule to settings. Also uninstalls the generated editor extension. Available for one app or for all. |
| **Stop managing an app** | Restore the original setup for that app, and switch it off for future themes |

---

## 8. Theme store

### 8.1 Minimal path

| Stage | What exists | Backend |
|---|---|---|
| S0 | Import and export of `.scenetheme` files; sharing by AirDrop or link | None |
| S1 | A curated catalog in the app, from a signed static index | A Git repository, CI, static hosting |
| S2 | Creator publishing by pull request; reports; updates | Same, plus a report form |
| S3 (only if needed) | Web upload, creator accounts, download counts | A small web service |

Precedents: Zed pins each extension to a reviewed commit and reviews every update ([Doc](https://zed.dev/docs/extensions/publishing/publishing-guide)). Homebrew requires a SHA-256 for every cask ([Doc](https://docs.brew.sh/Cask-Cookbook)). Omarchy's new registry pins validated commits ([Doc](https://github.com/omacom/omarchy-theme-registry)). The counter-example is the KDE Store, where themes could run code; in 2024 a global theme deleted a user's files ([Comm](https://www.bleepingcomputer.com/news/linux/kde-advises-extreme-caution-after-theme-wipes-linux-users-files/)).

### 8.2 S1 and S2 design

```
Creator ─ pull request (theme folder) ─► registry repository
                                           │
                                           ▼
                             CI: validate (same SceneCore code) · re-encode images ·
                                 render previews · build .scenetheme · update index · sign
                                           │
                                           ▼
                  Static hosting / CDN:  index.json  index.sig  themes/…/1.2.0.scenetheme  previews/…
                                           │  HTTPS, ETag
                                           ▼
Scene.app StoreClient: verify signature and expiry ─► browse ─► download ─► check SHA-256 ─► validate ─► Library
```

- **Index.** One JSON file. Per theme version: `id`, `version`, `format`, minimum Scene version, SHA-256, size, license, tags for search, creator, preview URLs, and removal notices. The index has a sequence number and an expiry date. The app rejects an index older than the one it has (rollback) or past its expiry (freeze). This is the smallest useful part of The Update Framework ([Doc](https://theupdateframework.io/docs/overview/)).
- **Signing.** Plain Ed25519 over the index bytes, verified with CryptoKit `Curve25519.Signing`. An offline root key, pinned in the app, signs the online index key, so the index key can rotate. Do not use minisign's default format: it prehashes with BLAKE2b ([Doc](https://jedisct1.github.io/minisign/)), which CryptoKit does not provide (Inferred).
- **Images.** CI decodes and re-encodes every image to a known format and size. This strips metadata and malformed data. It also protects the system wallpaper process, which decodes the file again outside Scene's control (Inferred).
- **Review.** A pull request template covers original work or license proof, attribution, the image content policy, and no trademarks in names. Automated checks run first. A person approves.
- **Reports.** A "Report theme" button opens a prefilled form. Removal takes the theme out of the index and adds a notice, so installed copies show "Removed from the store: reason".
- **Attribution and licensing.** The theme license (SPDX) and each image license appear on the theme page and in the app.

### 8.3 Offline and updates

- Installed themes live in the library as full packages. Applying never needs the network.
- The app checks the index at launch and at most once a day.
- An update never changes what is on screen. It installs next to the current version. For the applied theme, the app shows "Update available" and applies it only after a click.
- The app keeps the previous version of each theme for a one-click rollback.

### 8.4 Trust boundary

Community themes are data. Everything that runs is inside the signed app: integrations, renderers, templates, and descriptors. Theme values reach config files only as typed numbers, formatted by trusted code.

This rule is necessary because every target format can do more than colors. Ghostty's docs warn that a theme file "can set any valid configuration option" (Local). kitty can run a program from `geninclude` ([Doc](https://sw.kovidgoyal.net/kitty/conf/)). Neovim and WezTerm configs are Lua. Omarchy's v4.0.0 fixes show the same class of bug in practice (§2.1).

Images are the largest remaining attack surface. ImageIO bugs were used in the FORCEDENTRY and BLASTPASS attacks ([Doc](https://projectzero.google/2021/12/a-deep-dive-into-nso-zero-click.html), [Doc](https://citizenlab.ca/2023/09/blastpass-nso-group-iphone-zero-click-zero-day-exploit-captured-in-the-wild/)). Scene calls `CGImageSourceSetAllowableTypes` at launch to allow only PNG, JPEG, and HEIC decoders in its process (macOS 14.2+, [Doc](https://developer.apple.com/documentation/imageio/cgimagesourcesetallowabletypes(_:))). Decoding in a separate XPC service is a later hardening step, if E12 shows a need.

---

## 9. User experience

### 9.1 Window or menu bar

Recommendation: a standard window app with an optional menu bar extra.

- Browsing, previewing, planning, and reading results need space. A popover is too small for a plan with six apps and a preview.
- Quick switching between favorites, Light/Dark/Auto, and Undo fit the menu bar. The extra is off by default. It also keeps Scene running for the apps and Spaces that need it (§6.6).
- The alternative, a menu-bar-only app, feels lighter but hides the plan and the results, which carry the trust story.

### 9.2 Primary flows

| Flow | Steps |
|---|---|
| First launch | Scene lists detected apps and what it can do for each. One sentence explains backups. No permission prompts yet. |
| Browse | A grid of themes with rendered cards: wallpaper, terminal sample, code sample. Each card has a Light/Dark toggle. |
| Preview | A detail view with three tabs: Desktop, Terminal, and Code |
| Apply | The apply sheet shows the plan: one row per app, with a switch and a status. Permission explanations appear here, before macOS asks. |
| Results | The same rows with outcomes. "Undo" stays visible. Details per app list the changed files, with "Reveal in Finder" and a diff. |
| Customize | "Duplicate and edit": role colors with a live preview, a wallpaper picker, per-app switches. Saved as a local theme. |
| Restore | Settings → "Restore original setup", for everything or per app, with a preview of what will change |
| Share | Export a `.scenetheme` file through the share sheet |

### 9.3 Previews

- **Exact:** color values, the wallpaper image, terminal output (Scene renders sample ANSI output with the real palette), and contrast ratios.
- **Close:** macOS controls, because Scene draws real AppKit controls with a forced `NSAppearance`.
- **Illustrative:** app layouts (VS Code, Zed) and syntax highlighting. Scene's tokenizer uses the same roles, but each editor's grammar splits tokens differently. The preview says "App layouts are approximate."

### 9.4 Permissions

Scene asks at the moment of use, never at launch. Before macOS shows the Automation prompt, Scene shows one sentence: "To switch Light and Dark mode, Scene needs to control System Events. macOS will ask you once." Scene checks the permission first with `AEDeterminePermissionToAutomateTarget`. If the user declines, the row says "Needs permission", with a button that opens Privacy & Security → Automation. When the experimental Light/Dark call is on for the current macOS build, no prompt is needed (E2).

### 9.5 Manual steps and missing apps

A manual step is a card with the exact action, a button that does the part Scene can do (copy, open the file, open the app), and "Check again", which verifies the result. Apps that are not installed are hidden. Apps that Scene cannot theme appear in a collapsed "Follows Light/Dark" group with their one-sentence reason (§4.6). Technical details (paths, diffs, backups) are one click away, and never in the first view.

---

## 10. Risks and experiments

Run every experiment in a separate macOS user account or a virtual machine, with fixture configs. Never run one on a live setup.

| # | Assumption at risk | Experiment | Pass criterion |
|---|---|---|---|
| E1 | The wallpaper changes where the user looks | macOS 26.6 and 27; two displays; three Spaces; "Show on all Spaces" on and off. Call `setDesktopImageURL`. Re-apply on `NSWorkspace.activeSpaceDidChangeNotification`. Try an appearance-keyed HEIC ([Comm](https://github.com/mczachurski/wallpapper)). | Behavior documented. One strategy chosen: current Space with re-apply, or dynamic HEIC. |
| E2 | Light/Dark and Auto can be set cleanly | In a VM: System Events (prompt flow, denial path, `AEDeterminePermissionToAutomateTarget`) against `SLSSetAppearanceThemeNotifying` and `SLSSetAppearanceThemeSwitchesAutomatically` called from `scene-tweak`. Confirm what each argument means. | Switch under 1 s on both paths; Auto restorable; default path chosen |
| E3 | Accent and highlight color apply live | In a VM: `NSColorSetUserAccentColor` and `NSColorSetUserHighlightColor` for every preset, called from `scene-tweak`, to confirm argument types. Compare defaults plus notifications, and the Settings intent through `shortcuts run`. | Running apps update live; revert is exact; no crash |
| E3b | Icon and widget style apply live | In a VM: fetch, set, and save `SLSIconAppearanceConfiguration` for each style and tint, including a custom `CGColor`. Check Finder, the Dock, widgets, and folders. Revert. | Live change; exact revert; type encodings match the expected list |
| E3c | Liquid Glass can be set | In a VM on 26.x and 27: call `setSystemLegibility` through its mangled symbol with a matching enum layout. Compare writing `NSGlassDiffusionSetting` and posting `NSGlassEffectDiffusionDidChangeNotification`. | Works on at least one tested build per major version, or stays off |
| E4 | Ghostty reload needs no user action | SIGUSR2 on 1.2 and 1.3; AppleScript `perform action "reload_config"`; `+show-config` conflict detection | All windows recolor; overrides are reported correctly |
| E5 | The iTerm2 Dynamic Profile covers the user's sessions | Parent GUID plus separate light/dark colors. Set it as default through the UI, and through preferences while iTerm2 is quit. Watch open sessions. | Sessions on the profile recolor live; the one-time step is short and clear |
| E6 | VS Code shows new theme content without a reload | VS Code 1.139, Cursor, VSCodium: `_watch` rewrite in place; reinstall with a new version and `--force`; `autoDetectColorScheme`; profiles; Settings Sync on | Open windows recolor without "Reload Window"; sync effects known |
| E7 | The Neovim shim coexists with common setups | LazyVim, kickstart.nvim, NvChad, auto-dark-mode.nvim; Neovim 0.11 and 0.12 | Shim applies and restores; conflicts detected |
| E8 | Xcode themes apply without surprises | Xcode 26.6 and 27: write the theme and keys while Xcode runs and after a restart. Check that fonts are kept and the color space is right. Decode how 27 stores a custom theme in `DVTWorkspaceThemeSettings`. | Known behavior per version; fonts unchanged |
| E9 | Terminal.app import is tolerable | Import `.terminal` with the window-close workaround; versioned profile names; live recolor of tabs | No leftover windows or duplicate profiles |
| E10 | Restore loses nothing | Fixture home folders: plain, Stow symlinks, chezmoi, commented JSONC, missing files. Apply, edit, restore. | Byte-identical files where the user made no edits; user edits kept |
| E11 | Crash recovery works | Kill the app with SIGKILL at each journal step | Every app ends in a consistent state after relaunch |
| E12 | In-process image handling is safe enough | A fuzz corpus through the validator with `CGImageSourceSetAllowableTypes` set | No crash; limits hold; decision on an XPC decoder |
| E13 | Private calls survive macOS updates | Run the E2, E3, E3b, and E3c suite in a VM on every macOS beta and release | The tested-build list is updated before users get the release. A failure keeps the tweak off, and the app still works. |

Highest risks, in order:

1. **E1, wallpaper and Spaces.** If the wallpaper changes on one Space only, the "coordinated" feeling breaks for users with several Spaces.
2. **E6, VS Code refresh.** A theme that needs "Reload Window" feels broken.
3. **E5, the iTerm2 one-time step.** If it confuses users, iTerm2 moves out of the MVP.
4. **Quality of generated editor themes.** Test with E7, E8, and a design review of three themes against their upstream ports.
5. **E10 and E11, trust.** One lost config ends trust in the product.
6. **E13, macOS updates against the experimental tier.** The tier is only as good as its test pass, and macOS 27 already changed the Liquid Glass call.

---

## 11. Roadmap

No time estimates. A phase ends when its acceptance criteria pass.

| Phase | Build | Acceptance criteria |
|---|---|---|
| 0. Spikes | E1, E2, E3, E3b, E4, E5, E6, E7, E12 in isolated accounts and VMs | Each experiment has a written result, a go/no-go, and a fixture. The MVP integration list is confirmed or changed. |
| 1. Core | SceneCore model, schema v1 and its JSON Schema, package validator, migrations, renderers, library, gallery and preview UI, four bundled themes | At least 50 malformed packages are rejected, each with a specific error. A fuzz run finds no crash. Renderer output passes each app's own check where one exists (`ghostty +validate-config`, kitty's config loader, `plutil -lint`, JSON parsing). Snapshot tests pin renderer output. The build has no code path that writes outside Scene's folder. |
| 2. Engine and MVP | Journal, backups, ledger, restore, change detection. Wallpaper, Light/Dark, Ghostty, iTerm2, VS Code family, Neovim. Experimental accent and highlight color and icon style, with `scene-tweak`, the tested-build list, and fallbacks. Apply sheet and results. Developer ID signing, notarization, Sparkle. | Apply then restore leaves fixture files byte-identical for plain, symlinked, and comment-heavy configs. A user edit made after apply survives restore. SIGKILL at any journal step recovers to a consistent state per app. Unrelated keys and comments survive in JSONC files. Each reported outcome matches a manual check. A full apply on the test Mac takes under 3 s, not counting permission prompts. Each experimental tweak applies and restores exactly in the VM suite on every build in its list. On an unlisted build it stays off and says why. A crash in `scene-tweak` produces a "Failed" row, and the app keeps running. |
| 3. Breadth | The §4.2 list, including experimental Liquid Glass and menu bar background; descriptor integrations, importers, theme editor, menu bar extra with appearance following | Every integration passes the Phase 2 restore suite. Each importer converts 20 real themes and marks every derived value. Appearance following re-applies within 2 s of a system change. |
| 4. Store | Registry repository; CI that validates, re-encodes, renders previews, and signs; in-app browse, install, update, remove, and report | A tampered package, an expired index, and an older index are all rejected. Themes work offline. An update never changes the applied theme without a click. Removal notices reach installed copies. |
| 5. Later | Firefox companion extension, Xcode 27, store accounts only if pull requests become the bottleneck | For each feature, the same restore and verification bar as Phase 2 |

---

## 12. Open questions

Each answer changes the design:

1. **Audience.** Developers first (terminals and editors), or general Mac users (wallpaper, appearance, browsers)? The MVP list and the interface density follow from this. This document assumes developers first.
2. **Business model.** Free, paid, or open source? It decides whether the format and integrations are public, whether Setapp fits, and how the store is funded. Paid themes are not planned.
3. **Background presence.** Should Scene start at login by default? It is needed for wallpaper on every Space and for apps without native Light/Dark. The alternative is a smaller promise.
4. **Omarchy compatibility.** Should Omarchy `colors.toml` themes import as a first-class source? Community themes carry their own licenses.
5. **Minimum macOS.** 14, 15, or 26? 14 has the current wallpaper system. 26 has the Settings App Intents that E3 depends on.
6. **Dotfile managers.** When chezmoi or Home Manager owns a config, should Scene only show the line to add, or also offer to edit the tool's source file?
7. **Name.** "Scene" is a working name.
8. **Experimental tier default.** On tested builds, should private-call tweaks be on by default, or opt-in in Settings? On by default gives the full look at first apply. Opt-in keeps the default path to documented mechanisms only.

---

## Appendix A: local checks

All checks ran on the test Mac. They were read-only, or they used isolated fixtures in a scratch folder.

| # | Check | Result |
|---|---|---|
| 1 | `sdef` of Terminal.app 2.15 | `settings set` exposes background, normal text, bold text, and cursor colors only. The app has `default settings` and `startup settings`. |
| 2 | `sdef` of System Events | `appearance preferences` has `dark mode` (boolean), `appearance` (blue or graphite), and `highlight color` (8 names or RGB). No Auto, no accent color. |
| 3 | Ghostty 1.3.1 built-in docs, `Ghostty.sdef`, App Intents | `config-file` loads after the including file. The `theme` docs warn that a theme "can set any valid configuration option". AppleScript has `perform action` on a terminal. |
| 4 | Ghostty 1.3.1 with an isolated `XDG_CONFIG_HOME` | User `palette` lines beat `theme` colors. Explicit colors in an include beat user lines. A missing `?` include is valid. A generated snippet passes `+validate-config`. |
| 5 | kitty 0.44.0 config loader, offline | Position decides. The definition that comes later wins, whether it is in the main file or in the included file. |
| 6 | Neovim 0.11.5, isolated config | A `plugin/` shim applies a colorscheme from a data file and re-applies it after an atomic file replace, in a running instance. `--remote-send` works. The default socket is `$TMPDIR/nvim.$USER/<random>/nvim.<pid>.0`. With lazy.nvim and `rtp.reset = true`, the shim still loads. |
| 7 | VS Code 1.136.2, isolated extensions folder | A hand-built VSIX (plain zip, no `vsce`) installs through the CLI. A folder missing from `extensions.json` is not listed. |
| 8 | Xcode 26.6 and 27.1 beta | `.xccolortheme` has 28 syntax keys and embeds fonts. Selection keys: `XCFontAndColorCurrentTheme` and `XCFontAndColorCurrentDarkTheme`. Xcode 27 adds `DVTWorkspaceThemeSettings`: JSON with `light` and `dark` entries. The 27.1 beta bundle still ships only `.xccolortheme` files. |
| 9 | `NSWorkspace` from a Swift script | `desktopImageURL(for:)` and `desktopImageOptions(for:)` read per display |
| 10 | Global defaults (read) | `AppleInterfaceStyle`, `AppleAccentColor`, `NSGlassDiffusionSetting`, and `SLSMenuBarUseBlurredAppearance` exist. The wallpaper store `Index.plist` references images by URL. |
| 11 | Terminal.app preferences (read) | Profiles include "Clear Dark" and "Clear Light". Colors are `ANSI*Color`, `BackgroundColor`, `TextColor`, `TextBoldColor`, and `SelectionColor`, stored as archived `NSColor` data. |
| 12 | Omarchy v4.0.4 clone | The quotes and file lists in §2 match the tag. The development branch's VS Code script derives the version from theme content and sets `_watch`. |
| 13 | This document | The example manifest is valid JSON. The Swift interface sketch type-checks with Swift 6.4. |
| 14 | Existing theme managers on the test Mac (pattern search only) | kitty: kitten theme block plus `dark-theme.auto.conf`. Ghostty: `theme = light:…,dark:…` plus `palette` overrides. Neovim: an appearance-bridge plugin. |
| 15 | `dyld_info -exports` on SkyLight and AppKit | `SLSSetAppearanceThemeNotifying`, `…Legacy`, `…Options`, `…SwitchesAutomatically`, `SLSSetMenuBarUseBlurredAppearance`, `NSColorSetUserAccentColor`, `NSColorSetUserHighlightColor`, and Swift `NSGlassEffectView.Legibility.setSystemLegibility(_:completionHandler:)` exist on 26.6.2. |
| 16 | Appearance pane (`Appearance.appex`): entitlements and imports | Private entitlements cover screen capture, default handlers, accessibility storage, and power logging only. The pane imports the setters above and `SLSIconAppearanceConfiguration`. |
| 17 | Objective-C runtime listing of `SLSIconAppearanceConfiguration` (no method called) | Class method `fetchCurrentIconAppearanceConfiguration`. `UInt32` properties `appearanceTheme`, `iconAppearanceTheme`, `iconTintColorName`. `CGColor` property `otherIconTintColor`. Instance method `save`. |
| 18 | Disassembly of the pane's call sites (x86_64 slice) | `SLSSetAppearanceThemeNotifying` gets two integers, for example `(1, 0)`. `SLSSetAppearanceThemeSwitchesAutomatically` gets one boolean. `NSColorSetUserAccentColor` gets an 8-byte value and 1. `NSColorSetUserHighlightColor` gets two object pointers and 1. |
