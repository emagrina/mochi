#!/bin/bash
# Packages a built Mochi.app into a distributable DMG: dist/Mochi-<version>.dmg, containing
# Mochi.app and an /Applications symlink so opening the DMG shows the familiar
# "drag app onto Applications" install experience.
#
# Deliberately plain `hdiutil` (standard macOS tooling), not a third-party packager like
# create-dmg: a custom-arranged Finder window (background image, exact icon positions) needs
# driving Finder via AppleScript, which is well known to be unreliable on a GitHub Actions
# runner with no interactive login session — this stays simple and 100% reproducible in CI
# at the cost of a plain (not custom-styled) Finder window when the DMG is opened.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="${1:-$ROOT_DIR/.build/Mochi.app}"
VERSION="${MOCHI_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.0.0)}"
DIST_DIR="$ROOT_DIR/dist"
DMG_NAME="Mochi-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/.build/dmg-staging"

echo "==> Packaging $DMG_NAME from $APP_PATH"

if [ ! -d "$APP_PATH" ]; then
    echo "error: $APP_PATH not found — run Scripts/build-app.sh first" >&2
    exit 1
fi
if [ ! -x "$APP_PATH/Contents/MacOS/Mochi" ]; then
    echo "error: $APP_PATH does not contain a valid Mochi executable" >&2
    exit 1
fi

echo "==> Cleaning previous packaging artifacts"
rm -rf "$STAGING_DIR"
rm -f "$DMG_PATH"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

echo "==> Staging DMG contents"
cp -R "$APP_PATH" "$STAGING_DIR/Mochi.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating $DMG_PATH"
hdiutil create \
    -volname "Mochi" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

if [ ! -f "$DMG_PATH" ]; then
    echo "error: $DMG_PATH was not created" >&2
    exit 1
fi

echo "==> Created $DMG_PATH"
