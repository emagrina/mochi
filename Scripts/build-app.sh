#!/bin/sh
# Builds Mochi.app: compiles the SwiftUI executable via SwiftPM, then hand-assembles a real
# .app bundle (Info.plist, icon, ad-hoc codesign) since there is no Xcode project in this
# repo — SwiftPM alone produces a bare executable, not something Launch Services, Notification
# Center, or SMAppService will treat as an app.
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# Single source of truth for the version: the VERSION file for local/dev builds, or
# MOCHI_VERSION (set by Scripts/release.sh from the git tag in CI, or by hand) to override it
# without editing anything. Both Info.plist version keys come from this one value — see
# docs/releasing.md's "Versioning" section for why CFBundleVersion isn't a separate number.
VERSION_STRING="${MOCHI_VERSION:-$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo 0.0.0)}"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
    SWIFT_CONFIG_FLAG="-c release"
else
    SWIFT_CONFIG_FLAG=""
fi

# Visual assets are generated from Resources/DesignSources/*.png BEFORE the build, not after:
# the menu bar template (Sources/MochiApp/Resources/MochiMenuBarTemplate.png) is a SwiftPM
# resource that gets compiled INTO the executable's resource bundle, so it must exist on disk
# before `swift build` runs — unlike AppIcon.icns, which is copied into the .app bundle
# separately afterward and never touches SwiftPM's resource pipeline at all.
if [ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ] || [ ! -f "$ROOT_DIR/Sources/MochiApp/Resources/MochiMenuBarTemplate.png" ]; then
    echo "==> Generating visual assets from Resources/DesignSources/"
    swift "$ROOT_DIR/Scripts/generate-assets.swift"
    iconutil -c icns "$ROOT_DIR/Resources/AppIcon.iconset" -o "$ROOT_DIR/Resources/AppIcon.icns"
fi

echo "==> Building MochiApp ($CONFIG)"
# shellcheck disable=SC2086
swift build --target MochiApp $SWIFT_CONFIG_FLAG

BIN_PATH=$(swift build --target MochiApp $SWIFT_CONFIG_FLAG --show-bin-path)

# Some toolchains' `--show-bin-path` doesn't match where the executable actually lands (seen
# on a GitHub Actions runner with a newer Xcode than any used in local development so far) —
# rather than hardcode a guess at that toolchain's exact layout, just verify the expected
# location and fall back to a plain filesystem search for the real one if it's not there.
if [ ! -x "$BIN_PATH/MochiApp" ]; then
    echo "==> MochiApp not at the reported bin path ($BIN_PATH/MochiApp) — searching .build/ for it"
    # Scoped to a path containing the actual config name first: a debug build can genuinely
    # coexist with a release one under .build/ (this script's own debug-build branch and this
    # release branch both ran in the same job), so an unscoped search could silently grab the
    # wrong one instead of just failing loudly.
    FOUND=$(find "$ROOT_DIR/.build" -type f -name MochiApp -perm -u+x -ipath "*$CONFIG*" 2>/dev/null | head -n 1)
    if [ -z "$FOUND" ]; then
        FOUND=$(find "$ROOT_DIR/.build" -type f -name MochiApp -perm -u+x 2>/dev/null | head -n 1)
    fi
    if [ -z "$FOUND" ]; then
        echo "error: couldn't find a built MochiApp executable anywhere under .build/" >&2
        exit 1
    fi
    BIN_PATH="$(dirname "$FOUND")"
    echo "==> Found it at $BIN_PATH"
fi

APP_DIR="$ROOT_DIR/.build/Mochi.app"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/MochiApp" "$APP_DIR/Contents/MacOS/Mochi"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# SwiftPM-processed resources (currently: MochiMenuBarTemplate.png) land in their own
# resource bundle next to the executable; Launch Services only finds it if it's copied
# alongside the binary inside the .app, not left in .build.
RESOURCE_BUNDLE="$BIN_PATH/Mochi_MochiApp.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Mochi</string>
    <key>CFBundleDisplayName</key>
    <string>Mochi</string>
    <key>CFBundleIdentifier</key>
    <string>dev.mochi.app</string>
    <key>CFBundleVersion</key>
    <string>__VERSION__</string>
    <key>CFBundleShortVersionString</key>
    <string>__VERSION__</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Mochi</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Mochi</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# The heredoc above is quoted ('PLIST') specifically so $-expansion doesn't touch anything in
# it — Info.plist has its own literal `$`-free content anyway, but this keeps that invariant
# obvious. The version placeholder is substituted afterward instead, in one place.
sed -i '' "s/__VERSION__/$VERSION_STRING/g" "$APP_DIR/Contents/Info.plist"

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Built $APP_DIR (version $VERSION_STRING)"
