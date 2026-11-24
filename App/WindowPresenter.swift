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
        cfg.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "io.github.boorghany.macdisplaymenu"]
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

    /// True when the picked window is on the monitor itself. Then it is shown where it is, at its real size,
    /// and the rest of the monitor goes black. Otherwise (a MacBook window) it is scaled to fill the monitor.
    private var inPlace = false
    /// The monitor's bounds in global display coordinates (points, origin at the top left of the main display).
    private var monitorBounds = CGRect.zero
    private var lastLayerFrame = CGRect.null

    private func configuration(for filter: SCContentFilter, on screen: NSScreen) -> SCStreamConfiguration {
        let c = SCStreamConfiguration()
        let target = CGSize(width: screen.frame.width * screen.backingScaleFactor,
                            height: screen.frame.height * screen.backingScaleFactor)
        if inPlace {
            // A surface as big as the monitor holds the window unscaled whatever its size, so it stays
            // sharp when it is resized. Each frame says where the window is, and the layer follows it.
            c.width = Int(target.width)
            c.height = Int(target.height)
            c.scalesToFit = false
            c.showsCursor = false // the real cursor is already there
        } else {
            // Capture straight at the size the window will fill on the monitor, in the monitor's pixels,
            // so the frame is shown 1:1 and ScreenCaptureKit does the scaling from the window's own pixels.
            let src = filter.contentRect.size
            let fit = min(target.width / max(src.width, 1), target.height / max(src.height, 1))
            c.width = max(2, Int((src.width * fit).rounded()))
            c.height = max(2, Int((src.height * fit).rounded()))
            c.scalesToFit = true
            c.showsCursor = true
        }
        c.captureResolution = .best
        c.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        c.pixelFormat = kCVPixelFormatType_32BGRA
        c.queueDepth = 5
        c.ignoreShadowsSingleWindow = true
        return c
    }

    private func start(with filter: SCContentFilter) {
        guard let screen = Self.externalScreen(), let ext = Displays.external else { NSSound.beep(); return }
        endStream() // picking again replaces the window being shown

        var picked: SCWindow?
        if #available(macOS 15.2, *) { picked = filter.includedWindows.first }
        let frame = picked?.frame ?? filter.contentRect
        monitorBounds = CGDisplayBounds(ext)
        inPlace = monitorBounds.contains(CGPoint(x: frame.midX, y: frame.midY))

        showWindow(on: screen)
        displayLayer.contentsScale = screen.backingScaleFactor
        lastLayerFrame = .null
        if inPlace {
            displayLayer.videoGravity = .resize
            displayLayer.autoresizingMask = []
            displayLayer.frame = .zero // placed by the first frame
            // Bring the window's app forward so clicks on the image reach the window under it.
            if let pid = picked?.owningApplication?.processID {
                NSRunningApplication(processIdentifier: pid)?.activate()
            }
        } else {
            displayLayer.videoGravity = .resizeAspect
            displayLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            displayLayer.frame = window?.contentView?.bounds ?? .zero
        }

        let config = configuration(for: filter, on: screen)
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
              let info = infos.first,
              let raw = info[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete
        else { return }

        if inPlace { placeLayer(for: sampleBuffer, info: info) }

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

    /// Positions the layer so the window in the frame lands exactly where the real window is on the monitor.
    private func placeLayer(for sampleBuffer: CMSampleBuffer, info: [SCStreamFrameInfo: Any]) {
        guard let screenDict = info[.screenRect], let contentDict = info[.contentRect],
              let onScreen = CGRect(dictionaryRepresentation: screenDict as! CFDictionary),
              let inSurface = CGRect(dictionaryRepresentation: contentDict as! CFDictionary),
              let image = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let scale = (info[.scaleFactor] as? CGFloat) ?? 1
        // The whole surface in points, and where its top-left corner has to go so the content matches the window.
        let surface = CGSize(width: CGFloat(CVPixelBufferGetWidth(image)) / scale,
                             height: CGFloat(CVPixelBufferGetHeight(image)) / scale)
        let k = onScreen.width / max(inSurface.width, 1) // 1 unless the surface had to shrink the window
        let topLeft = CGPoint(x: onScreen.minX - inSurface.minX * k - monitorBounds.minX,
                              y: onScreen.minY - inSurface.minY * k - monitorBounds.minY)
        let size = CGSize(width: surface.width * k, height: surface.height * k)
        let frame = CGRect(x: topLeft.x, y: monitorBounds.height - topLeft.y - size.height,
                           width: size.width, height: size.height)
        DispatchQueue.main.async {
            guard self.inPlace, frame != self.lastLayerFrame else { return }
            self.lastLayerFrame = frame
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.displayLayer.frame = frame
            CATransaction.commit()
        }
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
        if window == nil {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.ignoresMouseEvents = true // clicks go to the real windows underneath
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.layer?.addSublayer(displayLayer)
            w.contentView = view
            window = w
        }
        guard let w = window else { return }
        w.setFrame(screen.frame, display: false)
        let menuBar = Int(CGWindowLevelForKey(.mainMenuWindow))
        // A MacBook window covers the whole monitor. A window shown in place keeps the menu bar usable.
        w.level = NSWindow.Level(rawValue: inPlace ? menuBar - 1 : menuBar + 1)
        w.orderFrontRegardless()
    }

    private func screensChanged() {
        guard let window else { return }
        if let screen = Self.externalScreen(), let ext = Displays.external, Displays.current() == .extend {
            monitorBounds = CGDisplayBounds(ext)
            lastLayerFrame = .null
            window.setFrame(screen.frame, display: true)
        } else {
            stop() // monitor unplugged or switched to mirror
        }
    }
}
