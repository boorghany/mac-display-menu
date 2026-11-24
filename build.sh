#!/bin/zsh
# Build DisplayMenu.app and the displaymode CLI into ./build
set -euo pipefail
cd "$(dirname "$0")"
APP=build/DisplayMenu.app
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.user.displaymenu</string>
  <key>CFBundleName</key><string>DisplayMenu</string>
  <key>CFBundleExecutable</key><string>DisplayMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
swiftc -O -swift-version 5 DisplayMenu/*.swift -o "$APP/Contents/MacOS/DisplayMenu"
codesign --force --sign - "$APP"
swiftc -O -swift-version 5 cli/displaymode.swift -o build/displaymode
echo "Built $APP and build/displaymode"
