#!/usr/bin/env bash
# Builds a universal Scene.app, signs it with the Developer ID, notarizes and staples it,
# and writes dist/Scene-<version>.zip. It publishes nothing.
#
#   Scripts/release.sh
#
# Environment:
#   NOTARY_PROFILE   notarytool keychain profile  (default: camus-notary)
#   SIGN_IDENTITY    Developer ID identity        (default: Developer ID Application: Techzy LLC (539293JFA3))
#   DEVELOPER_DIR    toolchain                    (default: /Applications/Xcode.app, the release Xcode; never a beta)
set -euo pipefail

# The release Xcode links against the current SDK. A beta toolchain may record an older SDK,
# and apps linked before SDK 26 do not get the macOS 26 design.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Scene"
TEAM_ID="539293JFA3"
NOTARY_PROFILE="${NOTARY_PROFILE:-camus-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Techzy LLC ($TEAM_ID)}"
DIST="$ROOT/dist"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source "$ROOT/version.env"
VERSION="$MARKETING_VERSION"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

# --- Preflight -------------------------------------------------------------
step "Preflight for $VERSION (build $BUILD_NUMBER) with $(xcrun swift --version 2>&1 | head -1 | sed 's/.*Apple Swift/Swift/')"
# With pipefail, `command | grep -q` fails when grep exits before the command ends. So the text goes to a variable.
IDENTITIES="$(security find-identity -v -p codesigning)"
[[ "$IDENTITIES" == *"$SIGN_IDENTITY"* ]] || fail "signing identity not found: $SIGN_IDENTITY"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || fail "notarytool profile '$NOTARY_PROFILE' not found. Store it one time with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id $TEAM_ID --password <app-specific-password>"
echo "  identity and notary profile are ready"

step "Tests"
"$ROOT/Scripts/test.sh" -quiet

# --- Build and sign --------------------------------------------------------
step "Build a universal app and sign it with the Developer ID"
APP_IDENTITY="$SIGN_IDENTITY" ARCHES="arm64 x86_64" "$ROOT/Scripts/package_app.sh" release
APP="$ROOT/build/$APP_NAME.app"
codesign --verify --deep --strict "$APP" || fail "the signature does not verify"
for code in "$APP/Contents/Helpers/scene-tweak" "$APP"; do
  INFO="$(codesign -dvv "$code" 2>&1)"
  [[ "$INFO" == *"TeamIdentifier=$TEAM_ID"* ]] || fail "$(basename "$code") is not signed by team $TEAM_ID"
  [[ "$INFO" == *"runtime"* ]] || fail "$(basename "$code") has no hardened runtime"
  [[ "$INFO" == *"Timestamp="* ]] || fail "$(basename "$code") has no secure timestamp"
done
SDK="$(vtool -show-build "$APP/Contents/MacOS/$APP_NAME" | awk '$1 == "sdk" { print $2; exit }')"
[[ "${SDK%%.*}" -ge 26 ]] || fail "the app is linked against SDK $SDK. Build with Xcode 26 or later"
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$BUILT" == "$VERSION" ]] || fail "the built app reports version '$BUILT', not $VERSION"
echo "  $(lipo -archs "$APP/Contents/MacOS/$APP_NAME"), SDK $SDK, version $BUILT, team $TEAM_ID"

# --- Notarize --------------------------------------------------------------
step "Notarize with profile '$NOTARY_PROFILE' (this takes a few minutes)"
rm -rf "$DIST" && mkdir -p "$DIST"
/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$DIST/notarize.zip"
NOTARY_LOG="$(xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
echo "$NOTARY_LOG" | grep -E "id:|status:" | tail -2 | sed 's/^/  /'
[[ "$NOTARY_LOG" == *"status: Accepted"* ]] || fail "notarization failed. See: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE"
rm "$DIST/notarize.zip"

step "Staple and verify"
xcrun stapler staple "$APP" >/dev/null
xcrun stapler validate "$APP" >/dev/null || fail "the staple ticket is not valid"
spctl -a -t exec -vv "$APP" 2>&1 | sed 's/^/  /'
spctl -a -t exec "$APP" || fail "Gatekeeper rejects the app"

/usr/bin/ditto --norsrc -c -k --keepParent "$APP" "$ZIP"
echo "  $(basename "$ZIP")  sha256 $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
step "Done. Nothing was published."
