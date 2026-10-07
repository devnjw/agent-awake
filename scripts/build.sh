#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$(pwd)"
OUTPUT_DIR="$TASK_ROOT/dist"
UNIVERSAL=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --universal) UNIVERSAL=true; shift ;;
        --output-dir) OUTPUT_DIR="${2:?Missing output directory}"; shift 2 ;;
        *) printf 'Usage: %s [--universal] [--output-dir DIRECTORY]\n' "$0" >&2; exit 2 ;;
    esac
done
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"
APP="$OUTPUT_DIR/AgentAwake.app"
if [[ "$UNIVERSAL" == true ]]; then
    MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release --arch arm64 --scratch-path .build/universal-arm64
    ARM_BIN="$(swift build -c release --arch arm64 --scratch-path .build/universal-arm64 --show-bin-path)/AgentAwake"
    MACOSX_DEPLOYMENT_TARGET=14.0 swift build -c release --arch x86_64 --scratch-path .build/universal-x86_64
    INTEL_BIN="$(swift build -c release --arch x86_64 --scratch-path .build/universal-x86_64 --show-bin-path)/AgentAwake"
else
    swift build -c release
    HOST_BIN="$(swift build -c release --show-bin-path)/AgentAwake"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "$UNIVERSAL" == true ]]; then
    lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/AgentAwake"
else
    cp "$HOST_BIN" "$APP/Contents/MacOS/AgentAwake"
fi
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
