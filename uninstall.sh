#!/bin/zsh
# Quit Mac Display Menu and remove it. Also removes the files of the 1.2.0 .pkg install, if present.
LABEL=io.github.boorghany.macdisplaymenu
if [[ -e "/Library/LaunchAgents/$LABEL.plist" || -e /usr/local/bin/displaymode ]]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  sudo rm -f "/Library/LaunchAgents/$LABEL.plist" /usr/local/bin/displaymode
  sudo pkgutil --forget io.github.boorghany.macdisplaymenu.pkg >/dev/null 2>&1
fi
pkill -x MacDisplayMenu 2>/dev/null
if [[ -O "/Applications/Mac Display Menu.app" ]]; then
  rm -rf "/Applications/Mac Display Menu.app"
else
  sudo rm -rf "/Applications/Mac Display Menu.app"
fi
echo "Mac Display Menu removed. Its login item disappears with the app."
