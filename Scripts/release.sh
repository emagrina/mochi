#!/bin/bash
# Local (and CI) entry point for a full release: tests, a release build, optional signing +
# notarization, the DMG, and a final mount-and-check validation pass. Run it as:
#
#   ./Scripts/release.sh
#
# with no Apple Developer credentials configured, this produces an unsigned
# dist/Mochi-<version>.dmg — see docs/releasing.md for what "configured" means and how to get
# there once you have a Developer ID. This script is additional to, not a replacement for,
# the everyday dev loop: swift build / swift test / ./Scripts/build-app.sh / open
# .build/Mochi.app all still work exactly as before.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${MOCHI_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.0.0)}"
export MOCHI_VERSION="$VERSION"
APP_PATH="$ROOT_DIR/.build/Mochi.app"
DMG_PATH="$ROOT_DIR/dist/Mochi-$VERSION.dmg"

echo "==> Releasing Mochi $VERSION"
echo ""

echo "==> Cleaning previous release artifacts"
rm -rf "$ROOT_DIR/dist"
rm -rf "$APP_PATH"

echo "==> Running tests"
swift test

echo "==> Building release app"
"$ROOT_DIR/Scripts/build-app.sh" release

if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
    echo "==> Apple Developer signing is configured — producing a signed, notarized build."
    "$ROOT_DIR/Scripts/sign-app.sh" "$APP_PATH"
    "$ROOT_DIR/Scripts/notarize.sh" "$APP_PATH"
else
    echo "⚠️  Apple Developer signing is not configured. Creating unsigned DMG."
fi

"$ROOT_DIR/Scripts/package-dmg.sh" "$APP_PATH"

echo "==> Validating $DMG_PATH"
MOUNT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mochi-dmg-verify.XXXXXX")
cleanup_mount() {
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
    rmdir "$MOUNT_DIR" 2>/dev/null || true
}
trap cleanup_mount EXIT

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null

if [ ! -d "$MOUNT_DIR/Mochi.app" ]; then
    echo "error: Mochi.app is missing from $DMG_PATH" >&2
    exit 1
fi
if [ ! -L "$MOUNT_DIR/Applications" ]; then
    echo "error: the Applications symlink is missing from $DMG_PATH" >&2
    exit 1
fi
if [ ! -x "$MOUNT_DIR/Mochi.app/Contents/MacOS/Mochi" ]; then
    echo "error: Mochi.app's executable is missing or not executable inside $DMG_PATH" >&2
    exit 1
fi

if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
    echo "==> Verifying codesign + Gatekeeper on the packaged app"
    codesign --verify --deep --strict "$MOUNT_DIR/Mochi.app"
    if ! spctl --assess --type execute "$MOUNT_DIR/Mochi.app"; then
        echo "⚠️  spctl did not pass yet — this is expected for a few minutes after notarization"
        echo "    while Apple's ticket propagates; it isn't necessarily a real problem."
    fi
fi

echo "==> Validation passed"
echo ""
echo "Release ready:"
echo "dist/Mochi-$VERSION.dmg"
