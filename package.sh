#!/bin/zsh
# Build the installer package build/MacDisplayMenu-<version>.pkg
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${VERSION:-1.2.0}
export VERSION
./build.sh

ROOT=build/pkgroot
rm -rf "$ROOT" build/MacDisplayMenu-component.pkg build/res
mkdir -p "$ROOT/Applications" "$ROOT/Library/LaunchAgents" "$ROOT/usr/local/bin" build/res
cp -R "build/Mac Display Menu.app" "$ROOT/Applications/"
cp packaging/io.github.boorghany.macdisplaymenu.plist "$ROOT/Library/LaunchAgents/"
cp build/displaymode "$ROOT/usr/local/bin/"
chmod 755 packaging/scripts/*
xattr -cr "$ROOT" # no AppleDouble ._ files in the payload

# Install the app where the package says, even if another copy exists elsewhere on the Mac.
pkgbuild --analyze --root "$ROOT" build/component.plist >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO build/component.plist

pkgbuild --root "$ROOT" --component-plist build/component.plist --scripts packaging/scripts \
  --identifier io.github.boorghany.macdisplaymenu.pkg --version "$VERSION" \
  --install-location / build/MacDisplayMenu-component.pkg

sed "s/__VERSION__/$VERSION/" packaging/distribution.xml > build/distribution.xml
cp packaging/welcome.html build/res/
productbuild --distribution build/distribution.xml --package-path build --resources build/res \
  "build/MacDisplayMenu-$VERSION.pkg"
rm -f build/MacDisplayMenu-component.pkg
echo "Package: build/MacDisplayMenu-$VERSION.pkg"
