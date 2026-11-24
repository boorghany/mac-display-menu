// WindowPresenter — "extend with one window": show a single chosen window, live, on the external monitor.
//
// It relies on macOS's own window picker (ScreenCaptureKit's SCContentSharingPicker, macOS 14+).
// Because the person picks the window in the system's own UI, macOS grants access to that window only,
// with no Screen Recording or Accessibility permission. macOS shows its usual screen-sharing indicator
// in the menu bar, where the shared window can also be changed or sharing stopped.

import AppKit
import AVFoundation
import CoreMedia
import ScreenCaptureKit

final class WindowPresenter: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var window: NSWindow?
    private let displayLayer = AVSampleBufferDisplayLayer()
    private let frameQueue = DispatchQueue(label: "displaymenu.frames", qos: .userInteractive)

    var isActive: Bool { stream != nil }

    override init() {
        super.init()
        let picker = SCContentSharingPicker.shared
        var cfg = SCContentSharingPickerConfiguration()
        cfg.allowedPickerModes = [.singleWindow]
        cfg.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "com.user.displaymenu"]
        // Changing the window of a running stream makes macOS check Screen Recording permission,
        // so every pick starts a fresh stream from the picker instead.
        cfg.allowsChangingSelectedContent = false
        picker.defaultConfiguration = cfg
        picker.maximumStreamCount = 1
        picker.add(self)

        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.screensChanged()
        }
    }

    /// Opens the system window picker. Picking again while a window is shown switches to the new window.
    /// It leaves the screen arrangement and every window where they are.
    func choose() {
        let picker = SCContentSharingPicker.shared
        picker.isActive = true
        picker.present(using: .window)
    }

    func stop() {
        endStream()
        window?.orderOut(nil)
        window = nil
        SCContentSharingPicker.shared.isActive = false
    }

    private func endStream() {
        stream?.stopCapture { _ in }
        stream = nil
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
    }


    // MARK: SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async { self.start(with: filter) }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async {
            if self.stream == nil { picker.isActive = false }
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        NSLog("DisplayMenu: window picker failed: %@", String(describing: error))
        DispatchQueue.main.async { self.stop() }
    }

    // MARK: Streaming

    private func configuration(for filter: SCContentFilter, on screen: NSScreen) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        // Capture straight at the size the window will fill on the monitor, in the monitor's pixels,
        // so the frame is shown 1:1 and ScreenCaptureKit does the scaling from the window's own pixels.
        let target = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
        let src = filter.contentRect.size
        let fit = min(target.width / max(src.width, 1), target.height / max(src.height, 1))
        c.width = max(2, Int((src.width * fit).rounded()))
        c.height = max(2, Int((src.height * fit).rounded()))
        c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.queueDepth = 5
        c.showsCursor = true
        c.scalesToFit = true
        c.ignoreShadowsSingleWindow = true
        return c
    }

    private func start(with filter: SCContentFilter) {
        guard let screen = Self.externalScreen() else { NSSound.beep(); return }
        endStream() // picking again replaces the window being shown
        if window == nil { showWindow(on: screen) }
        displayLayer.contentsScale = screen.backingScaleFactor
        let config = configuration(for: filter, on: screen)
        NSLog("DisplayMenu: showing window %@ @%.0fx as %dx%d px",
              NSStringFromRect(filter.contentRect), filter.pointPixelScale, config.width, config.height)

        let s = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        } catch {
            NSLog("DisplayMenu: could not add stream output: %@", String(describing: error))
            stop(); return
        }
        stream = s
        s.startCapture { [weak self] error in
            if let error {
                NSLog("DisplayMenu: capture failed to start: %@", String(describing: error))
                DispatchQueue.main.async { self?.stop() }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let infos = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = infos.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete
        else { return }

        // Show each frame as soon as it arrives instead of scheduling it on a timebase.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict,
                                 Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        renderer.enqueue(sampleBuffer)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Also called when sharing is stopped from the menu-bar indicator or the window closes.
        DispatchQueue.main.async {
            if self.stream === stream { self.stream = nil; self.stop() }
        }
    }

    // MARK: Output window on the monitor

    static func externalScreen() -> NSScreen? {
        guard let ext = Displays.external else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == ext
        }
    }

    private func showWindow(on screen: NSScreen) {
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        // Above the menu bar so the monitor shows only the chosen window.
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        w.backgroundColor = .black
        w.isOpaque = true
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.frame = view.bounds
        displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(displayLayer)
        w.contentView = view
        w.orderFrontRegardless()
        window = w
    }

    private func screensChanged() {
        guard let window else { return }
        if let screen = Self.externalScreen(), Displays.current() == .extend {
            window.setFrame(screen.frame, display: true)
        } else {
            stop() // monitor unplugged or switched to mirror
        }
    }
}
