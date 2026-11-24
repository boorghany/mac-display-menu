# Mac Display Menu

**If you want the Windows <kbd>Win</kbd>+<kbd>P</kbd> experience on your Mac, and even something better (showing a single window on the monitor), this project is for you.**

Press **⌘P** anywhere. A small window opens in the middle of the screen, and you choose how your external monitor is used:

1. **Extend**: two separate screens.
2. **Mirror for the MacBook**: both screens show the same image at the MacBook's resolution.
3. **Mirror for the monitor**: both screens show the same image at the monitor's native resolution.
4. **Extend one window**: the monitor shows only the window you pick, live. This works well for presenting one app while you keep the rest of your screen private.

Click an option or press 1–4. Esc closes the window. A check mark shows the current mode.

## Install

Download `MacDisplayMenu-<version>.pkg` from [Releases](../../releases) and open it.

The installer puts **Mac Display Menu** in `/Applications`, sets it to start at login, and adds the `displaymode` command-line tool to `/usr/local/bin`. The app has no Dock icon. Press ⌘P to use it.

The package is not notarized by Apple. The first time you open it, macOS may say it can't verify the developer. In that case, open **System Settings › Privacy & Security** and click **Open Anyway** next to the message about the package.

Requirements: macOS 14 Sonoma or later, on an Apple silicon or Intel Mac.

## Permissions

Mac Display Menu uses only macOS's own APIs. It does not ask for Accessibility, Input Monitoring or Screen Recording.

- Display modes use the CoreGraphics display configuration API, which changes the same setting as System Settings › Displays.
- The ⌘P shortcut is a Carbon global hotkey.
- Mode 4 uses the macOS window picker (`SCContentSharingPicker` in ScreenCaptureKit). You pick the window in the system's own interface, so macOS gives the app access to that window only. Each pick starts a new capture stream. While a window is shown, macOS displays its usual screen-sharing indicator in the menu bar.

## Mode 4 in detail

Mode 4 does not move any window or change the screen arrangement. If the screens are mirrored, it switches to extend first, because the monitor has to be a separate screen.

- **A window on the MacBook** fills the monitor. Each frame is captured at the exact pixel size it fills on the monitor, and the window's Retina pixels are scaled down, so text stays sharp.
- **A window on the monitor itself** stays where it is, at its real size, and the rest of the monitor goes black. The menu bar and the Dock stay usable. The window's app comes to the front, so clicks reach the real window under the image. The image follows the window when you move or resize it.

To pick another window, choose mode 4 again. To stop, choose modes 1–3 or use the menu-bar sharing indicator.

## Command-line tool

```sh
displaymode extend | mirror-builtin | mirror-external | status | menu
```

`menu` opens the picker of the running app.

## Notes

- ⌘P is taken system-wide, so ⌘P for Print no longer reaches other apps. To use a different key, change the `RegisterEventHotKey` call in `App/main.swift` and rebuild.
- The app assumes one built-in screen and one external monitor.

## Uninstall

```sh
./uninstall.sh
```

The script stops the app and removes the app, the login item and the CLI. It asks for your password because the package installs into system folders.

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh      # universal app and CLI in ./build
./package.sh    # build/MacDisplayMenu-<version>.pkg
```

## Layout

- `App/main.swift`: display modes, the picker window and the hotkey.
- `App/WindowPresenter.swift`: mode 4, which shows one window on the monitor.
- `cli/displaymode.swift`: the command-line tool.
- `packaging/`: installer scripts.

## License

MIT
