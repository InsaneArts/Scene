#!/bin/bash
# Live test of the experimental tier on this Mac (design doc E2, E3, E3b).
# It changes Light/Dark, accent color, and icon style for a few seconds each, reads every value back,
# and always puts your original values back, even when a step fails.
# Usage: ./Scripts/verify-tweaks.sh   (prints the macOS build to add to TweakCatalog.testedBuilds on success)
set -uo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcodebuild build -project Scene.xcodeproj -scheme Scene -configuration Debug -quiet \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/Xcode \
  -clonedSourcePackagesDirPath .build/SourcePackages >/dev/null || exit 1
T=.build/Xcode/Build/Products/Debug/scene-tweak
BUILD="$(sysctl -n kern.osversion)"
value() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(json.dumps(d['value'], separators=(',',':')) if d.get('ok') else 'ERR:'+d.get('error',''))" "$1"; }

ORIG_APPEARANCE=$(value "$($T get appearance)")
ORIG_ACCENT=$(value "$($T get accent)")
ORIG_ICON=$(value "$($T get iconStyle)")
echo "macOS build $BUILD"
echo "original: appearance=$ORIG_APPEARANCE accent=$ORIG_ACCENT icon=$ORIG_ICON"
case "$ORIG_APPEARANCE$ORIG_ACCENT$ORIG_ICON" in *ERR:*) echo "cannot read current values; nothing changed"; exit 1;; esac

restore() {
  $T set appearance "$ORIG_APPEARANCE" >/dev/null
  $T set accent "$ORIG_ACCENT" >/dev/null
  $T set iconStyle "$ORIG_ICON" >/dev/null
  echo "restored: appearance=$(value "$($T get appearance)") accent=$(value "$($T get accent)") icon=$(value "$($T get iconStyle)")"
}
trap restore EXIT

PASS=()
FAIL=()
check() { # name, command args…
  local name="$1"; shift
  local out; out=$("$T" "$@"); local code=$?
  if [ $code -eq 0 ]; then PASS+=("$name"); echo "  ok   $name → $(value "$out")"; else FAIL+=("$name"); echo "  FAIL $name → $out"; fi
  sleep 1
}

echo "applying test values:"
DARK=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['dark'])" "$ORIG_APPEARANCE")
if [ "$DARK" = "True" ]; then check "appearance light" set appearance '{"dark":false,"auto":false}'; else check "appearance dark" set appearance '{"dark":true,"auto":false}'; fi
check "appearance auto" set appearance '{"dark":true,"auto":true}'
check "accent purple" set accent 5
check "accent multicolor" set accent -2
check "icon dark" set iconStyle '{"style":"RegularDark"}'
check "icon tinted custom" set iconStyle '{"style":"TintedDark","tint":"Other","custom":"#7aa2f7"}'
check "icon clear" set iconStyle '{"style":"ClearAutomatic"}'
echo "passed: ${#PASS[@]}, failed: ${#FAIL[@]}"
[ ${#FAIL[@]} -eq 0 ] && echo "All tweaks passed on $BUILD. Add \"$BUILD\" to TweakCatalog.testedBuilds." 
