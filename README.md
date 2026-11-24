# DisplayMenu

A small macOS helper for a MacBook with one external monitor. Press **⌘P** anywhere, and a small window opens in the middle of the screen where you choose how the monitor is used:

1. **Extend**: two separate screens.
2. **Mirror, optimized for the MacBook screen**: both screens show the same image at the MacBook's resolution.
3. **Mirror, optimized for the monitor**: both screens show the same image at the monitor's native resolution.
4. **Extend with one window**: the monitor shows only the window you pick, live, like presenting one window. You keep working on the MacBook screen.

You can click an option or press 1–4. Esc closes the window. The current mode has a check mark.

The interface is in Persian (right to left).

## Permissions

DisplayMenu uses only macOS's own APIs and does not ask for Accessibility, Input Monitoring or Screen Recording:

- Display modes use the CoreGraphics display configuration API (`CGConfigureDisplayMirrorOfDisplay`), which is the same setting as System Settings › Displays.
- The ⌘P shortcut is a Carbon global hotkey (`RegisterEventHotKey`).
- Mode 4 uses the macOS window picker (`SCContentSharingPicker`, ScreenCaptureKit, macOS 14+). You pick the window in the system's own UI, so macOS gives access to that window only. While a window is shown, macOS displays its usual screen-sharing indicator in the menu bar, where you can switch to another window or stop. Choosing mode 4 again also lets you switch windows, and choosing modes 1–3 stops it.

## Moving a window to the monitor (extend mode)

macOS has its own *Window › Move to «display»* menu items. You can give them shortcuts in the global `NSUserKeyEquivalents`. Use the display names as macOS shows them:

```sh
defaults write -g NSUserKeyEquivalents -dict-add \
  "Move to LG FHD" "^~@\\Uf703" \
  "Move to Built-in Retina Display" "^~@\\Uf702"
```

With this setting, ⌃⌥⌘→ moves the focused window to the monitor and ⌃⌥⌘← moves it back. Apps that are already open pick up the shortcuts after a restart.

## Install

Requirements: macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./install.sh
```

This script builds the app and copies it to `~/Applications/DisplayMenu.app`. It also adds the `displaymode` CLI to `~/.local/bin` and starts the app at login with the launchd agent `com.user.displaymenu`.

To remove everything:

```sh
./uninstall.sh
```

## CLI

```sh
displaymode extend | mirror-builtin | mirror-external | status | menu
```

`menu` opens the picker window of the running app.

## Notes

- ⌘P is taken system-wide, so ⌘P for Print no longer reaches apps. To use a different key, change the `RegisterEventHotKey` call in `DisplayMenu/main.swift` and run `./install.sh` again.
- The tool assumes one built-in screen and one external monitor.

## Layout

- `DisplayMenu/main.swift`: display modes, the picker window and the hotkey.
- `DisplayMenu/WindowPresenter.swift`: mode 4, which shows one window on the monitor.
- `cli/displaymode.swift`: the command-line tool.
- `build.sh`, `install.sh`, `uninstall.sh`
