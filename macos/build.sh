#!/bin/bash
# Builds Screen Timer.app into ./build, no Xcode project required.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Screen Timer"
BUNDLE_ID="com.aakashns.screentimer"
EXEC_NAME="ScreenTimer"
APP="build/${APP_NAME}.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit \
  -o "$APP/Contents/MacOS/$EXEC_NAME" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleExecutable</key><string>${EXEC_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "note: ad-hoc codesign skipped"

echo "Built $APP"
