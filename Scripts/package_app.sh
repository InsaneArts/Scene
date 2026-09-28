#!/usr/bin/env bash
# Builds Scene.app with Xcode and signs it: the app, the scene-tweak helper, and the bundled themes.
#
#   Scripts/package_app.sh                                   # release, host architecture, ad-hoc signature
#   Scripts/package_app.sh debug
#   ARCHES="arm64 x86_64" APP_IDENTITY="Developer ID Application: Techzy LLC (539293JFA3)" Scripts/package_app.sh
#
# Scripts/release.sh uses the last form, then notarizes and staples.
set -euo pipefail

# The release Xcode, never a beta: a beta toolchain may link against an old SDK, and apps linked
# before SDK 26 do not get the macOS 26 design.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=Scene
APP_IDENTITY=${APP_IDENTITY:-}
# shellcheck disable=SC1091
source "$ROOT/version.env"

# Split on spaces on purpose: ARCHES="arm64 x86_64".
# shellcheck disable=SC2206
ARCH_LIST=( ${ARCHES:-} )
[[ ${#ARCH_LIST[@]} -gt 0 ]] || ARCH_LIST=("$(uname -m)")

case "$CONF" in
  debug) CONFIGURATION=Debug ;;
  release) CONFIGURATION=Release ;;
  *) echo "Usage: $0 [debug|release]" >&2; exit 1 ;;
esac

# Xcode builds the app and the helper, compiles the icon, and copies the themes. Signing happens below.
DERIVED_DATA="$ROOT/.build/Xcode"
xcodebuild build -project "$ROOT/Scene.xcodeproj" -scheme Scene -quiet \
  -configuration "$CONFIGURATION" -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" -clonedSourcePackagesDirPath "$ROOT/.build/SourcePackages" \
  "ARCHS=${ARCH_LIST[*]}" ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  "MARKETING_VERSION=$MARKETING_VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER"

APP="$ROOT/build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$ROOT/build"
ditto "$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app" "$APP"

for binary in "$APP/Contents/MacOS/$APP_NAME" "$APP/Contents/Helpers/scene-tweak"; do
  actual=$(lipo -archs "$binary")
  for arch in "${ARCH_LIST[@]}"; do
    [[ " $actual " == *" $arch "* ]] || { echo "ERROR: $(basename "$binary") is missing $arch (has: $actual)" >&2; exit 1; }
  done
done

# Xcode copies the Themes folder whole. Only the files a theme package may contain ship.
find "$APP/Contents/Resources/Themes" -type f ! -name theme.json ! -path '*/wallpapers/*' ! -path '*/apps/*' -delete

# Extended attributes and AppleDouble files break the code seal.
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

if [[ -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --options runtime --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi
# Nested code first, then the app. Debug builds put the app code and the preview loader beside the executable.
for library in "$APP/Contents/MacOS/"*.dylib; do
  [[ -f "$library" ]] || continue
  codesign "${CODESIGN_ARGS[@]}" "$library"
done
codesign "${CODESIGN_ARGS[@]}" "$APP/Contents/Helpers/scene-tweak"
codesign "${CODESIGN_ARGS[@]}" --entitlements "$ROOT/Config/Scene.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built $APP $MARKETING_VERSION ($BUILD_NUMBER), $(lipo -archs "$APP/Contents/MacOS/$APP_NAME"), signed with: ${APP_IDENTITY:-ad-hoc}"
