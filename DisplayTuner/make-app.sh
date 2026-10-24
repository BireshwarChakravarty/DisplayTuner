#!/bin/bash
# Build a signed app and ZIP. Installation is explicit: --install.
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:---package}"
case "$MODE" in --package|--install|--stage) ;; *) echo 'Usage: make-app.sh [--package|--stage|--install]' >&2; exit 2 ;; esac
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
APP="Gamut Pro.app"
STAGE=".build/app/$APP"
python3 ../scripts/build-assets.py
swift build --arch arm64 -c release
BIN_DIR=$(swift build --arch arm64 -c release --show-bin-path)
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN_DIR/DisplayTuner" "$STAGE/Contents/MacOS/DisplayTuner"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
cp Resources/AppIcon.icns "$STAGE/Contents/Resources/AppIcon.icns"
cp ../LICENSE "$STAGE/Contents/Resources/LICENSE"
codesign --force --sign - "$STAGE"
codesign --verify --deep --strict "$STAGE"
if [[ "$MODE" == --stage ]]; then echo "Built: $STAGE"; exit 0; fi
mkdir -p dist
cp Resources/AppIcon.png dist/GamutPro-Icon.png
ARCHIVE="GamutPro-$VERSION-macOS.zip"
rm -f "dist/$ARCHIVE"
ditto -c -k --keepParent "$STAGE" "dist/$ARCHIVE"
(cd dist && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
if [[ "$MODE" == --install ]]; then
    # Quit the running copy and replace the bundle outright: merging into an
    # old bundle can leave stray files that break its code signature.
    osascript -e 'quit app id "app.displaytuner.DisplayTuner"' 2>/dev/null || true
    rm -rf "/Applications/$APP" "/Applications/Display Tuner.app"
    ditto "$STAGE" "/Applications/$APP"
    open "/Applications/$APP"
fi
echo "Built: dist/$ARCHIVE"
