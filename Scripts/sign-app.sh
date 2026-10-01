#!/bin/bash
# Signs Mochi.app with a Developer ID Application identity, if one is configured — a no-op
# (not a failure) when it isn't, so Scripts/release.sh and the release workflow can call this
# unconditionally in both the unsigned and signed pipelines. See docs/releasing.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$ROOT_DIR/.build/Mochi.app}"
ENTITLEMENTS="$ROOT_DIR/Resources/Mochi.entitlements"

if [ -z "${APPLE_SIGNING_IDENTITY:-}" ]; then
    echo "==> Apple Developer signing is not configured (APPLE_SIGNING_IDENTITY unset)."
    echo "    $APP_PATH remains ad-hoc signed (from Scripts/build-app.sh)."
    exit 0
fi

if [ ! -d "$APP_PATH" ]; then
    echo "error: $APP_PATH not found" >&2
    exit 1
fi
if [ ! -f "$ENTITLEMENTS" ]; then
    echo "error: $ENTITLEMENTS not found" >&2
    exit 1
fi

echo "==> Signing $APP_PATH with identity: $APPLE_SIGNING_IDENTITY"

# Sign nested executable components first, deepest first, rather than relying on `--deep`
# (which Apple's own documentation recommends against for Developer ID builds precisely
# because it signs things in the wrong order/with the wrong flags for nested content). Mochi
# ships no bundled frameworks, dylibs, or helper apps today — only a resource bundle with no
# executable code, which the outer signature's sealed-resources manifest already covers — but
# this keeps the script correct if that ever changes.
while IFS= read -r nested; do
    echo "==> Signing nested component: $nested"
    codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" "$nested"
done < <(find "$APP_PATH/Contents" \( -name "*.framework" -o -name "*.dylib" -o -name "*.app" \) 2>/dev/null)

codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$APPLE_SIGNING_IDENTITY" \
    "$APP_PATH"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Signed $APP_PATH"
