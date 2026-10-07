#!/bin/bash
# Verifies the actual download artifacts without applying any power settings.
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$(pwd)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
ARTIFACT_DIR="${1:-$TASK_ROOT/dist/releases/v$APP_VERSION}"
ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/agent-awake-verify.XXXXXX")"
MOUNT="$STAGING/mount"
MOUNTED=false
cleanup() {
    if [[ "$MOUNTED" == true ]]; then hdiutil detach "$MOUNT" >/dev/null; fi
    rm -rf "$STAGING"
}
trap cleanup EXIT
(cd "$ARTIFACT_DIR" && shasum -a 256 -c SHA256SUMS.txt)
ditto -x -k "$ARTIFACT_DIR/AgentAwake-$APP_VERSION-universal.zip" "$STAGING/zip"
APP="$STAGING/zip/AgentAwake.app"
codesign --verify --strict "$APP"
for architecture in arm64 x86_64; do
    lipo "$APP/Contents/MacOS/AgentAwake" -verify_arch "$architecture"
done
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$APP_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == '14.0'
cmp LICENSE "$APP/Contents/Resources/LICENSE.txt"
"$APP/Contents/MacOS/AgentAwake" --diagnose
DMG="$ARTIFACT_DIR/AgentAwake-$APP_VERSION-universal.dmg"
hdiutil verify "$DMG"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
MOUNTED=true
test "$(readlink "$MOUNT/Applications")" == '/Applications'
test -f "$MOUNT/INSTALL.txt"
cmp LICENSE "$MOUNT/LICENSE.txt"
codesign --verify --strict "$MOUNT/AgentAwake.app"
diff -qr "$APP" "$MOUNT/AgentAwake.app"
printf 'Verified: checksums, universal ZIP, signature, version, license, DMG, and Applications shortcut.\n'
