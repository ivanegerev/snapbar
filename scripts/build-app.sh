#!/bin/bash
# Builds SnapBar.app and the release zip into dist/. Usage: scripts/build-app.sh
# Set ALLOW_ADHOC=1 to build without the "SnapBar Dev Signing" identity (local testing only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/SnapBar.app"
ZIP="$DIST/SnapBar.zip"

# Stable identity, so TCC grants survive rebuilds and updates. Ad-hoc signatures change
# with every build and leave updating users stuck in the Screen Recording prompt loop.
# grep without -q reads all input, so pipefail can't trip on SIGPIPE.
if security find-identity -p codesigning -v 2>/dev/null | grep "SnapBar Dev Signing" >/dev/null; then
    SIGN_ID="SnapBar Dev Signing"
elif [ "${ALLOW_ADHOC:-}" = 1 ]; then
    SIGN_ID="-"
else
    echo "error: 'SnapBar Dev Signing' codesigning identity not found." >&2
    echo "       Ad-hoc builds break Screen Recording grants for updating users, so they must not ship." >&2
    echo "       For a local-only build, rerun with ALLOW_ADHOC=1." >&2
    exit 1
fi

echo "==> swift build -c release (universal: arm64 + x86_64)"
cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64

echo "==> assembling bundle"
rm -rf "$APP" "$ZIP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/apple/Products/Release/SnapBar" "$APP/Contents/MacOS/SnapBar"
strip -x "$APP/Contents/MacOS/SnapBar"
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

if [ "$SIGN_ID" = "-" ]; then
    echo "==> codesigning (ad-hoc, ALLOW_ADHOC=1: local testing only, do not ship)"
else
    echo "==> codesigning ($SIGN_ID)"
fi
codesign --force --sign "$SIGN_ID" --identifier com.ivanegerev.snapbar "$APP"
codesign --verify --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/SnapBar" -verify_arch arm64 x86_64

echo "==> zipping"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> done: $APP"
echo "    release asset: $ZIP"
