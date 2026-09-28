#!/usr/bin/env bash
# Runs the SceneKit unit tests through the Scene scheme. The live tests stay opt-in (see README).
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
xcodebuild test -project "$ROOT/Scene.xcodeproj" -scheme Scene \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$ROOT/.build/Xcode" \
  -clonedSourcePackagesDirPath "$ROOT/.build/SourcePackages" \
  "$@"
