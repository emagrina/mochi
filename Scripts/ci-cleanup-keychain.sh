#!/bin/bash
# CI-only: removes the temporary signing keychain Scripts/ci-import-certificate.sh created.
# The release workflow runs this with `if: always()`, so it fires even if signing,
# notarization, or an earlier step failed — a certificate and its keychain should never be
# left behind on a GitHub-hosted runner.
set -uo pipefail

TMP_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
KEYCHAIN_PATH="$TMP_DIR/mochi-signing.keychain-db"
KEYCHAIN_PATH_FILE="$TMP_DIR/mochi-signing-keychain-path.txt"

if [ -f "$KEYCHAIN_PATH" ]; then
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
    echo "==> Removed temporary signing keychain"
else
    echo "==> No temporary signing keychain to remove"
fi

rm -f "$KEYCHAIN_PATH_FILE"
