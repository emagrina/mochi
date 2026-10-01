#!/bin/bash
# Submits a signed Mochi.app to Apple's notary service with notarytool (never the deprecated
# altool), waits for a result, and staples the ticket onto the app itself — not the DMG — so
# Scripts/package-dmg.sh can run afterward and simply zip up an app that's already
# Gatekeeper-ready; stapling the .app directly is the standard, documented target for
# `stapler staple`, and avoids relying on the DMG container preserving it correctly.
#
# A no-op (not a failure) when notarization credentials aren't configured, so
# Scripts/release.sh and the release workflow can call this unconditionally either way.
# See docs/releasing.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/Mochi.app}"

if [ -z "${APPLE_NOTARIZATION_APPLE_ID:-}" ] && [ -z "${APPLE_NOTARIZATION_KEY_ID:-}" ]; then
    echo "==> Apple notarization is not configured (no APPLE_NOTARIZATION_* secrets)."
    echo "    $APP_PATH will remain un-notarized."
    exit 0
fi

if [ ! -d "$APP_PATH" ]; then
    echo "error: $APP_PATH not found" >&2
    exit 1
fi

ZIP_PATH="$ROOT_DIR/.build/mochi-notarization-submission.zip"
rm -f "$ZIP_PATH"

echo "==> Zipping $APP_PATH for submission"
# notarytool accepts a zip, a disk image, or a flat package — never a raw, unzipped .app.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting to Apple's notary service (this can take several minutes)"
if [ -n "${APPLE_NOTARIZATION_KEY_ID:-}" ]; then
    # App Store Connect API key auth — Apple's currently recommended approach, and what
    # docs/releasing.md asks for when setting this up, over an Apple ID + app-specific password.
    xcrun notarytool submit "$ZIP_PATH" \
        --key "${APPLE_NOTARIZATION_KEY_PATH:?APPLE_NOTARIZATION_KEY_PATH is required alongside APPLE_NOTARIZATION_KEY_ID}" \
        --key-id "$APPLE_NOTARIZATION_KEY_ID" \
        --issuer "${APPLE_NOTARIZATION_ISSUER_ID:?APPLE_NOTARIZATION_ISSUER_ID is required alongside APPLE_NOTARIZATION_KEY_ID}" \
        --wait
else
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_NOTARIZATION_APPLE_ID" \
        --team-id "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}" \
        --password "${APPLE_NOTARIZATION_PASSWORD:?APPLE_NOTARIZATION_PASSWORD is required}" \
        --wait
fi
# `--wait` makes this command itself exit non-zero if Apple rejects the submission, which
# (with `set -e`) is what makes a rejection fail this script and, in turn, the whole release.

rm -f "$ZIP_PATH"

echo "==> Stapling notarization ticket onto $APP_PATH"
xcrun stapler staple "$APP_PATH"

echo "==> Validating the stapled result"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

echo "==> Notarized and stapled $APP_PATH"
