#!/bin/bash
# Builds "Display Tuner.app" (ad-hoc signed) and installs it in /Applications.
# Usage: ./make-app.sh             build and install
#        ./make-app.sh --package   build dist/DisplayTuner.zip only (for CI)
set -euo pipefail
cd "$(dirname "$0")"

PACKAGE_ONLY=false
[ "${1:-}" = "--package" ] && PACKAGE_ONLY=true

APP="Display Tuner.app"
STAGE=".build/app/$APP"

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/DisplayTuner" "$STAGE/Contents/MacOS/DisplayTuner"
cp Resources/Info.plist "$STAGE/Contents/Info.plist"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$STAGE"

if $PACKAGE_ONLY; then
    echo "==> Packaging dist/DisplayTuner.zip"
    mkdir -p dist
    rm -f dist/DisplayTuner.zip
    ditto -c -k --keepParent "$STAGE" dist/DisplayTuner.zip
    echo "Done: dist/DisplayTuner.zip"
    exit 0
fi

echo "==> Installing to /Applications"
pkill -x DisplayTuner 2>/dev/null || true
rm -rf "/Applications/$APP"
cp -R "$STAGE" /Applications/
open "/Applications/$APP"
echo "Done. Display Tuner is open (and in the menu bar)."
