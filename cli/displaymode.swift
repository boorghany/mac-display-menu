// displaymode — switch between extend and mirror using macOS's own CoreGraphics display API.
// No Accessibility or other permission is needed.
//
// Usage:
//   displaymode extend           two separate screens
//   displaymode mirror-builtin   mirror, optimized for the built-in screen
//   displaymode mirror-external  mirror, optimized for the external monitor
//   displaymode status
//   displaymode menu             open the Mac Display Menu picker window (if the app is running)

import CoreGraphics
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var n: UInt32 = 0
    CGGetOnlineDisplayList(16, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

let displays = onlineDisplays()
guard let builtin = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { fail("No built-in display found.") }
let external = displays.first(where: { CGDisplayIsBuiltin($0) == 0 })

let modeOptions = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
let kDefaultFlag: UInt32 = 0x4

func modes(_ d: CGDirectDisplayID) -> [CGDisplayMode] {
    (CGDisplayCopyAllDisplayModes(d, modeOptions) as? [CGDisplayMode] ?? []).filter { $0.isUsableForDesktopGUI() }
}

/// The mode macOS marks as the display's default ("recommended") one.
func defaultMode(_ d: CGDirectDisplayID) -> CGDisplayMode? {
    let all = modes(d)
    return all.first(where: { $0.ioFlags & kDefaultFlag != 0 }) ?? all.max(by: { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight })
}

/// A mode on `d` with the same point size as `target`; prefers the same pixel size, then the highest refresh rate.
func matchingMode(_ d: CGDirectDisplayID, like target: CGDisplayMode) -> CGDisplayMode? {
    let same = modes(d).filter { $0.width == target.width && $0.height == target.height }
    let samePixels = same.filter { $0.pixelWidth == target.pixelWidth && $0.pixelHeight == target.pixelHeight }
    return (samePixels.isEmpty ? same : samePixels).max(by: { $0.refreshRate < $1.refreshRate })
}

func configure(_ body: (CGDisplayConfigRef) -> Void) {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { fail("Could not start display configuration.") }
    body(cfg)
    let err = CGCompleteDisplayConfiguration(cfg, .permanently)
    if err != .success { fail("Display configuration failed (\(err.rawValue)).") }
}

func setMode(_ d: CGDirectDisplayID, _ m: CGDisplayMode?) {
    guard let m else { return }
    if let cur = CGDisplayCopyDisplayMode(d), cur.ioDisplayModeID == m.ioDisplayModeID { return }
    configure { CGConfigureDisplayWithDisplayMode($0, d, m, nil) }
}

func describe(_ d: CGDirectDisplayID) -> String {
    let m = CGDisplayCopyDisplayMode(d)
    let size = m.map { "\($0.width)x\($0.height) (\($0.pixelWidth)x\($0.pixelHeight) px, \(Int($0.refreshRate)) Hz)" } ?? "?"
    let role = CGDisplayIsBuiltin(d) != 0 ? "built-in" : "external"
    let mirror = CGDisplayMirrorsDisplay(d)
    return "\(role) #\(d): \(size)" + (CGDisplayIsMain(d) != 0 ? " main" : "") + (mirror != kCGNullDirectDisplay ? " mirrors #\(mirror)" : "")
}

let cmd = CommandLine.arguments.dropFirst().first ?? "status"

func needExternal() -> CGDirectDisplayID {
    guard let external else { fail("No external display connected.") }
    return external
}

switch cmd {
case "extend":
    let ext = needExternal()
    configure { cfg in
        CGConfigureDisplayMirrorOfDisplay(cfg, ext, kCGNullDirectDisplay)
        CGConfigureDisplayMirrorOfDisplay(cfg, builtin, kCGNullDirectDisplay)
    }
    setMode(builtin, defaultMode(builtin))
    setMode(ext, defaultMode(ext))

case "mirror-builtin":
    let ext = needExternal()
    configure { cfg in
        CGConfigureDisplayMirrorOfDisplay(cfg, builtin, kCGNullDirectDisplay)
        CGConfigureDisplayMirrorOfDisplay(cfg, ext, builtin)
    }
    if let m = defaultMode(builtin) {
        setMode(builtin, m)
        setMode(ext, matchingMode(ext, like: m))
    }

case "mirror-external":
    let ext = needExternal()
    configure { cfg in
        CGConfigureDisplayMirrorOfDisplay(cfg, ext, kCGNullDirectDisplay)
        CGConfigureDisplayMirrorOfDisplay(cfg, builtin, ext)
    }
    if let m = defaultMode(ext) {
        setMode(ext, m)
        setMode(builtin, matchingMode(builtin, like: m))
    }

case "menu":
    DistributedNotificationCenter.default().postNotificationName(.init("io.github.boorghany.macdisplaymenu.show"), object: nil, userInfo: nil, deliverImmediately: true)

case "status":
    for d in onlineDisplays() { print(describe(d)) }

default:
    fail("Unknown command '\(cmd)'. Use: extend | mirror-builtin | mirror-external | status | menu")
}
