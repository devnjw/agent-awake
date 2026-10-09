#!/bin/bash
# Builds an Apple Silicon app, a drag-to-install disk image, and a portable ZIP.
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$(pwd)"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
PROFILE=''
while [[ $# -gt 0 ]]; do
    case "$1" in
        --notarize-profile) PROFILE="${2:?Missing keychain profile}"; shift 2 ;;
        *) printf 'Usage: %s [--notarize-profile NAME]\n' "$0" >&2; exit 2 ;;
    esac
done
if [[ -n "$PROFILE" && "${CODESIGN_IDENTITY:--}" == '-' ]]; then
    printf 'Notarization requires CODESIGN_IDENTITY (Developer ID Application).\n' >&2
    exit 2
fi
STAGING="$(mktemp -d "$TASK_ROOT/dist-package.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ARTIFACT_DIR="$TASK_ROOT/dist/releases/v$APP_VERSION"
mkdir -p "$ARTIFACT_DIR"
notarize() {
    local archive="$1" report="$2"
    xcrun notarytool submit "$archive" --keychain-profile "$PROFILE" --wait \
        --output-format json > "$report"
    python3 - "$report" <<'PY'
import json
import sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
print(f"Apple notarization: {result.get('status')} (submission {result.get('id')})")
if result.get('status') != 'Accepted':
    raise SystemExit('Notarization was not accepted; release packaging stopped.')
PY
}
bash scripts/build.sh --output-dir "$STAGING/build"
APP="$STAGING/build/AgentAwake.app"
if [[ -n "$PROFILE" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$APP" "$STAGING/notarize.zip"
    notarize "$STAGING/notarize.zip" "$ARTIFACT_DIR/notarization-app.json"
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
fi
ZIP="$ARTIFACT_DIR/AgentAwake-$APP_VERSION-arm64.zip"
DMG="$ARTIFACT_DIR/AgentAwake-$APP_VERSION-arm64.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
mkdir -p "$STAGING/volume"
ditto "$APP" "$STAGING/volume/AgentAwake.app"
ln -s /Applications "$STAGING/volume/Applications"
cp docs/INSTALL.txt "$STAGING/volume/INSTALL.txt"
cp LICENSE "$STAGING/volume/LICENSE.txt"
if [[ -n "$PROFILE" ]]; then
    printf '\nRelease signing: Developer ID signed and Apple notarized.\n' >> "$STAGING/volume/INSTALL.txt"
elif [[ "${CODESIGN_IDENTITY:--}" != '-' ]]; then
    printf '\nRelease signing: Developer ID signed; not Apple notarized.\nFirst launch: https://support.apple.com/102445\n' >> "$STAGING/volume/INSTALL.txt"
else
    printf '\nLocal preview: ad hoc signed; not Apple notarized.\n' >> "$STAGING/volume/INSTALL.txt"
fi
hdiutil create -volname "AgentAwake $APP_VERSION" -srcfolder "$STAGING/volume" \
    -format UDZO -ov "$DMG"
if [[ "${CODESIGN_IDENTITY:--}" != '-' ]]; then
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
    codesign --verify --strict "$DMG"
fi
if [[ -n "$PROFILE" ]]; then
    notarize "$DMG" "$ARTIFACT_DIR/notarization-dmg.json"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
fi
(cd "$ARTIFACT_DIR" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > SHA256SUMS.txt)
printf 'Release files: %s\n' "$ARTIFACT_DIR"
