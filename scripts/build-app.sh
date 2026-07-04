#!/bin/bash
# Builds SnapBar.app into dist/. Usage: scripts/build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/SnapBar.app"

echo "==> swift build -c release"
cd "$ROOT"
swift build -c release

echo "==> assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/SnapBar" "$APP/Contents/MacOS/SnapBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

if [ ! -f "$ROOT/Resources/SnapBar.icns" ]; then
    echo "==> generating app icon"
    ICONSET="$DIST/SnapBar.iconset"
    rm -rf "$ICONSET"
    swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ROOT/Resources/SnapBar.icns"
    rm -rf "$ICONSET"
fi
cp "$ROOT/Resources/SnapBar.icns" "$APP/Contents/Resources/SnapBar.icns"

if security find-identity -p codesigning -v 2>/dev/null | grep -q "SnapBar Dev Signing"; then
    echo "==> codesigning (SnapBar Dev Signing — stable identity, TCC grants survive rebuilds)"
    codesign --force --sign "SnapBar Dev Signing" --identifier com.ivanegerev.snapbar "$APP"
else
    echo "==> codesigning (ad-hoc)"
    codesign --force --sign - --identifier com.ivanegerev.snapbar "$APP"
fi

echo "==> done: $APP"
