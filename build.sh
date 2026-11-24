#!/bin/zsh
# Build "Mac Display Menu.app" and the displaymode CLI into ./build as universal (Apple silicon + Intel) binaries.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${VERSION:-1.3.0}
APP="build/Mac Display Menu.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" build/obj
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.boorghany.macdisplaymenu</string>
  <key>CFBundleName</key><string>Mac Display Menu</string>
  <key>CFBundleDisplayName</key><string>Mac Display Menu</string>
  <key>CFBundleExecutable</key><string>MacDisplayMenu</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST

universal() { # universal <output> <sources...>
  local out=$1; shift
  for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target $arch-apple-macos14.0 "$@" -o "build/obj/$(basename "$out")-$arch"
  done
  lipo -create "build/obj/$(basename "$out")-arm64" "build/obj/$(basename "$out")-x86_64" -output "$out"
}

universal "$APP/Contents/MacOS/MacDisplayMenu" App/*.swift
universal build/displaymode cli/displaymode.swift
codesign --force --sign - build/displaymode
cp build/displaymode "$APP/Contents/MacOS/displaymode" # the CLI ships inside the app
codesign --force --sign - "$APP/Contents/MacOS/displaymode"
codesign --force --sign - "$APP"
echo "Built $APP and build/displaymode ($VERSION)"
