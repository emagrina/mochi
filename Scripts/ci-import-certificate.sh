#!/bin/bash
# CI-only: imports a Developer ID Application certificate (a base64-encoded .p12) into a
# fresh, dedicated keychain so `codesign` can find it during a GitHub Actions run, then adds
# that keychain to the search list so Scripts/sign-app.sh's plain `codesign --sign <identity>`
# works identically to how it already does on a developer's own Mac — there, the certificate
# just already lives in the login keychain. Never called by Scripts/release.sh directly, and
# never meant for local use. Paired with Scripts/ci-cleanup-keychain.sh, which removes
# everything this creates (see docs/releasing.md's security notes and .github/workflows/release.yml).
set -euo pipefail

: "${APPLE_CERTIFICATE_BASE64:?required: base64-encoded Developer ID Application .p12}"
: "${APPLE_CERTIFICATE_PASSWORD:?required: the password that .p12 was exported with}"

TMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN_PATH="$TMP_DIR/mochi-signing.keychain-db"
KEYCHAIN_PATH_FILE="$TMP_DIR/mochi-signing-keychain-path.txt"
CERT_PATH="$TMP_DIR/mochi-signing-certificate.p12"
KEYCHAIN_PASSWORD=$(openssl rand -base64 24)

echo "==> Decoding certificate"
echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$CERT_PATH"

echo "==> Creating temporary keychain"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "==> Importing certificate"
security import "$CERT_PATH" -k "$KEYCHAIN_PATH" -P "$APPLE_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

echo "==> Adding it to the keychain search list"
EXISTING_KEYCHAINS=$(security list-keychains -d user | sed 's/[[:space:]]*"\(.*\)"[[:space:]]*/\1/')
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS

rm -f "$CERT_PATH"
echo "$KEYCHAIN_PATH" > "$KEYCHAIN_PATH_FILE"

echo "==> Imported signing certificate into a temporary keychain"
