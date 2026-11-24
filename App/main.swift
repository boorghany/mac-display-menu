// Mac Display Menu — press ⌘P anywhere to open a small window in the middle of the screen
// and pick how the external monitor is used. Uses only macOS's own APIs:
// CoreGraphics for display configuration and a Carbon global hotkey,
// so it needs no Accessibility, Input Monitoring or Screen Recording permission.

import AppKit
import Carbon.HIToolbox
import CoreGraphics
import SwiftUI

// MARK: - Display configuration

enum Mode: Int, CaseIterable, Identifiable {
    case extend, mirrorBuiltin, mirrorExternal, singleWindow
    var id: Int { rawValue }

    var title: String {
        switch self {
        case .extend: return "Extend"
        case .mirrorBuiltin: return "Mirror for the MacBook"
        case .mirrorExternal: return "Mirror for the monitor"
        case .singleWindow: return "Extend one window"
        }
    }

    var subtitle: String {
        switch self {
        case .extend: return "Two separate screens"
        case .mirrorBuiltin: return "Same image, at the MacBook's resolution"
        case .mirrorExternal: return "Same image, at the monitor's resolution"
        case .singleWindow: return "Show only the window you pick on the monitor"
        }
    }

    var symbol: String {
        switch self {
        case .extend: return "rectangle.split.2x1"
        case .mirrorBuiltin: return "laptopcomputer"
        case .mirrorExternal: return "display"
        case .singleWindow: return "macwindow"
        }
    }
}

enum Displays {
    static let modeOptions = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary

    static func online() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        return Array(ids.prefix(Int(n)))
    }

    static var builtin: CGDirectDisplayID? { online().first { CGDisplayIsBuiltin($0) != 0 } }
    static var external: CGDirectDisplayID? { online().first { CGDisplayIsBuiltin($0) == 0 } }

    static func current() -> Mode? {
        guard let b = builtin, let e = external else { return nil }
        if CGDisplayMirrorsDisplay(e) == b { return .mirrorBuiltin }
        if CGDisplayMirrorsDisplay(b) == e { return .mirrorExternal }
        return .extend
    }

    static func modes(_ d: CGDirectDisplayID) -> [CGDisplayMode] {
        (CGDisplayCopyAllDisplayModes(d, modeOptions) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
    }

    /// The mode macOS marks as the display's default (recommended) one.
    static func defaultMode(_ d: CGDirectDisplayID) -> CGDisplayMode? {
        let all = modes(d)
        return all.first { $0.ioFlags & 0x4 != 0 } ?? all.max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
    }

    /// A mode on `d` with the same point size as `target`; same pixel size preferred, then the highest refresh rate.
    static func matchingMode(_ d: CGDirectDisplayID, like target: CGDisplayMode) -> CGDisplayMode? {
        let same = modes(d).filter { $0.width == target.width && $0.height == target.height }
        let samePixels = same.filter { $0.pixelWidth == target.pixelWidth && $0.pixelHeight == target.pixelHeight }
        return (samePixels.isEmpty ? same : samePixels).max { $0.refreshRate < $1.refreshRate }
    }

    @discardableResult
    static func configure(_ body: (CGDisplayConfigRef) -> Void) -> Bool {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return false }
        body(cfg)
        return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
    }

    static func setMode(_ d: CGDirectDisplayID, _ m: CGDisplayMode?) {
        guard let m else { return }
        if let cur = CGDisplayCopyDisplayMode(d), cur.ioDisplayModeID == m.ioDisplayModeID { return }
        configure { CGConfigureDisplayWithDisplayMode($0, d, m, nil) }
    }

    static func apply(_ mode: Mode) {
        guard let b = builtin, let e = external else { NSSound.beep(); return }
        switch mode {
        case .singleWindow:
            return // handled by WindowPresenter
        case .extend:
            configure {
                CGConfigureDisplayMirrorOfDisplay($0, e, kCGNullDirectDisplay)
                CGConfigureDisplayMirrorOfDisplay($0, b, kCGNullDirectDisplay)
            }
            setMode(b, defaultMode(b))
            setMode(e, defaultMode(e))
        case .mirrorBuiltin:
            configure {
                CGConfigureDisplayMirrorOfDisplay($0, b, kCGNullDirectDisplay)
                CGConfigureDisplayMirrorOfDisplay($0, e, b)
            }
            if let m = defaultMode(b) { setMode(b, m); setMode(e, matchingMode(e, like: m)) }
        case .mirrorExternal:
            configure {
                CGConfigureDisplayMirrorOfDisplay($0, e, kCGNullDirectDisplay)
                CGConfigureDisplayMirrorOfDisplay($0, b, e)
            }
            if let m = defaultMode(e) { setMode(e, m); setMode(b, matchingMode(b, like: m)) }
        }
    }
}

// MARK: - Picker window

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

final class HoverModel: ObservableObject {
    @Published var mode: Mode?
}

struct PickerView: View {
    let current: Mode?
    let hasExternal: Bool
    @ObservedObject var hover: HoverModel
    let choose: (Mode) -> Void
    var hovered: Mode? { hover.mode }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a display mode")
                .font(.system(size: 17, weight: .semibold))
            if !hasExternal {
                Text("No external monitor is connected.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(Mode.allCases) { mode in
                Button { choose(mode) } label: { row(mode) }
                    .buttonStyle(.plain)
                    .disabled(!hasExternal)
                    .onHover { inside in
                        if inside { hover.mode = mode } else if hover.mode == mode { hover.mode = nil }
                    }
            }
            Text("Press 1–4 to choose, Esc to close.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
            }

    func row(_ mode: Mode) -> some View {
        let isCurrent = mode == current
        return HStack(spacing: 12) {
            Image(systemName: mode.symbol)
                .font(.system(size: 22))
                .frame(width: 36)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title).font(.system(size: 14, weight: .medium))
                Text(isCurrent && mode == .singleWindow
                     ? "Showing now. Choose again to pick another window."
                     : mode.subtitle)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
            }
            Text("\(mode.rawValue + 1)")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5)))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovered == mode ? Color.accentColor.opacity(0.18) : (isCurrent ? Color.accentColor.opacity(0.08) : Color.clear))
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: KeyPanel?
    var previousApp: NSRunningApplication?
    var hotKeyRef: EventHotKeyRef?
    let presenter = WindowPresenter()

    func applicationDidFinishLaunching(_ note: Notification) {
        registerHotKey()
        // Pick a mode from scripts (object = "1"..."4"), mainly for testing.
        DistributedNotificationCenter.default().addObserver(forName: .init("io.github.boorghany.macdisplaymenu.mode"), object: nil, queue: .main) { [weak self] note in
            if let s = note.object as? String, let i = Int(s), let m = Mode(rawValue: i - 1) { self?.pick(m) }
        }
        // Also open the picker from scripts:
        //   swift -e 'import Foundation; DistributedNotificationCenter.default().post(name: .init("io.github.boorghany.macdisplaymenu.show"), object: nil)'
        DistributedNotificationCenter.default().addObserver(forName: .init("io.github.boorghany.macdisplaymenu.show"), object: nil, queue: .main) { [weak self] _ in
            self?.toggle()
        }
    }

    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            DispatchQueue.main.async { me.toggle() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x444D_4E55), id: 1) // 'DMNU'
        // ⌘P
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey), id, GetApplicationEventTarget(), 0, &hotKeyRef)
        NSLog("DisplayMenu: ⌘P hotkey registration status %d", status)
    }

    func toggle() {
        if panel != nil { close(restoreFocus: true) } else { show() }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        let current: Mode? = presenter.isActive ? .singleWindow : Displays.current()
        let view = PickerView(current: current, hasExternal: Displays.external != nil, hover: HoverModel()) { [weak self] mode in
            self?.pick(mode)
        }
        let host = NSHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize

        let p = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .modalPanel
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.delegate = self

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        p.contentView = blur

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.midY - size.height / 2))
        }

        p.onKey = { [weak self] event in
            guard let self else { return false }
            if event.keyCode == UInt16(kVK_Escape) {
                self.close(restoreFocus: true); return true
            }
            let chars = event.charactersIgnoringModifiers ?? ""
            let digits: [String: Int] = ["1": 0, "2": 1, "3": 2, "4": 3, "۱": 0, "۲": 1, "۳": 2, "۴": 3]
            if let i = digits[chars], let m = Mode(rawValue: i), Displays.external != nil {
                self.pick(m); return true
            }
            return false
        }

        p.onCancel = { [weak self] in self?.close(restoreFocus: true) }

        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func pick(_ mode: Mode) {
        close(restoreFocus: mode != .singleWindow)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            guard mode == .singleWindow else {
                presenter.stop()
                if Displays.current() != mode { Displays.apply(mode) }
                return
            }
            guard Displays.external != nil else { NSSound.beep(); return }
            if Displays.current() == .extend {
                presenter.choose()
            } else {
                // The window is shown on the monitor as a separate screen, so switch to extend first
                // and give macOS a moment to settle the new layout.
                Displays.apply(.extend)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.presenter.choose() }
            }
        }
    }

    func close(restoreFocus: Bool) {
        guard let p = panel else { return }
        panel = nil
        p.delegate = nil
        p.orderOut(nil)
        if restoreFocus { previousApp?.activate() }
    }

    func windowDidResignKey(_ notification: Notification) {
        close(restoreFocus: false)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
