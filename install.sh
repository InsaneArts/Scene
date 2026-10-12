#!/bin/sh
# Installs the latest Scene, the Mac app that gives the desktop, terminals, and code editors one theme in one step.
#
#   curl -fsSL https://raw.githubusercontent.com/InsaneArts/Scene/main/install.sh | sh
#
# It reads the release that Scene's update feed lists, checks that Apple notarized the app and that Scene's
# developer signed it, and copies it to /Applications, or to ~/Applications if /Applications is not writable.
# SCENE_INSTALL_DIR picks another folder. Later updates come through Scene itself.
#
# Everything runs inside main, so a download cut short runs nothing.

FEED="${SCENE_FEED:-https://github.com/InsaneArts/Scene/releases/latest/download/appcast.xml}"
TEAM_ID="539293JFA3"   # the same as TEAM_ID in Scripts/release.sh

say() { printf '%s\n' "$*"; }
fail() { printf 'Scene was not installed: %s\n' "$*" >&2; exit 1; }

main() {
  set -eu
  [ "$(uname -s)" = Darwin ] || fail "Scene runs on macOS only."
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Scene needs macOS 14 or later."

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  # The feed lists the newest release first.
  curl -fsSL "$FEED" -o "$tmp/appcast.xml" || fail "Scene has no release at $FEED yet."
  url=$(sed -n 's/.*url="\([^"]*\.zip\)".*/\1/p' "$tmp/appcast.xml" | head -n 1)
  version=$(sed -n 's/.*<sparkle:shortVersionString>\(.*\)<\/sparkle:shortVersionString>.*/\1/p' "$tmp/appcast.xml" | head -n 1)
  [ -n "$url" ] || fail "the update feed lists no download."

  say "Downloading Scene ${version:-}…"
  curl -fL --progress-bar "$url" -o "$tmp/Scene.zip" || fail "the download from $url failed."
  ditto -x -k "$tmp/Scene.zip" "$tmp/unzipped" || fail "the download is not a valid zip."
  app="$tmp/unzipped/Scene.app"
  [ -d "$app" ] || fail "the download has no Scene.app."

  # Check the signature and notarization before anything is copied.
  codesign --verify --deep --strict "$app" 2>/dev/null || fail "the app's signature does not check out."
  team=$(codesign -dv "$app" 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [ "$team" = "$TEAM_ID" ] || fail "the app is signed by team ${team:-none}, not by Scene's developer ($TEAM_ID)."
  spctl --assess --type execute "$app" 2>/dev/null || fail "Gatekeeper rejects the app: Apple has not notarized it."

  dest="${SCENE_INSTALL_DIR:-/Applications}"
  if [ -z "${SCENE_INSTALL_DIR:-}" ] && [ ! -w "$dest" ]; then dest="$HOME/Applications"; fi
  mkdir -p "$dest" || fail "Scene cannot write to $dest."
  if pgrep -f "^$dest/Scene.app/Contents/MacOS/Scene" >/dev/null 2>&1; then
    fail "Scene is running from $dest. Quit it, then run this again."
  fi
  rm -rf "$dest/Scene.app.old"
  if [ -d "$dest/Scene.app" ]; then mv "$dest/Scene.app" "$dest/Scene.app.old"; fi
  if ditto "$app" "$dest/Scene.app"; then
    rm -rf "$dest/Scene.app.old"
  else
    rm -rf "$dest/Scene.app"
    if [ -d "$dest/Scene.app.old" ]; then mv "$dest/Scene.app.old" "$dest/Scene.app"; fi
    fail "Scene could not be copied to $dest."
  fi

  say "Scene ${version:-} is in $dest. Open it from there, or with Spotlight."
}

main "$@"
