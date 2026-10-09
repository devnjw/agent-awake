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
ditto -x -k "$ARTIFACT_DIR/AgentAwake-$APP_VERSION-arm64.zip" "$STAGING/zip"
APP="$STAGING/zip/AgentAwake.app"
codesign --verify --strict "$APP"
test "$(lipo -archs "$APP/Contents/MacOS/AgentAwake")" == 'arm64'
while IFS= read -r -d '' component; do
    if [[ "$(file -b "$component")" == *Mach-O* ]]; then
        test "$(lipo -archs "$component")" == 'arm64'
    fi
done < <(find "$APP" -type f -print0)
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")" == "$APP_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$APP/Contents/Info.plist")" == '14.0'
test "$(/usr/libexec/PlistBuddy -c 'Print LSRequiresNativeExecution' "$APP/Contents/Info.plist")" == 'true'
cmp LICENSE "$APP/Contents/Resources/LICENSE.txt"
"$APP/Contents/MacOS/AgentAwake" --diagnose
DMG="$ARTIFACT_DIR/AgentAwake-$APP_VERSION-arm64.dmg"
hdiutil verify "$DMG"
mkdir -p "$MOUNT"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT" "$DMG" >/dev/null
MOUNTED=true
test "$(readlink "$MOUNT/Applications")" == '/Applications'
test -f "$MOUNT/INSTALL.txt"
cmp LICENSE "$MOUNT/LICENSE.txt"
codesign --verify --strict "$MOUNT/AgentAwake.app"
diff -qr "$APP" "$MOUNT/AgentAwake.app"
printf 'Verified: checksums, arm64-only ZIP, signature, version, license, DMG, and Applications shortcut.\n'
