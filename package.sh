#!/bin/zsh
# Build the disk image build/MacDisplayMenu-<version>.dmg (the app plus a link to Applications).
set -euo pipefail
cd "$(dirname "$0")"
VERSION=${VERSION:-1.3.0}
export VERSION
./build.sh
STAGE=build/dmg
rm -rf "$STAGE" "build/MacDisplayMenu-$VERSION.dmg"
mkdir -p "$STAGE"
cp -R "build/Mac Display Menu.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mac Display Menu" -srcfolder "$STAGE" -ov -format UDZO \
  "build/MacDisplayMenu-$VERSION.dmg" >/dev/null
echo "Disk image: build/MacDisplayMenu-$VERSION.dmg"
