#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$(pwd)"
OUTPUT_DIR="$TASK_ROOT/dist"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output-dir) OUTPUT_DIR="${2:?Missing output directory}"; shift 2 ;;
        *) printf 'Usage: %s [--output-dir DIRECTORY]\n' "$0" >&2; exit 2 ;;
    esac
done
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
APP="$OUTPUT_DIR/AgentAwake.app"
# Always target Apple Silicon, regardless of the build machine's architecture.
MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release --arch arm64 --scratch-path .build/apple-silicon
ARM_BIN="$(swift build -c release --arch arm64 --scratch-path .build/apple-silicon --show-bin-path)/AgentAwake"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ARM_BIN" "$APP/Contents/MacOS/AgentAwake"
test "$(lipo -archs "$APP/Contents/MacOS/AgentAwake")" == 'arm64'
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
swift scripts/icon.swift "$APP/Contents/Resources"
SIGNING_IDENTITY="${CODESIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == '-' ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
lipo -archs "$APP/Contents/MacOS/AgentAwake"
printf 'Built: %s\n' "$APP"
