#!/bin/sh
# Builds Mochi.app: compiles the SwiftUI executable via SwiftPM, then hand-assembles a real
# .app bundle (Info.plist, icon, ad-hoc codesign) since there is no Xcode project in this
# repo — SwiftPM alone produces a bare executable, not something Launch Services, Notification
# Center, or SMAppService will treat as an app.
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CONFIG="${1:-debug}"
if [ "$CONFIG" = "release" ]; then
    SWIFT_CONFIG_FLAG="-c release"
else
    SWIFT_CONFIG_FLAG=""
fi

echo "==> Building MochiApp ($CONFIG)"
# shellcheck disable=SC2086
swift build --target MochiApp $SWIFT_CONFIG_FLAG

BIN_PATH=$(swift build --target MochiApp $SWIFT_CONFIG_FLAG --show-bin-path)
APP_DIR="$ROOT_DIR/.build/Mochi.app"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/MochiApp" "$APP_DIR/Contents/MacOS/Mochi"

if [ ! -f "$ROOT_DIR/Resources/AppIcon.icns" ]; then
    echo "==> Generating app icon"
    swift "$ROOT_DIR/Scripts/generate-app-icon.swift"
    iconutil -c icns "$ROOT_DIR/Resources/AppIcon.iconset" -o "$ROOT_DIR/Resources/AppIcon.icns"
fi
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Bundled SwiftUI resources (none yet beyond the icon, but keep the copy in case the
# MochiApp target's `resources: [.process("Resources")]` ever produces a .bundle).
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
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
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
    <key>NSHumanReadableCopyright</key>
    <string>Mochi</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Built $APP_DIR"
