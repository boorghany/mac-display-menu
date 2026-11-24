#!/bin/zsh
# Build, install to ~/Applications, and start DisplayMenu at login with a launchd agent.
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
LABEL=com.user.displaymenu
APP="$HOME/Applications/DisplayMenu.app"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/.local/bin"
rm -rf "$APP"
cp -R build/DisplayMenu.app "$APP"
cp build/displaymode "$HOME/.local/bin/displaymode"

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/DisplayMenu</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST

if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
else
  launchctl bootstrap "gui/$(id -u)" "$AGENT"
fi
echo "DisplayMenu is running. Press ⌘P to open it."
