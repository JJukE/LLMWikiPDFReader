#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LLMWikiPDFReader"
BUNDLE_ID="com.example.LLMWikiPDFReader"
EXECUTABLE_NAME="LLMWikiPDFReader"
SWIFTPM_PRODUCT_NAME="LLMWikiPDFReaderMac"
APP_DIR="$HOME/Applications/$APP_NAME.app"
LEGACY_APP_DIR="$HOME/Applications/LLM Wiki PDF Reader.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_FILE="AppIcon.icns"

cd "$PROJECT_DIR"
swift build -c release --product "$SWIFTPM_PRODUCT_NAME"

if [[ -d "$LEGACY_APP_DIR" && "$LEGACY_APP_DIR" != "$APP_DIR" ]]; then
    rm -rf "$LEGACY_APP_DIR"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp ".build/release/$SWIFTPM_PRODUCT_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$PROJECT_DIR/Resources/$ICON_FILE" "$RESOURCES_DIR/$ICON_FILE"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_FILE</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Installed $APP_DIR"
echo "Open it with: open \"$APP_DIR\""
