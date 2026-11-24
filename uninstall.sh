#!/bin/zsh
# Stop DisplayMenu and remove the app, the CLI and the launchd agent.
set -u
LABEL=com.user.displaymenu
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/displaymode"
rm -rf "$HOME/Applications/DisplayMenu.app"
echo "DisplayMenu removed."
