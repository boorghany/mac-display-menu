#!/bin/zsh
# Stop Mac Display Menu and remove the app, the login item and the CLI.
LABEL=io.github.boorghany.macdisplaymenu
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
sudo rm -f "/Library/LaunchAgents/$LABEL.plist" /usr/local/bin/displaymode
sudo rm -rf "/Applications/Mac Display Menu.app"
sudo pkgutil --forget io.github.boorghany.macdisplaymenu.pkg >/dev/null 2>&1
echo "Mac Display Menu removed."
